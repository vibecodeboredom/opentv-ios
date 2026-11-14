import Foundation
import SQLite3

/// SQLite-backed cache for the XMLTV guide.
///
/// All SQLite access is serialized on a private serial queue, so the
/// store is safe to call from any thread (the EPG refresh parses on a
/// background task while the UI reads from the main thread).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class EPGStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.opentv.epgstore")

    init() {
        queue.sync {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("epg.sqlite").path
            if sqlite3_open(path, &db) != SQLITE_OK {
                db = nil
            } else {
                createTables()
            }
        }
    }

    deinit {
        queue.sync {
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
        }
    }

    // MARK: - Schema (always called on the serial queue)

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func createTables() {
        exec("CREATE TABLE IF NOT EXISTS channels(id TEXT PRIMARY KEY, name TEXT);")
        exec("CREATE TABLE IF NOT EXISTS programmes(id TEXT PRIMARY KEY, channel_id TEXT, title TEXT, start REAL, stop REAL, description TEXT);")
        exec("CREATE INDEX IF NOT EXISTS idx_prog_channel_start ON programmes(channel_id, start);")
    }

    // MARK: - Writes

    func clearAll() {
        queue.sync {
            exec("DELETE FROM programmes;")
            exec("DELETE FROM channels;")
        }
    }

    func replaceChannelNames(_ names: [String: String]) {
        queue.sync {
            guard let db, !names.isEmpty else { return }
            exec("BEGIN TRANSACTION;")
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO channels(id, name) VALUES (?, ?);", -1, &stmt, nil)
            for (id, name) in names {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
            sqlite3_finalize(stmt)
            exec("COMMIT;")
        }
    }

    func insertProgrammes(_ programmes: [Programme]) {
        queue.sync {
            guard let db, !programmes.isEmpty else { return }
            exec("BEGIN TRANSACTION;")
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO programmes(id, channel_id, title, start, stop, description) VALUES (?, ?, ?, ?, ?, ?);", -1, &stmt, nil)
            for programme in programmes {
                sqlite3_bind_text(stmt, 1, programme.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, programme.channelID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, programme.title, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 4, programme.start.timeIntervalSince1970)
                sqlite3_bind_double(stmt, 5, programme.stop.timeIntervalSince1970)
                if let description = programme.description {
                    sqlite3_bind_text(stmt, 6, description, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                sqlite3_step(stmt)
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
            sqlite3_finalize(stmt)
            exec("COMMIT;")
        }
    }

    // MARK: - Reads

    func programmes(for channelID: String, from: Date, to: Date) -> [Programme] {
        queue.sync {
            guard let db else { return [] }
            var result: [Programme] = []
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id, channel_id, title, start, stop, description FROM programmes WHERE channel_id = ? AND stop > ? AND start < ? ORDER BY start;", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, channelID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let programme = readProgramme(stmt) { result.append(programme) }
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func currentProgramme(for channelID: String, at date: Date = Date()) -> Programme? {
        queue.sync {
            guard let db else { return nil }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id, channel_id, title, start, stop, description FROM programmes WHERE channel_id = ? AND start <= ? AND stop > ? ORDER BY start LIMIT 1;", -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, channelID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, date.timeIntervalSince1970)
            var result: Programme? = nil
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = readProgramme(stmt)
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func programmeCount() -> Int {
        queue.sync {
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM programmes;", -1, &stmt, nil)
            var count = 0
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
            sqlite3_finalize(stmt)
            return count
        }
    }

    // MARK: - Helpers (always called on the serial queue)

    private func readProgramme(_ stmt: OpaquePointer?) -> Programme? {
        guard let idPtr = sqlite3_column_text(stmt, 0),
              let channelPtr = sqlite3_column_text(stmt, 1),
              let titlePtr = sqlite3_column_text(stmt, 2) else { return nil }
        let descPtr = sqlite3_column_text(stmt, 5)
        return Programme(
            id: String(cString: idPtr),
            channelID: String(cString: channelPtr),
            title: String(cString: titlePtr),
            start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
            stop: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
            description: descPtr.map { String(cString: $0) }
        )
    }
}
