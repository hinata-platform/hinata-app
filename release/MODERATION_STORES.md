# Moderation in den Stores (HIN-178)

Was die Pipeline selbst erledigt und was in den Konsolen von Hand bleibt. Die
Stores verlangen für Apps mit Inhalten von Nutzern: Regeln, die man vorher
annimmt, Melden, Blockieren, eine Moderation, die handelt, und einen Kontakt.

## Einmal vorher: zwei Prüfkonten

1. Auf der Prüfinstanz (`https://api.track.asta.hn`) zwei **eigene** Konten
   anlegen, nicht das eigene Konto nehmen: ein normales Mitglied und eines mit
   der Rolle Moderation.
2. Beide in eine Demo-Organisation mit ein paar Vorgängen, Kommentaren, einer
   Datei und einer Wissensseite, damit Melden und Blockieren etwas zum Anklicken
   haben. Echte Inhalte der Organisation dürfen die Konten nicht sehen.
3. Auf der Instanz prüfen: Kontakt für Meldungen gesetzt, Hausregeln
   veröffentlicht, Textprüfung „Klare Verstöße ablehnen“ an.
4. Repository-Secrets in `hinata-platform/hinata-app` setzen:
   - `APP_REVIEW_DEMO_USER`, `APP_REVIEW_DEMO_PASSWORD` (Mitglied)
   - `APP_REVIEW_MODERATOR_USER`, `APP_REVIEW_MODERATOR_PASSWORD` (Moderation)

Ohne die vier Secrets bricht „Publish (button)“ für iOS und macOS vor dem Build
ab. Das ist Absicht: Ohne Anmeldefelder meldet deliver an App Review, dass kein
Konto nötig sei.

Zugangsdaten gehören nie in `fastlane/metadata`. Das Repository ist öffentlich.

## Apple

Automatisch mit jedem „Publish (button)“:

- **Review-Hinweise** aus `ios/fastlane/metadata/review_information/notes.txt`
  (macOS: dieselbe Datei unter `macos/`). Die Release-Lane setzt das Mitglied
  in die Anmeldefelder und hängt das Moderationskonto an die Hinweise an.
- **Altersfragen** aus `ios/fastlane/age_rating.json` (macOS ebenso): User
  Generated Content ja, Messaging and Chat ja, Unrestricted Web Access nein.
  Alle anderen Antworten bleiben, wie App Store Connect sie hat. Social Media
  kennt die API nicht als eigene Frage; in App Store Connect auf Nein lassen.
  Die errechnete Altersstufe bleibt: Inhalte von Nutzern und Nachrichten heben
  sie allein nicht an.

Von Hand:

- **Bildschirmaufnahme** auf einem iPhone: App-Bedingungen vor der Anmeldung,
  Melden, Blockieren. In App Store Connect unter App Review, Anhang hochladen.

## Google Play (Play Console, App-Inhalte)

- **App-Zugriff:** „Alle oder einige Funktionen sind eingeschränkt“. Zwei
  Einträge, je mit Benutzername und Passwort eines Prüfkontos, und dazu:

  ```text
  Hinata is the app for a self-hosted server. On "Connect to your server", enter
  https://api.track.asta.hn and tap Connect, then sign in. Report: the menu of an
  issue, comment, file, knowledge base page or person, "Report …". Block: "Block
  person" in the menu of a comment. House rules and contact: Settings, Help and
  contact. Moderation: sign in with the moderator account, Settings, Moderation.
  ```

- **Altersfreigabe (IARC):** Fragebogen neu ausfüllen. „Können Nutzer
  miteinander interagieren oder Inhalte austauschen?“: Ja. Sonst wie bisher.
- **Datensicherheit:** keine neue Erhebung durch die App. Meldungen,
  Widersprüche und Blockierungen gehen an den Server der Organisation, wie
  Kommentare und Dateien schon. Prüfen, dass „Andere nutzergenerierte Inhalte“
  angegeben ist.
- **Kontolöschung:** Link auf
  `https://hinata.ahmadre.com/en/guide-account.html#delete-your-account-art-17`.

## Microsoft Store

- **Zertifizierungsnotiz** steht in `windows/store/captions.json`
  (`notesForCertification`): wo Hausregeln, Melden, Blockieren und Kontakt
  liegen. Actions, „Windows listing (screenshots)“ schiebt sie in die offene
  Einreichung, auch wenn die Bilder gleich bleiben.
