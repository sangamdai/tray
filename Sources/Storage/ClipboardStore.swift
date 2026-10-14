import Foundation
import os

private let logger = Logger(subsystem: "com.tray.app", category: "ClipboardStore")

final class ClipboardStore: ClipboardStoring {

    private let db: SQLiteDB
    private let imageStorage: ImageStorage
    private var maxHistoryItems: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        dbPath: String? = nil,
        inMemory: Bool = false,
        maxHistoryItems: Int = 200,
        imageStorage: ImageStorage? = nil
    ) throws {
        self.maxHistoryItems = maxHistoryItems

        if inMemory {
            self.db = try SQLiteDB(inMemory: true)
        } else {
            let path = dbPath ?? ClipboardStore.defaultDBPath()
            self.db = try SQLiteDB(path: path)
        }

        self.imageStorage = imageStorage ?? ImageStorage()
        try Migrations.run(on: db)
    }

    /// For testing: inject a pre-configured DB
    init(db: SQLiteDB, imageStorage: ImageStorage, maxHistoryItems: Int = 200) throws {
        self.db = db
        self.imageStorage = imageStorage
        self.maxHistoryItems = maxHistoryItems
        try Migrations.run(on: db)
    }

    /// Changes how many unpinned items are kept, trimming the oldest right away if lowered
    func setMaxHistoryItems(_ limit: Int) {
        maxHistoryItems = limit
        do {
            try enforceMaxHistory()
        } catch {
            logger.error("Trim to \(limit) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - ClipboardStoring

    func save(_ item: ClipboardItem) throws {
        let metadataJSON = try encoder.encode(item.metadata)
        let metadataString = String(data: metadataJSON, encoding: .utf8) ?? "{}"

        // Check for duplicate by hash — bump timestamp instead of inserting
        let existing = try db.query(
            sql: "SELECT id FROM clipboard_items WHERE data_hash = ?",
            params: [item.dataHash]
        )

        if let existingRow = existing.first, let existingID = existingRow["id"] as? String {
            try db.execute(
                sql: "UPDATE clipboard_items SET created_at = ? WHERE id = ?",
                params: [item.createdAt.timeIntervalSince1970, existingID]
            )
            logger.debug("Deduplicated item, bumped timestamp for \(existingID)")
        } else {
            try db.execute(
                sql: """
                    INSERT INTO clipboard_items
                    (id, type, created_at, is_pinned, is_hidden, custom_name,
                     source_app_id, source_app_name, content_preview, data_hash, metadata_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                params: [
                    item.id.uuidString,
                    item.type.rawValue,
                    item.createdAt.timeIntervalSince1970,
                    item.isPinned ? 1 : 0,
                    item.isHidden ? 1 : 0,
                    item.customName as Any?,
                    item.sourceAppBundleID as Any?,
                    item.sourceAppName as Any?,
                    item.contentPreview,
                    item.dataHash,
                    metadataString
                ]
            )
        }

        try enforceMaxHistory()
    }

    func fetchRecent(limit: Int = 50) -> [ClipboardItem] {
        do {
            let rows = try db.query(
                sql: """
                    SELECT * FROM clipboard_items
                    WHERE is_pinned = 0
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                params: [limit]
            )
            return rows.compactMap { rowToItem($0) }
        } catch {
            logger.error("fetchRecent failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchPinned() -> [ClipboardItem] {
        do {
            let rows = try db.query(
                sql: "SELECT * FROM clipboard_items WHERE is_pinned = 1 ORDER BY created_at DESC"
            )
            return rows.compactMap { rowToItem($0) }
        } catch {
            logger.error("fetchPinned failed: \(error.localizedDescription)")
            return []
        }
    }

    func search(query: String, limit: Int = 50) -> [ClipboardItem] {
        do {
            let pattern = "%\(query)%"
            let rows = try db.query(
                sql: """
                    SELECT * FROM clipboard_items
                    WHERE content_preview LIKE ? OR custom_name LIKE ?
                    ORDER BY created_at DESC
                    LIMIT ?
                    """,
                params: [pattern, pattern, limit]
            )
            return rows.compactMap { rowToItem($0) }
        } catch {
            logger.error("search failed: \(error.localizedDescription)")
            return []
        }
    }

    func delete(id: UUID) throws {
        imageStorage.deleteFiles(for: id)
        try db.execute(
            sql: "DELETE FROM clipboard_items WHERE id = ?",
            params: [id.uuidString]
        )
    }

    /// Deletes all unpinned items. Pinned items are kept: that's what pinning is for.
    func deleteAll() throws {
        // Clean up image files for the items being removed
        let rows = try db.query(sql: "SELECT id FROM clipboard_items WHERE is_pinned = 0")
        for row in rows {
            if let idStr = row["id"] as? String, let uuid = UUID(uuidString: idStr) {
                imageStorage.deleteFiles(for: uuid)
            }
        }
        try db.execute(sql: "DELETE FROM clipboard_items WHERE is_pinned = 0")
    }

    func togglePin(id: UUID) throws {
        try db.execute(
            sql: "UPDATE clipboard_items SET is_pinned = CASE WHEN is_pinned = 1 THEN 0 ELSE 1 END WHERE id = ?",
            params: [id.uuidString]
        )
    }

    func toggleHide(id: UUID) throws {
        try db.execute(
            sql: "UPDATE clipboard_items SET is_hidden = CASE WHEN is_hidden = 1 THEN 0 ELSE 1 END WHERE id = ?",
            params: [id.uuidString]
        )
    }

    func rename(id: UUID, name: String) throws {
        try db.execute(
            sql: "UPDATE clipboard_items SET custom_name = ? WHERE id = ?",
            params: [name, id.uuidString]
        )
    }

    func itemCount() -> Int {
        (try? db.scalar(sql: "SELECT COUNT(*) FROM clipboard_items")) ?? 0
    }

    func hashExists(_ hash: String) -> Bool {
        let count = (try? db.scalar(sql: "SELECT COUNT(*) FROM clipboard_items WHERE data_hash = ?", params: [hash])) ?? 0
        return count > 0
    }

    func getFullData(id: UUID) -> ClipboardItemData? {
        do {
            let rows = try db.query(
                sql: "SELECT * FROM clipboard_items WHERE id = ?",
                params: [id.uuidString]
            )
            guard let row = rows.first, let item = rowToItem(row) else { return nil }

            var rawData: Data?
            switch item.type {
            case .image:
                if let path = item.metadata.imagePath {
                    rawData = imageStorage.loadImage(filename: path)
                }
            case .richText:
                if let rtfData = item.metadata.rtfData {
                    rawData = rtfData
                }
            default:
                break
            }

            return ClipboardItemData(
                type: item.type,
                metadata: item.metadata,
                rawData: rawData
            )
        } catch {
            logger.error("getFullData failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private

    private func rowToItem(_ row: [String: Any]) -> ClipboardItem? {
        guard
            let idStr = row["id"] as? String,
            let id = UUID(uuidString: idStr),
            let typeStr = row["type"] as? String,
            let type = ClipboardItemType(rawValue: typeStr),
            let createdAtVal = row["created_at"] as? Double,
            let contentPreview = row["content_preview"] as? String,
            let dataHash = row["data_hash"] as? String,
            let metadataJSON = row["metadata_json"] as? String
        else {
            return nil
        }

        let isPinned = (row["is_pinned"] as? Int64 ?? 0) != 0
        let isHidden = (row["is_hidden"] as? Int64 ?? 0) != 0
        let customName = row["custom_name"] as? String
        let sourceAppID = row["source_app_id"] as? String
        let sourceAppName = row["source_app_name"] as? String

        let metadata: ClipboardItemMetadata
        if let data = metadataJSON.data(using: .utf8) {
            metadata = (try? decoder.decode(ClipboardItemMetadata.self, from: data)) ?? .empty
        } else {
            metadata = .empty
        }

        return ClipboardItem(
            id: id,
            type: type,
            createdAt: Date(timeIntervalSince1970: createdAtVal),
            isPinned: isPinned,
            isHidden: isHidden,
            customName: customName,
            sourceAppBundleID: sourceAppID,
            sourceAppName: sourceAppName,
            contentPreview: contentPreview,
            dataHash: dataHash,
            metadata: metadata
        )
    }

    private func enforceMaxHistory() throws {
        let count = try db.scalar(
            sql: "SELECT COUNT(*) FROM clipboard_items WHERE is_pinned = 0"
        )
        guard count > maxHistoryItems else { return }

        let excess = count - maxHistoryItems
        // Get IDs of oldest non-pinned items to clean up files
        let rows = try db.query(
            sql: """
                SELECT id FROM clipboard_items
                WHERE is_pinned = 0
                ORDER BY created_at ASC
                LIMIT ?
                """,
            params: [excess]
        )
        for row in rows {
            if let idStr = row["id"] as? String, let uuid = UUID(uuidString: idStr) {
                imageStorage.deleteFiles(for: uuid)
            }
        }

        try db.execute(
            sql: """
                DELETE FROM clipboard_items
                WHERE is_pinned = 0 AND id IN (
                    SELECT id FROM clipboard_items
                    WHERE is_pinned = 0
                    ORDER BY created_at ASC
                    LIMIT ?
                )
                """,
            params: [excess]
        )
        logger.debug("Enforced max history, removed \(excess) items")
    }

    private static func defaultDBPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Tray", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        return appSupport.appendingPathComponent("tray.sqlite3").path
    }
}
