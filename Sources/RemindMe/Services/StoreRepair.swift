import Foundation
import SQLite3

/// One-time cleanup for data written by builds before `ItemDeletion` existed.
///
/// Those builds deleted a routine without its occurrences, leaving occurrence
/// rows whose link points at a routine that's gone. SwiftData halts the app as
/// soon as it follows one of those links, so the app crashed on every launch.
/// This runs on the raw database file *before* SwiftData opens it, so it never
/// has to follow a broken link: it simply deletes the occurrence rows whose
/// routine no longer exists.
///
/// It relies on Core Data's standard table naming for these two models
/// (`ZOCCURRENCE.ZITEM` → `ZITEM.Z_PK`). If that ever differs, the statement
/// fails and nothing is changed — it can only remove orphaned rows.
enum StoreRepair {
    private static let orphanFilter =
        "FROM ZOCCURRENCE WHERE ZITEM IS NOT NULL AND ZITEM NOT IN (SELECT Z_PK FROM ZITEM)"

    /// Deletes orphaned occurrence rows. Returns how many were removed.
    @discardableResult
    static func removeOrphanedOccurrences(storeURL: URL) -> Int {
        withDatabase(at: storeURL) { db in
            guard sqlite3_exec(db, "DELETE \(orphanFilter);", nil, nil, nil) == SQLITE_OK else { return 0 }
            return Int(sqlite3_changes(db))
        } ?? 0
    }

    /// How many orphaned occurrence rows the store holds (for diagnostics and tests).
    static func orphanCount(storeURL: URL) -> Int {
        withDatabase(at: storeURL) { db in
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) \(orphanFilter);", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        } ?? 0
    }

    private static func withDatabase(at url: URL, _ body: (OpaquePointer) -> Int) -> Int? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        return body(db)
    }
}
