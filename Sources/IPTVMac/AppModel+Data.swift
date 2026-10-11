import AppKit
import IPTVCore
import IPTVAppKit

// Preferences, info and backup live in IPTVAppKit's LibraryModel; only what needs AppKit stays here.
extension AppModel {
    /// Only the link we build from the validated video id is ever opened, never a URL from the provider.
    func openTrailer(_ info: ItemInfo) { if let u = info.trailerURL { NSWorkspace.shared.open(u) } }
}
