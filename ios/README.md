# IPTVMac for iPhone and iPad (foundation)

A plain SwiftUI app on top of the same libraries as the Mac app: sources (Xtream / M3U), Live / Movies / Series with search, tap to play
full screen through libmpv (OpenGL ES view), play/pause/close. The design polish and the real player UI come on top of this.

## Layout

| Path | What |
|---|---|
| `Package.swift` (repo root) | Library products `IPTVCore`, `IPTVPlayer`, `IPTVAppKit`, for macOS 14 and iOS 17. The Mac app and its tests are unchanged. |
| `Sources/IPTVAppKit/LibraryModel.swift` | The platform-neutral app model (accounts, All mode, categories, search, favorites, sync, EPG, info, backup, progress). The Mac `AppModel` and the iOS `PhoneModel` subclass it. |
| `Sources/IPTVPlayer/MPVVideoViewiOS.swift` | The OpenGL ES video view (the Mac one stays `MPVVideoView.swift`). Everything else in IPTVPlayer is shared. |
| `Sources/CLibMPViOS/` | libmpv's C headers for iOS (ISC licence, unmodified from the media-kit build). The Mac keeps the `CLibMPV` pkg-config target. |
| `ios/project.yml` | XcodeGen spec of the app target `IPTVPhone`. |
| `ios/Sources/` | The app: `IPTVPhoneApp`, `PhoneModel`, `RootTabs`, `ItemsScreen`, `SourcesScreen`, `AddSourceSheet`, `SeriesSheet`, `PasswordSheet`, `PhonePlayer`, `PlayerScreen`. |
| `ios/Resources/` | Owned by the resources work (assets, privacy manifest, `InfoPlist.strings`, `Info-extra.plist`). Optional: the build works while it is empty or missing. |
| `ios/Generated/` | Git-ignored: `Info.plist`, `cacert.pem`, `generated.yml`. |
| `ios/IPTVPhone.xcodeproj` | Git-ignored, generated from `project.yml`. |
| `scripts/ios-setup.sh` | One command from a clean checkout to the Xcode project. |
| `scripts/fetch-ios-mpv.sh` | Downloads the iOS libmpv (media-kit v0.7.3, mpv 0.36, LGPL) into `build/vendor/ios-mpv`, sha256 pinned. |
| `scripts/make-ca-bundle.sh` | Makes `ios/Generated/cacert.pem` from this Mac's `/etc/ssl/cert.pem`. |

The 31 `Localizable.strings` are the Mac app's (`Sources/IPTVMac/Resources/*.lproj`), referenced by the project, not copied. The language follows the system.

## Build

Needs Xcode (not only the Command Line Tools). Nothing is installed system-wide: XcodeGen 2.46.0 is downloaded into `build/tools` and its sha256 is checked.

```
scripts/ios-setup.sh                       # libmpv + CA bundle + XcodeGen + ios/IPTVPhone.xcodeproj
cd ios
xcodebuild -project IPTVPhone.xcodeproj -scheme IPTVPhone -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project IPTVPhone.xcodeproj -scheme IPTVPhone -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Add `-configuration Release` for a release build (about 30 MB, 23 MB of it the mpv frameworks). The Mac app is built as before with `scripts/swift.sh build|test`.
The version is the repo's `VERSION` file; the build number is `IPTV_BUILD=7 scripts/ios-setup.sh` (default 1).

Why the project is generated and not committed: `project.yml` is the single source, the `.pbxproj` would be noisy to merge, and the signing team is personal.
Why the frameworks are linked by the Xcode project and not as SwiftPM binary targets: a package manifest is evaluated on the host and
SwiftPM refuses to load a package whose local binary target is missing, so `scripts/swift.sh build` would break on every Mac that has not fetched the iOS libmpv.
The package only needs libmpv's headers to compile `IPTVPlayer` for iOS; the symbols are resolved when the app links `Mpv.xcframework`.

## Run it on your own iPhone

1. iPhone: Settings > Privacy & Security > Developer Mode on (it restarts the phone). Connect it with a cable and trust the Mac.
2. `scripts/ios-setup.sh` once. To keep your team across regenerations: `IOS_TEAM_ID=<your 10-character Team ID> scripts/ios-setup.sh`.
3. Open `ios/IPTVPhone.xcodeproj` in Xcode. Target `IPTVPhone` > Signing & Capabilities: tick "Automatically manage signing" and choose your Team (skip if you used `IOS_TEAM_ID`).
   If Xcode says the bundle id `io.github.goelir.IPTVMac` is not available for your team, change it to one of yours (the field is in the same tab).
4. Pick your iPhone as the run destination and press Run. First launch: on the phone, Settings > General > VPN & Device Management > trust your developer certificate.
5. Sources tab > "Add source...": Xtream login or an M3U link. Tap "Test connection", then "Save and sync". Tap a channel to play.

A free Apple ID works for a personal device (the app stops opening after 7 days and has to be run again from Xcode).

## Checked

Unsigned `xcodebuild` builds of `IPTVPhone` succeed for `generic/platform=iOS` and `generic/platform=iOS Simulator`, Debug and Release. The bundle holds the 18 mpv
frameworks (`@rpath`, embedded), the 31 languages, `cacert.pem` and the generated `Info.plist` (background audio, orientations, ATS, encryption flag, languages).
macOS: `scripts/swift.sh build` and `test` as before (the IPTVAppKit tests are new).

## Not verified, and what is still missing

- **Nothing was run.** This Mac has Xcode's iOS 27 SDKs but no iOS Simulator runtime (`xcrun simctl list runtimes` is empty), so the app was never launched.
  `xcodebuild -downloadPlatform iOS` installs one (several GB, system-wide: the owner's call). Then: `xcrun simctl boot <device>`, `simctl install`, `simctl launch`,
  `simctl io <device> screenshot` and `xcrun simctl shutdown all` (never open Simulator.app). Whether libmpv renders a frame through OpenGL ES, hardware decode, audio
  and the background behaviour need a real iPhone anyway.
- OpenGL ES is deprecated and, in the background, a GLES call terminates the app: the view switches the video track off while the app is in the background (audio goes on) and back on in the foreground. Untested.
- Picture in Picture (needs `AVSampleBufferDisplayLayer`, see the feasibility report), lock-screen controls (`MPNowPlayingInfoCenter`), audio interruptions, seek bar and gestures, speed, subtitles and audio tracks, live retry, up-next, catch-up.
- Settings and backup UI (the model has them: `exportBackup`, `importBackup`, `clear`), the details sheet for movies and series, EPG schedule.
- Passwords are plain text in the SQLite file like on the Mac (a Keychain store is planned for iOS). The password sheet text still says "on this Mac".
- Downloads are off (App Review 5.2.3), and so is the updater.
- App Store: privacy policy URL, screenshots, age rating, export compliance answer, review notes, LGPL source offer, a bundle id under the owner's team.
- `NSLocalNetworkUsageDescription` and the document types come from `Info-extra.plist` of the resources work; with it missing only the short English local-network text from `project.yml` is used.
