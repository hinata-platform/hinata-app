#!/usr/bin/env python3
"""Compose an App Store / Play Store screenshot in the Hinata "Aurora Hive"
design from a raw NATIVE device capture.

Design tokens are lifted 1:1 from the app (AppColors / AmbientBackground): a
warm-paper diagonal gradient, soft aurora glow blobs (amber + indigo + ember),
a frosted-glass caption chip, a bold Sora headline in navy ink, and the real
device frame from tool/frames/ with a soft drop shadow bleeding off the bottom.

    store_compose.py <device> <screen-key> <raw.png> <out.png>

<device>     iphone | ipad | macbook | android | android_tablet
<screen-key> dashboard | board | issues | gantt | reports | knowledge

Output is sized to each store's required pixel dimensions (see DEVICES).
Pure-Pillow, no network. Reuses device_frames.frame_device for the bezel.
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import device_frames

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"
SORA = "Sora-Variable.ttf"

# --- Aurora Hive palette (DARK) — exact app tokens --------------------------
# The signature Hinata look: a deep navy/near-black canvas with a honeycomb
# hex texture, warm amber + indigo aurora glows, dark glass, and light ink.
BG_TOP = (27, 25, 54)         # --amb-2 (dark) #1B1936
BG_MID = (16, 15, 30)         # between --amb-1 #131226 and --page #0C0B12
BG_BOT = (23, 21, 49)         # --amb-3 (dark) #171531
INK = (236, 235, 243)         # --ink (dark) #ECEBF3
INK_SOFT = (168, 166, 194)    # --ink-soft (dark) #A8A6C2
NAVY = (45, 43, 85)           # --navy #2D2B55
AMBER = (217, 160, 50)        # --amber #D9A032
AMBER_STRONG = (185, 131, 31) # --amber-strong #B9831F
INDIGO = (94, 88, 190)        # --indigo #5E58BE
EMBER = (200, 90, 50)         # --ember #C85A32
HEX_LINE = (150, 140, 210)    # faint honeycomb stroke (indigo-tinted)
WHITE = (255, 255, 255)

# device -> output canvas (store-required px) + layout mode
DEVICES = {
    # Apple 6.9" iPhone slot (also covers 6.5"); ASC scales down as needed.
    "iphone":         {"canvas": (1290, 2796), "mode": "portrait"},
    # Apple 13"/12.9" iPad slot — LANDSCAPE (2732x2048).
    "ipad":           {"canvas": (2732, 2048), "mode": "landscape"},
    # Mac App Store accepted size.
    "macbook":        {"canvas": (2880, 1800), "mode": "landscape"},
    # Google Play phone — aspect kept <= 2:1 (1290x2560 = 1.98:1).
    "android":        {"canvas": (1290, 2560), "mode": "portrait"},
    # Google Play tablet — LANDSCAPE, 16:10 (2560x1600 = 1.6:1).
    "android_tablet": {"canvas": (2560, 1600), "mode": "landscape"},
}

# screen-key -> (line1, line2, chip-label, accent, emoji). Accents stay on the
# amber / indigo / ember / navy brand family — never a rainbow.
SCREENS = {
    "dashboard": ("Your work,",   "at a glance",      "Live dashboard",     AMBER,  "\U0001F4CA"),
    "board":     ("Plan sprints", "that ship",        "Scrum & Kanban",     INDIGO, "\U0001F5C2️"),
    "issues":    ("Every issue,", "in its place",     "Powerful tracking",  EMBER,  "✅"),
    "gantt":     ("See the",      "bigger picture",   "Timeline & Gantt",   AMBER,  "\U0001F5D3️"),
    "reports":   ("Insights",     "that matter",      "Reports & velocity", INDIGO, "\U0001F4C8"),
    "comments":  ("Discuss it,",  "in context",       "Threaded comments",  EMBER,  "\U0001F4AC"),
}


def _font(name, size):
    for cand in (name, "Sora-Variable.ttf", "IBMPlexSans-SemiBold.ttf"):
        p = os.path.join(FONT_DIR, cand)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def _emoji(ch, target):
    if not os.path.exists(EMOJI_FONT):
        return None
    for native in (160, 137, 96):
        try:
            f = ImageFont.truetype(EMOJI_FONT, native)
            tmp = Image.new("RGBA", (native * 2, native * 2), (0, 0, 0, 0))
            ImageDraw.Draw(tmp).text((native, native), ch, font=f, anchor="mm",
                                     embedded_color=True)
            bb = tmp.getbbox()
            if not bb:
                continue
            g = tmp.crop(bb)
            s = target / max(g.size)
            return g.resize((max(1, round(g.width * s)), max(1, round(g.height * s))),
                            Image.LANCZOS)
        except Exception:
            continue
    return None


def _hex_overlay(size, cell, color, alpha):
    """A faint flat-top honeycomb grid (the Hinata 'hive' texture)."""
    import math
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = cell
    dx = 1.5 * r                     # horizontal step between hex centers
    dy = math.sqrt(3) * r            # vertical step
    line = color + (alpha,)
    lw = max(1, round(cell * 0.03))
    col = -1
    x = -r
    while x < w + r:
        col += 1
        yoff = (dy / 2) if (col % 2) else 0
        y = -r + yoff
        while y < h + r:
            pts = [(x + r * math.cos(math.radians(a)),
                    y + r * math.sin(math.radians(a))) for a in range(0, 360, 60)]
            d.line(pts + [pts[0]], fill=line, width=lw, joint="curve")
            y += dy
        x += dx
    return layer


def _aurora_background(size):
    """The DARK Aurora Hive canvas: deep navy gradient + honeycomb hex texture +
    warm amber & indigo aurora glows + a soft edge vignette. numpy for speed."""
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    ang = np.radians(160.0)
    dx, dy = np.cos(ang), np.sin(ang)
    proj = xx * dx + yy * dy
    t = (proj - proj.min()) / (proj.max() - proj.min())
    top, mid, bot = (np.array(c, np.float32) for c in (BG_TOP, BG_MID, BG_BOT))
    u1 = np.clip(t / 0.55, 0, 1)[..., None]
    u2 = np.clip((t - 0.55) / 0.45, 0, 1)[..., None]
    rgb = top + (mid - top) * u1
    rgb = np.where(t[..., None] >= 0.55, mid + (bot - mid) * u2, rgb)

    def add_blob(cx, cy, radius, color, strength):
        r2 = ((xx - cx) ** 2 + (yy - cy) ** 2) / (radius ** 2)
        falloff = np.clip(1.0 - r2, 0, 1) ** 1.6
        a = (falloff * strength)[..., None]
        # Screen-blend the glow so it reads as light on the dark canvas.
        col = np.array(color, np.float32)
        nonlocal rgb
        rgb = 255 - (255 - rgb) * (255 - col * a) / 255

    R = float(max(w, h))
    add_blob(w * 0.82, h * 0.12, R * 0.70, AMBER, 0.55)    # amber, top-right
    add_blob(w * 0.10, h * 0.86, R * 0.72, INDIGO, 0.50)   # indigo, bottom-left
    add_blob(w * 0.55, h * 0.42, R * 0.55, EMBER, 0.16)    # ember, subtle center

    # Very soft, wide edge vignette — just seats the composition, no hard frame.
    edge = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]) / (min(w, h) * 0.85)
    vig = (np.clip(1 - edge, 0, 1) ** 2.4 * 0.22)[..., None]
    rgb = rgb * (1 - vig) + np.array((10, 9, 20), np.float32) * vig

    arr = np.clip(rgb, 0, 255).astype(np.uint8)
    canvas = Image.fromarray(arr, "RGB").convert("RGBA")
    # Honeycomb texture on top — visible but soft (reads as the "hive" texture,
    # not hard linework).
    hexes = _hex_overlay((w, h), cell=round(max(w, h) * 0.05), color=HEX_LINE, alpha=30)
    canvas.alpha_composite(hexes)
    return canvas


def _chip(label, accent, emoji_ch, scale=1.0):
    """A single clean Aurora-Hive pill: a soft accent glow behind one frosted
    white capsule holding an accent emoji tile + navy label. No stacked layers."""
    fs = round(46 * scale)
    font = _font(SORA, fs)
    pad_x, pad_y, gap = round(32 * scale), round(24 * scale), round(20 * scale)
    tile = round(fs * 1.5)
    glyph = _emoji(emoji_ch, round(tile * 0.60))
    tmp = ImageDraw.Draw(Image.new("RGBA", (4, 4)))
    tb = tmp.textbbox((0, 0), label, font=font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    inner_h = max(tile, th)
    w = pad_x * 2 + tile + gap + tw
    h = pad_y * 2 + inner_h
    rad = h // 2
    # Generous padding so the blurred glow fully fades to zero before the layer
    # edge (too little padding clips the blur into a visible rectangle).
    blur = round(h * 0.42)
    glow = blur * 3 + round(h * 0.3)
    layer = Image.new("RGBA", (w + glow * 2, h + glow * 2), (0, 0, 0, 0))
    ox, oy = glow, glow

    # Soft accent glow (Aurora): a blurred accent capsule sitting behind the pill.
    g = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    gm = round(h * 0.26)
    ImageDraw.Draw(g).rounded_rectangle(
        (ox - gm, oy - gm, ox + w + gm, oy + h + gm), radius=rad + gm,
        fill=accent + (150,))
    layer.alpha_composite(g.filter(ImageFilter.GaussianBlur(blur)))

    d = ImageDraw.Draw(layer)
    # One clean DARK-glass capsule + a glowing accent-tinted rim.
    d.rounded_rectangle((ox, oy, ox + w, oy + h), radius=rad, fill=(38, 37, 60, 232))
    d.rounded_rectangle((ox, oy, ox + w, oy + h), radius=rad,
                        outline=accent + (170,), width=max(2, round(2.5 * scale)))

    # Accent emoji tile + label.
    tx, ty = ox + pad_x, oy + (h - tile) // 2
    d.rounded_rectangle((tx, ty, tx + tile, ty + tile), radius=round(tile * 0.30),
                        fill=accent + (255,))
    if glyph:
        layer.alpha_composite(glyph, (tx + (tile - glyph.width) // 2,
                                      ty + (tile - glyph.height) // 2))
    d.text((tx + tile + gap, oy + h // 2), label, font=font, fill=INK + (255,),
           anchor="lm")
    return layer


def _soft_glow(size, color, alpha, spread=0.42):
    """A big, soft elliptical accent glow to sit BEHIND the device — a smooth
    radial halo (no hard silhouette edges) that blends into the aurora canvas.
    Padding is derived from the blur so the halo fully fades before the layer
    edge (otherwise the blur clips into a visible rectangle)."""
    w, h = size
    blur = int(max(w, h) * spread)
    pad = int(blur * 2)
    layer = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    inset = int(min(w, h) * 0.06)
    ImageDraw.Draw(layer).ellipse(
        (pad + inset, pad + inset, pad + w - inset, pad + h - inset),
        fill=color + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    return layer, pad


def compose(device, key, raw_path):
    cfg = DEVICES[device]
    W, H = cfg["canvas"]
    line1, line2, chip_label, accent, emoji_ch = SCREENS[key]
    canvas = _aurora_background((W, H))
    d = ImageDraw.Draw(canvas)
    cx = W // 2

    framed = device_frames.frame_device(device, Image.open(raw_path))

    # Compact caption region at the very top (headline + chip); the DEVICE is the
    # hero — filling the width and bleeding off the bottom edge.
    if cfg["mode"] == "landscape":
        hf = _font(SORA, round(W * 0.033))
        y = round(H * 0.028)
        d.text((cx, y), line1 + " " + line2, font=hf, fill=INK + (255,), anchor="ma")
        chip = _chip(chip_label, accent, emoji_ch, scale=W / 2880 * 0.9)
        chip_top = y + round(H * 0.036)
        max_w = round(W * 0.96)
        bleed = 0.26          # landscape frames are wide → let width govern
    else:
        hsize = round(W * 0.068)
        hf = _font(SORA, hsize)
        step = round(hsize * 1.12)
        y = round(H * 0.024)
        for line in (line1, line2):
            d.text((cx, y), line, font=hf, fill=INK + (255,), anchor="ma")
            y += step
        chip = _chip(chip_label, accent, emoji_ch, scale=W / 1290 * 0.88)
        chip_top = y + round(H * 0.002)
        max_w = round(W * 0.985)
        bleed = 0.14

    canvas.alpha_composite(chip, (cx - chip.width // 2, chip_top))
    chip_bottom = chip_top + chip.height

    # Device is the hero: as large as fits (usually width-limited), starting right
    # below the chip and bleeding off the bottom edge.
    avail_h = (H - chip_bottom) + round(H * bleed)
    scale = min(max_w / framed.width, avail_h / framed.height)
    fr = framed.resize((round(framed.width * scale), round(framed.height * scale)),
                       Image.LANCZOS)
    glow, pad = _soft_glow((fr.width, fr.height), accent, alpha=80)
    top = chip_bottom + round(H * 0.006)
    canvas.alpha_composite(glow, (cx - fr.width // 2 - pad, top - pad))
    canvas.alpha_composite(fr, (cx - fr.width // 2, top))

    return canvas.convert("RGB")


def main(argv):
    if len(argv) != 5 or argv[1] not in DEVICES or argv[2] not in SCREENS:
        print(__doc__)
        print("devices:", ", ".join(DEVICES))
        print("screens:", ", ".join(SCREENS))
        return 2
    device, key, src, dst = argv[1:5]
    out = compose(device, key, src)
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    out.save(dst, quality=95)
    print(f"  {device:15} {key:10} -> {out.size[0]}x{out.size[1]}  {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
