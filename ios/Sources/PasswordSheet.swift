import SwiftUI
import IPTVCore

/// Asks for an Xtream password when none is stored (for example after a backup was imported).
struct PasswordSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section { SecureField(L("field.password"), text: $password) } header: { Text(String(format: L("password.body.ios"), account.name)) }
            }
            .navigationTitle(L("password.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("player.close")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L(password.isEmpty ? "password.none" : "onb.save")) { Task { await model.savePassword(password, for: account) } }
                }
            }
        }
    }
}
