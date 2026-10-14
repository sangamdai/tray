import Foundation
import os

private let logger = Logger(subsystem: "com.tray.app", category: "Migrations")

enum Migrations {

    static func run(on db: SQLiteDB) throws {
        try createClipboardItemsTable(db)
        logger.info("Migrations completed")
    }

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

        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC)
            """)

        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS idx_is_pinned ON clipboard_items(is_pinned)
            """)

        // Was an index on content_preview: LIKE '%…%' search can't use it, and it
        // cost a write on every copy
        try db.execute(sql: "DROP INDEX IF EXISTS idx_content_preview")
    }
}
