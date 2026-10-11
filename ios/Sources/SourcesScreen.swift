import SwiftUI
import IPTVCore

/// The list of sources (playlists): add, sync, delete.
struct SourcesScreen: View {
    @Environment(PhoneModel.self) private var model
    @State private var adding = false
    @State private var deleting: Account?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.accounts) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.name)
                        Text(a.kind == .xtream ? L("kind.xtream") : L("kind.m3u")).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button(L("settings.delete"), role: .destructive) { deleting = a } }
                }
                Button(L("account.add")) { adding = true }
            }
            .navigationTitle(L("settings.accounts"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.syncing { ProgressView() }
                    else { Button { Task { await model.sync() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.accounts.isEmpty) }
                }
            }
            .sheet(isPresented: $adding) { AddSourceSheet() }
            .confirmationDialog(deleting?.name ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button(L("settings.delete"), role: .destructive) { if let a = deleting { model.deleteAccount(a) }; deleting = nil }
            }
        }
    }
}
