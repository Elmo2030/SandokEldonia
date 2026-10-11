import SwiftUI
import IPTVCore

/// The list of the selected tab (the shared model holds one result list for the current type, category and search).
struct ItemsScreen: View {
    @Environment(PhoneModel.self) private var model
    let title: String
    @State private var adding = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.accounts.isEmpty {
                    ContentUnavailableView {
                        Label(L("onb.welcome.title"), systemImage: "tv")
                    } description: {
                        Text(L("onb.welcome.body"))
                    } actions: {
                        Button(L("account.add")) { adding = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if let m = model.syncMessage { Label("\(L("sync.failed")): \(m). \(L("sync.notUpdated"))", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        ForEach(model.results) { ItemRow(item: $0) }
                    }
                    .overlay {
                        if model.results.isEmpty { if model.syncing { ProgressView(L("sync.running")) } else { Text(L("empty.results")).foregroundStyle(.secondary) } }
                    }
                    .searchable(text: $model.searchText, prompt: L("search.prompt"))
                    .refreshable { await model.sync() }
                }
            }
            .navigationTitle(title)
            .toolbar { if !model.accounts.isEmpty { ToolbarItem(placement: .topBarTrailing) { CategoryMenu() } } }
            .sheet(isPresented: $adding) { AddSourceSheet() }
        }
    }
}

private struct CategoryMenu: View {
    @Environment(PhoneModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Menu {
            if model.accounts.count > 1 {
                Picker(L("playlist.label"), selection: $model.playlist) {
                    Label(L("playlist.all"), systemImage: "square.stack.3d.up").tag(Account?.none)
                    ForEach(model.accounts) { Text($0.name).tag(Optional($0)) }
                }
            }
            Picker(L("cat.all"), selection: $model.selectedCategory) {
                Label(L("cat.all"), systemImage: "square.grid.2x2").tag("__all")
                Label(L("cat.favorites"), systemImage: "star").tag("__fav")
                Label(L("cat.continue"), systemImage: "clock").tag("__hist")
                ForEach(model.categories) { Text($0.name).tag(model.categoryTag($0)) }
            }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
    }
}

private struct ItemRow: View {
    @Environment(PhoneModel.self) private var model
    let item: Item
    var body: some View {
        let fav = model.isFavorite(item)
        HStack(spacing: 12) {
            AsyncImage(url: item.iconURL) { $0.resizable().scaledToFit() } placeholder: { Color.secondary.opacity(0.15) }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).lineLimit(2)
                if let now = model.epgTitle(item) { Text(now).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button { model.toggleFavorite(item) } label: { Image(systemName: fav ? "star.fill" : "star").frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(fav ? Color.yellow : Color.secondary)
                .accessibilityLabel(L(fav ? "fav.remove" : "fav.add"))
        }
        .contentShape(Rectangle())
        .onTapGesture { model.play(item) }
        .task { await model.loadEPGNow(item) }
    }
}
