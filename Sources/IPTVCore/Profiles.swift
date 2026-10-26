import Foundation
import CryptoKit
import GRDB

/// A person using the app. Favorites, watch history and "watch later" belong to a profile; playlists do not.
public struct Profile: Codable, Identifiable, Hashable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "profile"
    public var id: Int64?
    public var name: String
    /// A kids profile shows only categories that look made for children (see `CategoryFilter.kids`).
    public var kids: Bool
    /// "salt:hash" of the PIN that is asked to leave this profile; nil = none. A convenience lock, not security: the database is a plain file.
    public var pin: String?

    public var hasPIN: Bool { pin != nil }
    public init(id: Int64? = nil, name: String, kids: Bool = false, pin: String? = nil) { self.id = id; self.name = name; self.kids = kids; self.pin = pin }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum ProfileError: Error, Equatable { case invalidName, invalidPIN, cannotDelete, tooMany }

public enum Profiles {
    public static let maxCount = 8
    public static let maxNameLength = 30

    public static func all(_ db: Database) throws -> [Profile] { try Profile.order(Column("id")).fetchAll(db) }

    public static func current(_ db: Database) throws -> Profile {
        try Profile.fetchOne(db, sql: "SELECT profile.* FROM profile JOIN current_profile c ON c.profileId = profile.id")
            ?? Profile.fetchOne(db, sql: "SELECT * FROM profile ORDER BY id LIMIT 1")
            ?? Profile(id: 1, name: "Main")
    }

    /// Everything the screens show about favorites, history and watch later changes with it, at once.
    public static func switchTo(_ db: Database, id: Int64) throws {
        guard try Profile.fetchOne(db, key: id) != nil else { return }
        try db.execute(sql: "UPDATE current_profile SET profileId = ?", arguments: [id])
    }

    @discardableResult
    public static func create(_ db: Database, name: String, kids: Bool) throws -> Profile {
        guard try Profile.fetchCount(db) < maxCount else { throw ProfileError.tooMany }
        var p = Profile(name: try clean(name), kids: kids)
        try p.insert(db)
        return p
    }

    public static func update(_ db: Database, id: Int64, name: String, kids: Bool) throws {
        try db.execute(sql: "UPDATE profile SET name = ?, kids = ? WHERE id = ?", arguments: [try clean(name), kids, id])
    }

    /// The profile in use cannot be deleted, nor the last one. Its favorites, history and watch later go with it.
    public static func delete(_ db: Database, id: Int64) throws {
        let current = try current(db)
        guard id != current.id, try Profile.fetchCount(db) > 1 else { throw ProfileError.cannotDelete }
        try db.execute(sql: "DELETE FROM profile WHERE id = ?", arguments: [id])
    }

    /// `pin` is 4 to 8 digits; nil removes the PIN.
    public static func setPIN(_ db: Database, id: Int64, pin: String?) throws {
        var stored: String?
        if let pin {
            guard (4...8).contains(pin.count), pin.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw ProfileError.invalidPIN }
            let salt = (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
            stored = "\(salt):\(hash(salt, pin))"
        }
        try db.execute(sql: "UPDATE profile SET pin = ? WHERE id = ?", arguments: [stored, id])
    }

    /// True when the profile has no PIN, or `pin` is it.
    public static func accepts(_ profile: Profile, pin: String?) -> Bool {
        guard let stored = profile.pin else { return true }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let pin else { return false }
        return hash(parts[0], pin) == parts[1]
    }

    private static func hash(_ salt: String, _ pin: String) -> String {
        SHA256.hash(data: Data((salt + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func clean(_ name: String) throws -> String {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
        guard !n.isEmpty else { throw ProfileError.invalidName }
        return n
    }
}
