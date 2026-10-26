import Foundation
import Observation
import GRDB
import IPTVCore

// The platform-neutral part of the app model (accounts, categories, search, favorites, sync, playlists/All mode, info, backup,
// progress, EPG), shared by the macOS app (`AppModel`, Sources/IPTVMac) and the iOS app (`PhoneModel`, ios/Sources).
// No AppKit/UIKit here: windows, full screen, PiP, alerts, updates and downloads live in the platform's subclass.

public enum SearchScopeChoice: String, CaseIterable { case category, type, everywhere }

public enum ClearKind: String, CaseIterable, Identifiable { case history, favorites, images; public var id: String { rawValue } }

public struct PlayRequest: Identifiable {
    public let id = UUID()
    public var title: String
    public var url: URL
    public var isLive: Bool
    public var item: Item?
    public var episodeKey: String?     // history key for episodes: "ep:<episodeId>"
    public var start: Double = 0
    public init(title: String, url: URL, isLive: Bool, item: Item? = nil, episodeKey: String? = nil, start: Double = 0) {
        self.title = title; self.url = url; self.isLive = isLive; self.item = item; self.episodeKey = episodeKey; self.start = start
    }
}

@MainActor @Observable
open class LibraryModel {
    public let db: AppDatabase
    public let secrets: SecretStore
    /// Set when the database file was corrupt and moved aside at launch (the platform tells the user).
    public let dbMovedAside: String?
    public var accounts: [Account] = []
    public var account: Account? {
        didSet {
            guard account?.id != oldValue?.id else { return }
            rememberPlaylist()
            if !allPlaylists { playlistChanged() }              // in All mode `account` is only the playlist to return to
        }
    }
    /// All playlists at once (results, search, favorites, continue watching and the category list span every account).
    public var allPlaylists = false {
        didSet { guard allPlaylists != oldValue else { return }; rememberPlaylist(); playlistChanged() }
    }
    /// The toolbar switcher: nil = all playlists.
    public var playlist: Account? {
        get { allPlaylists ? nil : account }
        set { if let a = newValue { account = a; allPlaylists = false } else { allPlaylists = true } }
    }
    private var scopeAccountId: Int64? { allPlaylists ? nil : account?.id }
    private var hasPlaylist: Bool { allPlaylists || account != nil }
    private static let playlistKey = "playlist"      // "all" or an account id

    private func rememberPlaylist() {
        UserDefaults.standard.set(allPlaylists ? "all" : account?.id.map(String.init), forKey: Self.playlistKey)
    }

    private func playlistChanged() {
        if playing != nil { stopPlayback() }                    // progress/favorites/credentials belong to the account that started it
        selectedCategory = "__all"; searchText = ""            // a category id of account A means nothing in B
        favoriteKeys = []; newSinceSync = [:]; loadCategories(); loadFavorites(); scheduleSearch(); loadHomeRows()
    }

    public var tab: ItemType = .live { didSet { leavePlayerForBrowsing(); selectedCategory = "__all"; loadCategories(); scheduleSearch() } }
    public var categories: [IPTVCore.Category] = []
    public var selectedCategory = "__all" { didSet { leavePlayerForBrowsing(); scheduleSearch() } }
    public var searchText = "" { didSet { leavePlayerForBrowsing(); scheduleSearch() } }
    public var scope: SearchScopeChoice = .category { didSet { scheduleSearch() } }
    public var results: [Item] = []
    public var syncing = false
    /// How far the running sync is, 0...1 (every playlist counted in All mode); nil when none is running.
    public private(set) var syncProgress: Double?
    public var syncMessage: String?
    public var playing: PlayRequest?
    public var openSeries: Item?
    /// Set when an Xtream account has no stored password (e.g. after upgrading from the Keychain version).
    public var passwordPrompt: Account?
    public var favoriteKeys: Set<String> = []
    private var epgNow: [String: String] = [:]      // "accountId:streamId" -> program title
    private var epgStamp: [String: Date] = [:]
    private var epgEntries: [String: [EPGEntry]] = [:]   // current + next program, for the phone's rows
    private var epgInFlight: Set<String> = []
    public var schedule: [EPGEntry] = []      // current + upcoming programs of the channel being watched
    private var searchTask: Task<Void, Never>?

    /// `secrets` defaults to the database-backed store; tests pass `AppDatabase()` (in memory) and a `MemorySecretStore`.
    public init(db: AppDatabase, secrets: SecretStore? = nil, dbMovedAside: String? = nil) {
        self.db = db
        self.secrets = secrets ?? DatabaseSecretStore(db: db)
        self.dbMovedAside = dbMovedAside
    }

    // MARK: Platform hooks (the defaults are for a platform without a player to manage)

    /// Called when browsing state changes (tab, category, search): the macOS app moves a running video to a floating window.
    open func leavePlayerForBrowsing() {}
    /// Starts playing `r`; the platform replaces this with its player.
    open func startPlayback(_ r: PlayRequest) { playing = r }
    open func stopPlayback() { playing = nil }

    // MARK: Launch

    private var started = false

    /// Loads the accounts, starts the auto-refresh loop and syncs the shown playlist. Runs once, whatever number of windows ask.
    open func start() async {
        guard !started else { return }
        started = true
        Task { await refreshLoop() }
        loadProfiles()
        loadAccounts()
        if account != nil { await sync() }
        await refreshSubscriptionsIfDue()
    }

    public func loadAccounts() {
        accounts = (try? db.dbQueue.read { try Account.order(Column("id")).fetchAll($0) }) ?? []
        if account == nil {                                     // launch: reopen the last choice (read before `account` rewrites it)
            let r = Account.restore(UserDefaults.standard.string(forKey: Self.playlistKey), from: accounts)
            if r.all { allPlaylists = true }
            account = r.account
        } else if !accounts.contains(where: { $0.id == account?.id }) { account = accounts.first }
        if accounts.count < 2 { allPlaylists = false }
    }

    public func loadCategories() {
        guard hasPlaylist else { categories = []; return }
        let t = tab, aid = scopeAccountId
        categories = categoryFilter.visible((try? db.dbQueue.read {
            var q = IPTVCore.Category.filter(Column("type") == t.rawValue)
            if let aid { q = q.filter(Column("accountId") == aid) }
            return try q.order(Column("accountId"), Column("id")).fetchAll($0)
        }) ?? [])
    }

    public func loadFavorites() {
        guard hasPlaylist else { return }
        let aid = scopeAccountId
        favoriteKeys = (try? db.dbQueue.read { try UserData.favoriteKeys($0, accountId: aid) }) ?? []
        watchlistKeys = (try? db.dbQueue.read { try UserData.watchlistKeys($0, accountId: aid) }) ?? []
    }

    /// In All mode a category is tagged "<accountId>|<remoteId>" (remote ids repeat across playlists); otherwise by remote id alone.
    public func categoryTag(_ c: IPTVCore.Category) -> String { allPlaylists ? "\(c.accountId)|\(c.remoteId)" : c.remoteId }

    public func scheduleSearch() {
        searchTask?.cancel()
        guard hasPlaylist else { results = []; return }
        let text = searchText, tab = tab, cat = selectedCategory, scope = scope, all = allPlaylists, aid = scopeAccountId, hide = categoryFilter
        let rating = tab == .live ? nil : minRating, unseen = hideWatched, newest = newestFirst      // channels have no rating or watched mark
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(text.isEmpty ? 0 : 100))
            if Task.isCancelled { return }
            let rows: [Item] = (try? await db.dbQueue.read { d in
                let found: [Item]
                if text.isEmpty && cat == "__fav" { found = try UserData.favorites(d, accountId: aid, type: tab) }
                else if text.isEmpty && cat == "__hist" { found = try UserData.continueWatching(d, accountId: aid, type: tab) }
                else if text.isEmpty && cat == "__watch" { found = try UserData.watchlist(d, accountId: aid, type: tab) }
                else {
                    var owner = aid, catId: String? = nil
                    if scope == .category && !cat.hasPrefix("__") {
                        if !all { catId = cat }
                        else if let bar = cat.firstIndex(of: "|") { owner = Int64(cat[..<bar]); catId = String(cat[cat.index(after: bar)...]) }
                    }
                    let type: ItemType? = (scope == .everywhere && !text.isEmpty) ? nil : tab
                    found = try Search.run(d, SearchRequest(accountId: owner, text: text, type: type, categoryId: catId,
                                                            minRating: rating, hideWatched: unseen, newestFirst: newest))
                }
                return try hide.visible(found, in: d)
            }) ?? []
            if !Task.isCancelled { results = rows }
        }
    }

    public func hasPassword(_ a: Account) -> Bool {
        guard a.kind == .xtream, let id = a.id else { return true }
        return secrets.password(for: id) != nil  // "" = deliberately no password
    }

    // MARK: Subscription

    /// What each Xtream panel said about its subscription (the expiry date), by playlist id. The last answers are kept in the defaults, so a
    /// date shows at once and offline; the settings screen refreshes them (one login request per playlist).
    public private(set) var subscriptions: [Int64: SubscriptionInfo] = LibraryModel.savedSubscriptions()
    private static let subscriptionsKey = "subscriptions"

    private static func savedSubscriptions() -> [Int64: SubscriptionInfo] {
        guard let d = UserDefaults.standard.data(forKey: subscriptionsKey),
              let m = try? JSONDecoder().decode([String: SubscriptionInfo].self, from: d) else { return [:] }
        return Dictionary(uniqueKeysWithValues: m.compactMap { k, v in Int64(k).map { ($0, v) } })
    }

    private func saveSubscriptions() {
        let m = Dictionary(uniqueKeysWithValues: subscriptions.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(try? JSONEncoder().encode(m), forKey: Self.subscriptionsKey)
    }

    /// The Xtream playlist whose subscription ends within a week (or ended), from the last answers; nil when none. Drives the warning strip.
    public var expiringSubscription: (name: String, info: SubscriptionInfo)? {
        SubscriptionInfo.mostUrgent(accounts.compactMap { a in a.id.flatMap { subscriptions[$0] }.map { (a.name, $0) } })
    }

    /// At launch: asks each Xtream panel again, at most every 12 hours (one login request per playlist), so the warning has a fresh date.
    public func refreshSubscriptionsIfDue(now: Date = Date()) async {
        let key = "subscriptionsChecked"
        if let last = UserDefaults.standard.object(forKey: key) as? Date, now.timeIntervalSince(last) < 12 * 3600 { return }
        UserDefaults.standard.set(now, forKey: key)
        for a in accounts { await refreshSubscription(a) }
    }

    /// Asks the panel again. A failed request (offline, wrong password, a panel without the field) keeps what was known.
    public func refreshSubscription(_ a: Account) async {
        guard a.kind == .xtream, let id = a.id, hasPassword(a),
              let urls = XtreamURLs(server: a.server ?? "", username: a.username ?? "", password: secrets.password(for: id) ?? "") else { return }
        guard let info = try? await XtreamClient(urls: urls).subscription(), info != subscriptions[id] else { return }
        subscriptions[id] = info
        saveSubscriptions()
    }

    // MARK: Sync

    private var syncGen = 0
    @ObservationIgnored public var lastSync: Date?                     // read by the auto-refresh loop

    /// Syncs the shown playlist, or every playlist one after the other in All mode.
    public func sync() async { await sync(allPlaylists ? accounts : account.map { [$0] } ?? []) }

    public func sync(_ targets: [Account]) async {
        lastSync = Date()                                       // an attempt counts: a failing provider is not retried every minute
        if let a = targets.first(where: { !hasPassword($0) }) { passwordPrompt = a }
        let ready = targets.filter(hasPassword)
        guard !ready.isEmpty else { return }
        syncGen += 1; let gen = syncGen
        syncing = true; syncMessage = nil; syncProgress = 0
        defer { if gen == syncGen { syncing = false; syncProgress = nil } }
        var failures: [String] = []
        var found: [ItemType: Int] = [:]
        for (index, a) in ready.enumerated() {
            guard let aid = a.id else { continue }
            let share = 1 / Double(ready.count), base = Double(index) * share      // All mode: the playlists go one after the other
            let report: @Sendable (Double) -> Void = { [weak self] p in
                Task { @MainActor in
                    guard let self, gen == self.syncGen, base + p * share > (self.syncProgress ?? 0) else { return }
                    self.syncProgress = base + p * share
                }
            }
            do {
                let r = try await SyncService(db: db).sync(account: a, password: secrets.password(for: aid), progress: report)
                found.merge(r.newCounts, uniquingKeysWith: +)
            } catch { failures.append(ready.count > 1 ? "\(a.name): \(error.localizedDescription)" : error.localizedDescription) }
            guard gen == syncGen else { return }                // a newer sync owns the UI state now
        }
        syncMessage = failures.isEmpty ? nil : failures.joined(separator: "; ")
        newSinceSync = found.filter { $0.key != .live && $0.value > 0 }
        loadCategories(); scheduleSearch(); loadHomeRows()
        Task { await refreshGuides() }                           // best effort, after the lists are on screen
    }

    /// Movies and series that the last finished sync found new (empty when none, or on a playlist's first sync). The UI announces it once.
    public var newSinceSync: [ItemType: Int] = [:]

    /// The "recently added" shelf: movies and series first seen in the last 14 days, in the shown playlist (or all of them).
    public private(set) var recentlyAdded: [Item] = []
    /// The "continue watching" shelf of the home screen: movies and series that were stopped halfway.
    public private(set) var continueRow: [Item] = []
    /// "More from <category>": the category of what was watched last, and its titles not seen yet. Empty when there is nothing to suggest.
    public private(set) var moreFromTitle: String?
    public private(set) var moreFromItems: [Item] = []
    /// "Similar to <title>": titles whose names share words with the one watched last (worked out on the device). Empty when too few.
    public private(set) var similarToTitle: String?
    public private(set) var similarItems: [Item] = []

    /// Loads the home screen's shelves (all in one read). Hidden categories are left out of each.
    public func loadHomeRows() {
        guard hasPlaylist else {
            recentlyAdded = []; continueRow = []; moreFromItems = []; moreFromTitle = nil; similarItems = []; similarToTitle = nil; return
        }
        let aid = scopeAccountId, hide = categoryFilter
        Task {
            let rows = try? await db.dbQueue.read { d in
                (recent: try hide.visible(try UserData.recentlyAdded(d, accountId: aid), in: d),
                 resume: try hide.visible(try UserData.continueWatchingMixed(d, accountId: aid), in: d),
                 more: try UserData.moreLikeWatched(d, accountId: aid).flatMap { m -> (String, [Item])? in
                     let items = try hide.visible(m.items, in: d)
                     return items.isEmpty ? nil : (m.category.name, items)
                 },
                 similar: try UserData.lastWatchedTitle(d, accountId: aid).flatMap { last -> (String, [Item])? in
                     let items = try hide.visible(try Similar.titles(like: last, in: d), in: d)
                     return items.count >= 4 ? (last.name, items) : nil
                 })
            }
            guard aid == scopeAccountId else { return }       // the playlist may have been switched while this ran
            recentlyAdded = rows?.recent ?? []; continueRow = rows?.resume ?? []
            moreFromTitle = rows?.more?.0; moreFromItems = rows?.more?.1 ?? []
            similarToTitle = rows?.similar?.0; similarItems = rows?.similar?.1 ?? []
        }
    }

    // MARK: Filters (movies and series lists)

    /// Only titles rated at least this (0...10); nil = any.
    public var minRating: Double? { didSet { scheduleSearch() } }
    public var hideWatched = false { didSet { scheduleSearch() } }
    /// Titles a refresh found lately first.
    public var newestFirst = false { didSet { scheduleSearch() } }
    public var filtersActive: Bool { minRating != nil || hideWatched || newestFirst }
    public func resetFilters() { minRating = nil; hideWatched = false; newestFirst = false }

    // MARK: Watch later

    public var watchlistKeys: Set<String> = []
    public func isOnWatchlist(_ i: Item) -> Bool { watchlistKeys.contains(UserData.favoriteKey(accountId: i.accountId, type: i.type, streamId: i.streamId)) }

    public func toggleWatchlist(_ i: Item) {
        Task {
            _ = try? await db.dbQueue.write { try UserData.toggleWatchlist($0, accountId: i.accountId, type: i.type, streamId: i.streamId) }
            loadFavorites()
            if selectedCategory == "__watch" { scheduleSearch() }
        }
    }

    public func savePassword(_ password: String, for a: Account) async {
        guard let id = a.id else { return }
        do { try secrets.setPassword(password, for: id) } catch { syncMessage = error.localizedDescription; return }
        passwordPrompt = nil
        await sync([a])   // saving a password must not switch the selected playlist (that stops the playback)
    }

    public func addAccount(_ a: Account, password: String?) async {
        let saved: Account
        do {
            saved = try await db.dbQueue.write { d in var x = a; try x.insert(d); return x }
            if let p = password, let id = saved.id { try secrets.setPassword(p, for: id) }
        } catch { syncMessage = error.localizedDescription; return }
        loadAccounts()
        let added = accounts.first { $0.id == saved.id }
        if !allPlaylists { account = added }
        await sync(added.map { [$0] } ?? [])
    }

    public func deleteAccount(_ a: Account) {
        guard let id = a.id else { return }
        if playing?.item?.accountId == id { stopPlayback() }
        _ = try? db.dbQueue.write { d in
            try d.execute(sql: "DELETE FROM favorite WHERE accountId = ?", arguments: [id])   // M3U ids are full URLs with credentials
            try d.execute(sql: "DELETE FROM history WHERE accountId = ?", arguments: [id])
            _ = try Account.deleteOne(d, key: id)
        }
        secrets.deletePassword(for: id)
        if subscriptions.removeValue(forKey: id) != nil { saveSubscriptions() }
        loadAccounts()
        if allPlaylists {                                       // still All: the deleted playlist's rows are gone
            if selectedCategory.hasPrefix("\(id)|") { selectedCategory = "__all" }
            loadCategories(); loadFavorites(); scheduleSearch()
        }
    }

    // MARK: Playback requests

    public func playlist(id: Int64) -> Account? { accounts.first { $0.id == id } }

    /// URLs for an Xtream account: the one that owns the item/series, else the current account.
    public func xtreamURLs(for accountId: Int64? = nil) -> XtreamURLs? {
        let owner = accountId.flatMap(playlist(id:)) ?? account
        guard let a = owner, a.kind == .xtream, let id = a.id else { return nil }
        return XtreamURLs(server: a.server ?? "", username: a.username ?? "", password: secrets.password(for: id) ?? "")
    }

    public func streamURL(_ item: Item) -> URL? {
        if let d = item.directURL { return Self.safeStreamURL(d) }
        return xtreamURLs(for: item.accountId)?.stream(type: item.type, id: item.streamId, ext: item.containerExt)
    }

    /// An M3U entry is untrusted: mpv would also open fd://, file://, edl://, memory:// ... so only network schemes pass.
    nonisolated public static func safeStreamURL(_ s: String) -> URL? {
        guard let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https", "rtmp", "rtmps", "rtsp", "udp", "rtp", "mms", "mmsh"].contains(u.scheme?.lowercased() ?? ""),
              u.host?.isEmpty == false else { return nil }
        return u
    }

    public func progress(accountId: Int64, type: ItemType, streamId: String) -> Double {
        let p: Double?? = try? db.dbQueue.read { try UserData.progress($0, accountId: accountId, type: type, streamId: streamId) }
        return (p ?? nil) ?? 0
    }

    /// A movie, channel or direct-URL entry plays (through `startPlayback`); a series opens its episode list (`openSeries`).
    public func play(_ item: Item) {
        if let a = playlist(id: item.accountId), !hasPassword(a) { passwordPrompt = a; return }
        if item.type == .series && item.directURL == nil { openSeries = item; return }
        guard let url = streamURL(item) else { syncMessage = IPTVError.badConfig.localizedDescription; return }
        startPlayback(PlayRequest(title: item.name, url: url, isLive: item.type == .live, item: item,
                                  start: item.type == .live ? 0 : progress(accountId: item.accountId, type: item.type, streamId: item.streamId)))
    }

    public func episodeRequest(_ e: Episode, of series: Item) -> PlayRequest? {
        guard let url = xtreamURLs(for: series.accountId)?.series(id: e.streamId, ext: e.containerExt) else { return nil }
        return PlayRequest(title: "\(series.name) — \(e.title)", url: url, isLive: false, item: series,
                           episodeKey: "ep:\(e.streamId)", start: progress(accountId: series.accountId, type: .series, streamId: "ep:\(e.streamId)"))
    }

    /// `background`: periodic saves go through asyncWrite so the main thread never waits behind a catalog sync holding the writer;
    /// saves on stop/close/quit stay synchronous so they are on disk before the app exits.
    public func saveProgress(_ r: PlayRequest, position: Double, duration: Double, background: Bool = false) {
        guard !r.isLive, let item = r.item else { return }
        let aid = item.accountId
        let sid = r.episodeKey ?? item.streamId
        let write: @Sendable (Database) throws -> Void = { try UserData.saveProgress($0, accountId: aid, type: item.type, streamId: sid, position: position, duration: duration) }
        if background { db.dbQueue.asyncWrite(write, completion: { _, _ in }) } else { _ = try? db.dbQueue.write(write) }
    }

    // MARK: Favorites and EPG

    public func isFavorite(_ i: Item) -> Bool { favoriteKeys.contains(UserData.favoriteKey(accountId: i.accountId, type: i.type, streamId: i.streamId)) }

    public func toggleFavorite(_ i: Item) {
        let aid = i.accountId
        Task {   // async: the writer may be busy with a catalog sync
            _ = try? await db.dbQueue.write { try UserData.toggleFavorite($0, accountId: aid, type: i.type, streamId: i.streamId) }
            loadFavorites()
            if selectedCategory == "__fav" { scheduleSearch() }
        }
    }

    /// Keeps `schedule` fresh for the live channel being watched; ends when the calling task is cancelled.
    public func watchSchedule(of item: Item) async {
        schedule = []
        guard item.type == .live else { return }
        if playlist(id: item.accountId)?.kind == .m3u {          // an M3U playlist's guide was downloaded from its header's link
            guard let channel = item.epgChannelId else { return }
            while !Task.isCancelled {
                schedule = (try? await db.dbQueue.read { try GuideStore.entries($0, accountId: item.accountId, channel: channel, limit: 3) }) ?? []
                try? await Task.sleep(for: .seconds(60))
            }
            return
        }
        guard let urls = xtreamURLs(for: item.accountId) else { return }
        while !Task.isCancelled {
            if let l = try? await XtreamClient(urls: urls).epgShort(streamId: item.streamId, limit: 3) { schedule = l }
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Downloads the guide of each M3U playlist that names one, at most every 6 hours per playlist, and never makes a sync fail.
    public func refreshGuides(now: Date = Date()) async {
        for a in accounts where a.kind == .m3u {
            guard let id = a.id else { continue }
            let key = "guideChecked.\(id)"
            if let last = UserDefaults.standard.object(forKey: key) as? Date, now.timeIntervalSince(last) < 6 * 3600 { continue }
            UserDefaults.standard.set(now, forKey: key)                      // an attempt counts, like a sync
            if (try? await GuideService(db: db).refresh(account: a, now: now)) ?? 0 > 0 { epgStamp = [:] }   // shown "now" titles are re-read
        }
    }

    public func epgTitle(_ i: Item) -> String? { epgNow["\(i.accountId):\(i.streamId)"] }
    /// The program on now and the one after it (nil when the provider has no guide for the channel).
    public func epgPrograms(_ i: Item) -> (now: EPGEntry?, next: EPGEntry?) {
        let l = epgEntries["\(i.accountId):\(i.streamId)"] ?? []
        return (l.first, l.count > 1 ? l[1] : nil)
    }

    /// "Now" per channel (keyed by playlist and stream id): refreshed after 5 minutes, fetched once at a time per channel.
    public func loadEPGNow(_ item: Item) async {
        let key = "\(item.accountId):\(item.streamId)"
        guard item.type == .live, !epgInFlight.contains(key) else { return }
        let fromGuide = playlist(id: item.accountId)?.kind == .m3u
        let urls = xtreamURLs(for: item.accountId)
        guard fromGuide ? item.epgChannelId != nil : urls != nil else { return }
        if let t = epgStamp[key], Date().timeIntervalSince(t) < 300 { return }
        epgInFlight.insert(key); defer { epgInFlight.remove(key) }
        let entries: [EPGEntry]?
        if fromGuide, let channel = item.epgChannelId {
            entries = try? await db.dbQueue.read { try GuideStore.entries($0, accountId: item.accountId, channel: channel, limit: 2) }
        } else if let urls {
            entries = try? await XtreamClient(urls: urls).epgShort(streamId: item.streamId, limit: 2)
        } else { entries = nil }
        guard !Task.isCancelled else { return }
        epgStamp[key] = Date()
        epgNow[key] = entries?.first?.title
        epgEntries[key] = entries ?? []
    }

    // MARK: Preferences, info, backup

    public var refreshHours: Int { UserDefaults.standard.integer(forKey: "refreshHours") }                     // 0 = only when the app opens
    public var categoryFilter: CategoryFilter {
        profile.kids ? CategoryFilter.kids : CategoryFilter(UserDefaults.standard.string(forKey: "hiddenCategoryWords") ?? "")
    }

    // MARK: Profiles

    public private(set) var profiles: [Profile] = []
    /// Whose favorites, history and watch later are shown. A kids profile also narrows every list to categories made for children.
    public private(set) var profile = Profile(id: 1, name: "Main")

    public enum ProfileSwitch: Equatable { case switched, needsPIN, wrongPIN }

    public func loadProfiles() {
        let r = try? db.dbQueue.read { (try Profiles.all($0), try Profiles.current($0)) }
        profiles = r?.0 ?? []; profile = r?.1 ?? profile
    }

    /// Leaving a profile that has a PIN asks for it. Everything that belongs to a profile is shown again for the new one.
    @discardableResult
    public func switchProfile(to target: Profile, pin: String? = nil) -> ProfileSwitch {
        guard let id = target.id, id != profile.id else { return .switched }
        if profile.hasPIN, !Profiles.accepts(profile, pin: pin) { return pin == nil ? .needsPIN : .wrongPIN }
        if playing != nil { stopPlayback() }                 // its resume point is saved now, while the profile that watched is still the current one
        // The write waits its turn behind a running catalog sync (many seconds): a click must not, so it happens off the main thread and
        // the lists are read again when it is done. The name and kids filter change at once.
        profile = target
        let db = db
        pendingProfileSwitch = Task {
            _ = try? await db.dbQueue.write { try Profiles.switchTo($0, id: id) }
            profileChanged()
        }
        return .switched
    }

    /// The switch started by the last `switchProfile` (tests wait for it).
    public private(set) var pendingProfileSwitch: Task<Void, Never>?

    /// Created, renamed, given a PIN or deleted. The lists are rebuilt only when the profile in use is another one now or its kids flag
    /// changed (that changes what every list shows); editing a different profile leaves the screen alone. Waits for the database off the
    /// main thread (a catalog sync can hold it for a long time).
    public func editProfiles(_ change: @escaping @Sendable (Database) throws -> Void) async throws {
        let before = profile
        try await db.dbQueue.write { try change($0) }
        loadProfiles()
        if profile.id != before.id || profile.kids != before.kids { profileChanged() }
    }

    private func profileChanged() {
        loadProfiles()
        if playing != nil { stopPlayback() }
        selectedCategory = "__all"; searchText = ""
        newSinceSync = [:]; resetFilters()
        loadCategories(); loadFavorites(); scheduleSearch(); loadHomeRows()
    }

    /// Syncs what is shown (the playlist, or all of them) once `refreshHours` have passed since the last sync; ends when cancelled.
    public func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            if !syncing, !accounts.isEmpty, RefreshSchedule.isDue(hours: refreshHours, lastSync: lastSync, now: Date()) { await sync() }
        }
    }

    /// The hidden words changed: the sidebar and the lists are filtered again (a selected category that is now hidden is left).
    public func hiddenCategoriesChanged() {
        loadCategories()
        if !selectedCategory.hasPrefix("__"), !categories.contains(where: { categoryTag($0) == selectedCategory }) { selectedCategory = "__all" }
        scheduleSearch(); loadHomeRows()
    }

    /// Details exist only for movies and series of an Xtream playlist (an M3U file has none).
    public func hasInfo(_ item: Item) -> Bool { item.type != .live && playlist(id: item.accountId)?.kind == .xtream }

    /// The provider's details for a title: cached for 14 days, else fetched (never for a whole list, only when a sheet asks).
    public func loadInfo(_ item: Item, refresh: Bool = false) async throws -> ItemInfo {
        guard let a = playlist(id: item.accountId), let id = a.id else { return ItemInfo() }
        guard hasPassword(a) else { throw IPTVError.badCredentials }
        return try await SyncService(db: db).info(account: a, password: secrets.password(for: id), type: item.type, streamId: item.streamId, refresh: refresh)
    }

    /// Whatever is cached, however old: for showing something at once while a fresh copy is on its way.
    public func cachedInfo(_ item: Item) async -> ItemInfo? {
        try? await db.dbQueue.read { try ItemInfoStore.cached($0, accountId: item.accountId, type: item.type, streamId: item.streamId, maxAge: nil) }
    }

    public func exportBackup(to url: URL) async throws {
        try await db.dbQueue.read { try Backup.make($0) }.write(to: url)
    }

    /// Merges a backup file. New playlists are synced; an Xtream one has no password yet, so sync() asks for it.
    open func importBackup(from url: URL) async throws {
        let backup = try Backup.read(from: url)
        let added = try await db.dbQueue.write { try backup.merge(into: $0) }.compactMap(\.id)
        loadAccounts(); loadFavorites(); scheduleSearch()
        await sync(accounts.filter { added.contains($0.id ?? 0) })
    }

    /// Checks a new source before it is saved (the same check on every platform): Xtream must log in, an M3U link must answer with a playlist.
    /// Throws an error whose localizedDescription is fit to show.
    nonisolated public static func testConnection(kind: AccountKind, server: String, username: String, password: String, url: String) async throws {
        if kind == .xtream {
            guard let u = XtreamURLs(server: server, username: username, password: password) else { throw IPTVError.badConfig }
            try await XtreamClient(urls: u).authenticate()
        } else {
            guard let u = URL(string: url.trimmingCharacters(in: .whitespaces)), u.scheme != nil, u.host != nil else { throw IPTVError.badConfig }
            var r = URLRequest(url: u); r.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
            let (d, _) = try await apiSession.data(for: r)
            guard String(decoding: d, as: UTF8.self).drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).hasPrefix("#EXTM3U")
            else { throw IPTVError.badResponse }
        }
    }

    /// The add-source form is complete (name, and server + user for Xtream or a link for M3U).
    nonisolated public static func isValidSource(kind: AccountKind, name: String, server: String, username: String, url: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kind == .xtream ? !server.isEmpty && !username.isEmpty : !url.isEmpty)
    }

    public func clear(_ kind: ClearKind) {
        switch kind {
        case .history: _ = try? db.dbQueue.write { try UserData.clearHistory($0) }
        case .favorites: _ = try? db.dbQueue.write { try UserData.clearFavorites($0) }
        case .images: URLCache.shared.removeAllCachedResponses()
        }
        loadFavorites(); scheduleSearch()
    }
}
