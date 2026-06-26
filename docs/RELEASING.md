# Releasing Hinata

Two independent release tracks. They do **not** depend on each other — you can
ship one without the other.

| Track | What it ships | Trigger |
|-------|---------------|---------|
| **Native apps** (Android / iOS / macOS) | Play Store (internal) + TestFlight | push a `vX.Y.Z` **git tag** |
| **Web + API server** | `track.asta.hn` + `api.track.asta.hn` | push to `main` → pull image → recreate containers |

---

## 1. Day-to-day: how to commit

Just commit to `main` with a [Conventional Commit](https://www.conventionalcommits.org) message:

```
feat(board): swimlane grouping by epic
fix(issues): keep resolvedAt in sync with project states
chore(deps): bump go_router to 16.1
```

Prefixes used here: `feat` · `fix` · `chore` · `refactor` · `ci` · `docs` · `release` · `revert`.

Pushing to `main` runs **CI** (tests + builds the web/server Docker images). It
does **NOT** release the native apps — that only happens on a `v*` tag (below).

---

## 2. Native app release (Android + iOS + macOS)

### The easy way (recommended)

```bash
tool/release.sh patch     # 1.0.2 -> 1.0.3  (bug fixes)
tool/release.sh minor     # 1.0.2 -> 1.1.0  (new features)
tool/release.sh major     # 1.0.2 -> 2.0.0  (breaking changes)
tool/release.sh 1.4.0     # set the version name explicitly
```

It bumps `pubspec.yaml`, commits, pushes `main`, and pushes the `vX.Y.Z` tag.
The **Store Release** GitHub workflow then builds and uploads all three apps.

### The manual way (what the script does)

1. Edit `pubspec.yaml` → `version: X.Y.Z+B`
   - **`X.Y.Z`** = version name (what users see).
   - **`+B`** = build number. **Android `versionCode` = this number** and it
     **must be higher than the last uploaded one**, or Play rejects the build.
     Always increment it.
2. `git commit -am "release: X.Y.Z+B"` and `git push origin main`
3. `git tag vX.Y.Z && git push origin vX.Y.Z`

### What happens after the tag is pushed

`.github/workflows/release.yml` runs three jobs:
- **Android → Play Store (internal track, as a _draft_)** — uses the pubspec
  versionCode.
- **iOS → TestFlight** — build number = latest TestFlight build + 1 (automatic).
- **macOS → TestFlight** — same automatic build number.

Watch progress: <https://github.com/hinata-platform/hinata-app/actions>

### After the build succeeds — the manual finishing steps

These can't be automated without store credentials / review, so they stay manual:
- **Android:** open Play Console → the internal release is a **draft** → review &
  roll out. To push internal → production later: `cd android && bundle exec fastlane promote`.
- **iOS / macOS:** the build lands in **TestFlight**. Add it to a test group, or
  submit for App Store / Mac App Store review from App Store Connect.
- **Screenshots / store listing:** uploaded by hand in each console
  (the marketing images live in `docs/screenshots/ios/`, 1242×2688 for the 6.5" slot).

### Prerequisites (already set up — for reference)
All signing secrets live in GitHub Actions secrets (Play service account, Apple
App Store Connect API key, fastlane `match`). Nothing to do per release.

---

## 3. Web + server release

Pushing to `main` builds the images. To make them live on the NAS, recreate
**only** the app + server containers (never the DB/storage):

```bash
docker compose -p hinata pull hinata-server hinata-app
docker compose -p hinata up -d --no-deps --force-recreate hinata-server hinata-app
```

(`--no-deps` is what keeps Mongo + MinIO online.) Env-only changes: edit the
stack env in Portainer and redeploy the stack.

---

## 4. Quick reference

```bash
# native apps
tool/release.sh patch

# web + server (on the NAS)
docker compose -p hinata pull hinata-server hinata-app
docker compose -p hinata up -d --no-deps --force-recreate hinata-server hinata-app
```
