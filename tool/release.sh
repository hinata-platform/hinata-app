#!/usr/bin/env bash
# One-command store release for the native apps (Android + iOS + macOS).
#
# Bumps the pubspec version, commits it, pushes main, then pushes a `vX.Y.Z`
# tag — which is what the "Store Release" GitHub workflow listens for. CI then
# builds & uploads to Play (internal, draft) + iOS/macOS TestFlight.
#
# Usage:
#   tool/release.sh patch     # 1.0.2  -> 1.0.3   (bug fixes)
#   tool/release.sh minor     # 1.0.2  -> 1.1.0   (new features)
#   tool/release.sh major     # 1.0.2  -> 2.0.0   (breaking)
#   tool/release.sh 1.4.0     # set the version name explicitly
#
# The Android versionCode = the pubspec build number (the part after "+"); this
# script always increments it by 1 so Play never rejects the upload. iOS/macOS
# build numbers are derived automatically from TestFlight (latest + 1), so the
# build number only matters for Android.
set -euo pipefail
cd "$(dirname "$0")/.."

bump="${1:-patch}"

# --- preflight ----------------------------------------------------------------
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || { echo "✗ Not on main (on '$branch'). Switch to main first."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "✗ Working tree has uncommitted changes. Commit or stash first."; exit 1; }
git fetch -q origin

# --- current version ----------------------------------------------------------
line=$(grep '^version:' pubspec.yaml | head -1)
current=${line#version: }                 # e.g. 1.0.2+12
name=${current%%+*}                        # 1.0.2
code=${current##*+}                        # 12
IFS='.' read -r MA MI PA <<<"$name"

case "$bump" in
  patch) new_name="$MA.$MI.$((PA+1))" ;;
  minor) new_name="$MA.$((MI+1)).0" ;;
  major) new_name="$((MA+1)).0.0" ;;
  [0-9]*.[0-9]*.[0-9]*) new_name="$bump" ;;
  *) echo "✗ Unknown bump '$bump' (use patch|minor|major|X.Y.Z)"; exit 1 ;;
esac
new_code=$((code+1))
new_version="$new_name+$new_code"
tag="v$new_name"

git rev-parse "$tag" >/dev/null 2>&1 && { echo "✗ Tag $tag already exists."; exit 1; }

echo "→ $current  →  $new_version   (tag $tag)"
read -r -p "Proceed? [y/N] " ok
[ "$ok" = "y" ] || { echo "Aborted."; exit 0; }

# --- bump + commit + tag + push ----------------------------------------------
# Portable in-place sed (macOS + Linux).
sed -i.bak "s/^version: .*/version: $new_version/" pubspec.yaml && rm -f pubspec.yaml.bak
git add pubspec.yaml
git commit -m "release: $new_version"
git push origin main
git tag "$tag"
git push origin "$tag"

echo "✓ Pushed $tag — the Store Release workflow is now building all three apps."
echo "  Watch it: https://github.com/hinata-platform/hinata-app/actions"
