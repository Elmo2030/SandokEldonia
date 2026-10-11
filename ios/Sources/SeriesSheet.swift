import SwiftUI
import IPTVCore

/// Episodes of a series by season; a tap plays the episode.
struct SeriesSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let series: Item
    @State private var episodes: [Episode] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView() }
                else if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).padding() }
                else {
                    List {
                        let bySeason = Dictionary(grouping: episodes, by: \.season)
                        ForEach(bySeason.keys.sorted(), id: \.self) { s in
                            Section("\(L("series.season")) \(s)") {
                                ForEach(bySeason[s] ?? []) { e in
                                    Button { dismiss(); model.playEpisode(e, of: series) } label: {
                                        HStack {
                                            Text("\(e.number)").monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 28, alignment: .trailing)
                                            Text(e.title).frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }.tint(.primary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("player.close")) { dismiss() } } }
        }
        .task {
            guard let a = model.playlist(id: series.accountId) else { return }
            do {
                episodes = try await SyncService(db: model.db).episodes(account: a, password: a.id.flatMap { model.secrets.password(for: $0) }, seriesId: series.streamId)
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
