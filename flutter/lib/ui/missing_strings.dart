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
}
