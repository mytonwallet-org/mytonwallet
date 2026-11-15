import Foundation
import SQLite3

/// Synchronous durable transactions belong on an IO executor, not the UI thread.
/// Separate app-private/no-backup directory; never accesses the wallet key store.
public final class GiftTradeSqliteJournal: GiftTradeJournalStore {
    private let directory: URL
    public convenience init() throws {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw GiftTradeJournalError.unavailable }
        try self.init(testDirectory: support.appendingPathComponent("GiftTradingPending", isDirectory: true))
    }
    // Internal injection only for isolated XCTest temporary directories.
    init(testDirectory: URL) throws {
        guard testDirectory.isFileURL, testDirectory.path.hasPrefix("/") else { throw GiftTradeJournalError.unavailable }
        directory = testDirectory
    }
    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw GiftTradeJournalError.unavailable }
    }
    private func query<T>(_ db: OpaquePointer, _ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let prepared = statement else { throw GiftTradeJournalError.unavailable }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }
    private func scalar(_ db: OpaquePointer, _ sql: String) throws -> Int64 {
        try query(db, sql) { statement in
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { throw GiftTradeJournalError.unavailable }
            let result = sqlite3_column_int64(statement, 0)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw GiftTradeJournalError.unavailable }
            return result
        }
    }
    private func write(_ db: OpaquePointer, _ sql: String, _ data: Data) throws {
        try query(db, sql) { statement in
            let bound = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw GiftTradeJournalError.unavailable }
        }
    }
    public func read() throws -> [GiftTradePending] {
        guard !Thread.isMainThread else { throw GiftTradeJournalError.unavailable }
        let file = directory.appendingPathComponent("pending-v1.db")
        do {
            try validateFile(file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return try transact { ($0, $0) }
        }
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard opened == SQLITE_OK, let db = handle else { if let handle { sqlite3_close(handle) }; throw GiftTradeJournalError.unavailable }
        defer { sqlite3_close(db) }
        guard sqlite3_busy_timeout(db, 1000) == SQLITE_OK, try scalar(db, "PRAGMA user_version") == 1 else {
            throw GiftTradeJournalError.unavailable
        }
        return try readSnapshot(db)
    }
    private func validateFile(_ file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 2 * 1024 * 1024 else {
            throw GiftTradeJournalError.unavailable
        }
    }
    private func readSnapshot(_ db: OpaquePointer) throws -> [GiftTradePending] {
        try query(db, "SELECT id,payload FROM pending LIMIT 2") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
                  sqlite3_column_int64(statement, 0) == 1, sqlite3_column_type(statement, 1) == SQLITE_BLOB else {
                throw GiftTradeJournalError.unavailable
            }
            let count = Int(sqlite3_column_bytes(statement, 1))
            guard count > 0, count <= GiftTradeJournalCodec.maxBytes, let bytes = sqlite3_column_blob(statement, 1) else {
                throw GiftTradeJournalError.unavailable
            }
            let records = try GiftTradeJournalCodec.decode(Data(bytes: bytes, count: count))
            guard sqlite3_step(statement) == SQLITE_DONE else { throw GiftTradeJournalError.unavailable }
            return records
        }
    }
    public func transact<T>(_ update: ([GiftTradePending]) throws -> ([GiftTradePending], T)) throws -> T {
        guard !Thread.isMainThread else { throw GiftTradeJournalError.unavailable }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        let file = directory.appendingPathComponent("pending-v1.db"), existed = manager.fileExists(atPath: file.path)
        if existed { try validateFile(file) }
        var handle: OpaquePointer?
        let opened = sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard opened == SQLITE_OK, let db = handle else { if let handle { sqlite3_close(handle) }; throw GiftTradeJournalError.unavailable }
        defer { sqlite3_close(db) }
        guard sqlite3_busy_timeout(db, 1000) == SQLITE_OK else { throw GiftTradeJournalError.unavailable }
        try exec(db, "PRAGMA synchronous=FULL")
        try exec(db, "BEGIN IMMEDIATE")
        var committed = false
        defer { if !committed { try? exec(db, "ROLLBACK") } }
        let version = try scalar(db, "PRAGMA user_version")
        if version == 0 {
            guard !existed, try scalar(db, "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else { throw GiftTradeJournalError.unavailable }
            try exec(db, "CREATE TABLE pending (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL CHECK(length(payload)<=131072))")
            try write(db, "INSERT INTO pending(id,payload) VALUES(1,?)", GiftTradeJournalCodec.encode([]))
            try exec(db, "PRAGMA user_version=1")
        } else if version != 1 { throw GiftTradeJournalError.unavailable }
        let current = try readSnapshot(db)
        let (next, result) = try update(current)
        try write(db, "UPDATE pending SET payload=? WHERE id=1", GiftTradeJournalCodec.encode(next))
        try exec(db, "COMMIT"); committed = true
        return result
    }
}
