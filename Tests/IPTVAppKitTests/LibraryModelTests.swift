import Testing
import Foundation
import IPTVCore
@testable import IPTVAppKit

// The shared model needs no window system: an in-memory database and a memory secret store are enough.
@MainActor private func model() throws -> LibraryModel { LibraryModel(db: try AppDatabase(), secrets: MemorySecretStore()) }

@Test func onlyNetworkSchemesAreStreamable() {
    #expect(LibraryModel.safeStreamURL(" http://h/live/1.ts ")?.host == "h")
    for bad in ["file:///etc/passwd", "fd://0", "edl://x", "memory://x", "http://", "javascript:1", ""] { #expect(LibraryModel.safeStreamURL(bad) == nil) }
}

@MainActor @Test func accountsCategoriesAndAllMode() async throws {
    let m = try model()
    let a = try await m.db.dbQueue.write { d -> Account in var x = Account(name: "a", kind: .m3u, url: "http://h/a.m3u"); try x.insert(d); return x }
    _ = try await m.db.dbQueue.write { d in var b = Account(name: "b", kind: .m3u, url: "http://h/b.m3u"); try b.insert(d) }
    m.loadAccounts()
    #expect(m.accounts.count == 2)
    let c = IPTVCore.Category(accountId: a.id!, type: .live, remoteId: "7", name: "News")
    #expect(m.categoryTag(c) == "7")
    m.allPlaylists = true
    #expect(m.categoryTag(c) == "\(a.id!)|7")                // remote ids repeat across playlists: All mode prefixes the owner
    #expect(m.playlist == nil)
    m.deleteAccount(a)
    #expect(m.accounts.count == 1 && m.allPlaylists == false)  // All needs more than one playlist
}

@MainActor @Test func playBuildsARequestFromTheItemAndHooksIntoThePlatform() async throws {
    final class Recorder: LibraryModel {
        var started: PlayRequest?
        override func startPlayback(_ r: PlayRequest) { started = r; super.startPlayback(r) }
    }
    let m = Recorder(db: try AppDatabase(), secrets: MemorySecretStore())
    let acct = try await m.db.dbQueue.write { d -> Account in var x = Account(name: "a", kind: .m3u, url: "http://h/a.m3u"); try x.insert(d); return x }
    m.loadAccounts()
    m.play(Item(accountId: acct.id!, type: .live, name: "Ch", streamId: "1", directURL: "http://h/1.ts"))
    #expect(m.started?.url.absoluteString == "http://h/1.ts" && m.started?.isLive == true && m.playing != nil)
    m.play(Item(accountId: acct.id!, type: .movie, name: "bad", streamId: "2", directURL: "file:///etc/passwd"))
    #expect(m.syncMessage != nil)                                // refused, nothing started for it
    let series = Item(accountId: acct.id!, type: .series, name: "S", streamId: "3")
    m.play(series)
    #expect(m.openSeries?.streamId == "3")                       // a series opens its episode list instead
    m.stopPlayback()
    #expect(m.playing == nil)
}
