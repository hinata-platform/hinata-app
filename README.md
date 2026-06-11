# Hivora

Open-source, self-hosted project management — the **Flutter app** for the
[Hivora Server](../Hivora-Server). GPL-3.0, no user or board limits.

Runs on **Android, iOS, Web and macOS** from a single codebase, fully
responsive (golden-ratio derived breakpoints, no fixed pixel breakpoints) and
localized in **English (UK)** and **Deutsch (Deutschland)** via i18next.

## How it works

1. **Connect**: on first start the app asks for your server URL — it only
   continues once the server answers.
2. **Version gate**: the app compares its version with the server's
   `minAppVersion` on every start and forces an update when required.
3. **Setup wizard**: a fresh server is configured directly in the app
   (organization + first admin), unless the server was bootstrapped via
   `HIVORA_SETUP_*` environment variables.
4. **Onboarding**: a one-time illustrated tour of the key features
   (Projects, Time Tracking, Gantt, Timesheets, Agile Boards, Reports,
   Dashboards, Knowledge Base).
5. **Sign in**: local credentials, or SSO (OpenID Connect, OAuth 2.0, SAML,
   LDAP — e.g. Synology SSO). SSO returns to the app via the
   `hivora://auth-callback` deep link.

## Features

Dashboard (today tasks, completion, ranking, tracker) · Projects · Issues with
comments, attachments & time logging · Agile board with drag & drop · Gantt
timeline · Weekly timesheets · Reports · Knowledge base · Notifications ·
Settings (language, privacy policy link, app + server version) · Admin area
(SSO, e-mail-to-ticket, user management).

## Architecture

- **State**: bloc / flutter_bloc / hydrated_bloc / bloc_concurrency / replay_bloc
- **Routing**: go_router with auth-aware redirects
- **i18n**: i18next (`assets/i18n/{en,de}/common.json`)
- **Networking**: dio with automatic token refresh
- **Modals**: wolt_modal_sheet (responsive: sheet on phones, dialog on desktop)
- **Charts**: fl_chart

```text
lib/
  core/        theme, responsive system, i18n, api, models, blocs, router, widgets
  features/    connect, setup, onboarding, auth, shell, dashboard, projects,
               issues, board, gantt, timesheet, reports, knowledge,
               notifications, settings, admin
```

## Development

```bash
flutter pub get
flutter run
```

Useful commands:

```bash
flutter analyze && flutter test          # quality gate (CI runs the same)
dart run flutter_native_splash:create    # regenerate splash screens
dart run flutter_launcher_icons          # regenerate app icons
```

Start the backend locally as described in
[Hivora-Server/README.md](../Hivora-Server/README.md), then connect the app to
`http://localhost:8080` (Android emulator: `http://10.0.2.2:8080`).

## Releases (Fastlane + GitHub Actions)

Pushing a `v*` tag triggers [release.yml](.github/workflows/release.yml):

- **Android** → Play Store *internal* track (`android/fastlane`, lane `internal`)
- **iOS** → TestFlight (`ios/fastlane`, lane `beta`, signing via *match*)

Required repository secrets:

| Secret | Used for |
| --- | --- |
| `PLAY_JSON_KEY` | Play Console service account JSON |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` | Upload keystore |
| `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT` | App Store Connect API key |
| `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION` | fastlane match certificate repo |

Store compliance notes: bundle id is `hivora.asta.hn`; the privacy policy URL
shown in the app comes from the server (`HIVORA_PRIVACY_POLICY_URL`) and is
required for App Store / Play Store review and GDPR (DSGVO). The UI is
accessibility-minded (BFSG): scalable text, semantic widgets, sufficient
contrast on the pastel palette.

## License

GPL-3.0 — see [LICENSE](LICENSE).
