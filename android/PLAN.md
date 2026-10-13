# IPTVMac for Android (APK): plan

Status: started 2026-10-13. Flutter + media_kit (the same libmpv builds the iPhone app uses). One codebase that later also builds for Windows.

## Decisions (made with the owner)
- Framework: Flutter, Dart. Player: `media_kit` (libmpv). Database: SQLite with FTS5 (`unicode61 remove_diacritics`), the same schema as `Sources/IPTVCore/AppDatabase.swift`.
- Location: `android/` in this repository (same history, same translations, same website).
- Package id: `io.github.goelir.iptvmac`. Minimum Android 8 (API 26).
- Version 1: phones and tablets, distributed as a signed APK on GitHub Releases (no Play Store yet). Android TV and remote control: version 2.
- Tests: headless emulator only (`emulator -no-window`), never a window popping up; a real phone later.
- Never ship content, never print provider hosts or passwords; the review/demo playlist is the Blender one.

## What is ported (about 2.7k lines of Swift, see the file list in `Sources/IPTVCore` and `Sources/IPTVAppKit`)
M3U parser and classifier, Xtream client and URLs, sync (live / VOD / series / EPG), models and schema, search with scopes, favorites and history, resume points, backup/restore, category hiding, refresh schedule, playback controller (retry, live recovery), speed/seek math, sleep timer, track labels.
The 31 `.lproj/Localizable.strings` files become Flutter `.arb` files by a script (one source of truth stays the Apple strings).

## Phases
0. Toolchain and spike: Flutter + JDK + Android SDK installed; an HLS stream plays through media_kit in the emulator; FTS5 `unicode61` search finds Hebrew and Arabic with and without diacritics.
1. Core in Dart with tests, ported 1:1 from the Swift tests (same fixtures): M3U, Xtream, schema, search, sync.
2. App shell: onboarding, sources, Live / Movies / Series / Library / Settings, search, details, series.
3. Player: touch controls and gestures, speed, tracks, subtitles, sleep timer, Picture in Picture (Android Activity PiP), background audio and notification controls.
4. Release: signed APK, `scripts/release` equivalent, website download button, privacy/acknowledgements screens.
5. Android TV (leanback, D-pad focus), then Windows from the same code.

## Risks
- Live stream robustness on many devices (hardware decoding differs). Mitigation: `hwdec=mediacodec-copy` with software fallback.
- FTS5 availability in the SQLite that ships with Android (old versions lack it). Mitigation: bundle SQLite (`sqlite3_flutter_libs`), tested in phase 0.
- 100k-item sync speed in Dart isolates. Mitigation: batch inserts in a transaction, measured against the Swift numbers (search under 250 ms).
- Play Store policy for IPTV players (not needed for the APK route).
