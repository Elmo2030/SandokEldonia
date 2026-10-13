# Localization

The Apple files `Sources/IPTVMac/Resources/<lang>.lproj/Localizable.strings` (31 languages, shared by the Mac and iOS apps) stay the single source of truth. Never edit the `.arb` files by hand: they are generated and overwritten.

## Regenerate

```
python3 -I flutter/tool/strings_to_arb.py && cd flutter && flutter gen-l10n
flutter test test/l10n_test.dart
```

`flutter pub get`, `flutter run` and `flutter test` also run gen-l10n. The script writes `app_<locale>.arb` (English `app_en.arb` is the template), `key_map.json`, and exits non-zero (writing nothing) on a syntax error, a Dart-name collision, or a locale whose placeholders differ from English. The generated Dart (`app_localizations*.dart`) is git-ignored; the `.arb` files and `key_map.json` are committed. After a fresh clone run `flutter pub get`.

Wiring in the app (not done in `main.dart`, which is a spike): `MaterialApp(localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales)` with `import 'l10n/app_localizations.dart'`, then `AppLocalizations.of(context).tabLive`.

## Keys

- Dotted Apple key to a lowerCamel Dart getter, per segment: `player.seekValue` -> `playerSeekValue`, `about.privacy.body` -> `aboutPrivacyBody`. `key_map.json` maps Dart name -> Apple key (`grep` the Apple key to find the Swift usage).
- Format specifiers become ICU placeholders `{p1} {p2}...`: `%@` String, `%d` (also `%i %u %ld %lld`) int, `%f` double. Unnumbered specifiers count in order; `%2$@` keeps its number, so a translation that reorders (`%2$@ ... %1$@`) keeps the translator's order. `%%` becomes `%`. Placeholders are positional, so Dart calls are `playerSeekValue(current, total)`, `seriesEpShort(season, episode)`.
- Apostrophes and braces are escaped for ICU (`'` -> `''`, `{` -> `'{'`); `l10n.yaml` has `use-escaping: true` for that. Do not turn it off.
- Locale codes: folder `zh-Hans.lproj` -> `app_zh_Hans.arb`. `pt.lproj` is `pt`.

## Known gaps

- Today there are no missing keys and no placeholder mismatches in any of the 31 locales (the script reports them if they appear). A missing key is copied from English into that locale's `.arb` (gen-l10n would otherwise fall back anyway) and listed in the script output.
- A locale key that English lacks is ignored and listed.
- gen-l10n requires a base locale for `zh_Hans` / `zh_Hant`, so the script also writes `app_zh.arb` as a copy of Simplified Chinese (32 supported locales, 31 Apple ones).
- Plural forms are not modelled: Apple strings like `%d minutes` have no plural variants, so neither do the `.arb` files.
- Some strings say "Mac" or "iOS Keychain" (`password.body`, `about.privacy.body`): they are the Apple wording and are not adapted for Android yet. Add Android-specific keys to the Apple files if needed (the script picks up any new key).
- The iOS app has no extra `Localizable` keys (`ios/Sources/Localization.swift` reads the shared files); `InfoPlist.strings` (permission texts, app name) is not included.
- The Apple `.strings` parser handles comments, `\" \\ \n \t \r \uXXXX` and octal escapes, unquoted keys, UTF-8/UTF-16; it was checked against `plutil -convert json` for all 31 files (identical).
