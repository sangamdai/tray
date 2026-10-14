import XCTest
@testable import Tray

final class SQLiteDBTests: XCTestCase {

    private var db: SQLiteDB!

    override func setUp() {
        super.setUp()
        db = try! SQLiteDB(inMemory: true)
    }

    func test_createTableAndInsert() throws {
        try db.execute(sql: "CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute(sql: "INSERT INTO test (id, name) VALUES (?, ?)", params: [1, "hello"])

        let rows = try db.query(sql: "SELECT * FROM test")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"] as? String, "hello")
    }

    func test_queryReturnsEmpty() throws {
        try db.execute(sql: "CREATE TABLE empty_test (id INTEGER)")
        let rows = try db.query(sql: "SELECT * FROM empty_test")
        XCTAssertTrue(rows.isEmpty)
    }

    func test_scalarCount() throws {
        try db.execute(sql: "CREATE TABLE count_test (id INTEGER)")
        try db.execute(sql: "INSERT INTO count_test VALUES (1)")
        try db.execute(sql: "INSERT INTO count_test VALUES (2)")

        let count = try db.scalar(sql: "SELECT COUNT(*) FROM count_test")
        XCTAssertEqual(count, 2)
    }

    func test_bindAllTypes() throws {
        try db.execute(sql: """
            CREATE TABLE types_test (
                int_col INTEGER,
                real_col REAL,
                text_col TEXT,
                blob_col BLOB
            )
            """)

        let blobData = "binary".data(using: .utf8)!
        try db.execute(
            sql: "INSERT INTO types_test VALUES (?, ?, ?, ?)",
            params: [42, 3.14, "text", blobData]
        )

        let rows = try db.query(sql: "SELECT * FROM types_test")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["int_col"] as? Int64, 42)
        XCTAssertEqual(rows[0]["real_col"] as? Double, 3.14)
        XCTAssertEqual(rows[0]["text_col"] as? String, "text")
    }

    func test_nullHandling() throws {
        try db.execute(sql: "CREATE TABLE null_test (id INTEGER, name TEXT)")
        try db.execute(sql: "INSERT INTO null_test VALUES (?, ?)", params: [1, nil])

        let rows = try db.query(sql: "SELECT * FROM null_test")
        XCTAssertTrue(rows[0]["name"] is NSNull)
    }

    func test_invalidSQLThrows() {
        XCTAssertThrowsError(try db.execute(sql: "INVALID SQL STATEMENT"))
    }

    func test_executeReturnsChangedRows() throws {
        try db.execute(sql: "CREATE TABLE change_test (id INTEGER, val TEXT)")
        try db.execute(sql: "INSERT INTO change_test VALUES (1, 'a')")
        try db.execute(sql: "INSERT INTO change_test VALUES (2, 'b')")

        let changed = try db.execute(
            sql: "UPDATE change_test SET val = 'x' WHERE id > 0"
        )
        XCTAssertEqual(changed, 2)
    }
}
