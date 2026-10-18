#!/usr/bin/env python3
"""Replace the Snap Store screenshots of `hinata` with docs/screenshots/linux.

The Snap Store keeps a listing's pictures as "binary metadata" next to the
text: icon, banner and screenshots. `snapcraft upload-metadata` only carries
the icon, so the screenshots were a by-hand job on snapcraft.io. This sends
the repo's set through the same dashboard endpoint the web form uses.

  SNAPCRAFT_STORE_CREDENTIALS=... python3 tool/snap_media.py          # report
  SNAPCRAFT_STORE_CREDENTIALS=... python3 tool/snap_media.py --apply  # replace

The store takes at most five screenshots; the first five of the sorted order
below go up. The icon and banner already in the store are kept as they are.
"""
import argparse
import base64
import hashlib
import json
import os
import pathlib
import sys

import requests

SNAP = "hinata"
DASHBOARD = "https://dashboard.snapcraft.io/dev/api"
ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = ROOT / "docs" / "screenshots" / "linux"
ORDER = ["dashboard", "board", "issues", "gantt", "reports", "comments"]
LIMIT = 5


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def auth_header():
    raw = os.environ.get("SNAPCRAFT_STORE_CREDENTIALS")
    if not raw:
        die("SNAPCRAFT_STORE_CREDENTIALS is not set")
    creds = json.loads(base64.b64decode(raw))
    value = creds.get("v", creds)
    if isinstance(value, str):
        value = json.loads(value)
    # The discharge ages out long before the exported login does; snapcraft
    # renews it on every call the same way, so this is not a new login.
    r = requests.post("https://login.ubuntu.com/api/v2/tokens/refresh",
                      json={"discharge_macaroon": value["d"]}, timeout=60)
    if r.status_code >= 400:
        die(f"refreshing the store login -> {r.status_code}: {r.text[:400]}")
    discharge = r.json()["discharge_macaroon"]
    return f'Macaroon root="{value["r"]}", discharge="{discharge}"'


def snap_id(session):
    r = session.get(f"{DASHBOARD}/account", timeout=60)
    if r.status_code >= 400:
        die(f"GET account -> {r.status_code}: {r.text[:400]}")
    for series in r.json().get("snaps", {}).values():
        if SNAP in series:
            return series[SNAP]["snap-id"]
    die(f"the account behind these credentials does not own {SNAP}")


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="replace the store's screenshots (default: report only)")
    args = ap.parse_args(argv)

    s = requests.Session()
    s.headers["Authorization"] = auth_header()
    sid = snap_id(s)
    url = f"{DASHBOARD}/snaps/{sid}/binary-metadata"
    r = s.get(url, timeout=60)
    if r.status_code >= 400:
        die(f"GET binary-metadata -> {r.status_code}: {r.text[:400]}")
    current = r.json()
    print(f"{SNAP} ({sid}) holds:")
    for item in current:
        print(f"  {item.get('type'):10} {item.get('filename')}  {item.get('url', '')}")

    shots = [SHOTS / f"{name}.png" for name in ORDER if (SHOTS / f"{name}.png").exists()][:LIMIT]
    if not shots:
        die(f"no screenshots in {SHOTS}")
    print("\nrepo set:", ", ".join(p.name for p in shots))
    if not args.apply:
        return 0

    # Keep icon and banner exactly as they are; the endpoint replaces the
    # whole set, so everything that stays has to be listed again.
    info = [{k: v for k, v in item.items() if k in ("type", "hash", "filename", "url")}
            for item in current if item.get("type") != "screenshot"]
    files = []
    for path in shots:
        data = path.read_bytes()
        info.append({"type": "screenshot", "filename": path.name,
                     "hash": hashlib.sha256(data).hexdigest(), "key": path.name})
        files.append((path.name, (path.name, data, "image/png")))
    r = s.put(url, data={"info": json.dumps(info)}, files=files, timeout=300)
    if r.status_code >= 400:
        die(f"PUT binary-metadata -> {r.status_code}: {r.text[:800]}")
    print("\nstore now holds:")
    for item in r.json():
        print(f"  {item.get('type'):10} {item.get('filename')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
