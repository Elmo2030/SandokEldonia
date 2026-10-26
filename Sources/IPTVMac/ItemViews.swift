import SwiftUI
import IPTVCore

/// Which playlist an item comes from; only shown while All playlists is on.
struct PlaylistBadge: View {
    @Environment(AppModel.self) var model
    let item: Item
    /// On a poster the badge sits on arbitrary artwork, so it gets its own dark ground instead of the system tint.
    var onArtwork = false
    var body: some View {
        if model.allPlaylists, let name = model.playlist(id: item.accountId)?.name {
            Text(name).font(.caption2.weight(.medium)).lineLimit(1)
                .foregroundStyle(onArtwork ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(onArtwork ? Color.black.opacity(0.62) : CinemaTheme.cardBorder, in: Capsule())
        }
    }
}

struct ChannelRow: View {
    @Environment(AppModel.self) var model
    let item: Item
    @State private var hover = false
    var body: some View {
        let isFav = model.isFavorite(item)
        let current = model.lastPlayedID == item.id
        HStack(spacing: 12) {
            Artwork(url: item.iconURL, symbol: "tv")
                .padding(4)
                .frame(width: 44, height: 44)
                .background(CinemaTheme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(CinemaTheme.primaryText).lineLimit(1)
                if let now = model.epgTitle(item) { Text(now).font(.caption).foregroundStyle(CinemaTheme.secondaryText).lineLimit(1) }
            }
            Spacer()
            PlaylistBadge(item: item)
            if item.tvArchive { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary) }
            Button { model.toggleFavorite(item) } label: {
                Image(systemName: isFav ? "star.fill" : "star").contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain).foregroundStyle(isFav ? CinemaTheme.accent : CinemaTheme.secondaryText)
            .accessibilityLabel(L(isFav ? "fav.remove" : "fav.add"))
            .motion(value: isFav)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    current ? CinemaTheme.selectedSurface :
                    hover ? CinemaTheme.elevatedSurface : CinemaTheme.surface
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            current ? CinemaTheme.accent.opacity(0.55) : CinemaTheme.cardBorder,
                            lineWidth: current ? 1.2 : 1
                        )
                }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .motion(.easeOut(duration: 0.12), value: hover)
        .onTapGesture { model.play(item) }
        .contextMenu { Button(model.isFavorite(item) ? L("fav.remove") : L("fav.add")) { model.toggleFavorite(item) } }
        .task { await model.loadEPGNow(item) }
    }
}

struct PosterCell: View {
    @Environment(AppModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduce
    let item: Item
    @State private var hover = false
    @FocusState private var infoFocused: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .bottomTrailing) {
                        Rectangle().fill(placeholderFill)
                        Artwork(url: item.iconURL, symbol: "film", fill: true, symbolFont: .largeTitle)

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.62)],
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        Button {
                            model.play(item)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CinemaTheme.background)
                                .frame(width: 38, height: 38)
                                .background(CinemaTheme.accent, in: Circle())
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        .opacity(hover ? 1 : 0)
                        .allowsHitTesting(hover)
                        .help(L("info.play"))
                        .accessibilityLabel("\(L("info.play")), \(item.name)")
                        .transition(.opacity)
                    }
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(CinemaTheme.accent.opacity(hover ? 0.42 : 0.13), lineWidth: 1) }
                .overlay { if model.lastPlayedID == item.id { shape.strokeBorder(CinemaTheme.accent, lineWidth: 2) } }
                .overlay(alignment: .topLeading) { PlaylistBadge(item: item, onArtwork: true).padding(5) }
                .overlay(alignment: .topTrailing) { if model.hasInfo(item) { infoButton } }
                .shadow(color: .black.opacity(hover ? 0.35 : 0), radius: hover ? 10 : 0, y: hover ? 5 : 0)
                .scaleEffect(hover && !reduce ? 1.035 : 1)
            Text(item.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(CinemaTheme.primaryText)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            CinemaTheme.surface,
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    CinemaTheme.accent.opacity(hover ? 0.38 : 0.10),
                    lineWidth: 1
                )
        }
        .shadow(
            color: .black.opacity(hover ? 0.22 : 0),
            radius: hover ? 12 : 0,
            y: hover ? 5 : 0
        )
        .contentShape(Rectangle())
        .zIndex(hover ? 1 : 0)
        .onHover { hover = $0 }
        .animation(reduce ? nil : .smooth(duration: 0.18), value: hover)
        .onTapGesture {
            if model.hasInfo(item) {
                model.openInfo = item
            } else {
                model.play(item)
            }
        }
        .contextMenu {
            if model.hasInfo(item) { Button(L("info.details")) { model.openInfo = item } }
            Button(model.isFavorite(item) ? L("fav.remove") : L("fav.add")) { model.toggleFavorite(item) }
            if item.type == .movie { Button(L("downloads.add")) { model.download(item) } }
        }
    }

    /// Always shown (brighter under the pointer or when focused); stays in the accessibility tree and focus order, so VoiceOver and keyboard users can reach it.
    private var infoButton: some View {
        let label = "\(L("info.details")), \(item.name)"
        return Button { model.openInfo = item } label: {
            Image(systemName: "info").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Color.black.opacity(0.62), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).focused($infoFocused)
        .help(L("info.details")).accessibilityLabel(label)
        .opacity(hover || infoFocused ? 1 : 0.8)        // always visible and clickable: the way to the details must not depend on hovering
        .motion(.easeOut(duration: 0.12), value: infoFocused)
        .padding(5)
    }
}

struct ResultsView: View {
    @Environment(AppModel.self) var model
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 16)]

    private func title(_ t: ItemType) -> String {
        switch t { case .live: L("tab.live"); case .movie: L("tab.movies"); case .series: L("tab.series") }
    }

    var body: some View {
        let groups = Dictionary(grouping: model.results, by: \.type)
        let phase = model.results.isEmpty ? (model.syncing ? 1 : 0) : 2
        Group {
        if model.results.isEmpty && model.syncing {
            SkeletonResults(posters: model.tab != .live).transition(.opacity)
        } else if model.results.isEmpty {
            ContentUnavailableView {
                Label(L("empty.results"), systemImage: "magnifyingglass")
            } description: {
                if !model.searchText.isEmpty { Text("\u{201C}\(model.searchText)\u{201D}") }
            } actions: {
                if !model.searchText.isEmpty { Button(L("clear.confirm")) { model.searchText = "" } }
            }.transition(.opacity)
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: .sectionHeaders) {
                    ForEach(ItemType.allCases, id: \.self) { t in
                        if let items = groups[t] {
                            Section {
                                if t == .live {
                                    ForEach(items) { ChannelRow(item: $0) }
                                } else {
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                                        ForEach(items) { PosterCell(item: $0) }
                                    }.padding(.horizontal, 12)
                                }
                            } header: {
                                if groups.count > 1 {
                                    Text(title(t)).font(.headline).padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(CinemaTheme.surface)
                                        .overlay(alignment: .bottom) {
                                            Rectangle().fill(CinemaTheme.separator).frame(height: 1)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {   // back from the player: show the row that was playing instead of the top of the list
                guard let id = model.scrollTarget else { return }
                model.scrollTarget = nil
                let key: Int64? = id   // rows are identified by Item.id, an Optional: scrollTo must get the same type
                if model.results.contains(where: { $0.id == key }) { DispatchQueue.main.async { proxy.scrollTo(key, anchor: .center) } }
            }
            }.transition(.opacity)
        }
        }
        .motion(.easeOut(duration: 0.2), value: phase)
    }
}
