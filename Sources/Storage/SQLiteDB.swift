import Foundation
import SQLite3
import os

private let logger = Logger(subsystem: "com.tray.app", category: "SQLiteDB")

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)
    case bindFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        case .executeFailed(let msg): return "SQLite execute failed: \(msg)"
        case .bindFailed(let msg): return "SQLite bind failed: \(msg)"
        }
    }
}

/// Thin wrapper around the C SQLite3 API. Thread-safe via serial queue.
final class SQLiteDB {

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.tray.sqlite", qos: .userInitiated)

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(msg)
        }
        // Enable WAL mode for better concurrent read performance
        try execute(sql: "PRAGMA journal_mode=WAL")
        logger.info("Database opened at \(path)")
    }

    /// In-memory database for testing or fallback
    init(inMemory: Bool = true) throws {
        let result = sqlite3_open(":memory:", &db)
        guard result == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(msg)
        }
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Execute (INSERT, UPDATE, DELETE, PRAGMA)

    @discardableResult
    func execute(sql: String, params: [Any?] = []) throws -> Int {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.prepareFailed(msg)
            }

            try bindParams(stmt: stmt!, params: params)

            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE || result == SQLITE_ROW else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.executeFailed(msg)
            }

            return Int(sqlite3_changes(db))
        }
    }

    // MARK: - Query (SELECT)

    func query(sql: String, params: [Any?] = []) throws -> [[String: Any]] {
        try queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                let msg = String(cString: sqlite3_errmsg(db))
                throw SQLiteError.prepareFailed(msg)
            }

            try bindParams(stmt: stmt!, params: params)

            var rows: [[String: Any]] = []
            let columnCount = sqlite3_column_count(stmt)

            while sqlite3_step(stmt) == SQLITE_ROW {
                var row: [String: Any] = [:]
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(stmt, i))
                    row[name] = columnValue(stmt: stmt!, index: i)
                }
                rows.append(row)
            }

            return rows
        }
    }

    /// Returns a single integer value (for COUNT queries etc.)
    func scalar(sql: String, params: [Any?] = []) throws -> Int {
        let rows = try query(sql: sql, params: params)
        guard let first = rows.first, let val = first.values.first else { return 0 }
        if let intVal = val as? Int { return intVal }
        if let int64Val = val as? Int64 { return Int(int64Val) }
        return 0
    }

    // MARK: - Binding

    private func bindParams(stmt: OpaquePointer, params: [Any?]) throws {
        for (index, param) in params.enumerated() {
            let sqlIndex = Int32(index + 1)
            let result: Int32

            switch param {
            case nil:
                result = sqlite3_bind_null(stmt, sqlIndex)
            case let val as String:
                result = sqlite3_bind_text(stmt, sqlIndex, (val as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let val as Int:
                result = sqlite3_bind_int64(stmt, sqlIndex, Int64(val))
            case let val as Int64:
                result = sqlite3_bind_int64(stmt, sqlIndex, val)
            case let val as Double:
                result = sqlite3_bind_double(stmt, sqlIndex, val)
            case let val as Data:
                result = val.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, sqlIndex, ptr.baseAddress, Int32(val.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            default:
                let str = String(describing: param!)
                result = sqlite3_bind_text(stmt, sqlIndex, (str as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }

            guard result == SQLITE_OK else {
                throw SQLiteError.bindFailed("Failed to bind param at index \(index)")
            }
        }
    }

    // MARK: - Column Reading

    private func columnValue(stmt: OpaquePointer, index: Int32) -> Any {
        let type = sqlite3_column_type(stmt, index)
        switch type {
        case SQLITE_INTEGER:
            return Int64(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return sqlite3_column_double(stmt, index)
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(stmt, index) else { return NSNull() } // NULL on out-of-memory
            return String(cString: text)
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(stmt, index))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
            return Data(bytes: bytes, count: count)
        case SQLITE_NULL:
            return NSNull()
        default:
            return NSNull()
        }
    }
}
