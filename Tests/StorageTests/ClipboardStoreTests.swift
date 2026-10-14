import XCTest
@testable import Tray

final class ClipboardStoreTests: XCTestCase {

    private var store: ClipboardStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let imageStorage = ImageStorage(baseDirectory: tempDir)
        store = try! ClipboardStore(
            inMemory: true,
            maxHistoryItems: 5,
            imageStorage: imageStorage
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeItem(
        preview: String = "test",
        hash: String? = nil,
        type: ClipboardItemType = .plainText,
        date: Date = Date()
    ) -> ClipboardItem {
        ClipboardItem(
            type: type,
            createdAt: date,
            contentPreview: preview,
            dataHash: hash ?? UUID().uuidString,
            metadata: ClipboardItemMetadata(plainText: preview)
        )
    }

    // MARK: - Tests

    func test_saveAndFetchRecent() throws {
        for i in 0..<5 {
            try store.save(makeItem(preview: "item \(i)"))
            Thread.sleep(forTimeInterval: 0.01)
        }
        let recent = store.fetchRecent(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].contentPreview, "item 4")
        XCTAssertEqual(recent[1].contentPreview, "item 3")
        XCTAssertEqual(recent[2].contentPreview, "item 2")
    }

    func test_deduplicationBumpsTimestamp() throws {
        let oldDate = Date(timeIntervalSinceNow: -3600)
        try store.save(makeItem(preview: "dup", hash: "same_hash", date: oldDate))
        XCTAssertEqual(store.itemCount(), 1)

        let newDate = Date()
        try store.save(makeItem(preview: "dup", hash: "same_hash", date: newDate))
        XCTAssertEqual(store.itemCount(), 1)

        let recent = store.fetchRecent(limit: 10)
        XCTAssertEqual(recent.count, 1)
        // The timestamp should have been bumped
        XCTAssert(recent[0].createdAt.timeIntervalSince1970 >= newDate.timeIntervalSince1970 - 1)
    }

    func test_maxHistoryEnforced() throws {
        for i in 0..<10 {
            try store.save(makeItem(preview: "item \(i)"))
            Thread.sleep(forTimeInterval: 0.01)
        }
        let recent = store.fetchRecent(limit: 100)
        XCTAssertEqual(recent.count, 5)
    }

    func test_pinSurvivesCleanup() throws {
        let pinnedItem = makeItem(preview: "pinned")
        try store.save(pinnedItem)
        try store.togglePin(id: pinnedItem.id)

        for i in 0..<10 {
            try store.save(makeItem(preview: "item \(i)"))
            Thread.sleep(forTimeInterval: 0.01)
        }

        let pinned = store.fetchPinned()
        XCTAssertEqual(pinned.count, 1)
        XCTAssertEqual(pinned[0].contentPreview, "pinned")
    }

    func test_searchFindsPartialMatch() throws {
        try store.save(makeItem(preview: "Hello World"))
        try store.save(makeItem(preview: "Goodbye"))

        let results = store.search(query: "worl", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].contentPreview, "Hello World")
    }

    func test_deleteRemovesItem() throws {
        let item = makeItem(preview: "to delete")
        try store.save(item)
        XCTAssertEqual(store.itemCount(), 1)

        try store.delete(id: item.id)
        XCTAssertEqual(store.itemCount(), 0)
    }

    func test_deleteAllPreservesPinned() throws {
        let pinned = makeItem(preview: "pinned")
        try store.save(pinned)
        try store.togglePin(id: pinned.id)

        try store.save(makeItem(preview: "regular 1"))
        try store.save(makeItem(preview: "regular 2"))
        XCTAssertEqual(store.itemCount(), 3)

        try store.deleteAll()
        XCTAssertEqual(store.itemCount(), 1)
        XCTAssertEqual(store.fetchPinned().first?.contentPreview, "pinned")
    }

    func test_toggleHide() throws {
        let item = makeItem(preview: "secret")
        try store.save(item)

        try store.toggleHide(id: item.id)
        let hidden = store.fetchRecent(limit: 10)
        XCTAssertTrue(hidden[0].isHidden)

        try store.toggleHide(id: item.id)
        let shown = store.fetchRecent(limit: 10)
        XCTAssertFalse(shown[0].isHidden)
    }

    func test_rename() throws {
        let item = makeItem(preview: "original")
        try store.save(item)

        try store.rename(id: item.id, name: "My Custom Name")
        let results = store.search(query: "Custom", limit: 10)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].customName, "My Custom Name")
    }

    func test_getFullData() throws {
        var meta = ClipboardItemMetadata()
        meta.plainText = "full text here"
        let item = ClipboardItem(
            type: .plainText,
            contentPreview: "full text here",
            dataHash: "hash123",
            metadata: meta
        )
        try store.save(item)

        let data = store.getFullData(id: item.id)
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.type, .plainText)
        XCTAssertEqual(data?.metadata.plainText, "full text here")
    }

    func test_fetchPinnedOrder() throws {
        for i in 0..<3 {
            let item = makeItem(preview: "pin \(i)")
            try store.save(item)
            try store.togglePin(id: item.id)
            Thread.sleep(forTimeInterval: 0.01)
        }

        let pinned = store.fetchPinned()
        XCTAssertEqual(pinned.count, 3)
        XCTAssertEqual(pinned[0].contentPreview, "pin 2") // newest first
    }

    // MARK: - Payload storage

    func test_listingOmitsFullContent_fullDataIncludesIt() throws {
        let longText = String(repeating: "x", count: 10_000)
        let item = ClipboardItem(
            type: .plainText,
            contentPreview: "x",
            dataHash: "long",
            metadata: ClipboardItemMetadata(plainText: longText)
        )
        try store.save(item)

        XCTAssertNil(store.fetchRecent(limit: 10).first?.metadata.plainText)
        XCTAssertEqual(store.getFullData(id: item.id)?.metadata.plainText, longText)
    }

    func test_migrationMovesContentOutOfMetadata() throws {
        // A v1 database: content inside metadata_json, no payload_json column
        let db = try SQLiteDB(inMemory: true)
        try db.execute(sql: """
            CREATE TABLE clipboard_items (
                id TEXT PRIMARY KEY, type TEXT NOT NULL, created_at REAL NOT NULL,
                is_pinned INTEGER DEFAULT 0, is_hidden INTEGER DEFAULT 0, custom_name TEXT,
                source_app_id TEXT, source_app_name TEXT, content_preview TEXT NOT NULL,
                data_hash TEXT NOT NULL, metadata_json TEXT NOT NULL, UNIQUE(data_hash))
            """)
        let id = UUID()
        let oldMetadata = String(decoding: try JSONEncoder().encode(ClipboardItemMetadata(plainText: "hello")), as: UTF8.self)
        try db.execute(
            sql: "INSERT INTO clipboard_items (id, type, created_at, content_preview, data_hash, metadata_json) VALUES (?, ?, ?, ?, ?, ?)",
            params: [id.uuidString, "plainText", 1.0, "hello", "h", oldMetadata]
        )

        let migrated = try ClipboardStore(db: db, imageStorage: ImageStorage(baseDirectory: tempDir))

        XCTAssertNil(migrated.fetchRecent(limit: 10).first?.metadata.plainText)
        XCTAssertEqual(migrated.getFullData(id: id)?.metadata.plainText, "hello")
        XCTAssertEqual(try db.scalar(sql: "PRAGMA user_version"), Migrations.currentVersion)
    }
}
