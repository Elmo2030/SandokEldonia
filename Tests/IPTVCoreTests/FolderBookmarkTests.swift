import Testing
import Foundation
import IPTVCore

/// Stand-in for the system calls of FolderBookmark: records what was started/stopped and can fail on demand.
private final class Fake: @unchecked Sendable {
    var made: [URL] = [], started: [URL] = [], stopped: [URL] = []
    var staleNext = false, resolveFails = false, makeFails = false, startReturns = true, usable = true
    let folder = URL(fileURLWithPath: "/Volumes/Media/Downloads")

    var ops: FolderBookmark.Ops {
        .init(make: { [self] u in
                  if makeFails { throw CocoaError(.fileReadNoPermission) }
                  made.append(u); return Data("bookmark:\(u.path)".utf8)
              },
              resolve: { [self] _ in
                  if resolveFails { throw CocoaError(.fileNoSuchFile) }
                  defer { staleNext = false }
                  return (folder, staleNext)
              },
              start: { [self] u in started.append(u); return startReturns },
              stop: { [self] u in stopped.append(u) },
              usable: { [self] _ in usable })
    }
}

private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "iptvmac-test-\(UUID().uuidString)")! }

@Test func aChosenFolderIsStoredAsABookmarkAndResolvesAfterARestart() throws {
    let f = Fake(), d = freshDefaults()
    try FolderBookmark(defaults: d, ops: f.ops).choose(URL(fileURLWithPath: "/Users/me/Movies"))
    #expect(d.data(forKey: FolderBookmark.bookmarkKey) == Data("bookmark:/Users/me/Movies".utf8))
    #expect(d.string(forKey: FolderBookmark.legacyPathKey) == "/Users/me/Movies")   // a downgrade keeps its folder
    // A new instance (= the next launch) finds it again through the bookmark alone.
    #expect(FolderBookmark(defaults: d, ops: f.ops).resolve() == f.folder)
}

@Test func aStaleBookmarkIsRefreshedWhileTheFolderIsAccessible() throws {
    let f = Fake(), d = freshDefaults()
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(URL(fileURLWithPath: "/old/place"))
    f.made.removeAll(); f.staleNext = true
    #expect(b.resolve() == f.folder)
    #expect(f.made == [f.folder])                                  // new bookmark data made from the resolved URL...
    #expect(f.started == [f.folder] && f.stopped == [f.folder])    // ...while access was open, and closed again
    #expect(d.data(forKey: FolderBookmark.bookmarkKey) == Data("bookmark:/Volumes/Media/Downloads".utf8))
}

@Test func aBookmarkThatNoLongerResolvesAsksAgainButIsKept() throws {
    let f = Fake(), d = freshDefaults()
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(f.folder)
    f.resolveFails = true
    #expect(b.resolve() == nil)
    #expect(b.withAccess { _ in 1 } == nil)
    #expect(d.data(forKey: FolderBookmark.bookmarkKey) != nil)     // an unplugged drive comes back: the bookmark works again
    f.resolveFails = false
    #expect(FolderBookmark(defaults: d, ops: f.ops).resolve() == f.folder)
}

@Test func aPlainPathFromAnOlderVersionIsMigratedOnce() {
    let f = Fake(), d = freshDefaults()
    d.set("/Users/me/Movies", forKey: FolderBookmark.legacyPathKey)
    let b = FolderBookmark(defaults: d, ops: f.ops)
    #expect(b.resolve() == URL(fileURLWithPath: "/Users/me/Movies", isDirectory: true))
    #expect(d.data(forKey: FolderBookmark.bookmarkKey) != nil)
    _ = b.resolve(); _ = FolderBookmark(defaults: d, ops: f.ops).resolve()
    #expect(f.made.count == 1)
}

@Test func aPlainPathThatCannotBeBookmarkedIsDroppedSoTheUserIsAskedAgain() {
    // The sandbox: no access to a path chosen in an earlier session, so no bookmark can be made from it.
    let f = Fake(), d = freshDefaults()
    f.makeFails = true
    d.set("/Users/me/Movies", forKey: FolderBookmark.legacyPathKey)
    #expect(FolderBookmark(defaults: d, ops: f.ops).resolve() == nil)
    #expect(d.data(forKey: FolderBookmark.bookmarkKey) == nil)
}

@Test func nothingStoredMeansNoFolder() {
    #expect(FolderBookmark(defaults: freshDefaults(), ops: Fake().ops).resolve() == nil)
}

@Test func accessIsOpenedForTheBodyOnlyAndAlwaysClosed() throws {
    let f = Fake(), d = freshDefaults()
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(f.folder)
    var inside: (started: Int, stopped: Int)?
    let r = b.withAccess { u -> String in inside = (f.started.count, f.stopped.count); return u.lastPathComponent }
    #expect(r == "Downloads" && inside?.started == 1 && inside?.stopped == 0)
    #expect(f.started.count == 1 && f.stopped.count == 1)
    struct Boom: Error {}
    #expect(throws: Boom.self) { try b.withAccess { _ in throw Boom() } }
    #expect(f.started.count == 2 && f.stopped.count == 2)          // closed on the error path too
}

@Test func nothingIsStoppedThatWasNeverStarted() throws {
    let f = Fake(), d = freshDefaults()
    f.startReturns = false                                          // not sandboxed: a URL without a scope
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(f.folder)
    #expect(b.withAccess { _ in true } == true)
    #expect(f.stopped.isEmpty)
}

@Test func aFolderThatIsGoneOrInTheTrashIsNotUsedAndAccessIsStillClosed() throws {
    let f = Fake(), d = freshDefaults()
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(f.folder)
    f.usable = false
    var ran = false
    #expect(b.withAccess { _ in ran = true } == nil && !ran)
    #expect(f.started.count == 1 && f.stopped.count == 1)
}

@Test func holdKeepsTheFolderOpenUntilReleasedOrReplaced() throws {
    let f = Fake(), d = freshDefaults()
    let b = FolderBookmark(defaults: d, ops: f.ops)
    try b.choose(f.folder)
    b.hold(); b.hold()
    #expect(f.started.count == 1 && f.stopped.isEmpty)             // a second hold does not open twice
    b.release(); b.release()
    #expect(f.stopped.count == 1)
    b.hold()
    try b.choose(URL(fileURLWithPath: "/elsewhere"))               // a new folder closes the old grant
    #expect(f.started.count == 2 && f.stopped.count == 2)
}

/// The real system calls (not sandboxed here, but the same API): make, resolve, open, write, close.
@Test func theRealBookmarkApiRoundTripsAFolder() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iptvmac-bm-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let d = freshDefaults()
    try FolderBookmark(defaults: d).choose(dir)
    let b = FolderBookmark(defaults: d)                             // "after a relaunch"
    #expect(b.resolve()?.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
    let wrote = b.withAccess { FileManager.default.createFile(atPath: $0.appendingPathComponent("x.mp4").path, contents: Data("x".utf8)) }
    #expect(wrote == true)
    try FileManager.default.removeItem(at: dir)
    #expect(b.withAccess { _ in true } == nil)                      // the folder is gone: asks again
}
