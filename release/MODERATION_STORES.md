# Moderation in den Stores (HIN-178)

Was die Pipeline selbst erledigt und was in den Konsolen von Hand bleibt. Die
Stores verlangen für Apps mit Inhalten von Nutzern: Regeln, die man vorher
annimmt, Melden, Blockieren, eine Moderation, die handelt, und einen Kontakt.

## Einmal vorher: ein Prüfserver mit zwei Konten

1. Einen eigenen Prüfserver aufsetzen: eine eigene Instanz mit eigener
   Datenbank, Demo-Daten und ohne echte Mitglieder. Nie den Produktivserver
   nehmen. Wer moderiert, sieht jeden Fall seines Servers, mit Meldungen,
   Inhalten und Dateien, und kann Inhalte entfernen und Konten sperren.
2. Dort zwei **eigene** Konten anlegen, nicht das eigene Konto nehmen: ein
   normales Mitglied und eines mit der Rolle Moderation.
3. Beide in eine Demo-Organisation mit ein paar Vorgängen, Kommentaren, einer
   Datei und einer Wissensseite, damit Melden und Blockieren etwas zum Anklicken
   haben.
4. Auf dem Prüfserver prüfen: Kontakt für Meldungen gesetzt, Hausregeln
   veröffentlicht, Textprüfung „Klare Verstöße ablehnen“ an.
5. Repository-Secrets in `hinata-platform/hinata-app` setzen:
   - `APP_REVIEW_SERVER`: die Adresse des Prüfservers, etwa
     `https://review.example.org`
   - `APP_REVIEW_PHONE`: eine Nummer, unter der App Review jemanden erreicht
   - `APP_REVIEW_DEMO_USER`, `APP_REVIEW_DEMO_PASSWORD` (Mitglied)
   - `APP_REVIEW_MODERATOR_USER`, `APP_REVIEW_MODERATOR_PASSWORD` (Moderation)

Ohne die sechs Secrets bricht „Publish (button)“ für iOS und macOS vor dem
Build ab. Das ist Absicht: Ohne Anmeldefelder meldet deliver an App Review,
dass kein Konto nötig sei. Die Pipeline gibt die Secrets nur einer Einreichung
mit, liest sie einmal und entfernt sie danach aus der Umgebung des Builds.

Zugangsdaten, die Adresse des Prüfservers und die Telefonnummer gehören nie in
`fastlane/metadata`. Das Repository ist öffentlich.

## Apple

Automatisch mit jedem „Publish (button)“:

- **Review-Hinweise** aus `ios/fastlane/metadata/review_information/notes.txt`
  (macOS: dieselbe Datei unter `macos/`). Die Release-Lane setzt die Adresse
  des Prüfservers für `{{REVIEW_SERVER}}` ein, das Mitglied in die
  Anmeldefelder und die Telefonnummer in die Kontaktdaten, und hängt das
  Moderationskonto an die Hinweise an.
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

  `REVIEW_SERVER` durch die Adresse des Prüfservers ersetzen:

  ```text
  Hinata is the app for a self-hosted server. On "Connect to your server", enter
  REVIEW_SERVER and tap Connect, then sign in. Report: the menu of an
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
  liegen. Prüfserver und Prüfkonten trägt man im Partner Center von Hand ein,
  nie in diese Datei. Actions, „Windows listing (screenshots)“ schiebt sie in die offene
  Einreichung, auch wenn die Bilder gleich bleiben.
