#!/usr/bin/env python3
"""Composite a raw screenshot into a real Apple device frame.

Uses the genuine transparent-screen PNG frames in tool/frames/:
  * macbook  — tool/frames/macbook.png  (16" MacBook, notch)
  * iphone   — tool/frames/iphone.png   (iPhone 17 Pro Max, Dynamic Island)

The screen cut-out is detected automatically (the interior transparent region,
flood-filled apart from the exterior), so the screenshot drops in with the
frame's exact rounded corners and the notch / Dynamic Island as part of the
chrome on top. For the phone a slim iOS status bar is synthesized so the
Dynamic Island sits above the app content (web captures have no safe-area inset).

The capture step sizes the browser viewport to the frame's screen aspect, so the
shot fills the cut-out with no distortion (16:10.32 desktop · 19.5:9 phone).

Pure-Pillow, no network. Standalone + reusable (e.g. a future fastlane lane):
    device_frames.py macbook  in.png  out.png
    device_frames.py iphone   in.png  out.png
"""
from __future__ import annotations

import functools
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FRAME_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INK = (235, 235, 240, 255)  # light glyphs for the (dark-island) status bar


# ---- screen-cutout detection ------------------------------------------------
@functools.lru_cache(maxsize=4)
def _frame_and_screen(device):
    """The frame RGBA + an L mask (255 = the interior screen cut-out) + its bbox."""
    frame = Image.open(os.path.join(FRAME_DIR, f"{device}.png")).convert("RGBA")
    # 0 where transparent, 255 where the device body is opaque.
    m = frame.getchannel("A").point(lambda v: 0 if v < 8 else 255)
    # Flood the *exterior* transparent area (reachable from the corners) to 128,
    # leaving only the enclosed screen cut-out at 0.
    for corner in [(0, 0), (frame.width - 1, 0), (0, frame.height - 1),
                   (frame.width - 1, frame.height - 1)]:
        ImageDraw.floodfill(m, corner, 128, thresh=10)
    screen = m.point(lambda v: 255 if v == 0 else 0)
    return frame, screen, screen.getbbox()


# ---- helpers ----------------------------------------------------------------
def _fit_cover(img, box):
    """Scale `img` to cover `box` (w,h), centre-crop the overflow."""
    bw, bh = box
    iw, ih = img.size
    scale = max(bw / iw, bh / ih)
    nw, nh = round(iw * scale), round(ih * scale)
    img = img.resize((nw, nh), Image.LANCZOS)
    left, top = (nw - bw) // 2, (nh - bh) // 2
    return img.crop((left, top, left + bw, top + bh))


def _font(size):
    for name in ("IBMPlexSans-SemiBold.ttf", "Sora-Variable.ttf"):
        path = os.path.join(ROOT, "assets", "fonts", name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _status_bar(shot, band):
    """Prepend a synthesized iOS status bar of height `band`px (clock + signal /
    battery) so the Dynamic Island sits above the app content."""
    if band <= 0:
        return shot
    sw = shot.width
    bg = shot.getpixel((2, 2))[:3] + (255,)
    out = Image.new("RGBA", (sw, shot.height + band), bg)
    out.alpha_composite(shot, (0, band))

    d = ImageDraw.Draw(out)
    cy = round(band * 0.52)
    ink = _dark_or_light(bg)
    d.text((round(sw * 0.085), cy), "9:41", font=_font(round(band * 0.34)),
           fill=ink, anchor="lm")
    # right cluster: cellular bars · battery
    x = sw - round(sw * 0.07)
    bh = round(band * 0.20)
    bw = round(bh * 2.0)
    by0 = cy - bh // 2
    d.rounded_rectangle((x - bw, by0, x, by0 + bh), radius=round(bh * 0.35),
                        outline=ink, width=max(2, round(sw * 0.004)))
    d.rounded_rectangle((x - bw + round(bw * 0.16), by0 + round(bh * 0.24),
                         x - round(bw * 0.34), by0 + bh - round(bh * 0.24)),
                        radius=round(bh * 0.16), fill=ink)
    d.rounded_rectangle((x + 2, cy - round(bh * 0.16), x + round(sw * 0.011),
                         cy + round(bh * 0.16)), radius=2, fill=ink)
    cx = x - bw - round(sw * 0.115)
    for i in range(4):
        h = round(bh * (0.5 + i * 0.2))
        bx = cx + i * round(sw * 0.017)
        d.rounded_rectangle((bx, cy + bh // 2 - h, bx + round(sw * 0.011),
                             cy + bh // 2), radius=2, fill=ink)
    return out


def _dark_or_light(bg):
    """Pick a legible status-bar ink for the app's top background colour."""
    lum = 0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2]
    return (24, 22, 30, 255) if lum > 140 else INK


# ---- public framing ---------------------------------------------------------
def frame_device(device, shot, status_bar=False):
    shot = shot.convert("RGBA")
    frame, screen, bbox = _frame_and_screen(device)
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]

    if status_bar:
        # Grow a status bar so (shot + band) matches the screen aspect exactly,
        # leaving the body of the capture un-cropped.
        band = max(0, round(shot.width * bh / bw) - shot.height)
        shot = _status_bar(shot, band)

    fitted = _fit_cover(shot, (bw, bh))
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    layer.paste(fitted, (bbox[0], bbox[1]))
    layer.putalpha(screen)          # clip to the exact screen shape
    layer.alpha_composite(frame)    # device chrome (bezel · notch · island) on top
    return layer


def frame_macbook(shot):
    return frame_device("macbook", shot)


def frame_iphone(shot):
    return frame_device("iphone", shot, status_bar=True)


FRAMES = {"macbook": frame_macbook, "iphone": frame_iphone}


def main(argv):
    if len(argv) != 4 or argv[1] not in FRAMES:
        print(__doc__)
        return 2
    device, src, dst = argv[1], argv[2], argv[3]
    out = FRAMES[device](Image.open(src))
    out.save(dst)
    print(f"  {device:8} -> {out.size[0]}x{out.size[1]}  {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
