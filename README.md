# Bili Lite for iPhone 4s
Version 0.1.5 is a **diagnostic compatibility build** for jailbroken iOS 8.4.1, ARMv7.

## Changes
- Adds explicit `UIDeviceFamily=1` (iPhone), `CFBundleSignature`, correct icon file names, and a legacy `Default@2x.png` launch screen.
- Builds rootful `iphoneos-arm` .deb with gzip compression and checks the application bundle layout.
- iFile post-install output explicitly prints APP_FILES_PRESENT or APP_FILES_MISSING.
- .ipa file also included for users with compatible sideloading tools. iFile normally installs .deb packages, not unsigned IPA files.

## iFile installation
1. Download the latest **successful** workflow artifact on the Actions page and unzip it.
2. In iFile, use Installer on `com.finn.bililite_0.1.5_iphoneos-arm.deb`.
3. Read **all text** in the iFile installation console. It should contain `APP_FILES_PRESENT`.
4. If the app has no icon, check in iFile: `/Applications/BiliLite.app/Info.plist`, and `/var/mobile/Media/BiliLite-install.log`.
5. On iOS 8, old UIKit Tools / uicache implementations can fail to show SpringBoard icons. Update UIKit Tools via Cydia if needed and use its `uicache` tool. Reboot after closing iFile if the files actually exist.

## Limitations
This is not yet verified on a physical iPhone 4s. The Bilibili web API may require authentication or fail with historical TLS support. A passing GitHub build only confirms binary and package structure.
