import Foundation
import GRDB

public final class AppDatabase {
    /// A WAL `DatabasePool` for the real file (readers never wait for the long sync write); an in-memory queue for tests.
    public let dbQueue: any DatabaseWriter

    public init(path: String? = nil) throws {
        if let path {
            var cfg = Configuration()
            cfg.busyMode = .timeout(5)              // a second process (selftest, `open -n`) waits instead of failing at once
            let pool = try DatabasePool(path: path, configuration: cfg)
            if try pool.read({ try !Self.migrator.hasCompletedMigrations($0) && $0.tableExists("account") }) {
                // Existing data and a pending migration: keep a copy first (it also holds the account passwords: same 0600 rules).
                let bak = path + ".bak"
                try? FileManager.default.removeItem(atPath: bak)
                try? pool.backup(to: DatabaseQueue(path: bak))
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bak)
            }
            dbQueue = pool
            try Self.migrator.migrate(dbQueue)
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path + suffix)
            }
        } else {
            dbQueue = try DatabaseQueue()
            try Self.migrator.migrate(dbQueue)
        }
    }

    /// Opens the database; a corrupt/non-SQLite file is moved aside (not deleted) and a fresh one is created.
    /// Returns the moved-aside path when that happened. Busy/IO errors are rethrown.
    public static func openRecovering(path: String) throws -> (db: AppDatabase, movedAside: String?) {
        do { return (try AppDatabase(path: path), nil) }
        catch let e as DatabaseError where [.SQLITE_NOTADB, .SQLITE_CORRUPT].contains(e.resultCode) {
            let aside = path + ".corrupt-\(Int(Date().timeIntervalSince1970))"
            try FileManager.default.moveItem(atPath: path, toPath: aside)
            for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
            return (try AppDatabase(path: path), aside)
        }
    }

    public static func defaultPath() throws -> String {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true).appendingPathComponent("IPTVMac")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appendingPathComponent("iptv.sqlite").path
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "account") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("server", .text); t.column("username", .text); t.column("url", .text)
            }
            try db.create(table: "category") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("remoteId", .text).notNull()
                t.column("name", .text).notNull()
                t.uniqueKey(["accountId", "type", "remoteId"])
            }
            try db.create(table: "item") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("name", .text).notNull()
                t.column("categoryId", .text)
                t.column("icon", .text); t.column("rating", .text)
                t.column("streamId", .text).notNull()
                t.column("containerExt", .text); t.column("directURL", .text)
                t.column("tvArchive", .boolean).notNull().defaults(to: false)
                t.column("archiveDays", .integer).notNull().defaults(to: 0)
                t.column("epgChannelId", .text)
                t.column("stale", .boolean).notNull().defaults(to: false)
                t.uniqueKey(["accountId", "type", "streamId"])
            }
            try db.create(index: "item_category", on: "item", columns: ["accountId", "type", "categoryId"])
            try db.create(virtualTable: "item_fts", using: FTS5()) { t in
                t.synchronize(withTable: "item")
                t.tokenizer = .unicode61(diacritics: .remove)
                t.column("name")
            }
            try db.create(table: "episode") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("seriesId", .text).notNull()
                t.column("season", .integer).notNull()
                t.column("number", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("streamId", .text).notNull()
                t.column("containerExt", .text)
                t.uniqueKey(["accountId", "streamId"])
            }
            try db.create(table: "favorite") { t in
                t.column("accountId", .integer).notNull()
                t.column("type", .text).notNull()
                t.column("streamId", .text).notNull()
                t.primaryKey(["accountId", "type", "streamId"])
            }
            try db.create(table: "history") { t in
                t.column("accountId", .integer).notNull()
                t.column("type", .text).notNull()
                t.column("streamId", .text).notNull()
                t.column("position", .double).notNull()
                t.column("duration", .double).notNull()
                t.column("updated", .datetime).notNull()
                t.primaryKey(["accountId", "type", "streamId"])
            }
        }
        // Account passwords live in the same private database file (no Keychain: it prompts for access on every new build).
        m.registerMigration("v2-secret") { db in
            try db.create(table: "secret") { t in
                t.column("accountId", .integer).primaryKey().references("account", onDelete: .cascade)
                t.column("password", .text).notNull()
            }
        }
        // Search index maintenance only when the name changes: re-syncs rewrite every row but almost never change a name.
        m.registerMigration("v3-fts-trigger") { db in
            try db.execute(sql: """
                DROP TRIGGER IF EXISTS "__item_fts_au";
                CREATE TRIGGER "__item_fts_au" AFTER UPDATE OF name ON item WHEN old.name IS NOT new.name BEGIN
                  INSERT INTO item_fts(item_fts, rowid, name) VALUES('delete', old.id, old.name);
                  INSERT INTO item_fts(rowid, name) VALUES (new.id, new.name);
                END;
                """)
        }
        // What the provider says about a movie or series (parsed JSON, no credentials), kept for 14 days; goes with its playlist.
        m.registerMigration("v4-item-info") { db in
            try db.create(table: "item_info") { t in
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("streamId", .text).notNull()
                t.column("json", .text).notNull()
                t.column("fetched", .datetime).notNull()
                t.primaryKey(["accountId", "type", "streamId"])
            }
        }
        // When a sync first saw a title. NULL = there since the first sync of its playlist (the baseline), or unknown.
        m.registerMigration("v5-added-at") { db in
            try db.alter(table: "item") { t in t.add(column: "addedAt", .datetime) }
            try db.create(index: "item_added", on: "item", columns: ["type", "addedAt"], condition: Column("addedAt") != nil)
        }
        // "Watch later": a title the user set aside. Keyed like favorites, so it follows a playlist's titles across syncs.
        m.registerMigration("v6-watchlist") { db in
            try db.create(table: "watchlist") { t in
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("streamId", .text).notNull()
                t.column("added", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
                t.primaryKey(["accountId", "type", "streamId"])
            }
        }
        // The guide of an M3U playlist: where its header says to get it, and the programs of its channels (epoch seconds).
        m.registerMigration("v7-guide") { db in
            try db.alter(table: "account") { t in t.add(column: "guideURL", .text) }
            try db.create(table: "programme") { t in
                t.column("accountId", .integer).notNull().references("account", onDelete: .cascade)
                t.column("channel", .text).notNull()
                t.column("start", .integer).notNull()
                t.column("stop", .integer).notNull()
                t.column("title", .text).notNull()
                t.primaryKey(["accountId", "channel", "start"])
            }
        }
        // Profiles. Favorites, watch history and "watch later" move to *_all tables that carry a profileId. The old names stay as VIEWS of the
        // current profile (current_profile, one row) with INSTEAD OF triggers, so every query that already reads or writes `favorite`,
        // `history` or `watchlist` keeps working, for the profile that is selected. Existing rows go to profile 1 ("Main").
        m.registerMigration("v8-profiles") { db in
            try db.execute(sql: """
                CREATE TABLE profile (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, kids BOOLEAN NOT NULL DEFAULT 0, pin TEXT);
                INSERT INTO profile (id, name) VALUES (1, 'Main');
                CREATE TABLE current_profile (id INTEGER PRIMARY KEY CHECK (id = 1), profileId INTEGER NOT NULL REFERENCES profile(id) ON DELETE RESTRICT);
                INSERT INTO current_profile (id, profileId) VALUES (1, 1);

                CREATE TABLE favorite_all (
                  profileId INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
                  accountId INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                  type TEXT NOT NULL, streamId TEXT NOT NULL, PRIMARY KEY (profileId, accountId, type, streamId));
                INSERT INTO favorite_all SELECT 1, f.accountId, f.type, f.streamId FROM favorite f JOIN account a ON a.id = f.accountId;
                DROP TABLE favorite;
                CREATE VIEW favorite AS SELECT accountId, type, streamId FROM favorite_all WHERE profileId = (SELECT profileId FROM current_profile);
                CREATE TRIGGER favorite_ins INSTEAD OF INSERT ON favorite BEGIN
                  INSERT OR IGNORE INTO favorite_all (profileId, accountId, type, streamId)
                  VALUES ((SELECT profileId FROM current_profile), NEW.accountId, NEW.type, NEW.streamId);
                END;
                CREATE TRIGGER favorite_del INSTEAD OF DELETE ON favorite BEGIN
                  DELETE FROM favorite_all WHERE profileId = (SELECT profileId FROM current_profile)
                    AND accountId = OLD.accountId AND type = OLD.type AND streamId = OLD.streamId;
                END;

                CREATE TABLE history_all (
                  profileId INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
                  accountId INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                  type TEXT NOT NULL, streamId TEXT NOT NULL, position DOUBLE NOT NULL, duration DOUBLE NOT NULL, updated DATETIME NOT NULL,
                  PRIMARY KEY (profileId, accountId, type, streamId));
                INSERT INTO history_all SELECT 1, h.accountId, h.type, h.streamId, h.position, h.duration, h.updated FROM history h JOIN account a ON a.id = h.accountId;
                DROP TABLE history;
                CREATE VIEW history AS SELECT accountId, type, streamId, position, duration, updated FROM history_all
                  WHERE profileId = (SELECT profileId FROM current_profile);
                CREATE TRIGGER history_ins INSTEAD OF INSERT ON history BEGIN
                  INSERT OR REPLACE INTO history_all (profileId, accountId, type, streamId, position, duration, updated)
                  VALUES ((SELECT profileId FROM current_profile), NEW.accountId, NEW.type, NEW.streamId, NEW.position, NEW.duration, NEW.updated);
                END;
                CREATE TRIGGER history_upd INSTEAD OF UPDATE ON history BEGIN
                  UPDATE history_all SET position = NEW.position, duration = NEW.duration, updated = NEW.updated
                  WHERE profileId = (SELECT profileId FROM current_profile)
                    AND accountId = OLD.accountId AND type = OLD.type AND streamId = OLD.streamId;
                END;
                CREATE TRIGGER history_del INSTEAD OF DELETE ON history BEGIN
                  DELETE FROM history_all WHERE profileId = (SELECT profileId FROM current_profile)
                    AND accountId = OLD.accountId AND type = OLD.type AND streamId = OLD.streamId;
                END;

                CREATE TABLE watchlist_all (
                  profileId INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
                  accountId INTEGER NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                  type TEXT NOT NULL, streamId TEXT NOT NULL, added DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  PRIMARY KEY (profileId, accountId, type, streamId));
                INSERT INTO watchlist_all SELECT 1, accountId, type, streamId, added FROM watchlist;
                DROP TABLE watchlist;
                CREATE VIEW watchlist AS SELECT accountId, type, streamId, added FROM watchlist_all
                  WHERE profileId = (SELECT profileId FROM current_profile);
                CREATE TRIGGER watchlist_ins INSTEAD OF INSERT ON watchlist BEGIN
                  INSERT OR IGNORE INTO watchlist_all (profileId, accountId, type, streamId, added)
                  VALUES ((SELECT profileId FROM current_profile), NEW.accountId, NEW.type, NEW.streamId, COALESCE(NEW.added, CURRENT_TIMESTAMP));
                END;
                CREATE TRIGGER watchlist_del INSTEAD OF DELETE ON watchlist BEGIN
                  DELETE FROM watchlist_all WHERE profileId = (SELECT profileId FROM current_profile)
                    AND accountId = OLD.accountId AND type = OLD.type AND streamId = OLD.streamId;
                END;
                """)
        }
        return m
    }
}
