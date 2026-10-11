import Foundation
import Observation
import IPTVCore
import IPTVAppKit

/// The iOS app model: everything shared (accounts, search, sync, favorites...) is LibraryModel; this adds the player.
@MainActor @Observable
final class PhoneModel: LibraryModel {
    var player: PhonePlayer?

    init() {
        let opened: (db: AppDatabase, movedAside: String?)
        var failure: String?
        do { opened = try AppDatabase.openRecovering(path: try AppDatabase.defaultPath()) }
        catch {   // no disk: an in-memory database keeps the app usable, nothing is saved this session
            opened = (try! AppDatabase(), nil); failure = error.localizedDescription
        }
        super.init(db: opened.db, dbMovedAside: opened.movedAside)
        syncMessage = failure
    }

    override func startPlayback(_ r: PlayRequest) {
        player?.close()
        playing = r
        let p = PhonePlayer(request: r)
        p.onSaveProgress = { [weak self] position, duration in self?.saveProgress(r, position: position, duration: duration) }
        player = p
    }

    override func stopPlayback() {
        player?.close(); player = nil
        playing = nil
    }

    func playEpisode(_ e: Episode, of series: Item) {
        if let r = episodeRequest(e, of: series) { startPlayback(r) }
    }
}
