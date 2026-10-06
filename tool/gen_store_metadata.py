#!/usr/bin/env python3
"""Generate all App Store / Mac App Store / Google Play metadata files that
Fastlane `deliver` (iOS+macOS) and `supply` (Android) upload.

Single source of truth for the store copy (EN-US + DE-DE), so the localized
listings stay in sync. Re-run after editing the copy below:

    python3 tool/gen_store_metadata.py

Length limits enforced (the script aborts if any field is over budget):
  Apple  name<=30 subtitle<=30 keywords<=100 promo<=170 desc<=4000 notes<=4000
  Play   title<=30 short<=80 full<=4000 changelog<=500

Output layout:
  ios/fastlane/metadata/            (app-level: copyright, categories)
  ios/fastlane/metadata/<loc>/      (per-locale: name, subtitle, description, ...)
  ios/fastlane/metadata/review_information/
  macos/fastlane/metadata/...       (mirror; description tuned for desktop)
  android/fastlane/metadata/android/<loc>/  (title, descriptions, changelogs/<code>.txt)
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VERSION = "10.4.1"
ANDROID_VERSION_CODE = 89          # pubspec 10.4.1+89
COPYRIGHT = "© 2026 - Rebar Ahmad"
MARKETING_URL = "https://hinata.ahmadre.com"
SUPPORT_URL = "https://hinata.ahmadre.com/en/terms-of-service.html#16-contact"
PRIVACY_URL = "https://hinata.ahmadre.com/en/privacy-policy.html"

# Apple locale codes are en-US / de-DE; Play uses the same here.
APPLE_LOCALES = {"en": "en-US", "de": "de-DE"}
PLAY_LOCALES = {"en": "en-US", "de": "de-DE"}

# ---------------------------------------------------------------------------
# COPY  (edit here)
# ---------------------------------------------------------------------------

NAME = {"en": "hinata", "de": "hinata"}
# The Mac App Store record carries the capitalised name.
MAC_NAME = {"en": "Hinata", "de": "Hinata"}

SUBTITLE = {
    "en": "Self-hosted project tracking",
    "de": "Projekte auf deinem Server",
}

KEYWORDS = {
    "en": "project management,issue tracker,kanban,scrum,sprint,gantt,time tracking,timesheet,self-hosted,wiki",
    "de": "Projektmanagement,Vorgänge,Kanban,Scrum,Sprint,Gantt,Zeiterfassung,Stundenzettel,selbst gehostet",
}

PROMO = {
    "en": "Boards, sprints, Gantt, time tracking, absences and a wiki for your team, on a Hinata Server you run yourself. There is no per-user price and no limit on boards.",
    "de": "Boards, Sprints, Gantt, Zeiterfassung, Abwesenheiten und ein Wiki für dein Team, auf einem Hinata-Server, den du selbst betreibst. Es gibt keinen Preis pro Nutzer.",
}

# Play short description (<=80)
SHORT = {
    "en": "Plan projects, run sprints and track time on your own Hinata Server.",
    "de": "Projekte planen, Sprints führen und Zeiten erfassen auf deinem Hinata-Server.",
}

# Full description (Apple description.txt / Play full_description.txt).
# {platform_note} is filled per platform (mac gets a desktop line).
DESCRIPTION = {
    "en": """Hinata is an open-source app for planning projects and tracking issues. It connects to a Hinata Server that you or your organization run, so your team's work stays on your own infrastructure. There is no per-user price and no limit on boards.

The same app runs on phones, tablets and computers, fits its layout to the screen and has a light and a dark theme. It speaks English, German, Chinese, Hindi, Spanish, Japanese, French, Russian and Arabic, and lays out right to left in Arabic.

PLANNING AND BOARDS
• Scrum and Kanban boards: drag cards between columns, set WIP limits, group the board by epic, assignee or project
• Board, backlog and timeline views of the same work
• Sprints with capacity, story points, burndown and velocity
• Issues in a hierarchy from epic to story to sub-task, with dependencies and labels. You can watch, clone, archive or move them to another project
• Print an issue, or export it as PDF, Excel, Word or XML
• Gantt chart with dependencies, milestones and the critical path
• Project templates: copy a project and set deadlines relative to the project's date, in calendar or working days

TIME AND ABSENCES
• A timer that works as a stopwatch, a countdown or a Pomodoro
• Log time in a list, a calendar or a weekly timesheet, and hand in your timesheet for approval
• Request time off, have it approved and see who is away in a shared team calendar
• Working hours, public holidays and leave balances in one place
• Time reports with a summary, single entries and workload, plus CSV import and export

WORKING TOGETHER
• Comments with replies, emoji reactions and voice messages
• Attach files, photos and videos and open them in a full-screen viewer
• A knowledge base with spaces, sub-pages and Markdown articles. Type @ to link an issue, an article or a colleague
• Project reports with burndown and breakdowns by state, priority and assignee, exported as PDF, CSV or JSON
• A dashboard you arrange yourself, and a weekly summary of what your team finished
• A command palette that searches projects, issues, people and articles
• Notifications in the app, by e-mail and as push for assignments, @mentions and due dates. You choose the days and hours when e-mail and push may reach you
• Git integration with GitHub, GitLab and Bitbucket

FOR ORGANIZATIONS
• Projects and teams with their own workflows, keys and members
• An organization admin role for working hours, approvals, absences, holidays and billing
• Sign in with a password and optional two-factor authentication (TOTP), or through SSO with OpenID Connect, OAuth 2.0, SAML or LDAP
• Self-registration with e-mail verification, and password reset
• Save several servers and switch between them. Each one keeps its own secure session

ACCESSIBILITY
Text colors meet WCAG contrast, touch targets are large and controls have labels for screen readers. Nothing gets cut off at twice the normal text size.

YOUR DATA STAYS ON YOUR SERVER
Hinata collects nothing for itself. Everything you create is stored on the Hinata Server you connect to. Push notifications go through Firebase Cloud Messaging and use only a device token. The app has no tracking and no analytics.
{platform_note}
You need a Hinata Server to sign in. hinata.ahmadre.com explains how to host one yourself.

PERMISSIONS AND WHY HINATA ASKS FOR THEM
• Notifications: assignments, @mentions, replies to your comments and due dates
• Microphone: voice comments, and sound in videos you attach
• Camera and photos: take or pick photos and videos to attach to issues
Hinata asks for each permission the first time you use the feature that needs it.""",
    "de": """Hinata ist eine quelloffene App, mit der du Projekte planst und Vorgänge verfolgst. Sie verbindet sich mit einem Hinata-Server, den du oder deine Organisation betreibt. So bleibt die Arbeit deines Teams auf eurer eigenen Infrastruktur. Es gibt keinen Preis pro Nutzer und keine Grenze bei den Boards.

Die App läuft auf Smartphone, Tablet und Computer, im hellen oder dunklen Design. Sprachen: Deutsch, Englisch, Chinesisch, Hindi, Spanisch, Japanisch, Französisch, Russisch und Arabisch (von rechts nach links).

PLANUNG UND BOARDS
• Scrum- und Kanban-Boards: Karten zwischen Spalten ziehen, WIP-Limits setzen, nach Epic, zuständiger Person oder Projekt gruppieren
• Board, Backlog und Zeitleiste als Ansichten derselben Arbeit
• Sprints mit Kapazität, Story Points, Burndown und Velocity
• Vorgänge in einer Hierarchie vom Epic über die Story bis zur Unteraufgabe, mit Abhängigkeiten und Labels. Beobachten, klonen, archivieren oder in ein anderes Projekt verschieben
• Einen Vorgang drucken oder als PDF, Excel, Word oder XML exportieren
• Gantt-Diagramm mit Abhängigkeiten, Meilensteinen und kritischem Pfad
• Projektvorlagen: ein Projekt kopieren und Fristen relativ zum Projektdatum setzen, in Kalender- oder Arbeitstagen

ZEIT UND ABWESENHEITEN
• Ein Timer als Stoppuhr, Countdown oder Pomodoro
• Zeiten in Liste, Kalender oder Stundenzettel erfassen und den Stundenzettel zur Freigabe einreichen
• Urlaub beantragen, genehmigen lassen und im Teamkalender sehen, wer abwesend ist
• Arbeitszeiten, Feiertage und Urlaubskonten an einem Ort
• Zeitberichte mit Übersicht, Einträgen und Auslastung, Import und Export als CSV

ZUSAMMENARBEIT
• Kommentare mit Antworten, Emoji-Reaktionen und Sprachnachrichten
• Dateien, Fotos und Videos anhängen und im Vollbild ansehen
• Eine Wissensdatenbank mit Bereichen, Unterseiten und Markdown-Artikeln. Mit @ verlinkst du einen Vorgang, einen Artikel oder eine Kollegin
• Projektberichte mit Burndown und Auswertungen nach Status, Priorität und zuständiger Person, Export als PDF, CSV oder JSON
• Ein Dashboard, das du selbst zusammenstellst, und eine Wochenübersicht
• Eine Befehlspalette, die Projekte, Vorgänge, Personen und Artikel durchsucht
• Benachrichtigungen in der App, per E-Mail und als Push für Zuweisungen, @Erwähnungen und Fälligkeiten. Du bestimmst, an welchen Tagen und zu welchen Zeiten E-Mails und Push kommen
• Git-Anbindung an GitHub, GitLab und Bitbucket

FÜR ORGANISATIONEN
• Projekte und Teams mit eigenen Workflows, Schlüsseln und Mitgliedern
• Eine Rolle für Organisations-Admins: Arbeitszeiten, Freigaben, Abwesenheiten, Feiertage und Abrechnung
• Anmeldung mit Passwort und optionaler Zwei-Faktor-Authentifizierung (TOTP) oder per SSO mit OpenID Connect, OAuth 2.0, SAML oder LDAP
• Selbst registrieren mit E-Mail-Bestätigung, Passwort zurücksetzen
• Mehrere Server speichern und wechseln, jeder mit eigener sicherer Sitzung

BARRIEREFREIHEIT
Textfarben erfüllen die WCAG-Kontrastwerte, Tippflächen sind groß und Bedienelemente haben Beschriftungen für Screenreader. Auch bei doppelter Schriftgröße wird nichts abgeschnitten.

DEINE DATEN BLEIBEN AUF DEINEM SERVER
Hinata sammelt selbst nichts. Alles, was du anlegst, liegt auf dem Hinata-Server, mit dem du dich verbindest. Push-Benachrichtigungen laufen über Firebase Cloud Messaging und nutzen nur ein Geräte-Token. Die App hat kein Tracking und keine Analyse.
{platform_note}
Zum Anmelden brauchst du einen Hinata-Server. Wie du selbst einen betreibst, steht auf hinata.ahmadre.com.

BERECHTIGUNGEN UND WOFÜR HINATA SIE BRAUCHT
• Benachrichtigungen: Zuweisungen, @Erwähnungen, Antworten auf deine Kommentare und Fälligkeiten
• Mikrofon: Sprachkommentare und Ton in Videos, die du anhängst
• Kamera und Fotos: Fotos und Videos aufnehmen oder auswählen, um sie an Vorgänge anzuhängen
Hinata fragt jede Berechtigung erst, wenn du die Funktion zum ersten Mal nutzt.""",
}

PLATFORM_NOTE = {
    ("en", "mac"): "\nOn the Mac, Hinata is a native desktop app that runs in the App Sandbox.\n",
    ("de", "mac"): "\nAuf dem Mac ist Hinata eine native Desktop-App, die in der App-Sandbox läuft.\n",
    ("en", "ios"): "",
    ("de", "ios"): "",
}

# What's new (Apple release_notes.txt / Play changelogs/<code>.txt).
# Apple allows up to 4000; Play changelog up to 500 -> keep this <=500 so both share it.
RELEASE_NOTES = {
    "en": """• Better accessibility: stronger contrast, larger touch targets, screen reader labels
• Text stays readable at twice the size, nothing gets cut off
• Calmer type with one consistent scale across the app
• Settings, organisation and admin pages share one layout and show one section at a time
• Report sick days straight from the absences page
• Smoother glass effects and several smaller fixes""",
    "de": """• Bessere Barrierefreiheit: stärkere Kontraste, größere Tippflächen, Beschriftungen für Screenreader
• Text bleibt auch in doppelter Größe lesbar und wird nicht abgeschnitten
• Ruhigere Schrift mit einer einheitlichen Größenskala
• Einstellungen, Organisation und Adminbereich haben ein gemeinsames Layout mit einem Abschnitt pro Ansicht
• Krankmeldung direkt aus den Abwesenheiten
• Flüssigere Glaseffekte und mehrere kleinere Korrekturen""",
}

# Apple App Review sign-in (the app is server-first: reviewers must connect to a
# reachable demo server, then log in). See the Manual Steps Report — the demo
# server URL below MUST be a reviewer-reachable instance seeded with demo data.
REVIEW = {
    "first_name": "Rebar",
    "last_name": "Ahmad",
    "email_address": "mail@ahmadre.com",
    "phone_number": "+4917664704392",   # TODO: real reachable number for review
    "demo_user": "4hm4dr3",
    "demo_password": "w%D0T63u]P'VWYOLIYdB$oRu0OC-\\nNB",
    "notes": """Hinata is a CLIENT for a self-hosted Hinata Server; it has no built-in backend.

TO REVIEW:
1. Launch the app. On the first screen ("Connect"), enter the demo server URL:
      https://api.track.asta.hn        <-- please confirm this is reachable
2. Tap Continue, then sign in on the Login screen with:
      Username: 4hm4dr3
      Password: w%D0T63u]P'VWYOLIYdB$oRu0OC-\\nNB
3. You now have full access to a demo organization (projects, boards, sprints,
   issues, reports, knowledge base).

Notes:
- SSO buttons open an external browser and return via the hinata://auth-callback
  deep link; local login above is sufficient to review all features.
- The app bakes in no server URL by design (self-hosting), which is why the demo
  server must be entered on first launch.""",
}

# ---------------------------------------------------------------------------
# WRITER
# ---------------------------------------------------------------------------
WRITTEN: list[str] = []
LIMITS = {"name": 30, "subtitle": 30, "keywords": 100, "promo": 170,
          "title": 30, "short": 80, "desc": 4000, "notes": 4000,
          "changelog": 500}


def _check(kind: str, text: str) -> str:
    lim = LIMITS.get(kind)
    if lim is not None and len(text) > lim:
        sys.exit(f"✗ {kind} too long: {len(text)} > {lim}\n   {text[:80]}...")
    return text


def w(path: str, text: str, kind: str | None = None):
    if kind:
        _check(kind, text)
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    # Leave a file alone when only its trailing newline differs, so a re-run
    # does not churn files that were saved without one.
    if os.path.exists(full):
        with open(full, encoding="utf-8") as f:
            if f.read().rstrip("\n") == text.rstrip("\n"):
                WRITTEN.append(path)
                return
    with open(full, "w", encoding="utf-8") as f:
        f.write(text if text.endswith("\n") else text + "\n")
    WRITTEN.append(path)


def apple(base: str, platform: str):
    """base = 'ios' or 'macos'; platform = 'ios' or 'mac' (for platform note)."""
    md = f"{base}/fastlane/metadata"
    w(f"{md}/copyright.txt", COPYRIGHT)
    w(f"{md}/primary_category.txt", "PRODUCTIVITY")
    w(f"{md}/secondary_category.txt", "BUSINESS")
    for lang, loc in APPLE_LOCALES.items():
        names = MAC_NAME if platform == "mac" else NAME
        w(f"{md}/{loc}/name.txt", names[lang], "name")
        w(f"{md}/{loc}/subtitle.txt", SUBTITLE[lang], "subtitle")
        w(f"{md}/{loc}/keywords.txt", KEYWORDS[lang], "keywords")
        w(f"{md}/{loc}/promotional_text.txt", PROMO[lang], "promo")
        note = PLATFORM_NOTE[(lang, platform)]
        w(f"{md}/{loc}/description.txt",
          DESCRIPTION[lang].format(platform_note=note), "desc")
        w(f"{md}/{loc}/release_notes.txt", RELEASE_NOTES[lang], "notes")
        w(f"{md}/{loc}/marketing_url.txt", MARKETING_URL)
        w(f"{md}/{loc}/support_url.txt", SUPPORT_URL)
        w(f"{md}/{loc}/privacy_url.txt", PRIVACY_URL)
    # App review information
    ri = f"{md}/review_information"
    for k in ("first_name", "last_name", "email_address", "phone_number",
              "demo_user", "demo_password", "notes"):
        w(f"{ri}/{k}.txt", REVIEW[k])


def play():
    md = "android/fastlane/metadata/android"
    for lang, loc in PLAY_LOCALES.items():
        w(f"{md}/{loc}/title.txt", NAME[lang], "title")
        w(f"{md}/{loc}/short_description.txt", SHORT[lang], "short")
        w(f"{md}/{loc}/full_description.txt",
          DESCRIPTION[lang].format(platform_note=PLATFORM_NOTE[(lang, "ios")]), "desc")
        w(f"{md}/{loc}/changelogs/{ANDROID_VERSION_CODE}.txt",
          RELEASE_NOTES[lang], "changelog")


def main():
    apple("ios", "ios")
    apple("macos", "mac")
    play()
    print(f"✓ wrote {len(WRITTEN)} metadata files (v{VERSION}, "
          f"Android versionCode {ANDROID_VERSION_CODE})")
    for p in WRITTEN:
        print("   ", p)


if __name__ == "__main__":
    main()
