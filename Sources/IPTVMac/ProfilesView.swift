import SwiftUI
import IPTVCore
import IPTVAppKit

/// What a PIN is being asked for.
enum PinRequest: Identifiable {
    case leave(Profile)          // switching away from a profile that has a PIN, to this one
    case manage                  // opening the profiles list while the current profile has a PIN
    var id: String { switch self { case .leave(let p): "leave-\(p.id ?? 0)"; case .manage: "manage" } }
}

struct PinSheet: View {
    let verify: (String) -> Bool
    let onAccepted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(CinemaTheme.accent)
            SecureField(L("profile.pin"), text: $pin).textFieldStyle(.roundedBorder).frame(width: 160).multilineTextAlignment(.center)
                .onSubmit(submit).onChange(of: pin) { wrong = false }
            if wrong { Text(L("profile.pin.wrong")).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L("common.cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("profile.pin"), action: submit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(pin.count < 4)
            }
        }
        .padding(24).frame(minWidth: 280)
    }

    private func submit() {
        if verify(pin) { dismiss(); onAccepted() } else { wrong = true; pin = "" }
    }
}

struct ProfilesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newKids = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("profile.title")).font(.title2.bold())
            List(model.profiles) { p in
                ProfileRow(profile: p, isCurrent: p.id == model.profile.id, onError: { failure = $0 })
            }.frame(minHeight: 200)
            HStack {
                TextField(L("field.name"), text: $newName).textFieldStyle(.roundedBorder)
                Toggle(L("profile.kids"), isOn: $newKids).toggleStyle(.checkbox)
                Button(L("profile.add")) { add() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || model.profiles.count >= Profiles.maxCount)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button(L("player.close")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(minWidth: 520, minHeight: 380)
    }

    private func add() {
        let name = newName, kids = newKids
        do { try model.editProfiles { _ = try Profiles.create($0, name: name, kids: kids) }; newName = ""; newKids = false; failure = nil }
        catch { failure = error.localizedDescription }
    }
}

private struct ProfileRow: View {
    @Environment(AppModel.self) private var model
    let profile: Profile
    let isCurrent: Bool
    let onError: (String) -> Void
    @State private var name: String
    @State private var pin = ""

    init(profile: Profile, isCurrent: Bool, onError: @escaping (String) -> Void) {
        self.profile = profile; self.isCurrent = isCurrent; self.onError = onError
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle").foregroundStyle(isCurrent ? CinemaTheme.accent : .secondary)
            TextField(L("field.name"), text: $name).textFieldStyle(.plain).onSubmit(save)
            Toggle(L("profile.kids"), isOn: Binding(get: { profile.kids }, set: { change(kids: $0) })).toggleStyle(.checkbox)
            Image(systemName: profile.hasPIN ? "lock.fill" : "lock.open").foregroundStyle(.secondary)
            SecureField(L("profile.pin"), text: $pin).textFieldStyle(.roundedBorder).frame(width: 80).onSubmit(savePIN)
            Button(role: .destructive) { remove() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(isCurrent || model.profiles.count < 2).help(L("settings.delete"))
        }
    }

    private func save() { change(name: name) }
    private func change(name: String? = nil, kids: Bool? = nil) {
        guard let id = profile.id else { return }
        let n = name ?? profile.name, k = kids ?? profile.kids
        do { try model.editProfiles { try Profiles.update($0, id: id, name: n, kids: k) } } catch { onError(error.localizedDescription) }
    }

    /// Typing a PIN and pressing Return sets it; pressing Return on an empty field removes it.
    private func savePIN() {
        guard let id = profile.id else { return }
        let value = pin.isEmpty ? nil : pin
        do { try model.editProfiles { try Profiles.setPIN($0, id: id, pin: value) }; pin = "" } catch { onError(error.localizedDescription) }
    }

    private func remove() {
        guard let id = profile.id else { return }
        do { try model.editProfiles { try Profiles.delete($0, id: id) } } catch { onError(error.localizedDescription) }
    }
}
