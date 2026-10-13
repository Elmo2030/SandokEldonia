# Player (Android, Flutter + media_kit / libmpv)

The model is the iPhone player (`ios/Sources/Player`, `Sources/IPTVPlayer`). The contract with the app shell is `play_request.dart`
(`PlayRequest`, `PlayerHost`): the shell pushes `PlayerScreen(request:, host:)`; the player never touches the library database.

```dart
// main(): WidgetsFlutterBinding.ensureInitialized(); MediaKit.ensureInitialized();
// MaterialApp needs AppLocalizations.localizationsDelegates (generated l10n).
Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(request: r, host: host)));
```

`PlayerHost.closePlayer()` is what the player calls when the user closes it (close button, system back, notification stop, sleep timer,
flick down); the shell pops the screen. Leaving the screen by any other way saves the position and tears down, without calling
`closePlayer` again.

## Structure

Pure Dart (tested on the host, no libmpv): `playback_controller.dart` (retry and live recovery with a fresh budget after playing
again, load generations so a stale retry never reloads an old item, resume position, end of file, a paused live stream that went
stale is reloaded, progress never saved as 0 or for live), `playback_watch.dart` (LiveRecovery, EndOfMedia, PauseClock,
ControlsVisibility), `playback_speed.dart`, `seek_bar_math.dart`, `sleep_timer.dart`, `track_label.dart`, `player_gestures.dart`
(zones, drag axis, scrub, level, pinch, SkipAccumulator), `player_options.dart` (VideoScale, BufferSize, hardened mpv options),
`system_policy.dart` (InterruptionPolicy, NowPlayingThrottle), `up_next.dart`.

Engine: `engine.dart` is the interface the controller needs; `media_kit_engine.dart` is libmpv through media_kit (hwdec
`mediacodec-copy,auto-safe`, hardened network options, subtitle files, tracks). Tests use `test/player/fake_engine.dart`.

UI: `player_model.dart` (state and gestures, the counterpart of PhonePlayer.swift), `player_screen.dart` (layout),
`player_controls.dart` (top bar, transport, bottom panel and menus), `player_seek_bar.dart`, `player_sheets.dart` (speed, subtitle
adjust), `player_gesture_surface.dart`, `player_widgets.dart` (HUD, error card, up-next card).

System: `player_system.dart` (the interface, no-op by default), `android_player_system.dart` (system bars, landscape on phones,
wake lock, brightness, volume, PiP over the `io.github.goelir.iptvmac/pip` channel), `media_session.dart` (audio_service
notification and audio focus through audio_session), `android/app/src/main/kotlin/.../MainActivity.kt` (PiP, a play/pause remote
action, auto-enter, notification permission), `AndroidManifest.xml` (PiP, foreground service, permissions).

`missing_strings.dart`: the one English literal (notification channel name). `player_prefs.dart`: settings read with the Apple key
names (`seekStep`, `barsHideSeconds`, `bufferSize`, `videoScale`, `subScale`, `subDelay`, `autoNextEpisode`, `prefSubLang`,
`prefAudioLang`) from shared_preferences.

## Run

Lab (no shell): `flutter build apk --debug -t lib/main_player_lab.dart` (set `ANDROID_HOME` and `JAVA_HOME`), then
`adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk`. Own streams:
`--dart-define=LAB_URLS="Title|https://host/a.m3u8,Name (live)|https://host/b.ts"`.
Tests: `cd flutter && flutter test test/player`.

## Verification

See the end of this file (filled in from the device runs).
