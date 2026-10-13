// English text for strings that do not exist in the Apple .strings files (and so not in the .arb files). They are NOT translated:
// add the key to the Apple files, regenerate (flutter/lib/l10n/README.md) and replace the use. Keep every literal in this file.
abstract final class Missing {
  /// The button that fills the add-source form from the clipboard.
  static const paste = 'Paste';

  /// The Apple texts say "iOS Keychain" / "iOS Settings"; these are the Android wording.
  static String passwordBody(String name) => 'Enter the password for “$name”. It is stored in the Android Keystore on this device.';
  static const passwordNote = 'Leave the new password empty to keep the current one. Passwords are stored in the Android Keystore.';
  static const languageNote =
      'IPTVMac uses the language of your device. To use another language for this app only, choose it in Android Settings, under Apps, IPTVMac, Language.';

  // ---- Downloads (Android only: the Apple .strings have nothing for the Android wording of these) ----
  static const downloadsFailed = 'Download failed';
  static const downloadsNotFound = 'Not found on the server';
  static const downloadsLost = 'The download was interrupted. Start it again.';
  static const downloadsCanceled = 'Canceled';
  static const downloadsFileMissing = 'The file is no longer on this device';
  static const downloadsRemove = 'Remove from the list';
  static const downloadsDeleteAll = 'Delete all downloads';
  static const downloadsDeleteAllWarn = 'All finished downloads and their files are deleted from this device. Downloads in progress are not affected.';
  static const downloadsDeleteWarn = 'The file is deleted from this device.';
  static String downloadsTotal(String size) => 'Downloaded: $size';
  static const downloadsAdded = 'Added to Downloads';
  static const downloadsCannotStart = 'This download could not be started';
  static const downloadsNote =
      'Files are saved in the app’s own folder on this device (Android/data/io.github.goelir.iptvmac/files/Downloads). They are removed when the app is uninstalled. Tap a finished download to watch it offline. Downloads continue in the background; many providers allow a single connection, so they run one at a time.';
}
