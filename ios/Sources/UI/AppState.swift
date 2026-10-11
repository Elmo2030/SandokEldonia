import SwiftUI
import IPTVCore
import IPTVAppKit
import GRDB
import UIKit

enum AppSection: String, Hashable, CaseIterable {
    case live, movies, series, library, settings

    var itemType: ItemType? { switch self { case .live: .live; case .movies: .movie; case .series: .series; default: nil } }
    init(_ t: ItemType) { self = t == .live ? .live : t == .movie ? .movies : .series }
    var title: String {
        switch self {
        case .live: L("tab.live"); case .movies: L("tab.movies"); case .series: L("tab.series")
        case .library: L("tab.library"); case .settings: L("settings.title")
        }
    }
    var symbol: String {
        switch self {
        case .live: "tv"; case .movies: "film"; case .series: "rectangle.stack"; case .library: "books.vertical"; case .settings: "gearshape"
        }
    }
}

/// What only the screens care about (the shared model has the data): which section is open, the details sheet, where the list
/// scrolls back to after the player, and the continue-watching shelves.
@MainActor @Observable
final class UIState {
    var section: AppSection = .live
    var openInfo: Item?
    /// The last item played, and (set only when the player closes) the row the list scrolls back to.
    var lastPlayedID: Int64?
    var scrollTarget: Int64?
    var continueMovies: [ContinueEntry] = []
    var continueSeries: [ContinueEntry] = []
    var pulling = false                       // a pull to refresh is running: its spinner is the progress
    var debugSheet: String?                   // DEBUG launch argument -uiSheet (screenshots)

    func continueEntries(_ t: ItemType) -> [ContinueEntry] { t == .movie ? continueMovies : t == .series ? continueSeries : [] }

    /// Movie or channel: details / play. A series opens its own screen (the model decides, and asks for a missing password first).
    func open(_ item: Item, model: PhoneModel) {
        if item.type == .movie && item.directURL == nil { openInfo = item } else { model.play(item) }
    }

    func reloadContinue(_ model: PhoneModel) async {
        let aid = model.playlist?.id, hide = model.categoryFilter
        guard model.allPlaylists || aid != nil else { continueMovies = []; continueSeries = []; return }
        let r: ([ContinueEntry], [ContinueEntry])? = try? await model.db.dbQueue.read { d in
            func visible(_ e: [ContinueEntry]) throws -> [ContinueEntry] {
                let ok = Set(try hide.visible(e.map(\.item), in: d).compactMap(\.id))
                return e.filter { ok.contains($0.id ?? -1) }
            }
            return (try visible(WatchProgress.continueEntries(d, accountId: aid, type: .movie)), try visible(WatchProgress.continueEntries(d, accountId: aid, type: .series)))
        }
        continueMovies = r?.0 ?? []; continueSeries = r?.1 ?? []
    }
}

/// Everything the lists ask of a screen: logos and posters at one size per kind.
enum PosterGrid {
    static func columns(regular: Bool, scale: CGFloat = 1) -> [GridItem] {
        [GridItem(.adaptive(minimum: (regular ? 140 : 104) * scale, maximum: (regular ? 190 : 150) * scale), spacing: 12, alignment: .top)]
    }
}

#if DEBUG
/// Screenshot and test hooks, DEBUG builds only: `-resetData 1` (fresh database), `-demoServer http://127.0.0.1:8099` (adds a demo Xtream source),
/// `-demoImages 1` (lets posters load from that local server), `-uiSection live|movies|series|library|settings`, `-uiCategory <tag>`,
/// `-uiSearch <text>`, `-uiScope category|type|everywhere`, `-uiSheet info|series|categories|add|about|acks|edit|privacy`.
enum DebugLaunch {
    private static var d: UserDefaults { .standard }

    static func prepare() {
        guard d.bool(forKey: "resetData") else { return }
        if let path = try? AppDatabase.defaultPath() { for s in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + s) } }
        for k in ["playlist", "recentSearches", "refreshHours", "hiddenCategoryWords", "appearance"] { d.removeObject(forKey: k) }
    }

    /// Favorites and resume points, so the library, the shelves and the series screen have something to show.
    @MainActor private static func seed(_ model: PhoneModel) async {
        guard let a = model.accounts.first, let aid = a.id, model.favoriteKeys.isEmpty else { return }
        let items = (try? await model.db.dbQueue.read { try Item.filter(Column("accountId") == aid).order(Column("id")).fetchAll($0) }) ?? []
        func pick(_ t: ItemType, _ idx: [Int]) -> [Item] { let l = items.filter { $0.type == t }; return idx.compactMap { $0 < l.count ? l[$0] : nil } }
        let live = pick(.live, [0, 2, 6]), movies = pick(.movie, [1, 4, 9, 13]), series = pick(.series, [0, 2, 4])
        for s in series.prefix(2) {
            if let eps = try? await SyncService(db: model.db).episodes(account: a, password: "demo", seriesId: s.streamId), eps.count > 2 {
                let first = s.id == series[0].id
                try? await model.db.dbQueue.write { d in
                    try UserData.saveProgress(d, accountId: aid, type: .series, streamId: "ep:\(eps[0].streamId)", position: first ? 2650 : 1800, duration: 2700)
                    try UserData.saveProgress(d, accountId: aid, type: .series, streamId: "ep:\(eps[1].streamId)", position: first ? 1100 : 20, duration: 2700)
                }
            }
        }
        try? await model.db.dbQueue.write { d in
            for (i, m) in movies.prefix(3).enumerated() { try UserData.saveProgress(d, accountId: aid, type: .movie, streamId: m.streamId, position: [1500, 4200, 600][i], duration: 6000) }
            for i in live + movies.prefix(2) + series.prefix(2) { _ = try UserData.toggleFavorite(d, accountId: aid, type: i.type, streamId: i.streamId) }
        }
        model.loadFavorites()
        await ui_reload(model)
    }
    @MainActor private static func ui_reload(_ model: PhoneModel) async { model.scheduleSearch() }

    @MainActor static func run(_ model: PhoneModel, _ ui: UIState) async {
        if let s = d.string(forKey: "demoServer"), model.accounts.isEmpty {
            await model.addAccount(Account(name: d.string(forKey: "demoName") ?? "Demo", kind: .xtream, server: s, username: "demo"), password: "demo")
        }
        if d.bool(forKey: "demoSeed") { await seed(model) }
        if let s = d.string(forKey: "uiSection"), let sec = AppSection(rawValue: s) {
            ui.section = sec
            if let t = sec.itemType { model.tab = t }
        }
        if let c = d.string(forKey: "uiCategory") { model.selectedCategory = c }
        if let s = d.string(forKey: "uiScope"), let sc = SearchScopeChoice(rawValue: s) { model.scope = sc }
        if let o = d.string(forKey: "uiOrientation"), let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: o == "landscape" ? .landscapeRight : .portrait))
        }
        try? await Task.sleep(for: .milliseconds(600))
        if let q = d.string(forKey: "uiSearch") { model.searchText = q }        // after the section change, which clears the search
        try? await Task.sleep(for: .milliseconds(400))
        await ui.reloadContinue(model)
        if let s = d.string(forKey: "uiSheet") {
            switch s {
            case "info": ui.openInfo = model.results.first { $0.type == .movie }
            case "series": model.openSeries = model.results.first { $0.type == .series }
            default: ui.debugSheet = s
            }
        }
    }
}
#endif
