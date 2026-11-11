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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(series.name).font(.title2.weight(.semibold)).lineLimit(2)
                Spacer()
                Button(L("player.close")) { dismiss() }
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
                            ForEach(bySeason[s] ?? []) { e in
                                HStack(spacing: 10) {
                                    Text("\(e.number)").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 28, alignment: .trailing)
                                    Text(e.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                        .onTapGesture { dismiss(); model.playEpisode(e, of: series, in: episodes) }
                                    if let p = progress[e.streamId] {
                                        if p.isWatched {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                                .help(L("series.watched")).accessibilityLabel(L("series.watched"))
                                        } else if p.position >= 5 {
                                            Text("\(Int(p.fraction * 100))%").font(.caption).monospacedDigit().foregroundStyle(CinemaTheme.accent)
                                        }
                                    }
                                    Button { model.download([e], of: series) } label: { Image(systemName: "arrow.down.circle") }
                                        .buttonStyle(IconButtonStyle()).help(L("downloads.add")).accessibilityLabel(L("downloads.add"))
                                }
                                .padding(.vertical, 2).hoverHighlight(radius: 6)
                                .background(upNext?.episode.id == e.id ? CinemaTheme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .id(e.id)
                            }
                        } header: {
                            HStack {
                                Text("\(L("series.season")) \(s)").font(.headline)
                                Spacer()
                                Button(L("downloads.season")) { model.download(bySeason[s] ?? [], of: series) }
                            }
                        }
                    }
                }
                .onAppear { if let id = upNext?.episode.id { proxy.scrollTo(id, anchor: .center) } }      // land on where you stopped
                }
            }
        }
        .padding().frame(minWidth: 520, minHeight: 480)
        .motion(value: loading)
        .motion(value: info)
        .task {
            guard let a = model.playlist(id: series.accountId) else { return }
            info = await model.cachedInfo(series)        // from an earlier visit; the episodes request below refreshes it for free
            do {
                episodes = try await SyncService(db: model.db).episodes(account: a, password: a.id.flatMap { model.secrets.password(for: $0) }, seriesId: series.streamId)
            } catch { self.error = error.localizedDescription }
            progress = (try? await model.db.dbQueue.read { try WatchProgress.episodeProgress($0, accountId: series.accountId) }) ?? [:]
            loading = false
            if let fresh = await model.cachedInfo(series) { info = fresh }
        }
    }
}
