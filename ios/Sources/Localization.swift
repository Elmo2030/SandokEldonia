import Foundation

/// The strings are the Mac app's Localizable.strings (Sources/IPTVMac/Resources/*.lproj, shared, not copied): they sit in the app
/// bundle, so the language follows the system (CFBundleLocalizations lists the 31 folders).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
