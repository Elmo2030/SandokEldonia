import Foundation

/// The text of an audio or subtitle track in a menu: the language by its name in the user's language ("English", "עברית"), then the
/// provider's title when it adds something ("Commentary"), else "#id". mpv gives ISO 639-2 codes ("eng", "heb") or 639-1 ones.
public enum TrackLabel {
    public static func text(for t: Track, locale: Locale = .current) -> String {
        let language = t.lang.flatMap { code -> String? in
            guard !code.isEmpty, code != "und" else { return nil }
            let name = locale.localizedString(forLanguageCode: code)
            return name == nil || name == code ? code.uppercased() : name?.localizedCapitalized
        }
        let title = t.title.flatMap { $0.isEmpty ? nil : $0 }
        switch (language, title) {
        case let (l?, ti?): return ti.caseInsensitiveCompare(l) == .orderedSame || l.hasPrefix(ti) ? l : "\(l) · \(ti)"
        case let (l?, nil): return l
        case let (nil, ti?): return ti
        default: return "#\(t.id)"
        }
    }
}
