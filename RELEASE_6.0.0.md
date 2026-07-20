# Hinata 6.0.0 — Store Release Handover

**Version:** `6.0.0` · Android **versionCode 63** (`6.0.0+63`) · Copyright **© 2026 - Rebar Ahmad**
**Prepared:** 2026-07-20 · Bundle id `com.ahmadre.hinata` (ASC app id 6781889251)

The **Release button** (`Actions → Release (button) → version 6.0.0 → Run`) pushes the
`v6.0.0` tag → the *Store Release* workflow builds & uploads **binaries + metadata + screenshots**
to all three stores as **drafts** (nothing is auto-submitted). You then review & submit.

---

## ✅ What CI does automatically (nothing for you to do)

| Store | Lane | Uploads |
|---|---|---|
| **Google Play** (internal, draft) | `android internal` | signed AAB · title · short/full description · localized changelog (`63.txt`) · 512 icon · 1024×500 feature graphic · 6 phone + 6 10″-tablet screenshots (en-US, de-DE) |
| **App Store** (draft, not submitted) | `ios release` | signed IPA · name · subtitle · keywords · promo text · description · what's-new · marketing/support/privacy URLs · copyright · categories · App Review sign-in · 6 iPhone 6.9″ + 6 iPad 13″ screenshots (en-US, de-DE) |
| **Mac App Store** (draft, not submitted) | `macos release` | signed .pkg · macOS listing (same fields) · 6 MacBook 2880×1800 screenshots (en-US, de-DE) |

All metadata is versioned in the repo:
- `ios/fastlane/metadata/` · `macos/fastlane/metadata/` · `android/fastlane/metadata/android/`
- Screenshots: `ios/fastlane/screenshots/en-US/` · `macos/fastlane/screenshots/en-US/` ·
  `android/fastlane/metadata/android/en-US/images/{phoneScreenshots,tenInchScreenshots}`
- Copy is regenerated from `tool/gen_store_metadata.py`; screenshots from `tool/capture_store.py`
  + `tool/store_compose.py` (native captures, Aurora-Hive framed).
- Export compliance: `ITSAppUsesNonExemptEncryption=false` in both Info.plists → **App-Verschlüsselung: Nein** auto-answered.

---

## 🔧 Manual steps you MUST do in the consoles (no API covers these)

### App Store Connect (iOS + macOS)
1. **App Privacy "nutrition labels"** — *App Store Connect → App Privacy*. Declare, per
   `release/permissions.yaml`:
   - *Identifiers → Device ID* → **App Functionality** (FCM push token, not used for tracking).
   - *User Content → Photos/Videos, Audio, Other files* → **App Functionality** (stored on the user's own server).
   - Everything: **Not used to track you**, **Not linked to identity**.
2. **App Review sign-in** — the review-info in `ios/fastlane/metadata/review_information/` points reviewers to
   `https://demo.hinata.ahmadre.com` + `admin / hinata-demo-2026`. **⚠ Confirm that demo server is
   reachable and seeded**, or update the URL — Hinata needs a server to log in, so reviewers WILL be
   blocked without one. (Phone number in `phone_number.txt` is a placeholder — set a real one.)
3. **Age rating** questionnaire (once) → 4+.
4. Attach the processed build to the version, then **Submit for Review** (iOS and macOS separately).

### Google Play Console
1. **Data safety form** — from `release/permissions.yaml`: Device IDs (shared w/ Firebase for push,
   not for tracking) · Photos/Videos, Audio, Files (collected, sent only to the user's own server).
2. **App content**: content rating questionnaire, target audience, ads = No, government app = No.
3. **App category** (Productivity) + contact details + privacy policy URL
   (`https://hinata.ahmadre.com/en/privacy-policy.html`).
4. First run lands on the **internal testing** track as a **draft** — add testers, then promote
   internal → production when ready (`fastlane android promote`, or in the console).
5. Confirm the **Play App Signing SHA-256** is in `deploy/well-known/assetlinks.json` (deep links).

---

## ⚠ Notes / follow-ups
- **Android 10″ tablet frame** = the iPad frame (`tool/frames/android_tablet.png` is a copy of
  `ipad.png`). The tablet shots are correct Play size (2560×1600) and content, but drop in a real
  Pixel-tablet frame later if you want Android hardware in the frame.
- **iPad shots are LIGHT theme**, iPhone/macOS/Android are DARK — an intentional showcase of both
  themes across the listing.
- **16 KB page size**: enforced by the existing CI config (forced Rust source build + NDK r28 +
  `super_native_extensions`/`shared_preferences` bumps). Verify on the built AAB with
  `bash <skill>/scripts/check_16kb_alignment.sh <app.aab>` if desired.
- **Permission transparency**: the store descriptions list the user-facing runtime permissions
  (notifications, microphone, camera/photos). Always-on entitlements (Keychain, network client,
  associated domains) are intentionally not listed as store "permissions".
- **de-DE screenshots**: only en-US screenshots were generated (per request). de-DE reuses en-US
  images (Apple/Play fall back automatically); regenerate localized shots with
  `--dart-define`/locale if you want German UI in the shots.
