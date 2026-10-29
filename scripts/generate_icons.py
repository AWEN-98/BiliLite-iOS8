#!/usr/bin/env python3
"""Generate lightweight pure-color linear icons for the iOS 8 app."""
import math
import os
import struct
import zlib


PINK = (233, 72, 117)
WHITE = (255, 255, 255)
LAUNCH_BG = (248, 249, 251)
SAMPLES = 4


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


def rounded_rect_distance(x, y, x0, y0, x1, y1, radius):
    cx = (x0 + x1) / 2.0
    cy = (y0 + y1) / 2.0
    qx = abs(x - cx) - ((x1 - x0) / 2.0 - radius)
    qy = abs(y - cy) - ((y1 - y0) / 2.0 - radius)
    outside = math.sqrt(max(qx, 0.0) ** 2 + max(qy, 0.0) ** 2)
    inside = min(max(qx, qy), 0.0)
    return outside + inside - radius


def segment_distance(x, y, x1, y1, x2, y2):
    dx, dy = x2 - x1, y2 - y1
    length2 = dx * dx + dy * dy
    if length2 <= 1e-12:
        return math.sqrt((x - x1) ** 2 + (y - y1) ** 2)
    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / length2))
    px, py = x1 + t * dx, y1 + t * dy
    return math.sqrt((x - px) ** 2 + (y - py) ** 2)


def logo_line(x, y):
    screen = abs(rounded_rect_distance(x, y, .20, .23, .80, .74, .065)) <= .018
    triangle = (
        segment_distance(x, y, .435, .355, .435, .625) <= .014 or
        segment_distance(x, y, .435, .355, .635, .490) <= .014 or
        segment_distance(x, y, .435, .625, .635, .490) <= .014
    )
    stand = (
        segment_distance(x, y, .50, .74, .50, .785) <= .012 or
        segment_distance(x, y, .415, .80, .585, .80) <= .012
    )
    return screen or triangle or stand


def launch_badge_inside(x, y, x0, y0, side):
    return rounded_rect_distance(x, y, x0, y0, x0 + side, y0 + side, side * .12) <= 0


def render_png(width, height, launch=False):
    raw = bytearray()
    side = min(width, height) * .30 if launch else 0
    x0, y0 = (width - side) / 2.0, (height - side) / 2.0
    for py in range(height):
        raw.append(0)
        for px in range(width):
            total = [0, 0, 0]
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    x = px + (sx + .5) / SAMPLES
                    y = py + (sy + .5) / SAMPLES
                    if launch:
                        if launch_badge_inside(x, y, x0, y0, side):
                            u, v = (x - x0) / side, (y - y0) / side
                            color = WHITE if logo_line(u, v) else PINK
                        else:
                            color = LAUNCH_BG
                    else:
                        u, v = x / width, y / height
                        color = WHITE if logo_line(u, v) else PINK
                    total[0] += color[0]
                    total[1] += color[1]
                    total[2] += color[2]
            count = SAMPLES * SAMPLES
            raw.extend((round(total[0] / count), round(total[1] / count), round(total[2] / count), 255))
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )


os.makedirs("Resources", exist_ok=True)
for filename, size in (("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-120.png", 120)):
    with open(os.path.join("Resources", filename), "wb") as file:
        file.write(render_png(size, size))
with open(os.path.join("Resources", "Default@2x.png"), "wb") as file:
    file.write(render_png(640, 960, launch=True))
print("Generated pure-color linear BiliLite icons and a lightweight launch screen")
