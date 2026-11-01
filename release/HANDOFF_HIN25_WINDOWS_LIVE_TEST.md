# Handoff HIN-25: Windows-Push und Toasts live testen

Stand 2026-11-01. Für die Fortsetzung auf dem Windows-Gerät, mit Rebar am Gerät
und Claude in derselben Sitzung.

## Worum es geht

Hinata nutzt für Windows-Push ab Branch `HIN-25` (PR #169) nur noch das eigene
Plugin [`windows_push`](https://pub.dev/packages/windows_push) 0.1.0
(`hinata-platform/windows_push`, MIT). Der eingebaute Code ist entfernt:
`windows/runner/wns_channel.*`, `windows/cmake/WindowsAppSDK.cmake`,
`tool/patch_msix_manifest.dart`. Übrig im Runner ist eine Zeile,
`WindowsPushInitialize()` am Anfang von `wWinMain`.

Bisher geprüft, ohne Windows-Gerät:

- Plugin-CI: Beispiel-App baut mit VS 2022 und VS 2026, MSIX wird gepatcht und
  gepackt, der unverpackte Build startet und läuft 15 Sekunden ohne Absturz.
- hinata-app-CI auf PR #169 komplett grün, auch der neue Job „Build Windows
  (Store package, unsigned)“: Release-Build, `msix:build`, `patch_manifest`,
  Prüfung der Toast-CLSID, `msix:pack`.
- `flutter analyze` sauber, Notification- und Timer-Surface-Tests grün.

**Nicht geprüft und Ziel dieses Tests:** echter Push, Klick bei laufender und
bei geschlossener App, Timer-Toasts, Store-Validierung.

## Was gleich bleiben muss (nicht anfassen)

| Wert | Wo | Warum |
| --- | --- | --- |
| Remote-ID `33fa840e-5c3b-4cc0-8308-227acbecdf0d` | `lib/core/notifications/wns_channel.dart` | Damit fordert die App den Kanal an, wie bisher. |
| Client-ID `e89a5a67-af01-4c79-98a7-09e609f0c831` | `AZURE_APP_ID` in `windows/fastlane/Fastfile` | Class-ID des Push-Aktivators im Manifest, wie bisher. |
| Toast-CLSID `C2EC5161-3E44-44EC-97FF-90DC93713ADF` | Fastfile, `--toast-clsid` | Ändert sie sich, öffnen Toasts im Info-Center die App nicht mehr. |
| Toast-Gruppe `timer` | `wns_channel.dart` | Damit Toasts der alten Version noch abgesagt werden können. |

Die beiden IDs sind absichtlich verschieden. Genau dieses Paar läuft seit
August im Store.

## Was sich geändert hat (darauf achten)

1. Das Fenster kommt jetzt nach vorn, wenn es gezeigt wird (das Plugin hört auf
   `WM_SHOWWINDOW`), nicht mehr aus dem Callback des ersten Frames.
2. Die Bootstrap-DLL `Microsoft.WindowsAppRuntime.Bootstrap.dll` liegt nicht mehr
   neben der exe. Kein Code hat sie aufgerufen; die Runtime kommt über die
   Framework-Abhängigkeit `Microsoft.WindowsAppRuntime.2`.
3. Die Methoden laufen über den Kanal `windows_push` statt `hinata/wns`.
4. Die COM-Server im Manifest heißen nach dem Paketnamen (`hinata`).

## 1. Gerät vorbereiten

Voraussetzungen: Visual Studio 2022 oder 2026 mit „Desktopentwicklung mit C++“
und Windows SDK 10.0.26100, Flutter 3.47.7 (wie `.fvmrc`), Git.

```powershell
git config --global core.longpaths true   # sonst scheitert pub get am flutter_local_notifications-Fork
git clone https://github.com/hinata-platform/hinata-app.git   # oder vorhandenen Klon nehmen
cd hinata-app
git fetch origin
git switch HIN-25
flutter pub get
```

Prüfen, dass die Windows App Runtime 2 installiert ist (kommt mit der
Store-Version von Hinata):

```powershell
Get-AppxPackage *WindowsAppRuntime.2* | Select Name, Version
```

Leer? Dann den „Windows App SDK Runtime“-Installer 2.x von Microsoft
installieren, sonst startet das MSIX nicht.

## 2. Unverpackt starten (erste Rauchprobe)

```powershell
flutter run -d windows
```

Erwartet: App startet normal, kein Absturz, keine Fehlermeldung zu Push. Ohne
Paket-Identität gibt es keinen Kanal, das ist richtig so.

## 3. MSIX bauen, signieren, installieren

Das Store-Paket ist unsigniert. Zum Seitenladen wird es mit einem
selbstsignierten Zertifikat signiert, dessen Subject genau dem Store-Publisher
entspricht (sonst lehnt Windows das Paket ab).

**Achtung:** Die Store-Version von Hinata hat dieselbe Paket-Identität und muss
vorher deinstalliert werden. Dabei gehen lokale Daten der App verloren
(gespeicherte Server, Anmeldung). Nach dem Test die Testversion deinstallieren
und Hinata wieder aus dem Store holen.

Einmalig, PowerShell **als Administrator**:

```powershell
$cert = New-SelfSignedCertificate -Type Custom `
  -Subject "CN=0A922060-E40D-4D55-9D1D-83B9594F60E5" `
  -KeyUsage DigitalSignature -FriendlyName "Hinata HIN-25 test" `
  -CertStoreLocation Cert:\CurrentUser\My `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")
$pw = ConvertTo-SecureString -String "hinata-test" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath $env:USERPROFILE\hinata-test.pfx -Password $pw
Import-PfxCertificate -FilePath $env:USERPROFILE\hinata-test.pfx -Password $pw `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople
```

Bauen wie die Fastlane-Lane `build` (Version frei wählbar, vierte Stelle 0):

```powershell
flutter build windows --release
dart run msix:build --store --version 99.0.0.0
dart run windows_push:patch_manifest --remote-id=e89a5a67-af01-4c79-98a7-09e609f0c831 --toast-clsid=C2EC5161-3E44-44EC-97FF-90DC93713ADF --runtime=2
dart run msix:pack --store --version 99.0.0.0
```

`patch_manifest` muss drei Zeilen melden: Push-Class-ID, Toast-CLSID,
Framework-Abhängigkeit.

Signieren und installieren:

```powershell
$msix = Get-ChildItem build\windows\x64\runner\Release\*.msix | Select -First 1
& "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign /fd SHA256 /f $env:USERPROFILE\hinata-test.pfx /p hinata-test $msix.FullName
Get-AppxPackage *hinata* | Remove-AppxPackage    # Store-Version entfernen, siehe Achtung oben
Add-AppxPackage $msix.FullName
```

Zeitstempel-Falle: Wurde vorher im selben Ordner mit `--debug` gebaut, kann
`build\windows\x64\runner\Release\data\app.so` veraltet sein. Uhrzeit mit den
Quellen vergleichen, im Zweifel `flutter clean`.

## 4. Testplan

App aus dem Startmenü starten, am eigenen Server anmelden (der mit Hinata
Connect, damit der Gateway zustellt).

| # | Test | Erwartet |
| --- | --- | --- |
| 1 | Start der installierten App | Startet normal, Fenster vorn. |
| 2 | Push bei laufender App: von einem zweiten Konto oder Gerät etwas auslösen, das dich benachrichtigt (z. B. Kommentar mit @Erwähnung, Zuweisung) | Toast erscheint. |
| 3 | Klick auf den Toast aus 2, App läuft, aber liegt hinter anderen Fenstern | Fenster kommt nach vorn, Hinata öffnet das betroffene Issue. |
| 4 | App ganz schließen (auch aus dem Tray), Push auslösen, Toast anklicken | App startet, Fenster kommt nach vorn, öffnet das Issue genau einmal. |
| 5 | Timer-Toast: Systemmitteilungen für den Timer in den Einstellungen einschalten (Einführung bestätigen), kurzen Countdown oder Fokus-Intervall starten | Am Ende erscheint ein Toast. |
| 6 | Klick auf den Timer-Toast, App läuft | Öffnet die Zeit-Ansicht. |
| 7 | Countdown starten, App schließen, Toast am Ende anklicken | App startet und öffnet die Zeit-Ansicht. |
| 8 | Countdown starten und vor dem Ende stoppen | Kein Toast. |
| 9 | Store-Prüfung: Windows App Certification Kit (`appcert.exe`) auf das MSIX laufen lassen | Bestanden, insbesondere Manifest und Abhängigkeiten. |

Schlägt 2 fehl, nacheinander prüfen:

- Gateway-Log auf ASTASRV01: steht dort `WNS configured; Windows push is
  active.`, und kommt beim Auslösen ein Versand an `notify.windows.com`?
- Hat der Server das Gerät? Der Kanal wird beim Anmelden an
  `POST /api/v1/me/devices` gemeldet. Server-Log beim Login ansehen.
- Liefert die App überhaupt einen Kanal? Im Debug-Build loggte der alte Code die
  URI; das Plugin loggt sie nicht. Zur Not die Beispiel-App des Plugins
  (`windows_push/example`, Start mit `--dart-define=WNS_REMOTE_ID=33fa840e-5c3b-4cc0-8308-227acbecdf0d`)
  als MSIX bauen, sie zeigt die URI an. Achtung, deren Paket-Identität ist eine
  andere.

Schlägt 3 oder 4 fehl (Toast kommt, Klick tut nichts):

- `AppxManifest.xml` im Installationsordner prüfen: zwei `com:ExeServer`
  (`----WindowsAppRuntimePushServer:` und `----AppNotificationActivated:`) und
  `ToastActivatorCLSID="C2EC5161-…"`.
- Kaltstart: Der Klick muss über `WindowsPushInitialize()` in
  `windows/runner/main.cpp` gelesen werden, vor dem Fenster.

Schlägt nur das Nach-vorn-Holen fehl: `HandleTopLevelMessage` in
`windows_push/windows/windows_push_plugin.cpp` (Reaktion auf `WM_SHOWWINDOW`).

## 5. Bei einem Fehler im Plugin

Fehler im Plugin werden im Plugin behoben, nicht in hinata-app:

1. Fix in `hinata-platform/windows_push`, `CHANGELOG.md` ergänzen, Version in
   `pubspec.yaml` erhöhen.
2. Tag `vX.Y.Z` pushen. Der Workflow `Publish` wartet auf Rebars Freigabe im
   Environment `pub.dev` und veröffentlicht dann per OIDC.
3. In hinata-app auf Branch `HIN-25` die Version in `pubspec.yaml` anheben.

Zum schnellen Ausprobieren vorher lokal: `pubspec_overrides.yaml` in hinata-app
mit `windows_push: { path: ../windows_push }` (nicht committen).

## 6. Nach dem Test

- Alles grün: PR #169 mergen, HIN-25 auf Done, Ergebnis als Kommentar ins
  Ticket (welche Tests, welches Windows, Datum).
- Testversion deinstallieren, Hinata aus dem Store neu installieren, Test-
  Zertifikat aus `LocalMachine\TrustedPeople` und `CurrentUser\My` löschen.
- Offener Punkt im Ticket bleibt: Test auf einer zweiten Maschine.

## Links

- Ticket: https://track.asta.hn/issues/HIN-25
- PR: https://github.com/hinata-platform/hinata-app/pull/169
- Plugin: https://github.com/hinata-platform/windows_push · https://pub.dev/packages/windows_push
- Bisheriger Betriebsleitfaden: `release/MANUAL_STEPS_WINDOWS.md`, Abschnitt 4
