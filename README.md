# BiliLite 2 · iOS 8

轻量原生 B 站客户端，面向越狱的 iPhone 4S / iOS 8.4.1，目标架构 ARMv7，rootful DEB。

## 当前版本：0.8.1

- 推荐、热门、搜索、收藏、历史和直播入口
- 自绘 AVPlayer 播放界面，横屏全屏播放
- 进度拖动、前后 15 秒、0.5× 至 2× 倍速、长按临时 2×
- 本地记忆视频播放进度
- 请求所选清晰度失败时自动尝试 360P
- 纯色背景与白色线性播放图标，适配旧设备

## 安装

下载 [BiliLite-iOS8-v0.8.1.deb](https://raw.githubusercontent.com/AWEN-98/BiliLite-iOS8/main/downloads/BiliLite-iOS8-v0.8.1.deb)，用 iFile 打开 DEB 并选择安装。可直接覆盖旧版，建议安装前先退出 BiliLite。

## 兼容性说明

播放器采用 iOS 原生 AVPlayer，支持系统可解码的 MP4 与兼容 HLS。B 站部分 DASH 分离音视频、DRM、HEVC 或受限视频源仍可能无法播放，播放器界面无法绕过源站鉴权或设备解码能力。云端编译通过不代表已在实体 iPhone 4S 上完成全部播放场景验证。
