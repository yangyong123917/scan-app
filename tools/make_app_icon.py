"""Generate the ScanLite app icon (1024x1024, RGB, no alpha) with only the stdlib.

Rendering is done with signed-distance fields plus analytic coverage, so the
edges come out anti-aliased without any supersampling.

Usage:  python make_app_icon.py <output.png>
"""

import math
import os
import struct
import sys
import time
import zlib

S = 1024

# ---------- palette ----------
BG_TOP = (92, 152, 255)     # #5C98FF
BG_BOT = (18, 62, 198)      # #123EC6
SHADOW = (6, 26, 78)
LINE = (199, 213, 236)      # #C7D5EC
BRACKET = (30, 92, 232)     # #1E5CE8

# ---------- geometry ----------
SHEET_CX, SHEET_CY = 512.0, 512.0
SHEET_HW, SHEET_HH, SHEET_R = 240.0, 306.0, 54.0

SHADOW_DX, SHADOW_DY = 12.0, 28.0
SHADOW_ALPHA = 0.185

# text placeholder lines: (centre_x, centre_y, half_width), half_height 13
LINES = ((512.0, 442.0, 130.0), (512.0, 512.0, 130.0), (467.0, 582.0, 85.0))
LINE_HH = 13.0

# scan brackets, half thickness 14
SEGS = (
    (324.0, 396.0, 324.0, 258.0), (324.0, 258.0, 462.0, 258.0),
    (562.0, 258.0, 700.0, 258.0), (700.0, 258.0, 700.0, 396.0),
    (700.0, 628.0, 700.0, 766.0), (700.0, 766.0, 562.0, 766.0),
    (462.0, 766.0, 324.0, 766.0), (324.0, 766.0, 324.0, 628.0),
)
SEG_HALF = 14.0

# glow (upper-left highlight)
GLOW_CX, GLOW_CY, GLOW_R, GLOW_A = 82.0, -102.0, 800.0, 0.13

_GRAD = (0.42, 0.91)
_GN = math.hypot(*_GRAD)
GX, GY = _GRAD[0] / _GN, _GRAD[1] / _GN
TMAX = GX * S + GY * S


def sd_round_box(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    ax = qx if qx > 0.0 else 0.0
    ay = qy if qy > 0.0 else 0.0
    inner = qx if qx > qy else qy
    if inner > 0.0:
        inner = 0.0
    return inner + math.hypot(ax, ay) - r


def sd_segment(px, py, ax, ay, bx, by):
    bax = bx - ax
    bay = by - ay
    pax = px - ax
    pay = py - ay
    den = bax * bax + bay * bay
    h = 0.0 if den == 0.0 else (pax * bax + pay * bay) / den
    if h < 0.0:
        h = 0.0
    elif h > 1.0:
        h = 1.0
    return math.hypot(pax - bax * h, pay - bay * h)


def cov(d):
    """Analytic pixel coverage from a signed distance."""
    c = 0.5 - d
    if c <= 0.0:
        return 0.0
    if c >= 1.0:
        return 1.0
    return c


def render():
    buf = bytearray(S * S * 3)
    span = SHEET_HW - SHEET_R
    span_y = SHEET_HH - SHEET_R
    t0 = time.time()

    for y in range(S):
        py = y + 0.5
        base = y * S * 3
        for x in range(S):
            px = x + 0.5

            # background gradient
            t = (px * GX + py * GY) / TMAX
            r = BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t
            g = BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t
            b = BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t

            # upper-left highlight
            if py < 700.0:
                gdx = px - GLOW_CX
                gdy = py - GLOW_CY
                gd2 = gdx * gdx + gdy * gdy
                if gd2 < GLOW_R * GLOW_R:
                    a = GLOW_A * (1.0 - math.sqrt(gd2) / GLOW_R)
                    a *= a
                    r += (255.0 - r) * a
                    g += (255.0 - g) * a
                    b += (255.0 - b) * a

            # drop shadow under the sheet
            if 262.0 < px < 786.0 and 238.0 < py < 878.0:
                d = sd_round_box(px, py,
                                 SHEET_CX + SHADOW_DX, SHEET_CY + SHADOW_DY,
                                 SHEET_HW, SHEET_HH, SHEET_R)
                if d < 0.5:
                    a = cov(d) * SHADOW_ALPHA
                    r += (SHADOW[0] - r) * a
                    g += (SHADOW[1] - g) * a
                    b += (SHADOW[2] - b) * a

            # the document sheet
            if 256.0 < px < 768.0 and 190.0 < py < 834.0:
                dx = px - SHEET_CX
                dy = py - SHEET_CY
                qx = abs(dx) - span
                qy = abs(dy) - span_y
                ax = qx if qx > 0.0 else 0.0
                ay = qy if qy > 0.0 else 0.0
                inner = qx if qx > qy else qy
                if inner > 0.0:
                    inner = 0.0
                d = inner + math.hypot(ax, ay) - SHEET_R
                if d < 0.5:
                    a = cov(d)
                    r += (255.0 - r) * a
                    g += (255.0 - g) * a
                    b += (255.0 - b) * a

                    # text placeholder lines
                    if 415.0 < py < 596.0:
                        for cx, cy, hw in LINES:
                            dl = sd_round_box(px, py, cx, cy, hw, LINE_HH, LINE_HH)
                            if dl < 0.5:
                                al = cov(dl)
                                r += (LINE[0] - r) * al
                                g += (LINE[1] - g) * al
                                b += (LINE[2] - b) * al

                    # scan brackets
                    if 300.0 < px < 724.0 and 234.0 < py < 790.0:
                        for ax0, ay0, bx0, by0 in SEGS:
                            ds = sd_segment(px, py, ax0, ay0, bx0, by0) - SEG_HALF
                            if ds < 0.5:
                                ab = cov(ds)
                                r += (BRACKET[0] - r) * ab
                                g += (BRACKET[1] - g) * ab
                                b += (BRACKET[2] - b) * ab

            i = base + x * 3
            buf[i] = 255 if r > 255.0 else (0 if r < 0.0 else int(r + 0.5))
            buf[i + 1] = 255 if g > 255.0 else (0 if g < 0.0 else int(g + 0.5))
            buf[i + 2] = 255 if b > 255.0 else (0 if b < 0.0 else int(b + 0.5))

        if y % 128 == 0:
            print("  row %d/1024  (%.1fs)" % (y, time.time() - t0), flush=True)

    return buf


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


def write_png(path, buf):
    raw = bytearray()
    stride = S * 3
    for y in range(S):
        raw.append(0)                       # filter type 0
        raw += buf[y * stride:(y + 1) * stride]
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    d = os.path.dirname(os.path.abspath(path))
    if d and not os.path.isdir(d):
        os.makedirs(d, exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)
    return len(png)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
    print("rendering 1024x1024 ...", flush=True)
    buf = render()
    size = write_png(out, buf)
    print("written: %s  (%d bytes)" % (out, size), flush=True)


if __name__ == "__main__":
    main()
