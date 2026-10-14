import Foundation
import os

private let logger = Logger(subsystem: "com.tray.app", category: "Migrations")

/// Schema setup and upgrades, tracked with SQLite's `user_version`.
enum Migrations {

    /// Bump when adding a step to `run`
    static let currentVersion = 2

    static func run(on db: SQLiteDB) throws {
        let version = try db.scalar(sql: "PRAGMA user_version")
        guard version < currentVersion else { return }

        try createClipboardItemsTable(db)
        if version < 2 { try splitPayload(db) }

        try db.execute(sql: "PRAGMA user_version = \(currentVersion)")
        logger.info("Migrated database from v\(version) to v\(currentVersion)")
    }

    // MARK: - v1

    private static func createClipboardItemsTable(_ db: SQLiteDB) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id              TEXT PRIMARY KEY,
                type            TEXT NOT NULL,
                created_at      REAL NOT NULL,
                is_pinned       INTEGER DEFAULT 0,
                is_hidden       INTEGER DEFAULT 0,
                custom_name     TEXT,
                source_app_id   TEXT,
                source_app_name TEXT,
                content_preview TEXT NOT NULL,
                data_hash       TEXT NOT NULL,
                metadata_json   TEXT NOT NULL,
                UNIQUE(data_hash)
            )
            """)

        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC)")
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_is_pinned ON clipboard_items(is_pinned)")
        // Was an index on content_preview: LIKE '%…%' search can't use it, and it
        // cost a write on every copy
        try db.execute(sql: "DROP INDEX IF EXISTS idx_content_preview")
    }

    // MARK: - v2: large content in its own column

    /// Moves full text / rich text / HTML out of `metadata_json` into `payload_json`,
    /// so listing items no longer reads every item's full content.
    private static func splitPayload(_ db: SQLiteDB) throws {
        let columns = try db.query(sql: "PRAGMA table_info(clipboard_items)")
        if !columns.contains(where: { $0["name"] as? String == "payload_json" }) {
            try db.execute(sql: "ALTER TABLE clipboard_items ADD COLUMN payload_json TEXT")
        }

        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let rows = try db.query(sql: "SELECT id, metadata_json FROM clipboard_items WHERE payload_json IS NULL")
        guard !rows.isEmpty else { return }

        try db.execute(sql: "BEGIN")
        do {
            for row in rows {
                guard let id = row["id"] as? String,
                      let json = (row["metadata_json"] as? String)?.data(using: .utf8),
                      let metadata = try? decoder.decode(ClipboardItemMetadata.self, from: json) else { continue }
                let light = String(decoding: try encoder.encode(metadata.withoutPayload), as: UTF8.self)
                let payload = String(decoding: try encoder.encode(metadata.payload), as: UTF8.self)
                try db.execute(
                    sql: "UPDATE clipboard_items SET metadata_json = ?, payload_json = ? WHERE id = ?",
                    params: [light, payload, id]
                )
            }
            try db.execute(sql: "COMMIT")
        } catch {
            _ = try? db.execute(sql: "ROLLBACK")
            throw error
        }
        // Reclaim the space the moved content used to take in metadata_json
        try db.execute(sql: "VACUUM")
        logger.info("Moved content of \(rows.count) items into payload_json")
    }
}
