import XCTest
@testable import WalletCore

final class GiftTradeJournalTests: XCTestCase {
    private final class ReadOnlyStore: GiftTradeJournalStore {
        let records: [GiftTradePending]
        init(_ records: [GiftTradePending]) { self.records = records }
        func read() throws -> [GiftTradePending] { records }
        func transact<T>(_ update: ([GiftTradePending]) throws -> ([GiftTradePending], T)) throws -> T {
            XCTFail("List should use the read snapshot")
            throw GiftTradeJournalError.unavailable
        }
    }

    func testListUsesReadSnapshot() throws {
        let i = try intent(), context = try GiftTradeJournalContext(account: i.account, network: i.network)
        let row = GiftTradePending(intentId: i.id, context: context, reference: i.reference, action: i.action, createdAt: 1000, updatedAt: 1000)
        let journal = GiftTradeJournal(store: ReadOnlyStore([row]))
        XCTAssertEqual(try journal.list(context), [row])
        let other = try GiftTradeJournalContext(account: address(8), network: i.network)
        XCTAssertEqual(try journal.list(other), [])
    }
    // All mutable test storage/fault controls are guarded by lock.
    final class MemoryStore: GiftTradeJournalStore, @unchecked Sendable {
        private var stored = Data("wallet-gift-pending-v2\n".utf8)
        private var loseReply = false
        private var failBefore = false
        private let lock = NSLock()
        var loseCommitReply: Bool {
            get { lock.lock(); defer { lock.unlock() }; return loseReply }
            set { lock.lock(); defer { lock.unlock() }; loseReply = newValue }
        }
        var failBeforeCommit: Bool {
            get { lock.lock(); defer { lock.unlock() }; return failBefore }
            set { lock.lock(); defer { lock.unlock() }; failBefore = newValue }
        }
        func transact<T>(_ update: ([GiftTradePending]) throws -> ([GiftTradePending], T)) throws -> T {
            lock.lock(); defer { lock.unlock() }
            let (next, result) = try update(GiftTradeJournalCodec.decode(stored))
            if failBefore { throw GiftTradeJournalError.unavailable }
            stored = try GiftTradeJournalCodec.encode(next)
            if loseReply { throw GiftTradeJournalError.unavailable }
            return result
        }
    }
    // Counters crossing test worker boundaries are guarded by lock.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var count = 0
        func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }
    private func address(_ n: Int) -> String { "0:" + String(repeating: "0", count: 63) + String(n) }
    private func intent() throws -> GiftTradeBoundIntent {
        try GiftTradeBoundIntent(account: address(1), network: "-239",
            reference: GiftTradeReference(network: "-239", kind: "sale", nft: address(2), contract: address(3)),
            action: "buy", counterparty: address(4), amount: "10000000000", fee: "0", royalty: "100000000",
            gasBudget: "500000000", expiresAt: 1060, feeRecipient: address(4), royaltyRecipient: address(5),
            stateHash: String(repeating: "a", count: 64), authority: address(4), provider: "wallet-market",
            messages: [GiftTradeMessage(to: address(3), amount: "10500000000", payload: "AAAA", stateInit: nil)])
    }
    private func evidence(_ intent: GiftTradeBoundIntent, kind: String = "software", allowed: Bool = true) throws -> GiftTradeHandoffEvidence {
        try GiftTradeHandoffEvidence(context: GiftTradeJournalContext(account: intent.account, network: intent.network),
            intentId: intent.id, stateHash: intent.stateHash, observedAt: 1000, accountKind: kind, allowed: allowed, cancelled: false)
    }
    func testWireV1MigrationAndMalformedRecords() throws {
        let i = try intent(), context = try GiftTradeJournalContext(account: i.account, network: i.network)
        let row = GiftTradePending(intentId: i.id, context: context, reference: i.reference, action: i.action, createdAt: 1000, updatedAt: 1000)
        let v2 = try GiftTradeJournalCodec.encode([row])
        XCTAssertEqual(try GiftTradeJournalCodec.decode(v2), [row])
        let v1 = String(decoding: v2, as: UTF8.self).replacingOccurrences(of: "pending-v2", with: "pending-v1").replacingOccurrences(of: "\t-\t-\n", with: "\t-\n")
        XCTAssertEqual(try GiftTradeJournalCodec.decode(Data(v1.utf8)), [row])
        XCTAssertThrowsError(try GiftTradeJournalCodec.decode(Data([255])))
        XCTAssertThrowsError(try GiftTradeJournalCodec.decode(Data(repeating: 65, count: GiftTradeJournalCodec.maxBytes + 1)))
        XCTAssertThrowsError(try GiftTradeJournalCodec.encode([row, row]))
    }
    func testReservationRestartAndLostCommitReply() throws {
        let i = try intent(), store = MemoryStore(), journal = GiftTradeJournal(store: store)
        store.loseCommitReply = true
        XCTAssertThrowsError(try journal.prepare(i, now: 1000)); store.loseCommitReply = false
        XCTAssertThrowsError(try GiftTradeJournal(store: store).prepare(i, now: 1001))
        XCTAssertEqual(try journal.list(GiftTradeJournalContext(account: i.account, network: i.network)).count, 1)
    }
    func testReentrancyCancellationAndExecutorFailure() throws {
        let i = try intent(), store = MemoryStore(), journal = GiftTradeJournal(store: store)
        let cancelled = try journal.prepare(i, now: 1000); var executions = 0
        XCTAssertThrowsError(try cancelled.handoff(clock: { 1001 }, recheck: { value in
            XCTAssertThrowsError(try cancelled.handoff(clock: { 1001 }, recheck: { try self.evidence($0) }, execute: { _ in executions += 1 }))
            XCTAssertTrue(try cancelled.cancelBeforeHandoff()); return try self.evidence(value)
        }, execute: { _ in executions += 1 }))
        XCTAssertEqual(executions, 0)
        let lost = try journal.prepare(i, now: 1001)
        XCTAssertThrowsError(try lost.handoff(clock: { 1002 }, recheck: { try self.evidence($0) }, execute: { _ -> Void in executions += 1; throw GiftTradeJournalError.unavailable }))
        XCTAssertFalse(try lost.cancelBeforeHandoff()); XCTAssertEqual(executions, 1)
        XCTAssertThrowsError(try journal.prepare(i, now: 1002))
    }
    func testStaleOrUnapprovedFinalEvidenceCannotExecute() throws {
        for kind in ["watch-only", "unsupported"] {
            let i = try intent(), reservation = try GiftTradeJournal(store: MemoryStore()).prepare(i, now: 1000)
            XCTAssertThrowsError(try reservation.handoff(clock: { 1001 }, recheck: { try self.evidence($0, kind: kind) }, execute: { _ in XCTFail("Executed") }))
        }
        let i = try intent(), expired = try GiftTradeJournal(store: MemoryStore()).prepare(i, now: 1000)
        XCTAssertThrowsError(try expired.handoff(clock: { 1060 }, recheck: { try self.evidence($0) }, execute: { _ in XCTFail("Executed") }))
        let revoked = try GiftTradeJournal(store: MemoryStore()).prepare(i, now: 1000)
        XCTAssertThrowsError(try revoked.handoff(clock: { 1001 }, recheck: { try self.evidence($0, allowed: false) }, execute: { _ in XCTFail("Executed") }))
    }
    func testStaleNonceAndReconciledRowCannotBeDeleted() throws {
        let i = try intent(), context = try GiftTradeJournalContext(account: i.account, network: i.network)
        let store = MemoryStore(), journal = GiftTradeJournal(store: store), old = try journal.prepare(i, now: 1000)
        try store.transact { _ in ([], ()) }
        let replacement = try journal.prepare(i, now: 1001)
        XCTAssertThrowsError(try old.cancelBeforeHandoff())
        XCTAssertEqual(try journal.list(context).count, 1)
        XCTAssertTrue(try replacement.cancelBeforeHandoff())
        let changed = try journal.prepare(i, now: 1002)
        try journal.reconcile(context, intentId: i.id, next: "submitted", messageHash: String(repeating: "c", count: 64), now: 1003)
        XCTAssertThrowsError(try changed.cancelBeforeHandoff())
        XCTAssertEqual(try journal.list(context).first?.state, "submitted")
    }
    func testCancellationStorageFailureNeverRestoresCapability() throws {
        for afterCommit in [false, true] {
            let i = try intent(), store = MemoryStore(), journal = GiftTradeJournal(store: store), cap = try journal.prepare(i, now: 1000)
            if afterCommit { store.loseCommitReply = true } else { store.failBeforeCommit = true }
            XCTAssertThrowsError(try cap.cancelBeforeHandoff())
            store.loseCommitReply = false; store.failBeforeCommit = false
            XCTAssertThrowsError(try cap.handoff(clock: { 1001 }, recheck: { try self.evidence($0) }, execute: { _ in XCTFail("Stale capability executed") }))
            let rows = try journal.list(GiftTradeJournalContext(account: i.account, network: i.network))
            XCTAssertEqual(rows.count, afterCommit ? 0 : 1)
        }
    }
    func testRecheckCanWaitForCancellationOnAnotherThreadWithoutDeadlock() throws {
        let i = try intent(), cap = try GiftTradeJournal(store: MemoryStore()).prepare(i, now: 1000), cancelled = DispatchSemaphore(value: 0), count = Counter()
        XCTAssertThrowsError(try cap.handoff(clock: { 1001 }, recheck: { value in
            DispatchQueue.global(qos: .utility).async { if (try? cap.cancelBeforeHandoff()) == true { count.increment() }; cancelled.signal() }
            XCTAssertEqual(cancelled.wait(timeout: .now() + 3), .success)
            return try self.evidence(value)
        }, execute: { _ in XCTFail("Cancelled operation executed") }))
        XCTAssertEqual(count.value, 1)
    }
    func testConcurrentCancellationAndHandoffHaveAtMostOneWinner() throws {
        let i = try intent(), store = MemoryStore(), journal = GiftTradeJournal(store: store), cap = try journal.prepare(i, now: 1000)
        let finalEvidence = try evidence(i), group = DispatchGroup(), executed = Counter(), cancelled = Counter()
        group.enter(); DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }; if (try? cap.cancelBeforeHandoff()) == true { cancelled.increment() }
        }
        group.enter(); DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }; _ = try? cap.handoff(clock: { 1001 }, recheck: { _ in finalEvidence }, execute: { _ in executed.increment() })
        }
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(executed.value + cancelled.value, 1)
        let rows = try journal.list(GiftTradeJournalContext(account: i.account, network: i.network))
        XCTAssertEqual(rows.count, executed.value)
    }
    func testCapacityNeverEvictsUnresolvedRows() throws {
        let i = try intent(), context = try GiftTradeJournalContext(account: i.account, network: i.network), store = MemoryStore(), journal = GiftTradeJournal(store: store)
        func padded(_ n: Int) -> String { let h = String(n, radix: 16); return String(repeating: "0", count: 64 - h.count) + h }
        let rows = try (100..<200).map { n in GiftTradePending(intentId: padded(n), context: context,
            reference: try GiftTradeReference(network: "-239", kind: "sale", nft: "0:" + padded(n), contract: "0:" + padded(n + 1000)), action: "buy", createdAt: 900, updatedAt: 900) }
        try store.transact { _ in (rows, ()) }; XCTAssertThrowsError(try journal.prepare(i, now: 1000))
        try journal.reconcile(context, intentId: rows[0].intentId, next: "failed", messageHash: String(repeating: "b", count: 64), now: 1000)
        _ = try journal.prepare(i, now: 1001)
        let after = try journal.list(context); XCTAssertEqual(after.count, 100); XCTAssertFalse(after.contains { $0.intentId == rows[0].intentId }); XCTAssertTrue(after.contains { $0.intentId == i.id })
    }
    func testSQLiteSurvivesNewInstanceOnBackgroundExecutor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gift-journal-test-" + UUID().uuidString, isDirectory: true)
        let i = try intent()
        let finished = expectation(description: "background SQLite")
        DispatchQueue.global(qos: .utility).async {
            defer { finished.fulfill() }
            do {
                let first = try GiftTradeSqliteJournal(testDirectory: directory)
                _ = try GiftTradeJournal(store: first).prepare(i, now: 1000)
                let second = try GiftTradeSqliteJournal(testDirectory: directory)
                XCTAssertThrowsError(try GiftTradeJournal(store: second).prepare(i, now: 1001))
                let file = directory.appendingPathComponent("pending-v1.db")
                let before = try Data(contentsOf: file)
                XCTAssertEqual(try GiftTradeJournal(store: second).list(GiftTradeJournalContext(account: i.account, network: i.network)).count, 1)
                XCTAssertEqual(try Data(contentsOf: file), before)
            } catch { XCTFail("SQLite test failed: \(error)") }
        }
        wait(for: [finished], timeout: 10)
        // Preserve this synthetic test database as evidence; no cleanup of unrelated app profiles.
    }
}
