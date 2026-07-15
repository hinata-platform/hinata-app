# Datenschutzerklärung

*Stand: 15. Juli 2026*

Der Schutz Ihrer personenbezogenen Daten ist uns wichtig. Nachfolgend informieren wir Sie gemäß Art. 13 und 14 der Datenschutz-Grundverordnung (DSGVO) über die Datenverarbeitung im Zusammenhang mit der Nutzung der Anwendung Hinata („App").

**Wichtig — Geltungsbereich:** Diese Datenschutzerklärung gilt ausschließlich für die App selbst und die Art und Weise, wie die App mit einem von Ihnen gewählten Server kommuniziert. Hinata ist eine Client-Anwendung für selbst gehostete Server-Instanzen: Der Herausgeber der App betreibt **keine** eigene Server-Instanz und hat **keinen Zugriff** auf die Server, mit denen Sie die App verbinden. Für sämtliche serverseitige Datenverarbeitung ist allein der jeweilige Betreiber der Server-Instanz verantwortlich (siehe § 2).

## § 1 Verantwortlicher für die App

Verantwortlicher im Sinne des Art. 4 Nr. 7 DSGVO für die Bereitstellung der App (Vertrieb über die App-Stores bzw. als Web-Anwendung) und die in dieser Erklärung beschriebene Verarbeitung ist:

Rebar Ahmad
Weberstr. 58
47798 Krefeld
Deutschland
E-Mail: mail@ahmadre.com

Ein Datenschutzbeauftragter ist gesetzlich nicht bestellt.

## § 2 Rollenverteilung: App-Herausgeber und Instanzbetreiber

Hinata ist eine Anwendung zur Projekt- und Vorgangsverwaltung, die von Organisationen auf **eigener Infrastruktur selbst gehostet** wird (Self-Hosting). Die App verbindet sich ausschließlich mit der Server-Instanz, deren Adresse Sie oder Ihre Organisation eingeben.

- Der **App-Herausgeber** (§ 1) stellt lediglich die Anwendungssoftware bereit. Er betreibt keine Server-Instanz, speichert keine Konto- oder Inhaltsdaten und hat keinen Zugriff auf die Daten, die Sie über die App an eine Server-Instanz übermitteln.
- Der **Betreiber der jeweiligen Server-Instanz** (z. B. Ihre Organisation) ist alleiniger Verantwortlicher im Sinne der DSGVO für die gesamte serverseitige Datenverarbeitung — insbesondere für Konten, Inhalte (Projekte, Vorgänge, Kommentare, Anhänge, Zeiterfassung, Wissensdatenbank), Server-Protokolle, den E-Mail-Versand (der Betreiber konfiguriert seinen eigenen E-Mail-/SMTP-Anbieter) sowie die eingesetzte Speicher- und Hosting-Infrastruktur.

Für Auskünfte, Löschung und alle weiteren Betroffenenrechte hinsichtlich der auf einer Instanz gespeicherten Daten wenden Sie sich bitte an den Betreiber Ihrer Instanz; es gelten dessen Datenschutzhinweise.

## § 3 Datenverarbeitung durch die App auf Ihrem Gerät

Die App selbst verarbeitet Daten ausschließlich lokal auf Ihrem Gerät, soweit dies für ihre Funktion technisch erforderlich ist:

- die von Ihnen eingetragene(n) Serveradresse(n),
- Anmelde-Token (Access-/Refresh-Token) für die gewählte(n) Instanz(en),
- Anwendungseinstellungen (z. B. Sprache, Design, Benachrichtigungseinstellungen).

Diese Daten verbleiben auf Ihrem Gerät und werden nicht an den App-Herausgeber übermittelt. Die App verwendet **keine** Cookies oder vergleichbaren Technologien zu Analyse- oder Werbezwecken, bindet **keine** Tracking-Dienste ein und sendet **keine** Telemetrie an den App-Herausgeber. Rechtsgrundlage der lokalen Speicherung ist Art. 6 Abs. 1 lit. b DSGVO bzw. § 25 Abs. 2 TDDDG (technische Erforderlichkeit).

## § 4 Kommunikation mit der von Ihnen gewählten Server-Instanz

Alle Daten, die Sie in der App eingeben (z. B. Zugangsdaten, Inhalte, Kommentare, Dateien, Sprachnachrichten), überträgt die App unmittelbar und transportverschlüsselt (TLS/HTTPS) an die von Ihnen gewählte Server-Instanz. Der App-Herausgeber ist an dieser Übertragung nicht beteiligt und kann sie nicht einsehen. Verantwortlicher für die Verarbeitung dieser Daten ist ausschließlich der Betreiber der Instanz (§ 2).

## § 5 Push-Benachrichtigungen (Hinata Connect und Firebase Cloud Messaging)

Wenn Sie Push-Benachrichtigungen aktivieren, werden diese technisch über eine zentrale Relay-Komponente („Hinata Connect") zugestellt, die vom App-Herausgeber betrieben wird, sowie über den Dienst Firebase Cloud Messaging (FCM) der Google Ireland Limited bzw. Google LLC. Dabei verarbeitet der App-Herausgeber:

- eine geräte- bzw. installationsbezogene Push-Kennung (FCM-Token),
- den Inhalt der jeweiligen Benachrichtigung — ausschließlich transient zum Zweck der Zustellung; eine dauerhafte Speicherung der Benachrichtigungsinhalte durch den App-Herausgeber erfolgt nicht.

Rechtsgrundlage ist Art. 6 Abs. 1 lit. a DSGVO (Ihre Einwilligung durch Aktivierung der Push-Benachrichtigungen). Push-Benachrichtigungen sind optional; Sie können sie jederzeit in den Systemeinstellungen Ihres Geräts oder in den Benachrichtigungseinstellungen der App deaktivieren. Ohne Push-Benachrichtigungen findet keinerlei Datenverarbeitung durch den App-Herausgeber statt.

## § 6 Datenübermittlung in Drittländer

Bei der Nutzung von Firebase Cloud Messaging (§ 5) kann es zu einer Verarbeitung von Daten durch die Google LLC in den USA kommen. Die Google LLC ist unter dem EU-U.S. Data Privacy Framework zertifiziert; ergänzend werden Standardvertragsklauseln der Europäischen Kommission (Art. 46 Abs. 2 lit. c DSGVO) als geeignete Garantien herangezogen. Darüber hinaus findet durch den App-Herausgeber keine Drittlandübermittlung statt. Ob und wohin der Betreiber Ihrer Server-Instanz Daten übermittelt, entnehmen Sie bitte dessen Datenschutzhinweisen.

## § 7 Speicherdauer

Der App-Herausgeber speichert personenbezogene Daten nur, soweit und solange dies für die Push-Zustellung erforderlich ist (§ 5); Push-Kennungen werden gelöscht, wenn sie ungültig werden oder Sie Push-Benachrichtigungen deaktivieren. Die lokalen Daten auf Ihrem Gerät (§ 3) können Sie jederzeit selbst löschen, indem Sie die App-Daten löschen oder die App deinstallieren. Für die Speicherdauer serverseitiger Daten ist der jeweilige Instanzbetreiber verantwortlich.

## § 8 Ihre Rechte als betroffene Person

Ihnen stehen nach der DSGVO insbesondere die Rechte auf Auskunft (Art. 15), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung der Verarbeitung (Art. 18), Datenübertragbarkeit (Art. 20), Widerspruch gegen Verarbeitungen auf Grundlage von Art. 6 Abs. 1 lit. f DSGVO (Art. 21) sowie auf Widerruf erteilter Einwilligungen mit Wirkung für die Zukunft (Art. 7 Abs. 3) zu.

- Für die in dieser Erklärung beschriebene Verarbeitung (App, Push-Zustellung) richten Sie Ihre Anliegen an die in § 1 genannte Kontaktadresse.
- Für Konto- und Inhaltsdaten auf einer Server-Instanz ist der jeweilige Betreiber der richtige Ansprechpartner. Die App stellt hierfür — abhängig von der Instanz — Selbstbedienungsfunktionen bereit (z. B. Datenauskunft/-export nach Art. 15 DSGVO und Kontolöschung nach Art. 17 DSGVO direkt in der App); die Verarbeitung dieser Anfragen erfolgt durch die jeweilige Instanz.

Unbeschadet anderweitiger Rechtsbehelfe steht Ihnen gemäß Art. 77 DSGVO ein Beschwerderecht bei einer Datenschutz-Aufsichtsbehörde zu, insbesondere in dem Mitgliedstaat Ihres Aufenthaltsorts, Ihres Arbeitsplatzes oder des Orts des mutmaßlichen Verstoßes.

## § 9 Keine automatisierte Entscheidungsfindung

Eine ausschließlich automatisierte Entscheidungsfindung einschließlich Profiling im Sinne des Art. 22 DSGVO durch den App-Herausgeber findet nicht statt.

## § 10 Minderjährige

Die App richtet sich nicht an Kinder unter 16 Jahren. Personen unter 16 Jahren sollten die App nur mit Einwilligung der Sorgeberechtigten nutzen.

## § 11 Datensicherheit

Die App überträgt Daten ausschließlich transportverschlüsselt (TLS/HTTPS) und speichert Anmelde-Token in den geschützten Speicherbereichen des jeweiligen Betriebssystems. Für die Sicherheit der serverseitigen Verarbeitung ist der jeweilige Instanzbetreiber verantwortlich.

## § 12 Änderungen dieser Datenschutzerklärung

Wir passen diese Datenschutzerklärung an, wenn Änderungen der App oder der Rechtslage dies erfordern. Es gilt jeweils die zum Zeitpunkt Ihrer Nutzung abrufbare Fassung. Das Datum am Anfang dieser Erklärung gibt den Stand der aktuellen Fassung an. Hinweis: Der Betreiber Ihrer Server-Instanz kann diese Erklärung um eigene, instanzspezifische Datenschutzhinweise ergänzen bzw. ersetzen; maßgeblich für die serverseitige Verarbeitung sind stets die Hinweise des Betreibers.

## § 13 Kontakt

Bei Fragen zum Datenschutz in Bezug auf die App erreichen Sie uns unter: mail@ahmadre.com
