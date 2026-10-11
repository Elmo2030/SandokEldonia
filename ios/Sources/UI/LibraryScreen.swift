import SwiftUI
import IPTVCore
import IPTVAppKit

/// What belongs to you: what you started watching, and your favorites by type.
struct LibraryScreen: View {
    @Environment(PhoneModel.self) private var model
    @Environment(UIState.self) private var ui
    @State private var favorites: [(ItemType, [Item])] = []
    @State private var loaded = false

    private struct Key: Hashable { var favorites: Set<String>; var all: Bool; var account: Int64?; var syncing: Bool }

    var body: some View {
        let shelf = ui.continueMovies + ui.continueSeries
        let hasFavorites = favorites.contains { !$0.1.isEmpty }
        NavigationStack {
            Group {
                if !loaded { Color.clear }
                else if shelf.isEmpty && !hasFavorites {
                    ContentUnavailableView { Label(L("library.empty"), systemImage: "books.vertical") } description: { Text(L("library.empty.hint")) }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20, pinnedViews: .sectionHeaders) {
                            if !shelf.isEmpty { ContinueShelf(entries: shelf) }
                            if hasFavorites {
                                Text(L("cat.favorites")).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader).padding(.horizontal, 16)
                                GroupedSections(groups: favorites, alwaysHeaders: false)
                            }
                        }
                        .padding(.top, 12).padding(.bottom, 24)
                    }
                    .syncRefreshable(model, ui)
                }
            }
            .background(Brand.canvas)
            .navigationTitle(L("tab.library"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { PlaylistMenu() } }
            .motion(value: loaded)
        }
        .task(id: Key(favorites: model.favoriteKeys, all: model.allPlaylists, account: model.account?.id, syncing: model.syncing)) {
            let aid = model.playlist?.id, hide = model.categoryFilter
            let r: [(ItemType, [Item])]? = try? await model.db.dbQueue.read { d in
                try ItemType.allCases.map { t in (t, try hide.visible(UserData.favorites(d, accountId: aid, type: t), in: d)) }
            }
            favorites = r ?? []; loaded = true
        }
    }
}
