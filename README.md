# 视频解析下载

Flutter iOS app for parsing user-accessible web video pages, sniffing media resources, downloading videos, merging HLS/m3u8 to mp4, and managing local files.

## UI

- Material 3 iPhone-style interface.
- Light and dark mode.
- Blue-purple gradient primary visual style.
- Bottom tabs: Home, Downloads, Library, Settings.
- Resource bottom sheet with real sniffed URLs, type, metadata, copy link, and download actions.

## Core Requirements Covered

- `flutter_inappwebview` for built-in WebView, resource callbacks, JavaScript hook, and cookie-aware sniffing.
- `video_player` for playback page.
- `ffmpeg_kit_flutter_new` for m3u8/ts merge path. This is the maintained full-GPL successor used because the original `ffmpeg_kit_flutter_full_gpl` iOS binary pod currently returns 404 in CI.
- Files are designed to save under `Documents/videos/`.
- iOS file sharing is enabled in `Info.plist`.
- Downloader service includes progress, cancel, pause/retry states, HTML mis-save guard, safe filenames, and HLS merge command path.

## Local Run

```bash
flutter pub get
flutter run
```

## iOS Unsigned IPA

GitHub Actions builds `VidSniffer-Pro-unsigned.ipa` on push to `main`.
