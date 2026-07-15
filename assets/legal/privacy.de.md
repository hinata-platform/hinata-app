# Datenschutzerklärung

*Stand: 15. Juli 2026*

Der Schutz Ihrer personenbezogenen Daten ist uns wichtig. Nachfolgend informieren wir Sie gemäß Art. 13 und 14 der Datenschutz-Grundverordnung (DSGVO) darüber, welche personenbezogenen Daten wir im Zusammenhang mit der Nutzung der Anwendung Hinata („App", „Dienst") verarbeiten, zu welchen Zwecken und auf welcher Rechtsgrundlage dies geschieht sowie welche Rechte Ihnen zustehen.

## § 1 Verantwortlicher

Verantwortlicher im Sinne des Art. 4 Nr. 7 DSGVO für die Bereitstellung der App ist:

Rebar Ahmad
[ANSCHRIFT EINTRAGEN — Straße, Hausnummer, PLZ, Ort]
E-Mail: rebar.ahmad@gmail.com

Ein Datenschutzbeauftragter ist gesetzlich nicht bestellt. Für alle Anliegen rund um den Datenschutz und zur Ausübung Ihrer Rechte erreichen Sie uns unter der vorstehenden Kontaktadresse.

## § 2 Geltungsbereich und Betrieb auf eigenen Servern

Hinata ist eine Anwendung zur Projekt- und Vorgangsverwaltung, die als Web-Anwendung sowie als App für mobile und Desktop-Betriebssysteme bereitgestellt wird. Die App verbindet sich mit einem Server („Instanz"), dessen Adresse Sie oder Ihre Organisation auswählen.

**Betrieb durch Dritte (Instanzbetreiber)**

Hinata kann von Organisationen auf eigener Infrastruktur selbst betrieben werden. Nutzen Sie eine Instanz, die von Ihrer Organisation oder einem sonstigen Dritten betrieben wird, so ist dieser Betreiber hinsichtlich der auf seiner Instanz gespeicherten Inhalts- und Kontodaten ein eigener Verantwortlicher. In diesem Fall gelten ergänzend die Datenschutzhinweise des jeweiligen Betreibers; bitte wenden Sie sich für Auskünfte zu diesen Daten an den Betreiber Ihrer Instanz. Die vorliegende Erklärung beschreibt die Datenverarbeitung, die der App selbst zugrunde liegt.

## § 3 Kategorien verarbeiteter Daten

Im Rahmen der Nutzung des Dienstes verarbeiten wir insbesondere:

**a) Bestands- und Kontodaten**

- Name bzw. Anzeigename und Benutzername
- E-Mail-Adresse
- Passwort (ausschließlich als kryptografischer Hash gespeichert, niemals im Klartext)
- optionales Profilbild (Avatar) sowie Profilangaben
- Spracheinstellung und Anwendungseinstellungen

**b) Authentifizierungs- und Sicherheitsdaten**

- Anmeldesitzungen (Sessions) einschließlich Sitzungskennung, Zeitstempel und Gerätekennung
- Zugriffs- und Erneuerungs-Token (Access-/Refresh-Token)
- bei aktivierter Zwei-Faktor-Authentifizierung: TOTP-Geheimnis und Wiederherstellungscodes
- bei Anmeldung über einen externen Identitätsanbieter (Single Sign-On): die von diesem übermittelte Nutzerkennung
- ggf. persönliche Zugriffstoken für Schnittstellen (z. B. den MCP-Server)

**c) Inhaltsdaten**

- Projekte, Vorgänge (Issues), Aufgaben, Epics und Teilaufgaben
- Kommentare einschließlich Sprachnachrichten (Audioaufnahmen) und Reaktionen
- Datei-Anhänge und Bilder
- Zeiterfassung (Worklogs) und Berichte
- Wissensdatenbank-Artikel, Teams und deren Zuordnungen

**d) Kommunikationsdaten**

- ein- und ausgehende E-Mails im Rahmen der Funktion „E-Mail zu Vorgang"
- In-App- und Push-Benachrichtigungen sowie deren Einstellungen

**e) Nutzungs- und Protokolldaten**

- server- und sicherheitsseitige Protokolle (Logs) einschließlich IP-Adresse, Datum und Uhrzeit des Zugriffs
- Prüf-/Audit-Protokolle über sicherheitsrelevante Aktionen im Konto
- technische Angaben zu Gerät, Betriebssystem und Browser/App-Version

**f) Push-Token**

Wenn Sie Push-Benachrichtigungen aktivieren, verarbeiten wir eine gerätebezogene Push-Kennung (FCM-Token), um Ihnen Benachrichtigungen zustellen zu können (siehe § 6).

## § 4 Zwecke und Rechtsgrundlagen der Verarbeitung

Wir verarbeiten Ihre Daten zu folgenden Zwecken und auf folgenden Rechtsgrundlagen:

- Bereitstellung, Betrieb und Funktionsumfang des Dienstes, Verwaltung Ihres Kontos und Ihrer Inhalte — Art. 6 Abs. 1 lit. b DSGVO (Vertrag bzw. vorvertragliche Maßnahmen).
- Gewährleistung von Sicherheit, Stabilität und Missbrauchsabwehr (z. B. Protokolle, Audit-Log, Sitzungsverwaltung) — Art. 6 Abs. 1 lit. f DSGVO (berechtigtes Interesse an einem sicheren Betrieb).
- Versand von Push- und E-Mail-Benachrichtigungen sowie Nutzung optionaler Integrationen — Art. 6 Abs. 1 lit. a DSGVO (Einwilligung), soweit gesondert aktiviert; im Übrigen Art. 6 Abs. 1 lit. b DSGVO.
- Erfüllung rechtlicher Verpflichtungen (z. B. Beantwortung von Betroffenenanfragen) — Art. 6 Abs. 1 lit. c DSGVO.

## § 5 Empfänger und Auftragsverarbeiter

Ihre Daten werden grundsätzlich nur zur Erbringung des Dienstes verarbeitet. Eine Weitergabe erfolgt nur, soweit dies zur Zweckerfüllung erforderlich ist. Wir setzen sorgfältig ausgewählte Dienstleister ein, mit denen — soweit erforderlich — Verträge zur Auftragsverarbeitung nach Art. 28 DSGVO bestehen:

- Hosting/Infrastruktur: Die Server- und Speicherdienste (u. a. Datenbank und Objektspeicher für Anhänge) werden auf der Infrastruktur des jeweiligen Instanzbetreibers bzw. eines von diesem beauftragten Hosting-Anbieters betrieben.
- Push-Benachrichtigungen: Google (Firebase Cloud Messaging), siehe § 6 und § 7.
- E-Mail-Versand: der zur Zustellung von System- und Benachrichtigungs-E-Mails eingesetzte E-Mail-/SMTP-Anbieter.
- Single Sign-On: der von Ihnen bzw. Ihrer Organisation gewählte externe Identitätsanbieter (nur bei Nutzung von SSO).
- Optionale Integrationen: mit dem Dienst verbundene externe Anbieter (z. B. Git-Dienste wie GitHub, GitLab oder Bitbucket), sofern Sie eine solche Integration einrichten.

Eine Übermittlung an Behörden erfolgt nur im Rahmen zwingender gesetzlicher Vorschriften.

## § 6 Push-Benachrichtigungen (Firebase Cloud Messaging)

Zur Zustellung von Push-Benachrichtigungen an mobile Geräte nutzen wir den Dienst Firebase Cloud Messaging (FCM) der Google Ireland Limited bzw. Google LLC. Hierbei wird eine geräte- bzw. installationsbezogene Push-Kennung verarbeitet und der Nachrichtentext zur Zustellung an den Push-Dienst übergeben. Die Zustellung erfolgt technisch über eine zentrale Relay-Komponente („Hinata Connect").

Push-Benachrichtigungen sind optional. Sie können sie in den Systemeinstellungen Ihres Geräts sowie in den Benachrichtigungseinstellungen der App jederzeit deaktivieren.

## § 7 Datenübermittlung in Drittländer

Soweit wir Firebase Cloud Messaging einsetzen, kann es zu einer Verarbeitung von Daten durch die Google LLC in den USA kommen. Die Google LLC ist unter dem EU-U.S. Data Privacy Framework zertifiziert; ergänzend werden Standardvertragsklauseln der Europäischen Kommission (Art. 46 Abs. 2 lit. c DSGVO) als geeignete Garantien herangezogen. Im Übrigen findet eine Verarbeitung Ihrer Daten grundsätzlich innerhalb der Europäischen Union bzw. des Europäischen Wirtschaftsraums statt, sofern der jeweilige Instanzbetreiber nichts anderes vorsieht.

## § 8 Cookies und lokale Speicherung

Die App verwendet keine Cookies oder vergleichbaren Technologien zu Analyse- oder Werbezwecken und bindet keine Tracking-Dienste Dritter ein. Zur Bereitstellung der Funktionen werden technisch notwendige Informationen lokal auf Ihrem Gerät gespeichert (u. a. Anmelde-Token, die gewählte Serveradresse sowie Ihre Anwendungseinstellungen). Diese lokale Speicherung ist für den Betrieb erforderlich; Rechtsgrundlage ist Art. 6 Abs. 1 lit. b DSGVO bzw. § 25 Abs. 2 TDDDG.

## § 9 Speicherdauer und Löschung

Wir speichern personenbezogene Daten nur so lange, wie es für die genannten Zwecke erforderlich ist oder gesetzliche Aufbewahrungspflichten dies vorschreiben. Konto- und Inhaltsdaten werden im Wesentlichen für die Dauer des Bestehens Ihres Kontos gespeichert.

Sie können Ihr Konto jederzeit selbst löschen. Bei einer Löschung werden Ihre Konto- und zugehörigen Daten entfernt bzw. anonymisiert, soweit keine gesetzlichen Aufbewahrungspflichten oder überwiegenden berechtigten Interessen (z. B. Sicherheits-Protokolle für einen begrenzten Zeitraum) entgegenstehen. Protokolldaten werden nach kurzer Frist gelöscht bzw. gekürzt.

## § 10 Ihre Rechte als betroffene Person

Ihnen stehen nach der DSGVO insbesondere folgende Rechte zu:

- Auskunft über die zu Ihnen gespeicherten Daten (Art. 15 DSGVO). Eine Datenauskunft/‑export können Sie direkt in der App anstoßen.
- Berichtigung unrichtiger Daten (Art. 16 DSGVO).
- Löschung Ihrer Daten (Art. 17 DSGVO). Die Löschung Ihres Kontos ist unmittelbar in der App möglich.
- Einschränkung der Verarbeitung (Art. 18 DSGVO).
- Datenübertragbarkeit (Art. 20 DSGVO).
- Widerspruch gegen Verarbeitungen, die auf Art. 6 Abs. 1 lit. f DSGVO beruhen (Art. 21 DSGVO).
- Widerruf erteilter Einwilligungen mit Wirkung für die Zukunft (Art. 7 Abs. 3 DSGVO).

Zur Ausübung Ihrer Rechte genügt eine formlose Mitteilung an die in § 1 genannte Kontaktadresse.

**Beschwerderecht bei einer Aufsichtsbehörde**

Unbeschadet anderweitiger Rechtsbehelfe steht Ihnen gemäß Art. 77 DSGVO ein Beschwerderecht bei einer Datenschutz-Aufsichtsbehörde zu, insbesondere in dem Mitgliedstaat Ihres Aufenthaltsorts, Ihres Arbeitsplatzes oder des Orts des mutmaßlichen Verstoßes.

## § 11 Erforderlichkeit der Bereitstellung

Die Bereitstellung bestimmter Daten (insbesondere E-Mail-Adresse und Passwort bzw. eine SSO-Anmeldung) ist für die Einrichtung und Nutzung eines Kontos erforderlich. Ohne diese Daten können wir den Dienst nicht bereitstellen. Weitere Angaben (z. B. Profilbild) sind freiwillig.

## § 12 Keine automatisierte Entscheidungsfindung

Eine ausschließlich automatisierte Entscheidungsfindung einschließlich Profiling im Sinne des Art. 22 DSGVO findet nicht statt.

## § 13 Minderjährige

Der Dienst richtet sich nicht an Kinder unter 16 Jahren. Personen unter 16 Jahren sollten den Dienst nur mit Einwilligung der Sorgeberechtigten nutzen.

## § 14 Datensicherheit

Wir treffen technische und organisatorische Maßnahmen, um Ihre Daten gegen unbefugten Zugriff, Verlust oder Manipulation zu schützen. Dazu zählen unter anderem eine verschlüsselte Übertragung (TLS/HTTPS), die ausschließlich gehashte Speicherung von Passwörtern sowie eine optionale Zwei-Faktor-Authentifizierung.

## § 15 Änderungen dieser Datenschutzerklärung

Wir passen diese Datenschutzerklärung an, wenn Änderungen der Datenverarbeitung oder der Rechtslage dies erfordern. Es gilt jeweils die zum Zeitpunkt Ihrer Nutzung abrufbare Fassung. Das Datum am Anfang dieser Erklärung gibt den Stand der aktuellen Fassung an.

## § 16 Kontakt

Bei Fragen zum Datenschutz oder zur Ausübung Ihrer Rechte erreichen Sie uns unter: rebar.ahmad@gmail.com
