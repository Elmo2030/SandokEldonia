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

// Stopping playback saves the resume point (the Mac app does it in stopPlayback). When the profile is switched, that point
// belongs to the profile that was watching, not to the one switched to.
@MainActor @Test func switchingProfileKeepsTheResumePointWithTheProfileThatWatched() async throws {
    final class Saving: LibraryModel {
        override func stopPlayback() { if let r = playing { saveProgress(r, position: 50, duration: 100) }; super.stopPlayback() }
    }
    let m = Saving(db: try AppDatabase(), secrets: MemorySecretStore())
    let acct = try await m.db.dbQueue.write { d -> Account in var x = Account(name: "a", kind: .m3u, url: "http://h/a.m3u"); try x.insert(d); return x }
    m.loadAccounts(); m.loadProfiles()
    let kid = try await m.db.dbQueue.write { try Profiles.create($0, name: "Kid", kids: false) }
    m.loadProfiles()

    m.play(Item(accountId: acct.id!, type: .movie, name: "Film", streamId: "7", directURL: "http://h/7.mp4"))
    #expect(m.playing != nil)
    #expect(m.switchProfile(to: kid) == .switched)
    #expect(m.playing == nil)

    func progress() async throws -> Double? {
        try await m.db.dbQueue.read { try UserData.progress($0, accountId: acct.id!, type: .movie, streamId: "7") }
    }
    #expect(try await progress() == nil)                                   // the kid has not watched it
    #expect(m.switchProfile(to: m.profiles[0]) == .switched)
    #expect(try await progress() == 50)                                    // Main has
}

@MainActor @Test func editingAnotherProfileDoesNotDisturbWhatIsOnScreen() async throws {
    let m = try model()
    _ = try await m.db.dbQueue.write { d in var x = Account(name: "a", kind: .m3u, url: "http://h/a.m3u"); try x.insert(d) }
    m.loadAccounts(); m.loadProfiles()
    let other = try await m.db.dbQueue.write { try Profiles.create($0, name: "Other", kids: false) }
    m.loadProfiles()
    m.selectedCategory = "__fav"
    try m.editProfiles { try Profiles.update($0, id: other.id!, name: "Renamed", kids: true) }
    #expect(m.profiles.last?.name == "Renamed")
    #expect(m.selectedCategory == "__fav")                                 // the list the user was looking at stays
    let mainId = m.profile.id!
    try m.editProfiles { try Profiles.update($0, id: mainId, name: "Main", kids: true) }
    #expect(m.selectedCategory == "__all")                                 // the profile in use became a kids profile: lists are rebuilt
}
