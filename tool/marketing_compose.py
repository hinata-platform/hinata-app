#!/usr/bin/env python3
"""Composite a raw iOS-simulator capture into an App Store marketing screenshot.

Layout (per the brand reference): a warm-paper canvas with a bold two-line
headline, an amber "sticker" pill (emoji + short label, slightly rotated), the
app icon, and the capture dropped into a real iPhone 17 Pro Max frame that
bleeds off the bottom edge.

Output is sized for the App Store 6.9" iPhone slot (1290 x 2796).

Pure-Pillow, no network. Reuses device_frames.frame_iphone for the bezel.
    marketing_compose.py <screen-key> <raw.png> <out.png>
where <screen-key> is one of MARKETING below (dashboard, board, ...).
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw, ImageFont

import device_frames

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR = os.path.join(ROOT, "assets", "fonts")
ICON = os.path.join(ROOT, "assets", "branding", "app_icon.png")
EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"

# App Store 6.9" portrait slot.
CANVAS = (1290, 2796)

PAPER = (244, 243, 239, 255)   # warm paper
INK = (26, 23, 38, 255)        # navy ink
SUBINK = (96, 92, 112, 255)    # muted subtitle ink
AMBER = (224, 164, 59, 255)    # honey amber

# screen-key -> (line1, line2, emoji, pill-label, accent rgb)
MARKETING = {
    "dashboard": ("Your work,", "at a glance", "\U0001F4CA", "Live dashboard", (224, 164, 59)),
    "board":     ("Plan sprints", "that ship", "\U0001F5C2️", "Scrum & Kanban", (158, 192, 240)),
    "issues":    ("Every issue,", "in its place", "✅", "Powerful tracking", (155, 224, 199)),
    "reports":   ("Insights", "that matter", "\U0001F4C8", "Reports & velocity", (224, 164, 59)),
    "gantt":     ("See the", "big picture", "\U0001F5D3️", "Timeline & Gantt", (200, 178, 240)),
    "knowledge": ("Your team's", "knowledge base", "\U0001F4DA", "Built-in wiki", (240, 196, 158)),
}


def _font(name, size):
    return ImageFont.truetype(os.path.join(FONT_DIR, name), size)


def _emoji(ch, target):
    """Render a colour emoji glyph to a `target`px RGBA, or None if unavailable."""
    if not os.path.exists(EMOJI_FONT):
        return None
    for native in (160, 137, 96):
        try:
            f = ImageFont.truetype(EMOJI_FONT, native)
            tmp = Image.new("RGBA", (native * 2, native * 2), (0, 0, 0, 0))
            d = ImageDraw.Draw(tmp)
            d.text((native, native), ch, font=f, anchor="mm", embedded_color=True)
            bbox = tmp.getbbox()
            if not bbox:
                continue
            glyph = tmp.crop(bbox)
            scale = target / max(glyph.size)
            return glyph.resize((max(1, round(glyph.width * scale)),
                                 max(1, round(glyph.height * scale))), Image.LANCZOS)
        except Exception:
            continue
    return None


def _rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width, img.height),
                                           radius=radius, fill=255)
    out = img.copy()
    out.putalpha(mask)
    return out


def _gradient_bg(accent):
    """Warm paper softly tinted toward the screen's accent near the top."""
    w, h = CANVAS
    top = tuple(round(PAPER[i] * 0.55 + accent[i] * 0.45) for i in range(3))
    bg = Image.new("RGB", (w, h), PAPER[:3])
    px = bg.load()
    band = int(h * 0.5)
    for y in range(band):
        t = (1 - y / band) ** 1.6
        row = tuple(round(PAPER[i] + (top[i] - PAPER[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = row
    return bg.convert("RGBA")


def _sticker(emoji_ch, label, accent):
    """An amber-ish rounded pill: emoji + label, returned as an RGBA layer."""
    font = _font("Sora-Variable.ttf", 46)
    pad_x, pad_y, gap = 44, 26, 22
    glyph = _emoji(emoji_ch, 60)
    tmp = Image.new("RGBA", (10, 10))
    td = ImageDraw.Draw(tmp)
    tb = td.textbbox((0, 0), label, font=font)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    gw = glyph.width if glyph else 0
    gh = glyph.height if glyph else 0
    inner_h = max(th, gh)
    w = pad_x * 2 + gw + (gap if glyph else 0) + tw
    h = pad_y * 2 + inner_h
    pill = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(pill)
    d.rounded_rectangle((0, 0, w, h), radius=h // 2, fill=accent + (255,))
    cy = h // 2
    x = pad_x
    if glyph:
        pill.alpha_composite(glyph, (x, cy - gh // 2))
        x += gw + gap
    # legible ink for the pill text
    lum = 0.299 * accent[0] + 0.587 * accent[1] + 0.114 * accent[2]
    ink = INK if lum > 150 else (255, 255, 255, 255)
    d.text((x, cy), label, font=font, fill=ink, anchor="lm")
    return pill.rotate(-4, expand=True, resample=Image.BICUBIC)


def compose(key, raw_path):
    line1, line2, emoji_ch, pill_label, accent = MARKETING[key]
    canvas = _gradient_bg(accent)
    d = ImageDraw.Draw(canvas)
    cx = CANVAS[0] // 2

    # --- app icon (rounded) ---
    icon = Image.open(ICON).convert("RGBA").resize((132, 132), Image.LANCZOS)
    icon = _rounded(icon, 30)
    canvas.alpha_composite(icon, (cx - icon.width // 2, 150))

    # --- headline ---
    hf = _font("Sora-Variable.ttf", 116)
    y = 330
    for line in (line1, line2):
        d.text((cx, y), line, font=hf, fill=INK, anchor="ma")
        y += 132

    # --- sticker pill ---
    pill = _sticker(emoji_ch, pill_label, accent)
    canvas.alpha_composite(pill, (cx - pill.width // 2, y + 18))

    # --- framed device, bleeding off the bottom ---
    framed = device_frames.frame_iphone(Image.open(raw_path))
    target_w = 1080
    scale = target_w / framed.width
    framed = framed.resize((target_w, round(framed.height * scale)), Image.LANCZOS)
    top = CANVAS[1] - framed.height + 150  # bleed ~150px past the bottom edge
    canvas.alpha_composite(framed, (cx - framed.width // 2, top))

    return canvas.convert("RGB")


def main(argv):
    if len(argv) != 4 or argv[1] not in MARKETING:
        print(__doc__)
        print("keys:", ", ".join(MARKETING))
        return 2
    key, src, dst = argv[1], argv[2], argv[3]
    compose(key, src).save(dst, quality=95)
    print(f"  {key:10} -> {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
