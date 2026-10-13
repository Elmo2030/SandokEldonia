# IPTVMac for Android (beta)

An IPTV player for your own M3U playlists and Xtream Codes logins, in Flutter with libmpv (media_kit). It contains no content. Same design as the Mac and iPhone apps: instant search over 100,000 items, a touch player with gestures, Picture in Picture, background audio with notification controls, 31 languages, no account, no ads, no tracking. Android 8 or later. No download yet: build it from source.

    cd flutter
    flutter pub get
    flutter analyze && flutter test      # 300+ tests, no device needed
    flutter build apk                    # needs JDK 17 and the Android SDK (36)
    flutter build apk --debug -t lib/main_player_lab.dart   # the player alone, with test streams

Where things are: `lib/core` (platform-neutral logic ported from the Swift core, tested with the same cases), `lib/app` (state, sync in a background isolate, secure password store), `lib/ui` (screens), `lib/player` (the player), `lib/l10n` (generated from the Apple strings: `python3 -I tool/strings_to_arb.py && flutter gen-l10n`). Plans and measurements: [PLAN.md](PLAN.md). Each folder has its own README.

Checked on a real phone (OnePlus 13, Android 16): the picture, HTTPS streams, the controls, Picture in Picture entry and the library with a real source. Not yet checked: background audio with the screen off, the notification buttons, calls and headphones interruptions, and older or weaker phones.
