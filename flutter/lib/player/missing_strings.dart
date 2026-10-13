/// English literals for the few strings the generated localizations do not have (the Apple strings files are the source of truth;
/// add the key there and regenerate when a translation exists, then delete the entry here).
abstract final class MissingStrings {
  /// Name of the notification channel for the playback notification (shown in Android's app notification settings).
  static const playbackChannel = 'Playback';
}
