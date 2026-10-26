<div align="center">

# SandokEldonia · صندوق الدنيا

**A native IPTV player for the Mac.**<br>
Xtream Codes and M3U, a home screen with shelves, ratings, profiles with a kids mode, and a built-in mpv player.<br>
Free and open source. No accounts, no analytics.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey?style=flat-square)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square)](LICENSE)

[Install](#install) &nbsp;|&nbsp; [First run](#first-run) &nbsp;|&nbsp; [Features](#features) &nbsp;|&nbsp; [Shortcuts](#keyboard-shortcuts) &nbsp;|&nbsp; [Build](#build-from-source) &nbsp;|&nbsp; [Credits](#credits-and-license) &nbsp;|&nbsp; [العربية](README.ar.md)

</div>

SandokEldonia is a Mac app for watching the live channels, movies and series of your own IPTV provider. It is a fork of the open source [IPTVMac](https://github.com/Goelir/IPTVMac) with a redesigned dark interface and a good deal of new functionality (listed below). It is only a player: it does **not** include or host any channels, movies or series. You need a source you are allowed to use.

## Install

Requires an Apple Silicon Mac (M1 or later) and macOS 14 or later. Nothing else to install: the player (libmpv) is inside the app.

1. Download **SandokEldonia-1.1.0.zip** from the [latest release](https://github.com/Elmo2030/SandokEldonia/releases/latest), double-click it, and drag **SandokEldonia** into your **Applications** folder.
2. Open it from Applications. **The first time, macOS will refuse**, because this build is not notarized by Apple (that needs a paid Apple Developer account). Do one of these once:
   - **macOS 15 and later:** try to open the app, then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to SandokEldonia.
   - **Older macOS:** right-click the app, choose **Open**, then **Open** again.
   - **Or in Terminal** (works everywhere): `xattr -dr com.apple.quarantine /Applications/SandokEldonia.app`

After that it opens with a normal double-click. This build does **not** update itself; you replace it with a newer copy. Your playlists, favorites and history are kept (they live outside the app, see [Your data](#your-data)).

## First run

The app opens a short guide. You add a playlist from your provider:

- **Xtream Codes:** server address (for example `http://host:8080`), username and password.
- **M3U:** a name and the playlist link.

Each person uses their own subscription. Sharing one account between people may be against your provider's terms, and many providers allow only one connection at a time.

## Features

**Library and home**
- Live channels, movies and series from Xtream Codes or M3U playlists, several playlists at once, or **All playlists** in one view.
- A **home screen** with shelves: *Continue watching*, *Recently added*, *Similar to the last title you watched* and *More from its category*.
- **Recently added:** a refresh compares the list with the previous one and tells you how many movies and series are new. The first refresh of a playlist is the baseline, so nothing is called new then.
- **Update lists** button on the home screen and in the toolbar (⌘R).
- Instant full-text search over 100,000+ titles (in a category, a section, or everywhere).
- **Filters** on the Movies and Series tabs: hide watched, newest first, minimum rating.
- **Ratings** under every movie and series that has one, and on the details screen. They come from your provider's own data; M3U playlists carry none.
- **Watch later** list (sidebar and right-click on any title), and favorites.
- A **details screen** with poster, plot, cast, year, rating, duration and trailer for Xtream movies and series (click a poster; the ⓘ button is always visible).

**People**
- **Profiles:** favorites, watch history and Watch later are separate for each person; playlists are shared. Up to 8 profiles.
- **Kids profile:** shows only categories whose names look made for children (kids, cartoon, family, أطفال, كرتون...). This is a guess from category names, so it is a convenience, not a guarantee.
- An optional **PIN** is asked when leaving a profile that has one. It is a convenience lock, not security.

**Playback**
- A built-in [mpv](https://mpv.io) player: hardware decoding, subtitles and audio tracks (embedded, or `.srt`/`.ass` files by drag and drop), speed 0.25x to 4x, sleep timer, fit/fill/stretch.
- **Picture in Picture**, **catch-up** (Xtream `tv_archive`), downloads of movies and episodes, resume where you stopped, and a next-episode countdown.
- **Smarter recovery:** movies and episodes reconnect after a dropped connection and resume just before the break; live channels retry with growing delays. If it still fails, **Copy diagnostics** copies the server name, file type and error. It never copies your account, password or tokens.
- **Program guide:** current and next program for Xtream channels, and for **M3U channels whose playlist names a guide** (`url-tvg`, XMLTV, plain or gzip).
- Volume, mute and next/previous episode or channel from the keyboard.

**Other**
- A warning strip when an Xtream subscription has a week or less left.
- Backup and restore of playlists (without passwords), favorites, watch history and Watch later (for the profile in use).
- 31 interface languages, with right-to-left layout for Arabic, Hebrew, Persian and Urdu. Apart from the original Hebrew, English and Arabic, translations were written with AI help and have not been reviewed by native speakers.

## Keyboard shortcuts

| Where | Keys |
|---|---|
| Anywhere | ⌘R update playlists · ⌘N show window |
| Playback menu | ⌘] next episode or channel · ⌘[ previous · ⌥⌘M mute · ⌥⌘↑ / ⌥⌘↓ volume |
| In the player | Space pause · ← / → skip · ↑ / ↓ volume · M mute · N / P next / previous · F full screen · A fit / fill / stretch · 2 double speed · [ / ] slower / faster · Esc back |

## Your data

Playlists, favorites, history and profiles are stored in `~/Library/Application Support/IPTVMac/` (readable by your user only). Account passwords are kept in that database in plain text, not in the Keychain. The app contacts only the servers you add (your provider, and the guide link named by an M3U playlist). No analytics, no telemetry. The folder keeps its original name `IPTVMac` so the app can read data from the original project.

## Good to know

- Details, catch-up, ratings and the subscription date come from **Xtream** panels. An **M3U** playlist has none of them; its channels get a program guide only when the playlist names one.
- "New" titles are detected by their stream ids. If a provider renumbers its catalog, or an M3U link carries a changing token, the app ignores a change that large; a very small list with changing links may be shown as new.
- Intel Macs and macOS 13 or older are not supported.
- Automatic updates are switched off in this fork (see [Credits](#credits-and-license)).

## Build from source

You need macOS 14+, the Xcode Command Line Tools, and Homebrew with `mpv` and `pkg-config`.

```
./scripts/swift.sh build -c release    # compile
./scripts/swift.sh test                # run the tests
./scripts/make-app.sh                  # assemble build/IPTVMac.app with the player bundled
```

`make-app.sh` expects the app icon at `~/Downloads/SandokEldonia.icns`; point `CUSTOM_ICON` in the script to your own `.icns` file, or edit the script to skip it. `scripts/swift.sh` is a small wrapper that picks an SDK on which SwiftUI compiles with only the Command Line Tools installed.

## Credits and license

SandokEldonia is a fork of **[IPTVMac](https://github.com/Goelir/IPTVMac)** by Goelir and its contributors, and keeps its license: **GPL-3.0** (see [LICENSE](LICENSE)). If you give someone the app, you must also give them (or point them to) this source code. The iOS (`ios/`) and Android (`flutter/`) sources in this repository come from the original project and do **not** include the changes described above. The files under `docs/` (a project website, privacy page and screenshots) are the original project's and do not describe this app.

The built-in updater of the original project is switched off here: it is tied to the original project's releases and signing key, and with the same app identifier it would otherwise replace SandokEldonia with the original app. The playback engine is [mpv](https://mpv.io) (libmpv, bundled), under its own license.
