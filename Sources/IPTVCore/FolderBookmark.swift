import Foundation

/// The download folder, remembered as a security-scoped bookmark. Under the App Sandbox a plain path string is useless after a
/// relaunch (the grant the open panel gave lives for one session only); the bookmark data carries the grant.
/// Without the sandbox the same bookmark just resolves, so there is a single code path.
/// A plain path saved by older versions is turned into a bookmark once. Every system call is injectable for tests.
#if os(macOS)
private let scopeCreate: URL.BookmarkCreationOptions = .withSecurityScope      // the Mac sandbox keeps a user-chosen folder by security-scoped bookmark
private let scopeResolve: URL.BookmarkResolutionOptions = .withSecurityScope
#else
private let scopeCreate: URL.BookmarkCreationOptions = []                       // iOS has no scope flag: plain bookmarks of folders picked in the document picker
private let scopeResolve: URL.BookmarkResolutionOptions = []
#endif

public final class FolderBookmark: @unchecked Sendable {
    public struct Ops {
        public var make: (URL) throws -> Data
        public var resolve: (Data) throws -> (url: URL, stale: Bool)
        public var start: (URL) -> Bool          // false: the URL carries no scope (nothing to release)
        public var stop: (URL) -> Void
        public var usable: (URL) -> Bool         // still a folder, and not in the Trash

        public init(make: @escaping (URL) throws -> Data, resolve: @escaping (Data) throws -> (url: URL, stale: Bool),
                    start: @escaping (URL) -> Bool, stop: @escaping (URL) -> Void, usable: @escaping (URL) -> Bool) {
            self.make = make; self.resolve = resolve; self.start = start; self.stop = stop; self.usable = usable
        }

        public static let system = Ops(
            make: { try $0.bookmarkData(options: scopeCreate, includingResourceValuesForKeys: nil, relativeTo: nil) },
            resolve: {
                var stale = false
                let u = try URL(resolvingBookmarkData: $0, options: scopeResolve, relativeTo: nil, bookmarkDataIsStale: &stale)
                return (u, stale)
            },
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() },
            usable: { u in
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { return false }
                // A bookmark follows its folder into the Trash: downloading there would silently lose the files.
                var rel = FileManager.URLRelationship.other
                try? FileManager.default.getRelationship(&rel, of: .trashDirectory, in: .userDomainMask, toItemAt: u)
                return rel != .contains
            }
        )
    }

    public static let bookmarkKey = "downloadFolderBookmark"
    /// The path string older versions stored; still written (display, and a downgrade keeps its folder).
    public static let legacyPathKey = "downloadFolder"

    private let defaults: UserDefaults
    private let ops: Ops
    private let lock = NSLock()
    private var cached: (data: Data, url: URL)?
    private var held: URL?

    public init(defaults: UserDefaults = .standard, ops: Ops = .system) { self.defaults = defaults; self.ops = ops }

    /// Remembers a folder the user just picked (the open panel's URL is accessible right now, which making the bookmark needs).
    public func choose(_ url: URL) throws {
        let data = try ops.make(url)
        lock.lock(); defer { lock.unlock() }
        releaseLocked()
        defaults.set(data, forKey: Self.bookmarkKey)
        defaults.set(url.path, forKey: Self.legacyPathKey)
        cached = nil
    }

    /// The stored folder: a stale bookmark is refreshed, a legacy path is migrated. Nil: none stored, or it no longer resolves
    /// (the caller asks the user again). Resolving does not grant access: use `withAccess`.
    public func resolve() -> URL? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return migrateLegacyLocked() }
        if let c = cached, c.data == data { return c.url }
        guard let (url, stale) = try? ops.resolve(data) else { return nil }
        var kept = data
        if stale {
            let started = ops.start(url); defer { if started { ops.stop(url) } }
            if let fresh = try? ops.make(url) { defaults.set(fresh, forKey: Self.bookmarkKey); kept = fresh }
        }
        cached = (kept, url)
        return url
    }

    /// Runs `body` with the folder accessible, and releases it afterwards. Nil when there is no usable folder.
    public func withAccess<T>(_ body: (URL) throws -> T) rethrows -> T? {
        guard let url = resolve() else { return nil }
        let started = ops.start(url); defer { if started { ops.stop(url) } }
        guard ops.usable(url) else { return nil }
        return try body(url)
    }

    /// Keeps the folder accessible until `release()` or the next `choose`: a downloaded file that is playing is read all along.
    public func hold() {
        guard let url = resolve() else { return }
        lock.lock(); defer { lock.unlock() }
        guard held == nil, ops.start(url) else { return }
        held = url
    }

    public func release() { lock.lock(); releaseLocked(); lock.unlock() }
    private func releaseLocked() { if let u = held { ops.stop(u); held = nil } }

    private func migrateLegacyLocked() -> URL? {
        guard let path = defaults.string(forKey: Self.legacyPathKey), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard let data = try? ops.make(url) else { return nil }   // sandboxed: no access to an old path, the user is asked again
        defaults.set(data, forKey: Self.bookmarkKey)
        cached = nil
        return url
    }
}
