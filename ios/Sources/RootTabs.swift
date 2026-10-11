import SwiftUI
import IPTVCore

/// Live / Movies / Series / Sources, the sheets, and the player over everything while something plays.
struct RootTabs: View {
    @Environment(PhoneModel.self) private var model
    @State private var selection = Tab.live

    enum Tab: Hashable {
        case live, movies, series, sources
        var itemType: ItemType? { self == .live ? .live : self == .movies ? .movie : self == .series ? .series : nil }
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $selection) {
            ItemsScreen(title: L("tab.live")).tabItem { Label(L("tab.live"), systemImage: "tv") }.tag(Tab.live)
            ItemsScreen(title: L("tab.movies")).tabItem { Label(L("tab.movies"), systemImage: "film") }.tag(Tab.movies)
            ItemsScreen(title: L("tab.series")).tabItem { Label(L("tab.series"), systemImage: "rectangle.stack") }.tag(Tab.series)
            SourcesScreen().tabItem { Label(L("settings.accounts"), systemImage: "list.bullet") }.tag(Tab.sources)
        }
        .onChange(of: selection) { _, tab in if let t = tab.itemType { model.tab = t } }
        .overlay { if let p = model.player { PlayerScreen(player: p).transition(.opacity) } }
        .sheet(item: $model.openSeries) { SeriesSheet(series: $0) }
        .sheet(item: $model.passwordPrompt) { PasswordSheet(account: $0) }
    }
}
