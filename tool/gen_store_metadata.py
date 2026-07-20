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
  android/fastlane/metadata/android/<loc>/  (title, descriptions, changelogs/63.txt)
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

VERSION = "6.0.0"
ANDROID_VERSION_CODE = 63          # pubspec 5.1.0+62 -> release button -> 6.0.0+63
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

NAME = {"en": "Hinata", "de": "Hinata"}

SUBTITLE = {
    "en": "Self-hosted project tracker",
    "de": "Projekte, selbst gehostet",
}

KEYWORDS = {
    "en": "project management,issue tracker,kanban,scrum,sprint,agile,gantt,backlog,self-hosted,tasks",
    "de": "Projektmanagement,Vorgänge,Kanban,Scrum,Sprint,Agile,Gantt,Backlog,self-hosted,Aufgaben",
}

PROMO = {
    "en": "Your own project HQ — boards, sprints, Gantt, reports, a wiki and threaded comments, all served by the Hinata Server you host. No user or board limits, ever.",
    "de": "Deine eigene Projektzentrale — Boards, Sprints, Gantt, Berichte, Wiki und Kommentare, auf deinem eigenen Hinata-Server. Ganz ohne Nutzer- oder Board-Limit.",
}

# Play short description (<=80)
SHORT = {
    "en": "Self-hosted project & issue tracking: boards, sprints, Gantt, reports & wiki.",
    "de": "Projekte & Vorgänge, selbst gehostet: Boards, Sprints, Gantt, Berichte & Wiki.",
}

# Full description (Apple description.txt / Play full_description.txt).
# {platform_note} is filled per platform (mac gets a desktop line).
DESCRIPTION = {
    "en": """Hinata is an open-source, self-hosted project- and issue-tracking client. You connect it to your own Hinata Server, so your team's work stays on infrastructure you control — with no per-user pricing and no board limits.

One app, every screen: phone, tablet and desktop share a single, fully responsive interface that adapts through golden-ratio breakpoints, in a light or dark theme.

WHAT YOU CAN DO
• Agile boards — drag & drop across columns, WIP limits, and Board, Backlog and Timeline views
• Sprints — plan, run and review with capacity, story points and burndown
• Issues — Epic → Story → Sub-task hierarchy, dependencies, labels and archiving
• Gantt & Timeline — start/due dates, dependencies and live progress
• Reports — burndown, velocity, cycle time and distribution charts
• Timesheets — weekly time tracking by activity
• Comments — threaded replies, emoji reactions and voice notes, updating live
• Attachments — drag-and-drop files, photos and videos with a glass lightbox
• Knowledge base — a built-in, hierarchical Markdown wiki with smart links
• Command palette — ⌘K global search across everything
• Notifications — in-app, e-mail and push for assignments, @mentions and due dates

BUILT FOR TEAMS
• Projects & teams with per-project workflows, keys and members
• Sign in with local credentials and optional two-factor (TOTP), or SSO (OpenID Connect, OAuth 2.0, SAML, LDAP)
• Self-registration with e-mail verification, and forgot-password
• Multi-server: save several servers and switch between them, each with its own secure session

YOUR DATA, YOUR SERVER
Hinata collects nothing for itself. All content lives on the Hinata Server you connect to. Push notifications are delivered through Firebase Cloud Messaging using only a device token — no tracking, no analytics.
{platform_note}
Requires a Hinata Server to sign in. Learn how to self-host at hinata.ahmadre.com.

PERMISSIONS & WHY WE NEED THEM
• Notifications — assignments, @mentions, comment replies and due dates
• Microphone — voice comments and sound for videos you attach
• Camera & Photos — take or pick photos/videos to attach to issues
We ask for each permission only when you first use the feature that needs it.""",
    "de": """Hinata ist ein quelloffener, selbst gehosteter Client für Projekt- und Vorgangsverwaltung. Du verbindest ihn mit deinem eigenen Hinata-Server – so bleibt die Arbeit deines Teams auf einer Infrastruktur, die du kontrollierst: ohne Preis pro Nutzer und ohne Board-Limit.

Eine App für jeden Bildschirm: Smartphone, Tablet und Desktop teilen sich eine vollständig responsive Oberfläche, die sich über Breakpoints nach dem Goldenen Schnitt anpasst – im hellen oder dunklen Design.

DAS KANNST DU TUN
• Agile Boards – Drag & Drop über Spalten, WIP-Limits sowie Board-, Backlog- und Timeline-Ansicht
• Sprints – planen, durchführen und auswerten mit Kapazität, Story Points und Burndown
• Vorgänge – Hierarchie aus Epic → Story → Unteraufgabe, Abhängigkeiten, Labels und Archivierung
• Gantt & Timeline – Start-/Fälligkeitsdaten, Abhängigkeiten und Live-Fortschritt
• Berichte – Burndown, Velocity, Durchlaufzeit und Verteilungen
• Zeiterfassung – wöchentliche Zeiten je Aktivität
• Kommentare – Antwort-Threads, Emoji-Reaktionen und Sprachnotizen, live aktualisiert
• Anhänge – Dateien, Fotos und Videos per Drag & Drop mit Glass-Lightbox
• Wissensdatenbank – ein integriertes, hierarchisches Markdown-Wiki mit Smart Links
• Befehlspalette – ⌘K-Suche über alles
• Benachrichtigungen – in der App, per E-Mail und Push für Zuweisungen, @Erwähnungen und Fälligkeiten

FÜR TEAMS GEMACHT
• Projekte & Teams mit projektbezogenen Workflows, Schlüsseln und Mitgliedern
• Anmeldung mit lokalen Zugangsdaten und optionaler Zwei-Faktor-Authentifizierung (TOTP) oder SSO (OpenID Connect, OAuth 2.0, SAML, LDAP)
• Selbstregistrierung mit E-Mail-Bestätigung und Passwort-vergessen
• Multi-Server: mehrere Server speichern und wechseln, jeder mit eigener sicherer Sitzung

DEINE DATEN, DEIN SERVER
Hinata sammelt selbst nichts. Alle Inhalte liegen auf dem Hinata-Server, mit dem du dich verbindest. Push-Benachrichtigungen werden über Firebase Cloud Messaging nur mit einem Geräte-Token zugestellt – kein Tracking, keine Analyse.
{platform_note}
Zur Anmeldung wird ein Hinata-Server benötigt. Wie du selbst hostest, erfährst du auf hinata.ahmadre.com.

BERECHTIGUNGEN & WARUM WIR SIE BENÖTIGEN
• Benachrichtigungen – Zuweisungen, @Erwähnungen, Kommentar-Antworten und Fälligkeiten
• Mikrofon – Sprachkommentare und Ton für Videos, die du anhängst
• Kamera & Fotos – Fotos/Videos aufnehmen oder auswählen, um sie an Vorgänge anzuhängen
Wir fragen jede Berechtigung erst ab, wenn du die zugehörige Funktion zum ersten Mal nutzt.""",
}

PLATFORM_NOTE = {
    ("en", "mac"): "\nOn the Mac, Hinata runs as a native, sandboxed desktop app with the same full feature set.\n",
    ("de", "mac"): "\nAuf dem Mac läuft Hinata als native, sandboxed Desktop-App mit dem vollen Funktionsumfang.\n",
    ("en", "ios"): "",
    ("de", "ios"): "",
}

# What's new (Apple release_notes.txt / Play changelogs/<code>.txt).
# Apple allows up to 4000; Play changelog up to 500 -> keep this <=500 so both share it.
RELEASE_NOTES = {
    "en": """Hinata 6.0 — a major release.

• Faster, smoother navigation and lists across the whole app
• Rebuilt issue filtering and type-ahead search
• Refreshed admin area and sign-in screens
• Voice comments, emoji reactions and threaded replies
• Reliability fixes for live updates, attachments and notifications

Thanks for using Hinata! Feedback: hinata.ahmadre.com""",
    "de": """Hinata 6.0 — ein großes Update.

• Schnellere, flüssigere Navigation und Listen in der ganzen App
• Neu gebaute Vorgangs-Filter und Type-ahead-Suche
• Überarbeiteter Admin-Bereich und Anmeldebildschirme
• Sprachkommentare, Emoji-Reaktionen und Antwort-Threads
• Stabilitätsfixes für Live-Updates, Anhänge und Benachrichtigungen

Danke, dass du Hinata nutzt! Feedback: hinata.ahmadre.com""",
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
    "demo_password": "w%D0T63u]P'VWYOLIYdB$oRu0OC-\nNB",
    "notes": """Hinata is a CLIENT for a self-hosted Hinata Server; it has no built-in backend.

TO REVIEW:
1. Launch the app. On the first screen ("Connect"), enter the demo server URL:
      https://api.track.asta.hn        <-- please confirm this is reachable
2. Tap Continue, then sign in on the Login screen with:
      Username: 4hm4dr3
      Password: w%D0T63u]P'VWYOLIYdB$oRu0OC-
NB
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
        w(f"{md}/{loc}/name.txt", NAME[lang], "name")
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
