import SwiftUI
import IPTVCore

/// A week or less left on an Xtream subscription, or it already ended: one line under the toolbar, dismissed for the rest of the day.
struct ExpiryStrip: View {
    @Environment(AppModel.self) private var model
    @AppStorage("expiryDismissed") private var dismissed = ""

    private func token(_ name: String) -> String { "\(name)|\(Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970))" }

    var body: some View {
        if let w = model.expiringSubscription, let end = w.info.expires, dismissed != token(w.name) {
            let date = end.formatted(date: .abbreviated, time: .omitted)
            let expired = w.info.state() == .expired
            let text = expired ? String(format: L("sub.expired"), date)
                               : "\(String(format: L("sub.expires"), date)) · \(String(format: L("sub.daysLeft"), w.info.daysLeft() ?? 0))"
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(expired ? .red : .orange)
                Text("\(w.name): \(text)").font(.callout).lineLimit(2)
                Spacer(minLength: 0)
                Button(L("update.later")) { dismissed = token(w.name) }.buttonStyle(.link)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CinemaTheme.surface)
            .overlay(alignment: .bottom) { Rectangle().fill(CinemaTheme.separator).frame(height: 1) }
            .accessibilityElement(children: .combine)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) var model
    @State private var catFilter = ""
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var showingHome = true

    var body: some View {
        @Bindable var model = model
        Group {
            if model.accounts.isEmpty { OnboardingView(isFirstRun: true) } else { main(model: $model) }
        }
        .sheet(isPresented: $model.showGuide) { OnboardingView(isFirstRun: false) }
        .sheet(item: $model.openSeries) { SeriesView(series: $0) }
        .sheet(item: $model.openInfo) { InfoSheet(item: $0) }
        .sheet(isPresented: $model.showDownloads) { DownloadsView() }
        .sheet(item: $model.passwordPrompt) { PasswordPrompt(account: $0) }
    }

    private func categoryColor(_ name: String) -> Color {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if ["sport", "bein", "football", "soccer", "رياض", "كورة", "كرة"].contains(where: n.contains) {
            return Color(red: 0.35, green: 0.68, blue: 1.0)
        }
        if ["movie", "cinema", "film", "أفلام", "افلام", "سينما"].contains(where: n.contains) {
            return CinemaTheme.accent
        }
        if ["series", "drama", "مسلسل", "مسلسلات", "دراما"].contains(where: n.contains) {
            return Color(red: 0.72, green: 0.60, blue: 1.0)
        }
        if ["news", "أخبار", "اخبار"].contains(where: n.contains) {
            return Color(red: 0.95, green: 0.48, blue: 0.45)
        }
        if ["kids", "children", "أطفال", "اطفال", "family"].contains(where: n.contains) {
            return Color(red: 0.30, green: 0.78, blue: 0.57)
        }
        return CinemaTheme.secondaryText
    }

    private func categorySymbol(_ name: String) -> String {
        let n = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if ["sport", "bein", "football", "soccer", "رياض", "كورة", "كرة"].contains(where: n.contains) { return "sportscourt.fill" }
        if ["movie", "cinema", "film", "أفلام", "افلام", "سينما"].contains(where: n.contains) { return "film.fill" }
        if ["series", "drama", "مسلسل", "مسلسلات", "دراما"].contains(where: n.contains) { return "tv.fill" }
        if ["news", "أخبار", "اخبار"].contains(where: n.contains) { return "newspaper.fill" }
        if ["kids", "children", "أطفال", "اطفال", "family"].contains(where: n.contains) { return "figure.2.and.child.holdinghands" }
        return "folder.fill"
    }

    /// "New movies: 12 · New series: 3" for what the last refresh found; nil when nothing was new.
    private func newTitlesText(_ found: [ItemType: Int]) -> String? {
        let parts = [(ItemType.movie, "sync.new.movies"), (.series, "sync.new.series")].compactMap { type, key in
            found[type].flatMap { $0 > 0 ? String(format: L(key), $0) : nil }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func showsPlayer(_ m: AppModel) -> Bool { m.playing != nil && !m.pip && m.player != nil }

    @ViewBuilder
    private func main(model: Bindable<AppModel>) -> some View {
        NavigationSplitView(columnVisibility: $columns) {
            VStack(spacing: 0) {
                TextField(L("cat.filter"), text: $catFilter).textFieldStyle(.roundedBorder).padding(8)
                List(selection: model.selectedCategory) {
                    Label { Text(L("cat.all")) } icon: { Image(systemName: "square.grid.2x2").foregroundStyle(Color(red: 0.35, green: 0.68, blue: 1.0)) }.tag("__all")
                    Label { Text(L("cat.favorites")) } icon: { Image(systemName: "star.fill").foregroundStyle(CinemaTheme.accent) }.tag("__fav")
                    Label { Text(L("cat.continue")) } icon: { Image(systemName: "clock.fill").foregroundStyle(Color(red: 0.30, green: 0.78, blue: 0.57)) }.tag("__hist")
                    Label { Text(L("cat.watchlist")) } icon: { Image(systemName: "bookmark.fill").foregroundStyle(Color(red: 0.72, green: 0.60, blue: 1.0)) }.tag("__watch")
                    let cats = model.wrappedValue.categories.filter { catFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(catFilter) }
                    if model.wrappedValue.allPlaylists {
                        ForEach(model.wrappedValue.accounts) { a in       // one header per playlist
                            let mine = cats.filter { $0.accountId == a.id }
                            if !mine.isEmpty {
                                Section(a.name) {
                                    ForEach(mine) { c in Label { Text(c.name).lineLimit(1) } icon: { Image(systemName: categorySymbol(c.name)).foregroundStyle(categoryColor(c.name)) }.tag(model.wrappedValue.categoryTag(c)) }
                                }
                            }
                        }
                    } else {
                        Section {
                            ForEach(cats) { c in Label { Text(c.name).lineLimit(1) } icon: { Image(systemName: categorySymbol(c.name)).foregroundStyle(categoryColor(c.name)) }.tag(model.wrappedValue.categoryTag(c)) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(CinemaTheme.background)
            }
            .background(CinemaTheme.background)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                if let r = model.wrappedValue.playing, !model.wrappedValue.pip, let pm = model.wrappedValue.player {
                    // Inside the detail column: the tabs, search and Back stay in the toolbar while watching.
                    PlayerScreen(request: r, pm: pm)    // no transition here: the video view is re-parented between hosts
                } else {
                    VStack(spacing: 0) {
                        #if !APPSTORE
                        UpdateBanner()
                        #endif
                        ExpiryStrip()
                        if model.wrappedValue.syncing {
                            StatusStrip(kind: .busy, text: syncStatusText(model.wrappedValue.syncProgress))
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if !model.wrappedValue.syncing, let text = newTitlesText(model.wrappedValue.newSinceSync) {
                            StatusStrip(kind: .info, text: text)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .task(id: model.wrappedValue.newSinceSync) {         // announced once, then it goes away
                                    try? await Task.sleep(for: .seconds(10))
                                    if !Task.isCancelled { model.wrappedValue.newSinceSync = [:] }
                                }
                        }
                        if let m = model.wrappedValue.syncMessage {
                            StatusStrip(kind: .warning, text: "\(L("sync.failed")): \(m). \(L("sync.notUpdated"))")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showingHome
                            && model.wrappedValue.selectedCategory == "__all"
                            && model.wrappedValue.searchText.isEmpty {
                            HomeDashboardView(onExplore: { showingHome = false })
                        } else {
                            ResultsView()
                        }
                    }
                    .motion(value: model.wrappedValue.syncing)
                    .motion(value: model.wrappedValue.syncMessage)
                }
            }
            .background(CinemaTheme.background)
            .searchable(text: model.searchText, prompt: L("search.prompt"))
            .searchScopes(model.scope) {
                Text(L("scope.category")).tag(SearchScopeChoice.category)
                Text(L("scope.type")).tag(SearchScopeChoice.type)
                Text(L("scope.everywhere")).tag(SearchScopeChoice.everywhere)
            }
            .toolbar {
                // Lives in the window toolbar, so it works whatever the video view covers.
                ToolbarItem(placement: .navigation) {
                    if model.wrappedValue.playing != nil {
                        Button { model.wrappedValue.stopPlayback() } label: { Label(L("player.back"), systemImage: "chevron.backward") }
                            .keyboardShortcut(.cancelAction).help(L("player.back"))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Picker("", selection: model.tab) {
                        Text(L("tab.live")).tag(ItemType.live)
                        Text(L("tab.movies")).tag(ItemType.movie)
                        Text(L("tab.series")).tag(ItemType.series)
                    }.pickerStyle(.segmented).frame(width: 240)
                }
                ToolbarItem {
                    if model.wrappedValue.accounts.count > 1 {
                        Menu {
                            Picker(L("playlist.label"), selection: model.playlist) {
                                Label(L("playlist.all"), systemImage: "square.stack.3d.up").tag(Account?.none)
                                ForEach(model.wrappedValue.accounts) { Text($0.name).tag(Optional($0)) }
                            }.pickerStyle(.inline)
                        } label: {
                            Label(model.wrappedValue.playlist?.name ?? L("playlist.all"), systemImage: "square.stack.3d.up").labelStyle(.titleAndIcon)
                        }.help(L("playlist.label"))
                    }
                }
                ToolbarItem {
                    if model.wrappedValue.tab != .live {
                        Menu {
                            Toggle(L("filter.hideWatched"), isOn: model.hideWatched)
                            Toggle(L("filter.newest"), isOn: model.newestFirst)
                            Picker(L("info.rating"), selection: model.minRating) {
                                Text(L("cat.all")).tag(Double?.none)
                                ForEach([6, 7, 8], id: \.self) { Text(String(format: L("filter.rating"), $0)).tag(Double?.some(Double($0))) }
                            }
                            if model.wrappedValue.filtersActive { Divider(); Button(L("filter.reset")) { model.wrappedValue.resetFilters() } }
                        } label: {
                            Image(systemName: model.wrappedValue.filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }.help(L("filter.title")).accessibilityLabel(L("filter.title"))
                    }
                }
                ToolbarItem {
                    Button { model.wrappedValue.showDownloads = true } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle")
                            if model.wrappedValue.downloads.activeCount > 0 { Text("\(model.wrappedValue.downloads.activeCount)").font(.caption).monospacedDigit() }
                        }
                    }.help(L("downloads.title"))
                }
                ToolbarItem { Button { Task { await model.wrappedValue.sync() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.wrappedValue.syncing).help(L("settings.refresh")).accessibilityLabel(L("settings.refresh")) }
            }
        }
        .onChange(of: model.wrappedValue.playerFullscreen) { _, full in columns = full ? .detailOnly : .automatic }
    }
}
