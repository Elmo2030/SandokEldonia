import SwiftUI
import IPTVCore
import IPTVAppKit

/// Add a source: the Mac onboarding's form and checks (LibraryModel.testConnection / isValidSource), on one screen.
struct AddSourceSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AccountKind = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var status: String?
    @State private var ok = false
    @State private var busy = false

    private var valid: Bool { LibraryModel.isValidSource(kind: kind, name: name, server: server, username: username, url: url) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("field.kind"), selection: $kind) {
                        Text(L("kind.xtream")).tag(AccountKind.xtream)
                        Text(L("kind.m3u")).tag(AccountKind.m3u)
                    }.pickerStyle(.segmented)
                    Text(kind == .xtream ? L("onb.where.xtream") : L("onb.where.m3u")).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    TextField(L("field.name"), text: $name)
                    if kind == .xtream {
                        TextField(L("field.server"), text: $server, prompt: Text("http://host:8080")).keyboardType(.URL)
                        TextField(L("field.username"), text: $username)
                        SecureField(L("field.password"), text: $password)
                    } else {
                        TextField(L("field.url"), text: $url, prompt: Text("http://example.com/list.m3u")).keyboardType(.URL)
                    }
                }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                Section {
                    HStack {
                        Button(L("onb.test")) { Task { await test() } }.disabled(!valid || busy)
                        if busy { ProgressView() }
                    }
                    if let status { Label(status, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .red) }
                }
            }
            .onChange(of: kind) { ok = false; status = nil }
            .navigationTitle(L("account.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("player.close")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(L("onb.save")) { save() }.disabled(!ok || busy) }
            }
        }
    }

    private func test() async {
        busy = true; ok = false; status = nil
        defer { busy = false }
        do {
            try await LibraryModel.testConnection(kind: kind, server: server, username: username, password: password, url: url)
            ok = true; status = L("onb.test.ok")
        } catch { status = "\(L("onb.test.fail")): \(error.localizedDescription)" }
    }

    private func save() {
        let a = kind == .xtream ? Account(name: name, kind: .xtream, server: server, username: username) : Account(name: name, kind: .m3u, url: url)
        let pw = kind == .xtream ? password : nil
        dismiss()
        Task { await model.addAccount(a, password: pw) }
    }
}
