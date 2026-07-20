#!/usr/bin/env python3
"""Capture NATIVE store screenshots for one device class and frame them in the
Hinata "Aurora Hive" design (store_compose.py), writing into the Fastlane dirs.

    tool/capture_store.py <device> [--settle N] [--only key1,key2]

<device> = iphone | ipad | macos | android | android_tablet

How the login + onboarding are bypassed (no UI automation):
  The app reads a `screenshot_route` pref at boot (AppStorage.screenshotRoute ->
  GoRouter.initialLocation) and a server URL + access/refresh tokens from plain
  prefs. On boot the app's storage migration lifts those into secure storage and
  signs in, so a plain launch lands authenticated on the target screen — no
  connect prompt, no login, no onboarding. We write those prefs straight into the
  app sandbox (iOS/macOS plist, Android shared_prefs XML) between launches.

Prereqs: the seeded dev server on :8080 (admin/hinata-demo-2026), the built app
for the target platform, and a booted simulator/emulator. Run per device.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import plistlib
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tool"))
import store_compose  # noqa: E402

BUNDLE = "com.ahmadre.hinata"
BOARD = "6a5bab34ab2b461dde4d8265"
DEMO_USER, DEMO_PASS = "admin", "hinata-demo-2026"

# Force English (USA) for the store shots. The app's UI language is a
# HydratedCubit seeded from the *device* locale (basicLocaleListResolution over
# PlatformDispatcher.locales), NOT the flutter.locale pref — so we override the
# app's effective language via the standard -AppleLanguages/-AppleLocale launch
# arguments (honoured by Cocoa on iOS + macOS) and clear stale hydrated state.
APPLE_LANG_ARGS = '-AppleLanguages "(en-US)" -AppleLocale "en_US"'

# iOS/macOS reach the host server on localhost; the Android emulator reaches the
# host loopback via 10.0.2.2.
HOST_API = "http://localhost:8080"

# A pre-seeded threaded discussion. Anchoring on a REPLY makes the app expand the
# thread (showing the connecting reply lines) and scroll it into view.
COMMENTS_ISSUE = "HIN-4"
COMMENTS_ANCHOR = "6a5d8349d38f3c05cb71058c"  # Tomáš's reply in Lena's thread

SCREENS = [
    ("dashboard", "/dashboard"),
    ("board", f"/boards/{BOARD}"),
    ("issues", "/issues"),
    ("gantt", "/gantt"),
    ("reports", "/reports"),
    ("comments", f"/issues/{COMMENTS_ISSUE}?comment={COMMENTS_ANCHOR}"),
]

SIM_UDID = {
    "iphone": "BD91470D-338D-48C6-856B-0821AE6A316B",   # iPhone 17 Pro Max (6.9")
    "ipad": "13D608A4-0D28-4C60-97BD-36869619E591",     # iPad Pro 13-inch (M5)
}
FRAME = {"iphone": "iphone", "ipad": "ipad", "macos": "macbook",
         "android": "android", "android_tablet": "android_tablet"}


def sh(cmd, check=True, capture=False, env=None):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), check=False,
                       capture_output=capture, text=True, env=env)
    if check and r.returncode != 0:
        out = (r.stdout or "") + (r.stderr or "")
        raise RuntimeError(f"cmd failed ({r.returncode}): {cmd}\n{out}")
    return r


def login(api=HOST_API):
    body = json.dumps({"identifier": DEMO_USER, "password": DEMO_PASS}).encode()
    req = urllib.request.Request(f"{api}/api/v1/auth/login", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.load(r)
    if not d.get("accessToken"):
        raise RuntimeError(f"login failed: {d}")
    return d["accessToken"], d["refreshToken"]


def out_path(device, i, key):
    if device in ("iphone", "ipad"):
        d = f"{ROOT}/ios/fastlane/screenshots/en-US"
        name = f"{device}_{i}_{key}.png"
    elif device == "macos":
        d = f"{ROOT}/macos/fastlane/screenshots/en-US"
        name = f"{i}_{key}.png"
    elif device == "android":
        d = f"{ROOT}/android/fastlane/metadata/android/en-US/images/phoneScreenshots"
        name = f"{i}_{key}.png"
    else:  # android_tablet
        d = f"{ROOT}/android/fastlane/metadata/android/en-US/images/tenInchScreenshots"
        name = f"{i}_{key}.png"
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, name)


def frame_and_save(device, key, raw, dst):
    img = store_compose.compose(FRAME[device], key, raw)
    img.save(dst, quality=95)
    print(f"    framed -> {os.path.basename(dst)}  {img.size[0]}x{img.size[1]}")


# ---------------------------------------------------------------- iOS ---------
def ios_container(udid):
    base = os.path.expanduser(
        f"~/Library/Developer/CoreSimulator/Devices/{udid}/data/Containers/Data/Application")
    for app in glob.glob(f"{base}/*"):
        meta = os.path.join(app, ".com.apple.mobile_container_manager.metadata.plist")
        try:
            with open(meta, "rb") as f:
                if plistlib.load(f).get("MCMMetadataIdentifier") == BUNDLE:
                    return app
        except Exception:
            continue
    return None


def ios_seed(plist, api, access, refresh, route, landscape=False):
    d = {
        "flutter.server_url": api,
        "flutter.access_token": access,
        "flutter.refresh_token": refresh,
        "flutter.onboarding_done": True,
        "flutter.locale": "en",
        "flutter.screenshot_route": route,
        "flutter.screenshot_landscape": landscape,
    }
    os.makedirs(os.path.dirname(plist), exist_ok=True)
    with open(plist, "wb") as f:
        plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)


def ios_set_landscape(udid):
    """Put the simulator DEVICE in landscape so the app fills the screen. The
    Device ▸ Orientation menu items are only enabled when the device window is the
    key window, so we raise it first. `simctl io screenshot` still writes the
    frame in the panel's native (portrait) pixel order, so callers additionally
    rotate the PNG 90° CCW to upright landscape."""
    # Only this sim booted so its window is unambiguous.
    for u in SIM_UDID.values():
        if u != udid:
            sh(f"xcrun simctl shutdown {u}", check=False)
    sh("open -a Simulator")
    time.sleep(2)
    sh("""osascript -e 'tell application "Simulator" to activate' -e 'delay 1' """
       """-e 'tell application "System Events" to tell process "Simulator" to """
       """set frontmost to true' """
       """-e 'try' -e 'tell application "System Events" to tell process "Simulator" to """
       """perform action "AXRaise" of window 1' -e 'end try' -e 'delay 0.5' """
       """-e 'tell application "System Events" to tell process "Simulator" to click """
       """menu item "Landscape Left" of menu 1 of menu item "Orientation" of menu """
       """"Device" of menu bar 1'""", check=False)
    time.sleep(2)


def rotate_upright_landscape(png):
    """simctl writes landscape frames in portrait pixel order; rotate 90° CCW."""
    from PIL import Image
    im = Image.open(png).transpose(Image.ROTATE_90)
    im.save(png)


def run_ios(device, settle, only):
    udid = SIM_UDID[device]
    landscape = device == "ipad"
    app = glob.glob(f"{ROOT}/build/ios/iphonesimulator/*.app")
    if not app:
        sys.exit("✗ build/ios/iphonesimulator/*.app missing — run "
                 "`flutter build ios --debug --simulator`")
    app = app[0]
    print(f"==> boot {device} {udid}{' (landscape)' if landscape else ''}")
    sh(f"xcrun simctl boot {udid}", check=False)
    sh(f"xcrun simctl bootstatus {udid}", check=False)
    # Force the DARK app theme (the app follows the OS appearance) for a
    # consistent, on-brand look across every device.
    sh(f"xcrun simctl ui {udid} appearance dark", check=False)
    # Landscape is forced by the app itself in screenshot mode (tablet-sized
    # screens), so no simulator rotation is needed here.
    # Clear any stale hydrated locale (a prior German launch persists de).
    sh(f"xcrun simctl uninstall {udid} {BUNDLE}", check=False)
    sh(f"xcrun simctl install {udid} '{app}'")
    # clean marketing status bar
    sh(f"xcrun simctl status_bar {udid} override --time 9:41 --batteryState charged "
       f"--batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi --operatorName ' '",
       check=False)
    sh(f"xcrun simctl launch {udid} {BUNDLE} {APPLE_LANG_ARGS}", check=False)
    time.sleep(6)
    if landscape:
        ios_set_landscape(udid)
        # Re-assert the clean marketing status bar after the rotation.
        sh(f"xcrun simctl status_bar {udid} override --time 9:41 --batteryState charged "
           f"--batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi --operatorName ' '",
           check=False)
    container = ios_container(udid)
    if not container:
        sys.exit("✗ could not locate app container plist")
    plist = f"{container}/Library/Preferences/{BUNDLE}.plist"
    access, refresh = login()
    for i, (key, route) in enumerate(SCREENS):
        if only and key not in only:
            continue
        print(f"==> {device} {key} ({route})")
        sh(f"xcrun simctl terminate {udid} {BUNDLE}", check=False)
        sh(f"xcrun simctl spawn {udid} launchctl stop com.apple.cfprefsd.xpc.daemon", check=False)
        time.sleep(1)
        ios_seed(plist, HOST_API, access, refresh, route, landscape=landscape)
        sh(f"xcrun simctl launch {udid} {BUNDLE} {APPLE_LANG_ARGS}", check=False)
        time.sleep(settle)
        raw = f"/tmp/hinata_shot_{device}_{key}.png"
        sh(f"xcrun simctl io {udid} screenshot --type=png '{raw}'")
        if landscape:
            rotate_upright_landscape(raw)
        frame_and_save(device, key, raw, out_path(device, i, key))
    sh(f"xcrun simctl status_bar {udid} clear", check=False)


# --------------------------------------------------------------- macOS --------
def macos_prefs():
    return os.path.expanduser(
        f"~/Library/Containers/{BUNDLE}/Data/Library/Preferences/{BUNDLE}.plist")


def run_macos(device, settle, only):
    apps = glob.glob(f"{ROOT}/build/macos/Build/Products/Debug/*.app") or \
        glob.glob(f"{ROOT}/build/macos/Build/Products/Release/*.app")
    if not apps:
        sys.exit("✗ macOS .app missing — run `flutter build macos --debug`")
    app = apps[0]
    proc = os.path.splitext(os.path.basename(app))[0]
    print(f"==> macOS app: {app} (process '{proc}')")
    # Wipe the sandbox container so the hydrated locale/theme cubits re-seed from
    # the launch args (else a prior German/light run persists).
    sh(f"osascript -e 'tell application \"{proc}\" to quit'", check=False)
    time.sleep(1)
    import shutil
    shutil.rmtree(os.path.expanduser(f"~/Library/Containers/{BUNDLE}"), ignore_errors=True)
    # First launch to create the sandbox container (English + dark), then quit.
    sh(f"open '{app}' --args -AppleInterfaceStyle Dark -AppleLanguages '(en-US)'")
    time.sleep(6)
    sh(f"osascript -e 'tell application \"{proc}\" to quit'", check=False)
    time.sleep(2)
    prefs = macos_prefs()
    access, refresh = login()
    for i, (key, route) in enumerate(SCREENS):
        if only and key not in only:
            continue
        print(f"==> macOS {key} ({route})")
        sh(f"osascript -e 'tell application \"{proc}\" to quit'", check=False)
        sh("killall -u $USER cfprefsd", check=False)
        time.sleep(1)
        ios_seed(prefs, HOST_API, access, refresh, route)  # same plist layout
        pos = "60,90"
        size = "1440,931"
        sh(f"open '{app}' --args -AppleInterfaceStyle Dark -AppleLanguages '(en-US)'")
        # Size the window FIRST (before the app finishes loading), so the
        # deep-link comment scroll runs at the final viewport size — otherwise a
        # later resize invalidates the scroll position (comments off-screen).
        time.sleep(3)
        sh(f"""osascript -e '
          tell application "{proc}" to activate
          delay 0.4
          tell application "System Events" to tell process "{proc}"
            set position of window 1 to {{60, 90}}
            set size of window 1 to {{1440, 931}}
          end tell' """, check=False)
        time.sleep(settle)  # app loads + comment scroll settles at the final size
        raw = f"/tmp/hinata_shot_macos_{key}.png"
        sh(f"screencapture -x -o -R{pos.replace(',', ',')},{size} '{raw}'")
        frame_and_save(device, key, raw, out_path(device, i, key))
    sh(f"osascript -e 'tell application \"{proc}\" to quit'", check=False)


# ------------------------------------------------------------- Android --------
def adb(serial, args, check=True, capture=False):
    return sh(["adb", "-s", serial, *args], check=check, capture=capture)


def android_serial():
    r = sh("adb devices", capture=True)
    for line in r.stdout.splitlines()[1:]:
        if line.strip().endswith("device"):
            return line.split()[0]
    return None


def android_prefs_xml(api, access, refresh, route, landscape=False):
    def esc(s):
        return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
    return (
        "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n"
        f'    <string name="flutter.server_url">{esc(api)}</string>\n'
        f'    <string name="flutter.access_token">{esc(access)}</string>\n'
        f'    <string name="flutter.refresh_token">{esc(refresh)}</string>\n'
        '    <boolean name="flutter.onboarding_done" value="true" />\n'
        '    <string name="flutter.locale">en</string>\n'
        f'    <string name="flutter.screenshot_route">{esc(route)}</string>\n'
        f'    <boolean name="flutter.screenshot_landscape" value="{"true" if landscape else "false"}" />\n'
        "</map>\n"
    )


def android_seed(serial, xml):
    # Write via run-as (app is debuggable). shared_prefs dir may not exist yet.
    b64 = __import__("base64").b64encode(xml.encode()).decode()
    script = (f"run-as {BUNDLE} sh -c "
              f"'mkdir -p shared_prefs && echo {b64} | base64 -d > "
              f"shared_prefs/FlutterSharedPreferences.xml'")
    adb(serial, ["shell", script])


def android_demo_statusbar(serial):
    cmds = [
        "settings put global sysui_demo_allowed 1",
        "am broadcast -a com.android.systemui.demo -e command enter",
        "am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941",
        "am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false",
        "am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4",
        "am broadcast -a com.android.systemui.demo -e command network -e mobile show -e level 4 -e datatype none",
        "am broadcast -a com.android.systemui.demo -e command notifications -e visible false",
    ]
    for c in cmds:
        adb(serial, ["shell", c], check=False)


def run_android(device, settle, only):
    apk = f"{ROOT}/build/app/outputs/flutter-apk/app-debug.apk"
    if not os.path.exists(apk):
        sys.exit("✗ app-debug.apk missing — run `flutter build apk --debug`")
    serial = android_serial()
    if not serial:
        sys.exit("✗ no android emulator connected (adb devices)")
    print(f"==> android serial {serial}")
    adb(serial, ["install", "-r", "-t", apk])
    adb(serial, ["shell", "cmd", "uimode", "night", "yes"], check=False)  # dark theme
    if device == "android_tablet":
        # Render at a 10" tablet resolution/density so the app shows its wide
        # tablet layout (side rail + multi-column), then lock to landscape. Done
        # on the reliable phone emulator (the tablet AVD wouldn't boot).
        adb(serial, ["shell", "wm", "size", "2560x1600"], check=False)
        adb(serial, ["shell", "wm", "density", "240"], check=False)
        adb(serial, ["shell", "settings", "put", "system", "accelerometer_rotation", "0"], check=False)
        adb(serial, ["shell", "settings", "put", "system", "user_rotation", "0"], check=False)
    android_demo_statusbar(serial)
    api = "http://10.0.2.2:8080"
    access, refresh = login()  # from host
    for i, (key, route) in enumerate(SCREENS):
        if only and key not in only:
            continue
        print(f"==> {device} {key} ({route})")
        adb(serial, ["shell", "am", "force-stop", BUNDLE], check=False)
        # ensure data dir exists: start once if first time
        adb(serial, ["shell", "monkey", "-p", BUNDLE, "-c",
                     "android.intent.category.LAUNCHER", "1"], check=False)
        time.sleep(3)
        adb(serial, ["shell", "am", "force-stop", BUNDLE], check=False)
        android_seed(serial, android_prefs_xml(api, access, refresh, route,
                                               landscape=device == "android_tablet"))
        adb(serial, ["shell", "monkey", "-p", BUNDLE, "-c",
                     "android.intent.category.LAUNCHER", "1"], check=False)
        time.sleep(settle)
        raw = f"/tmp/hinata_shot_{device}_{key}.png"
        # Binary capture — screencap emits PNG bytes, so never text-decode it.
        with open(raw, "wb") as f:
            f.write(subprocess.run(["adb", "-s", serial, "exec-out", "screencap", "-p"],
                                   capture_output=True).stdout)
        frame_and_save(device, key, raw, out_path(device, i, key))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("device", choices=list(FRAME))
    ap.add_argument("--settle", type=int, default=11)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = set(x for x in a.only.split(",") if x)
    if a.device in ("iphone", "ipad"):
        run_ios(a.device, a.settle, only)
    elif a.device == "macos":
        run_macos(a.device, a.settle, only)
    else:
        run_android(a.device, a.settle, only)
    print(f"✓ {a.device} done")


if __name__ == "__main__":
    main()
