# IPTVMac for Android (beta)

An IPTV player for your own M3U playlists and Xtream Codes logins, in Flutter with libmpv (media_kit). It contains no content. Same design as the Mac and iPhone apps: instant search over 100,000 items, a touch player with gestures, Picture in Picture, sound that keeps playing with the screen off (with notification controls), downloads of movies and episodes for offline viewing (direct files, in the app's own folder, long-press a movie or use the button in the details and episode rows), a rotate-to-portrait button, 31 languages, no account, no ads, no tracking. Android 8 or later. No download yet: build it from source.

    cd flutter
    flutter pub get
    flutter analyze && flutter test      # 300+ tests, no device needed
    flutter build apk                    # needs JDK 17 and the Android SDK (36)
    flutter build apk --debug -t lib/main_player_lab.dart   # the player alone, with test streams

Where things are: `lib/core` (platform-neutral logic ported from the Swift core, tested with the same cases), `lib/app` (state, sync in a background isolate, secure password store), `lib/ui` (screens), `lib/player` (the player), `lib/l10n` (generated from the Apple strings: `python3 -I tool/strings_to_arb.py && flutter gen-l10n`). Plans and measurements: [PLAN.md](PLAN.md). Each folder has its own README.

Checked on a real phone (OnePlus 13, Android 16): the picture, HTTPS streams, the controls, the rotate button, sound with the screen off, a real download (an open-licence film from the review playlist) and its offline playback, and the library with a real source. Not yet checked: Picture in Picture in use, the notification buttons, calls and headphone interruptions, downloads that run while the app is closed, resuming a download after a dropped connection, and older or weaker phones. Downloads are for direct files only (not HLS playlists, not live channels).
