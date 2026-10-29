#!/usr/bin/env python3
"""Lightweight source and package regression checks for the iOS 8 client.

These checks complement the armv7 compiler and DEB package verification.
They do not replace testing on a physical iPhone 4S.
"""
from pathlib import Path
import plistlib

root = Path(__file__).resolve().parent.parent
source = (root / "main.m").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")
control = (root / "control").read_text(encoding="utf-8")
info = plistlib.loads((root / "Resources/Info.plist").read_bytes())

def contains(fragment, description):
    assert fragment in source, f"Missing regression guard: {description}"

assert "export ARCHS = armv7" in makefile
assert "iphone:clang:10.3:8.0" in makefile
assert "ImageIO" in makefile
assert "SystemConfiguration" in makefile
assert info["MinimumOSVersion"] == "8.0"
assert info["CFBundleIdentifier"] == "com.finn.bililite"
assert info["CFBundleShortVersionString"] == "0.9.1"
assert "Version: 0.9.1" in control

contains("BLFetchImage(", "cover downloader")
contains("kCGImageSourceThumbnailMaxPixelSize", "bounded image decode")
contains("view.accessibilityIdentifier=address?:@\"\";", "image request reuse identity")
assert "UIImage imageWithData:data" not in source, "Full-size image decode regression"
contains("static NSCache *iconCache", "line icon caching")
contains("BLBufferedAhead(", "adaptive video buffer metric")
contains("BLObservedBitrate(", "adaptive throughput metric")
contains("BLQualityForNetwork(", "auto initial quality")
contains("self.autoQuality=NO;", "manual quality lock")
contains("if(!self.liveStream || !self.liveAutomatic", "live manual quality lock")
contains("@interface BLLiveWatchController", "portrait live player")
contains("UIInterfaceOrientationMaskPortrait", "portrait stream view")
contains("UIInterfaceOrientationMaskLandscape", "landscape full screen")
contains("BLLineIcon(12", "fullscreen control")
contains("self.fullscreenPlayer.liveAutomatic=self.qualityAuto;", "live auto state transfer")
contains("self.player.volume=value", "right-side volume gesture")
contains("[UIScreen mainScreen].brightness=value", "left-side brightness gesture")
assert "__unsafe_unretained BLDetailController" not in source
for symbol in ("▶", "↻", "★", "☆", "●", "Ⅱ", "🚀", "📺"):
    assert symbol not in source, f"Glyph icon returned: {symbol}"
print("Source audit passed: package, iOS 8, ARMv7, icons, images, playback, and portrait/live guards")
