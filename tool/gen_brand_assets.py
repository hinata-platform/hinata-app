#!/usr/bin/env python3
"""Hivora v2 brand-asset generator — honey-amber hex-mark on warm paper.

Pure stdlib (math + zlib + struct): rasterises the Hivora hex-mark with an
analytic distance field (perfect round caps/joins + 1px AA, matching the in-app
`HexMark`/`HiveLoader` painter) and writes every platform icon / splash PNG at
its existing dimensions. No Flutter SDK, Pillow or ImageMagick required.

Design (chosen 2026-06-14): amber mark (#D9A032) on warm-paper (#F4F3EF),
echoing the in-app brand lockup. Amber is constant across light & dark, so
night-mode splash marks are identical (only the background colour differs).
"""
import math
import os
import struct
import zlib

# ---- v2 palette --------------------------------------------------------------
ACCENT = (0xD9, 0xA0, 0x32)   # honey-amber signature mark
LINE   = (0xE4, 0xCE, 0x96)   # accentLine — subtle tile border
PAPER  = (0xF4, 0xF3, 0xEF)   # warm-paper canvas (light bg)
DARK   = (0x13, 0x11, 0x19)   # v2 canvasDark (dark bg)

# ---- logo geometry in the 120-unit design space (matches HexMark) -----------
HEX = [(60, 14), (99.8, 37), (99.8, 83), (60, 106), (20.2, 83), (20.2, 37)]
BAR = ((20.2, 60), (99.8, 60))
STROKE = 11.0  # stroke width in design units

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---- PNG encoding ------------------------------------------------------------
def write_png(path, w, h, buf):
    """buf: bytearray of length w*h*4 (straight RGBA, 8-bit)."""
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)  # filter type 0 (None)
        raw.extend(buf[y * stride:(y + 1) * stride])
    comp = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))


# ---- distance helpers --------------------------------------------------------
def _seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    L2 = vx * vx + vy * vy
    if L2 == 0:
        dx, dy = px - ax, py - ay
        return math.sqrt(dx * dx + dy * dy)
    t = ((px - ax) * vx + (py - ay) * vy) / L2
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    dx = px - (ax + t * vx)
    dy = py - (ay + t * vy)
    return math.sqrt(dx * dx + dy * dy)


def _rrect_sdf(px, py, cx, cy, hw, hh, r):
    """Signed distance to a rounded rect centred at (cx,cy); <0 inside."""
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax = max(qx, 0.0)
    ay = max(qy, 0.0)
    return math.sqrt(ax * ax + ay * ay) + min(max(qx, qy), 0.0) - r


def _over(dst, i, color, a):
    """Composite straight-alpha `color` (a in 0..1) over dst[i..i+4]."""
    if a <= 0:
        return
    if a > 1:
        a = 1.0
    db = dst[i + 3] / 255.0
    out_a = a + db * (1 - a)
    if out_a <= 0:
        return
    for k in range(3):
        sc = color[k]
        dc = dst[i + k]
        dst[i + k] = int(round((sc * a + dc * db * (1 - a)) / out_a))
    dst[i + 3] = int(round(out_a * 255))


# ---- master renderer ---------------------------------------------------------
def render(size, *, frac, bg, mark=ACCENT, tile=None, border=False, aa=1.0):
    """Render one square master at `size`px.

    frac   : mark width as fraction of `size` (the 120-box scaled)
    bg     : (r,g,b) opaque background, or None for transparent
    tile   : None, or dict(inset=frac, radius=frac, fill=(r,g,b)) rounded tile
    border : draw a subtle amber-line rounded border inset in the canvas
    """
    n = size * size * 4
    buf = bytearray(n)
    if bg is not None:
        for i in range(0, n, 4):
            buf[i] = bg[0]; buf[i + 1] = bg[1]; buf[i + 2] = bg[2]; buf[i + 3] = 255

    # rounded tile (macOS-style)
    if tile is not None:
        inset = tile["inset"] * size
        hw = (size - 2 * inset) / 2
        r = tile["radius"] * (size - 2 * inset)
        cx = cy = size / 2
        x0 = int(inset - 1); x1 = int(size - inset + 2)
        y0 = int(inset - 1); y1 = int(size - inset + 2)
        fill = tile["fill"]
        for y in range(max(0, y0), min(size, y1)):
            for x in range(max(0, x0), min(size, x1)):
                d = _rrect_sdf(x + 0.5, y + 0.5, cx, cy, hw, hw, r)
                cov = 0.5 - d / aa
                if cov <= 0:
                    continue
                _over(buf, (y * size + x) * 4, fill, cov if cov < 1 else 1.0)

    # subtle amber-line inner border
    if border:
        bi = 0.085 * size
        hw = (size - 2 * bi) / 2
        r = 0.20 * (size - 2 * bi)
        cx = cy = size / 2
        bw = max(1.0, size * 0.016)  # border stroke width
        for y in range(size):
            for x in range(size):
                d = abs(_rrect_sdf(x + 0.5, y + 0.5, cx, cy, hw, hw, r))
                cov = (bw / 2 - d) / aa + 0.5
                if cov <= 0:
                    continue
                _over(buf, (y * size + x) * 4, LINE, min(cov, 1.0) * 0.9)

    # the hex-mark itself (distance field over its bounding box only)
    scale = size * frac / 120.0
    off = size / 2 - 60 * scale
    half = STROKE / 2 * scale

    def D(p):  # design point -> pixel
        return (off + p[0] * scale, off + p[1] * scale)

    segs = []
    for k in range(len(HEX)):
        a = D(HEX[k]); b = D(HEX[(k + 1) % len(HEX)])
        segs.append((a[0], a[1], b[0], b[1]))
    ba, bb = D(BAR[0]), D(BAR[1])
    segs.append((ba[0], ba[1], bb[0], bb[1]))

    pad = half + aa + 1
    minx = max(0, int(off + 20.2 * scale - pad))
    maxx = min(size, int(off + 99.8 * scale + pad) + 1)
    miny = max(0, int(off + 14 * scale - pad))
    maxy = min(size, int(off + 106 * scale + pad) + 1)

    for y in range(miny, maxy):
        py = y + 0.5
        row = y * size
        for x in range(minx, maxx):
            px = x + 0.5
            d = 1e9
            for s in segs:
                dd = _seg_dist(px, py, s[0], s[1], s[2], s[3])
                if dd < d:
                    d = dd
                    if d <= 0:
                        break
            cov = (half - d) / aa + 0.5
            if cov <= 0:
                continue
            _over(buf, (row + x) * 4, mark, min(cov, 1.0))
    return buf, size


# ---- area-average downscale --------------------------------------------------
def resize(buf, src, dst):
    if src == dst:
        return buf
    out = bytearray(dst * dst * 4)
    sf = src / dst
    for ty in range(dst):
        sy0 = ty * sf; sy1 = (ty + 1) * sf
        iy0 = int(sy0); iy1 = min(src, int(math.ceil(sy1)))
        for tx in range(dst):
            sx0 = tx * sf; sx1 = (tx + 1) * sf
            ix0 = int(sx0); ix1 = min(src, int(math.ceil(sx1)))
            ar = ag = ab = aa_ = wsum = 0.0
            for yy in range(iy0, iy1):
                wy = min(sy1, yy + 1) - max(sy0, yy)
                base = (yy * src + ix0) * 4
                for xx in range(ix0, ix1):
                    wx = min(sx1, xx + 1) - max(sx0, xx)
                    w = wx * wy
                    i = base + (xx - ix0) * 4
                    al = buf[i + 3] / 255.0
                    ar += buf[i] * al * w
                    ag += buf[i + 1] * al * w
                    ab += buf[i + 2] * al * w
                    aa_ += al * w
                    wsum += w
            o = (ty * dst + tx) * 4
            if aa_ > 0:
                out[o] = int(round(ar / aa_))
                out[o + 1] = int(round(ag / aa_))
                out[o + 2] = int(round(ab / aa_))
            out[o + 3] = int(round(aa_ / wsum * 255)) if wsum > 0 else 0
    return out


def solid(size, color, alpha=255):
    buf = bytearray(size * size * 4)
    for i in range(0, len(buf), 4):
        buf[i] = color[0]; buf[i + 1] = color[1]; buf[i + 2] = color[2]
        buf[i + 3] = alpha
    return buf


# ---- design definitions ------------------------------------------------------
def p(*a):
    return os.path.join(ROOT, *a)


def main():
    # Master designs: (master_size, kwargs)
    designs = {}

    def master(name, size, **kw):
        designs[name] = (size, *render(size, **kw))

    master("icon",      1024, frac=0.54, bg=PAPER, border=True)
    master("maskable",   512, frac=0.46, bg=PAPER)
    master("macos",     1024, frac=0.40, bg=None,
           tile=dict(inset=0.096, radius=0.2237, fill=PAPER))
    master("splash",    1152, frac=0.46, bg=None)
    master("android12", 1152, frac=0.52, bg=None)
    master("fg",         512, frac=0.42, bg=None)   # adaptive foreground
    master("favicon",     64, frac=0.66, bg=PAPER)

    def emit(design, out, size):
        msize, buf, _ = designs[design]
        write_png(out, size, size, resize(buf, msize, size))
        print(f"  {size:>5}px  {os.path.relpath(out, ROOT)}")

    # ---- branding sources ----
    print("branding/")
    emit("icon", p("assets/branding/app_icon.png"), 1024)
    emit("fg",   p("assets/branding/app_icon_foreground.png"), 1024)
    emit("splash", p("assets/branding/splash_icon.png"), 1152)
    emit("splash", p("assets/branding/splash_icon_dark.png"), 1152)

    # ---- web ----
    print("web/")
    emit("favicon", p("web/favicon.png"), 16)
    emit("icon",     p("web/icons/Icon-192.png"), 192)
    emit("icon",     p("web/icons/Icon-512.png"), 512)
    emit("maskable", p("web/icons/Icon-maskable-192.png"), 192)
    emit("maskable", p("web/icons/Icon-maskable-512.png"), 512)

    # ---- android mipmaps (launcher) ----
    print("android mipmaps/")
    mip = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for d, s in mip.items():
        emit("icon", p(f"android/app/src/main/res/mipmap-{d}/ic_launcher.png"), s)

    # ---- android adaptive foreground + monochrome ----
    print("android adaptive/")
    fg = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for d, s in fg.items():
        emit("fg", p(f"android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png"), s)
        emit("fg", p(f"android/app/src/main/res/drawable-{d}/ic_launcher_monochrome.png"), s)

    # ---- android splash images (light + night share the amber mark) ----
    print("android splash/")
    spl = {"mdpi": 288, "hdpi": 432, "xhdpi": 576, "xxhdpi": 864, "xxxhdpi": 1152}
    for variant in ("", "-night"):
        for d, s in spl.items():
            emit("splash",    p(f"android/app/src/main/res/drawable{variant}-{d}/splash.png"), s)
            emit("android12", p(f"android/app/src/main/res/drawable{variant}-{d}/android12splash.png"), s)

    # ---- android 1x1 background tiles ----
    print("android backgrounds/")
    for d in ("drawable", "drawable-v21"):
        write_png(p(f"android/app/src/main/res/{d}/background.png"), 1, 1, solid(1, PAPER))
    for d in ("drawable-night", "drawable-night-v21"):
        write_png(p(f"android/app/src/main/res/{d}/background.png"), 1, 1, solid(1, DARK))

    # ---- iOS app icon set ----
    print("iOS AppIcon/")
    ios = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-50x50@1x.png": 50, "Icon-App-50x50@2x.png": 100,
        "Icon-App-57x57@1x.png": 57, "Icon-App-57x57@2x.png": 114,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-72x72@1x.png": 72, "Icon-App-72x72@2x.png": 144,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167, "Icon-App-1024x1024@1x.png": 1024,
    }
    base = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for fn, s in ios.items():
        emit("icon", p(base, fn), s)

    # ---- iOS launch image (transparent amber mark) + bg colorset tiles ----
    print("iOS launch/")
    for fn, s in {"LaunchImage.png": 128, "LaunchImage@2x.png": 256, "LaunchImage@3x.png": 384}.items():
        emit("splash", p("ios/Runner/Assets.xcassets/LaunchImage.imageset", fn), s)
    write_png(p("ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png"), 1, 1, solid(1, PAPER))
    write_png(p("ios/Runner/Assets.xcassets/LaunchBackground.imageset/darkbackground.png"), 1, 1, solid(1, DARK))

    # ---- macOS app icon set (rounded tile) ----
    print("macOS AppIcon/")
    mac = {16: "16", 32: "32", 64: "64", 128: "128", 256: "256", 512: "512", 1024: "1024"}
    mbase = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for s, tag in mac.items():
        emit("macos", p(mbase, f"app_icon_{tag}.png"), s)

    print("done.")


if __name__ == "__main__":
    main()
