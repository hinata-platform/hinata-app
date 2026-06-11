# Changelog

All notable changes to the Hivora app are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-06-11

### Added
- Server-first startup flow: server URL entry, reachability check, forced
  update gate (`minAppVersion`), Rocket.Chat-style first-run setup wizard
- One-time illustrated onboarding covering the key features
- Authentication: local login with brute-force-aware error handling, SSO
  buttons (OIDC/OAuth2/SAML) via external browser and `hivora://auth-callback`
  deep link, automatic token refresh, session-expiry logout
- Responsive shell following the base design: pill top navigation on wide
  screens, bottom navigation + "More" sheet on phones; golden-ratio derived
  breakpoints, overflow-safe layouts
- Dashboard: Today Task pastel cards, Project Completed donut, Rank
  Performance, weekly Tracker bars
- Projects: pastel card grid + creation modal
- Issues: debounced search, list, detail with state transitions, comments,
  time logging, edit/delete; responsive wolt_modal_sheet forms
- Agile board: board/sprint selectors, WIP limits, drag & drop between columns
- Gantt: day-grid timeline with progress bars and tooltips
- Timesheet: weekly user × day matrix with totals
- Reports: state/priority/assignee distribution and time-per-activity donuts
- Knowledge base: hierarchical article tree, reader and Markdown editor
- Notifications list with unread markers and deep links
- Settings: language switch (EN/DE via i18next), privacy policy link from the
  server, app + server version display, logout
- Admin area: runtime SSO configuration (OIDC, OAuth2, SAML, LDAP, Kerberos,
  CAS), e-mail-to-ticket (IMAP) settings, user management
- Theming per base design (pastel glassmorphism, navy primary), generated
  native splash screens and launcher icons, bundle id `hivora.asta.hn`
- State management with bloc/hydrated_bloc, routing with go_router,
  CI (analyze, test, Android/Web builds) and Fastlane store pipelines
