# Downloads (Android)

Save a movie or an episode from your own source to the phone and watch it offline. The Mac app has the same feature
(`Sources/IPTVMac/Downloads.swift`); the iPhone app ships without it on purpose (App Review). The Android APK is distributed
outside a store, so it has it. The app still contains no content: it only fetches what your own provider serves to your own login.

## What can be downloaded

Direct files only, in this first version:

- a movie (`ItemType.movie`) of an Xtream source with a video container (`mp4 mkv avi mov m4v ts webm flv wmv mpg mpeg m2ts mts 3gp`,
  or no container: Xtream then serves `.mp4`), or of an M3U playlist whose http(s) address ends in one of those extensions;
- an episode of an Xtream series (same rule for its container).

Not downloadable, and the button is not shown: live channels, HLS/DASH playlists (`.m3u8`, `.mpd`, or any other extension), M3U movies
whose address has no extension (cannot tell it is one file), rtmp/rtsp/udp addresses. HLS is a later version.
`LibraryDownloads.canDownload / canDownloadEpisode` decide (`library_downloads.dart`); the extension list is `DownloadNaming.videoExtensions`.

## Structure

| File | What |
|---|---|
| `download_naming.dart` | `DownloadNaming.fileName`: port of `Sources/IPTVCore/DownloadNaming.swift` (same rules, same test cases in `test/downloads/download_naming_test.dart`): unsafe characters become `-`, video extensions only (else `.mp4`), at most 120 characters and 200 bytes, `Name (2).mkv` when taken. `isDirectFile`. |
| `download_engine.dart` | `DownloadEngine`: the small interface the queue needs (`enqueue`, `pause`, `resume`, `cancel`, `updates` stream, `known()` for startup, `start()`), `EngineJob`, `EngineUpdate`, `EngineState`, `EngineError`. |
| `background_download_engine.dart` | The real engine on the `background_downloader` package (WorkManager). |
| `download_entry.dart` | `DownloadEntry`: one row of the list (JSON in and out) and `DownloadStatus` (queued, running, paused, done, failed, canceled). |
| `downloads_model.dart` | `DownloadsModel` (ChangeNotifier): the list, persistence, engine updates, startup reconcile, `add / pause / resume / remove / removeAllDone`. `DownloadsModel.disabled()` for platforms without downloads. |
| `library_downloads.dart` | Extension on `LibraryModel`: `canDownload`, `downloadUrl` (rebuilds the URL), `itemFor`, `offlineRequest`, `downloadMovie / downloadEpisode`. |
| `open_downloads.dart` | Builds the real model for `main.dart` (Android only; anything else or any failure gives the disabled model). |

UI is in `lib/ui`: `download_button.dart` (movie sheet in `details_sheet.dart`, each episode row and "Download season" in
`series_screen.dart`), `downloads_screen.dart` (reached from the Library tab's app bar and from Settings; a count badge on the Library
tab while something runs). `IptvApp(downloads:)` provides the model; without it the model is `disabled()` and nothing shows.

## How it works

1. **Add.** The button asks the library for the file extension and calls `DownloadsModel.add`. The model picks a safe unused name in
   `Downloads/` (also unique against the other entries, case-insensitively), writes the entry to the list, rebuilds the stream URL
   (`LibraryModel.downloadUrl`: the same URL builders as playback, password from memory/secret store) and hands the engine an
   `EngineJob(id, url, path, title)`. If the Xtream password is not stored, the usual password dialog opens instead.
2. **Engine.** `background_downloader` runs the job in WorkManager as a foreground service (type `dataSync`): it goes on in the
   background and after the app was closed, retries and resumes after a dropped connection, and shows one notification per file. One
   download at a time (the package's holding queue, `maxConcurrent` 1: many providers allow a single connection). Unfinished data goes
   to `Downloads/.partial` (same volume, so finishing is a rename). Less than 1 GB left after the download: the package fails the job,
   the model records `noSpace` and the screen says `downloadsNoSpace`. Checked by the package from the size the server reports, so the
   refusal comes when the download starts, not before the tap.
3. **State.** Engine updates (state and bytes) are mapped onto the entry; the list is saved on every state change. The notification's own
   Pause/Cancel buttons work: a cancel there shows as "Canceled" with a retry button.
4. **Startup.** `DownloadsModel.load()`: read the list, listen to the engine, `engine.start()` (delivers what happened while closed), then
   reconcile: unfinished entries take the engine's state; if the engine forgot a job and its file exists it is done, otherwise it is
   marked failed ("interrupted", with a retry button that rebuilds the URL and starts again from zero). Finished entries whose file
   is gone are marked `missing` (shown in the list, no play button, "Remove from the list"). The Downloads screen re-checks files each time it opens.
5. **Offline play.** `LibraryModel.offlineRequest(entry)`: a `PlayRequest` with `url = Uri.file(path)`, the library item (`itemFor`: the
   catalogue row, or a stand-in with the same key when the catalogue no longer has it) and the resume position. For an episode the file URL
   is registered with `rememberEpisode`, so the player host saves progress as `ep:<episodeId>`: the SAME key as streaming it. Favorites work
   too. The player is unchanged: libmpv opens `file://` URLs, and nothing in `lib/player` needs the network.

## Privacy and secrets

- `downloads.json` (app support folder, next to `iptv.sqlite`, NOT inside it: the schema stays identical to the Apple apps) holds id, library key
  (account id, type, stream id, episode id), title, season/episode, extension, file path, status, bytes, error. No URL, host, user name or
  password: `test/downloads/downloads_model_test.dart` asserts that. The URL is rebuilt from the library whenever it is needed.
- The engine needs the URL to resume, which is unavoidable. `background_downloader` keeps its task records (URL included) in its own
  private storage; `BackgroundDownloadEngine` deletes a record when the job ends or is canceled, and `known()` purges ended ones at the
  next start. The records of unfinished jobs stay until then. (The app does not set `android:allowBackup="false"`: those records live
  in app-private storage that Android Auto Backup may copy while a download is unfinished. The owner's call, same for the rest of the app.)
- Notifications show the title only (`{displayName}`, plus the progress bar and the percentage). File names come from the title. No URL, host or
  login in a notification, a file name, a log line (the package logs nothing on Android: checked by grep, not on a device) or the UI.

## Where the files are

`getExternalFilesDir(null)/Downloads/`, that is `Android/data/io.github.goelir.iptvmac/files/Downloads/` on shared storage: the app's own
folder, no permission needed, removed with the app. Android 11+ hides `Android/data` from other apps and from the system Files app; a file
manager with USB access, a computer (USB) or `adb pull` can still reach it. Playing is meant to happen inside IPTVMac (tap a finished download).
Moving files to the public Downloads/Movies folder is not done in this version.

## Limits

- No HLS/DASH (see above), no parallel downloads, no scheduling, no "only on Wi-Fi" switch.
- A paused download needs a server that supports ranges (most do); if not, the pause does nothing.
- Jobs waiting in the holding queue are lost if the app is killed before they start (the package's rule); at the next start they show as
  "interrupted" and a tap restarts them.
- Playing the next episode after an offline one asks the provider for the next episode online (even if it is downloaded).
- The package's Android notification buttons (Cancel, Pause, Resume) and channel name are its own English strings (override
  `bg_downloader_*` resources to translate); the app's own strings that do not exist in the Apple files are in `lib/ui/missing_strings.dart` (section Downloads).

## Not run on a device

Everything above the engine runs in `flutter test` (host). The engine, the manifest merge (checked: `flutter build apk --debug` works and the
merged manifest has `FOREGROUND_SERVICE_DATA_SYNC`, `SystemForegroundService` with `dataSync`, the package's receiver and UIDT service) and what
only a phone shows are NOT verified: a real download of a big file, background and closed-app behaviour, resume after a drop, the notification
and its permission prompt (Android 13+), `Config.tempFilePath` and `checkAvailableSpace` on a real volume, foreground service limits on Android 14+,
`file://` playback through media_kit on a device, the `NumberFormat` look of sizes in other languages.

## Tests

`cd flutter && flutter test test/downloads`: naming (Swift cases + emoji/CJK/control characters), model with `test/downloads/fake_download_engine.dart`
(enqueue, progress, pause/resume, cancel, failure kinds, refused job, restart reconcile, deleted file, damaged list, no secrets in the JSON),
widget tests (button on a movie and an episode, not on `.m3u8`/live, off when disabled, Downloads screen with progress and actions, confirmations, delete all,
missing file, badge, right-to-left with large text, offline play request with the item attached and the resume key).
