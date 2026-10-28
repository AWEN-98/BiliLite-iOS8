#!/usr/bin/env python3
"""Generate minimal iOS 8 compatible PNG app icons without third-party packages."""
import os
import struct
import zlib


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


def png(width, height):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            # Raspberry-colored background and a clean white play triangle.
            u, v = x / width, y / height
            bg = (233, 72, 117)
            # Triangle pointing to the right; preserve large surrounding margins.
            inside = (0.32 <= u <= 0.75 and abs(v - 0.5) < (u - 0.28) * 0.58)
            raw.extend((255, 255, 255, 255) if inside else (*bg, 255))
    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )


os.makedirs("Resources", exist_ok=True)
for filename, size in (("Icon.png", 57), ("Icon@2x.png", 114), ("Icon-120.png", 120)):
    with open(os.path.join("Resources", filename), "wb") as file:
        file.write(png(size, size))
with open(os.path.join("Resources", "Default@2x.png"), "wb") as file:
    file.write(png(640, 960))
print("Generated three icons and an iPhone 4s launch screen")
