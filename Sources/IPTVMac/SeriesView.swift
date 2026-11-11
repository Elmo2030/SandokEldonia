import SwiftUI
import IPTVCore
import IPTVAppKit

struct SeriesView: View {
    @Environment(AppModel.self) var model
    @Environment(\.dismiss) var dismiss
    let series: Item
    @State private var episodes: [Episode] = []
    @State private var loading = true
    @State private var error: String?
    @State private var info: ItemInfo?
    @State private var progress: [String: EpisodeProgress] = [:]      // by episode stream id: where you stopped

    /// The episode left halfway, else the one after the last finished (what to watch next).
    private var upNext: (episode: Episode, resume: Bool)? { WatchProgress.upNext(episodes, progress: progress) }

    @ViewBuilder private var upNextButton: some View {
        if let n = upNext {
            let e = n.episode, pct = progress[e.streamId].map { Int($0.fraction * 100) }
            Button {
                dismiss(); model.playEpisode(e, of: series, in: episodes)
            } label: {
                Label(String(format: L(n.resume ? "series.continueEp" : "series.playEp"), e.season, e.number) + (n.resume ? pct.map { " · \($0)%" } ?? "" : ""),
                      systemImage: "play.fill").font(.headline).padding(.horizontal, 14).padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).tint(CinemaTheme.accent)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(series.name).font(.title.weight(.bold)).lineLimit(2)
                Spacer()
                Button(L("player.close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let info, info.hasContent { SeriesHeader(series: series, info: info).transition(.opacity) }
            if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity) }
            else if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                upNextButton
                ScrollViewReader { proxy in
                    List {
                        let bySeason = Dictionary(grouping: episodes, by: \.season)
                        ForEach(bySeason.keys.sorted(), id: \.self) { s in
                            Section {
                                ForEach(bySeason[s] ?? []) { e in row(e).id(e.id) }
                            } header: {
                                HStack {
                                    Text("\(L("series.season")) \(s)").font(.title3.weight(.bold)).foregroundStyle(CinemaTheme.accent)
                                    Spacer()
                                    Button(L("downloads.season")) { model.download(bySeason[s] ?? [], of: series) }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .onAppear { if let id = upNext?.episode.id { proxy.scrollTo(id, anchor: .center) } }      // land on where you stopped
                }
            }
        }
        .padding(22)
        .frame(minWidth: 760, idealWidth: 940, minHeight: 600, idealHeight: 800)
        .background(CinemaTheme.background)
        .motion(value: loading)
        .motion(value: info)
        .task {
            guard let a = model.playlist(id: series.accountId) else { return }
            info = await model.cachedInfo(series)        // from an earlier visit; the episodes request below refreshes it for free
            // Seen before: the list is there at once (the provider can be slow, e.g. while a sync runs) and is refreshed behind it.
            func loadProgress() async { progress = (try? await model.db.dbQueue.read { try WatchProgress.episodeProgress($0, accountId: series.accountId) }) ?? [:] }
            episodes = await model.cachedEpisodes(of: series)
            if !episodes.isEmpty { await loadProgress(); loading = false }
            do {
                episodes = try await SyncService(db: model.db).episodes(account: a, password: a.id.flatMap { model.secrets.password(for: $0) }, seriesId: series.streamId)
            } catch { if episodes.isEmpty { self.error = error.localizedDescription } }
            await loadProgress()
            loading = false
            if let fresh = await model.cachedInfo(series) { info = fresh }
        }
    }

    /// One episode: its number, title, how far you got (a bar, or a check mark when finished) and a download button. The one to watch next is tinted.
    private func row(_ e: Episode) -> some View {
        let p = progress[e.streamId]
        let isNext = upNext?.episode.id == e.id
        return HStack(spacing: 14) {
            Text("\(e.number)").font(.callout.weight(.semibold)).monospacedDigit()
                .frame(width: 38, height: 38)
                .background(isNext ? CinemaTheme.accent.opacity(0.28) : CinemaTheme.elevatedSurface, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(e.title).font(.body).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if let p, !p.isWatched, p.position >= 5 {
                    ProgressView(value: p.fraction).tint(CinemaTheme.accent).frame(maxWidth: 240)
                }
            }
            if let p {
                if p.isWatched {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).imageScale(.large)
                        .help(L("series.watched")).accessibilityLabel(L("series.watched"))
                } else if p.position >= 5 {
                    Text("\(Int(p.fraction * 100))%").font(.callout).monospacedDigit().foregroundStyle(CinemaTheme.accent)
                }
            }
            Button { model.download([e], of: series) } label: { Image(systemName: "arrow.down.circle") }
                .buttonStyle(IconButtonStyle()).help(L("downloads.add")).accessibilityLabel(L("downloads.add"))
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(isNext ? CinemaTheme.accent.opacity(0.14) : CinemaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { dismiss(); model.playEpisode(e, of: series, in: episodes) }
        .hoverHighlight(radius: 12)
        .listRowSeparator(.hidden).listRowBackground(Color.clear)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }
}
