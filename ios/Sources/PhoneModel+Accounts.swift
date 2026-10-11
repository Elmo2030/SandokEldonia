import Foundation
import IPTVCore
import IPTVAppKit

extension PhoneModel {
    /// Saves edits to a source (name, address, login; a new password only when given) and syncs it again.
    func updateAccount(_ a: Account, password: String?) async {
        guard let id = a.id else { return }
        do {
            try await db.dbQueue.write { d in var x = a; try x.update(d) }
            if let password, !password.isEmpty { try secrets.setPassword(password, for: id) }
        } catch { syncMessage = error.localizedDescription; return }
        loadAccounts()
        let fresh = accounts.first { $0.id == id }
        if account?.id == id { account = fresh }                     // `account` is a copy: it would keep the old address
        await sync(fresh.map { [$0] } ?? [])
    }
}
