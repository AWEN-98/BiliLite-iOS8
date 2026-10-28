# Bili Lite: iPhone 4s / iOS 8.4.1

v0.1.6 is a compatibility diagnostic package. Earlier releases contained a post-install script that could exit 1, shown by iFile as **result 256**. This build deliberately removes all maintainer scripts and the nonessential dependency declaration to isolate the install mechanism.

1. Close Cydia completely before installing with iFile.
2. Download the latest successful v0.1.6 GitHub Actions artifact and unzip the .deb.
3. In iFile, tap .deb then choose Installer. Look for the actual error text above the final code, not just the return code.
4. If result 0, inspect /Applications/BiliLite.app in iFile. If it exists and the icon does not, refresh the icon cache or reboot.
5. If result 256, record the **entire iFile installer console**, especially dpkg error text. The stripped package cannot fail due to our old postinst script.
6. Do not delete jailbreak system directories or modify system packages.

The .deb is rootful iphoneos-arm, with gzip data compression. An IPA is generated as an alternate artifact, but it requires a compatible installer and signing configuration. GitHub Actions verifies the app's Info.plist, executable, icon, version, target architecture, and absence of install scripts. Device launch and Bilibili playback are not yet verified.
