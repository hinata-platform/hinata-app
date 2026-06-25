#!/usr/bin/env bash
# Capture marketing screenshots from the iPhone 17 Pro Max simulator.
#
# Navigation without UI automation: the app reads an optional `screenshot_route`
# pref at boot (AppStorage.screenshotRoute -> GoRouter.initialLocation), so a
# plain `simctl launch` lands on the target screen — no deep-link prompt, no taps.
# Auth + server are pre-seeded straight into the app's sandbox plist.
#
# Prereqs: dev backend up (admin/hinata-demo-2026), the app installed on the sim.
set -euo pipefail

UDID="${UDID:-BD91470D-338D-48C6-856B-0821AE6A316B}"
BUNDLE="com.ahmadre.hinata"
API="${API:-http://localhost:8080}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/tool/.venv/bin/python"
RAW="$ROOT/docs/screenshots/ios/raw"
OUT="$ROOT/docs/screenshots/ios"
BOARD="${BOARD:-6a3bb2c276e2e96eaeccfd84}"
mkdir -p "$RAW" "$OUT"

echo "==> login"
RESP=$(curl -s -m 30 -X POST "$API/api/v1/auth/login" -H 'Content-Type: application/json' \
  -d '{"identifier":"admin","password":"hinata-demo-2026"}')
ACCESS=$(echo "$RESP" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['accessToken'])")
REFRESH=$(echo "$RESP" | "$PY" -c "import sys,json;print(json.load(sys.stdin)['refreshToken'])")
PL=$(find ~/Library/Developer/CoreSimulator/Devices/$UDID/data/Containers/Data/Application/*/Library/Preferences/$BUNDLE.plist 2>/dev/null | head -1)
echo "    plist: $PL"

seed() { # $1 = route
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$UDID" launchctl stop com.apple.cfprefsd.xpc.daemon 2>/dev/null || true
  sleep 1
  ROUTE="$1" ACCESS="$ACCESS" REFRESH="$REFRESH" API="$API" PL="$PL" "$PY" - <<'PY'
import os, plistlib
pl=os.environ['PL']
try: d=plistlib.load(open(pl,'rb'))
except Exception: d={}
d.update({'flutter.server_url':os.environ['API'],
          'flutter.access_token':os.environ['ACCESS'],
          'flutter.refresh_token':os.environ['REFRESH'],
          'flutter.onboarding_done':True,'flutter.locale':'en',
          'flutter.screenshot_route':os.environ['ROUTE']})
plistlib.dump(d, open(pl,'wb'), fmt=plistlib.FMT_BINARY)
PY
}

shoot() { # $1 key  $2 route  $3 settle
  local key="$1" route="$2" settle="${3:-13}"
  echo "==> $key  ($route)"
  seed "$route"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep "$settle"
  xcrun simctl io "$UDID" screenshot --type=png "$RAW/$key.png" >/dev/null
  "$PY" "$ROOT/tool/marketing_compose.py" "$key" "$RAW/$key.png" "$OUT/$key.png"
}

shoot dashboard "/dashboard"
shoot board     "/boards/$BOARD"
shoot issues    "/issues"
shoot reports   "/reports"
shoot gantt     "/gantt"
shoot knowledge "/knowledge"

echo "done -> $OUT"
ls -la "$OUT"/*.png
