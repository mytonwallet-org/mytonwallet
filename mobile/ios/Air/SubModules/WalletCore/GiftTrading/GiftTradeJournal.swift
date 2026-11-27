import Foundation

@frozen public enum GiftTradeJournalError: Error {
    case invalidRecord, unavailable, capacity, conflict, consumed, staleEvidence
}

public struct GiftTradeJournalContext: Equatable, Sendable {
    public let account: String
    public let network: String
    public init(account: String, network: String) throws {
        _ = try GiftTradeReference(network: network, kind: "sale", nft: account, contract: account)
        self.account = account; self.network = network
    }
}

/// Public operation identity only. No message body, StateInit, key or NFT metadata.
public struct GiftTradePending: Equatable, Sendable {
    public let intentId: String
    public let context: GiftTradeJournalContext
    public let reference: GiftTradeReference
    public let action: String
    public let createdAt: Int64
    public let updatedAt: Int64
    public let state: String
    public let messageHash: String?
    public let reservationId: String?
    public init(intentId: String, context: GiftTradeJournalContext, reference: GiftTradeReference,
                action: String, createdAt: Int64, updatedAt: Int64, state: String = "uncertain",
                messageHash: String? = nil, reservationId: String? = nil) {
        self.intentId = intentId; self.context = context; self.reference = reference; self.action = action
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.state = state
        self.messageHash = messageHash; self.reservationId = reservationId
    }
}

/// Run update once within an atomic durable transaction, across connections/processes.
/// Return only after commit. Missing/corrupt storage must never become an empty journal.
public protocol GiftTradeJournalStore: AnyObject, Sendable {
    func transact<T>(_ update: ([GiftTradePending]) throws -> ([GiftTradePending], T)) throws -> T
    func read() throws -> [GiftTradePending]
}

public extension GiftTradeJournalStore {
    func read() throws -> [GiftTradePending] { try transact { ($0, $0) } }
}

@frozen public enum GiftTradeJournalCodec {
    public static let capacity = 100
    public static let maxBytes = 131072
    private static let header = "wallet-gift-pending-v2\n"
    private static let legacy = "wallet-gift-pending-v1\n"
    private static let actions: Set<String> = ["list", "buy", "cancel-sale", "make-offer", "accept-offer", "cancel-offer"]
    static func matches(_ value: String, _ pattern: String) -> Bool { GiftTradeReference.matches(value, pattern: pattern) }
    public static func checkTime(_ time: Int64) throws {
        guard (0...0xffffffff).contains(time) else { throw GiftTradeJournalError.invalidRecord }
    }
    @discardableResult public static func validate(_ records: [GiftTradePending]) throws -> [GiftTradePending] {
        guard records.count <= capacity else { throw GiftTradeJournalError.capacity }
        var ids = Set<String>(), pending = Set<String>()
        for row in records {
            guard matches(row.intentId, "[a-f0-9]{64}"), ids.insert(row.intentId).inserted,
                  actions.contains(row.action), row.reference.network == row.context.network,
                  row.reference.kind == (["list", "buy", "cancel-sale"].contains(row.action) ? "sale" : "offer"),
                  row.updatedAt >= row.createdAt, ["uncertain", "submitted", "settled", "failed"].contains(row.state),
                  row.messageHash.map({ matches($0, "[a-f0-9]{64}") }) ?? true,
                  row.reservationId.map({ matches($0, "[a-f0-9]{32}") }) ?? true,
                  row.state == "uncertain" || row.messageHash != nil else { throw GiftTradeJournalError.invalidRecord }
            _ = try GiftTradeJournalContext(account: row.context.account, network: row.context.network)
            _ = try GiftTradeReference.decode(row.reference.encoded, expectedNetwork: row.context.network)
            try checkTime(row.createdAt); try checkTime(row.updatedAt)
            if ["uncertain", "submitted"].contains(row.state) {
                guard pending.insert([row.context.account, row.context.network, row.reference.nft].joined(separator: "\t")).inserted else { throw GiftTradeJournalError.conflict }
            }
        }
        return records
    }
    public static func encode(_ records: [GiftTradePending]) throws -> Data {
        let rows = try validate(records).map { row in
            [row.intentId, row.context.account, row.context.network, row.reference.encoded, row.action,
             String(row.createdAt), String(row.updatedAt), row.state, row.messageHash ?? "-", row.reservationId ?? "-"].joined(separator: "\t") + "\n"
        }.joined()
        guard let data = (header + rows).data(using: .ascii), data.count <= maxBytes else { throw GiftTradeJournalError.invalidRecord }
        return data
    }
    public static func decode(_ data: Data) throws -> [GiftTradePending] {
        guard data.count >= header.utf8.count, data.count <= maxBytes,
              data.allSatisfy({ $0 == 9 || $0 == 10 || (32...126).contains($0) }),
              let text = String(data: data, encoding: .ascii), text.hasSuffix("\n"),
              text.hasPrefix(header) || text.hasPrefix(legacy) else { throw GiftTradeJournalError.invalidRecord }
        let isLegacy = text.hasPrefix(legacy), body = String(text.dropFirst(header.count))
        if body.isEmpty { return [] }
        let lines = body.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count <= capacity else { throw GiftTradeJournalError.capacity }
        return try validate(lines.map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == (isLegacy ? 9 : 10), matches(fields[5], "0|[1-9][0-9]{0,9}"), matches(fields[6], "0|[1-9][0-9]{0,9}"),
                  let created = Int64(fields[5]), let updated = Int64(fields[6]) else { throw GiftTradeJournalError.invalidRecord }
            let context = try GiftTradeJournalContext(account: fields[1], network: fields[2])
            return GiftTradePending(intentId: fields[0], context: context,
                reference: try GiftTradeReference.decode(fields[3], expectedNetwork: context.network), action: fields[4],
                createdAt: created, updatedAt: updated, state: fields[7], messageHash: fields[8] == "-" ? nil : fields[8],
                reservationId: isLegacy || fields[9] == "-" ? nil : fields[9])
        })
    }
}

/// Trusted local revalidator result, never copied from provider JSON. This does not authenticate chain state.
public struct GiftTradeHandoffEvidence: Sendable {
    public let context: GiftTradeJournalContext
    public let intentId: String
    public let stateHash: String
    public let observedAt: Int64
    public let accountKind: String
    public let allowed: Bool
    public let cancelled: Bool
    public init(context: GiftTradeJournalContext, intentId: String, stateHash: String, observedAt: Int64,
                accountKind: String, allowed: Bool, cancelled: Bool) {
        self.context = context; self.intentId = intentId; self.stateHash = stateHash; self.observedAt = observedAt
        self.accountKind = accountKind; self.allowed = allowed; self.cancelled = cancelled
    }
}

/// Process-local, nonserializable capability. No lock is held around storage or external callbacks.
// The only mutable capability state is phase, guarded by lock; intent/record/store are Sendable.
public final class GiftTradeReservation: @unchecked Sendable {
    private let lock = NSLock()
    private var phase = "ready"
    private let intent: GiftTradeBoundIntent
    private let original: GiftTradePending
    private let store: GiftTradeJournalStore
    fileprivate init(intent: GiftTradeBoundIntent, original: GiftTradePending, store: GiftTradeJournalStore) {
        self.intent = intent; self.original = original; self.store = store
    }
    private func locked<T>(_ block: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try block() }
    private func release() throws {
        try store.transact { records in
            let clean = try GiftTradeJournalCodec.validate(records)
            guard clean.filter({ $0.intentId == self.original.intentId }) == [self.original] else { throw GiftTradeJournalError.conflict }
            return (clean.filter { $0.intentId != self.original.intentId }, ())
        }
    }
    public func cancelBeforeHandoff() throws -> Bool {
        let releaseNeeded = locked { () -> Bool in
            guard phase == "ready" || phase == "checking" else { return false }
            phase = "closed"; return true
        }
        guard releaseNeeded else { return false }; try release(); return true
    }
    public func handoff<T>(clock: () -> Int64, recheck: (GiftTradeBoundIntent) throws -> GiftTradeHandoffEvidence,
                           execute: (GiftTradeBoundIntent) throws -> T) throws -> T {
        try locked { guard phase == "ready" else { throw GiftTradeJournalError.consumed }; phase = "checking" }
        do {
            try store.transact { records in
                let clean = try GiftTradeJournalCodec.validate(records)
                guard clean.filter({ $0.intentId == self.original.intentId }) == [self.original] else { throw GiftTradeJournalError.conflict }
                return (clean, ())
            }
            let evidence = try recheck(intent), now = clock()
            try locked {
                guard phase == "checking" else { throw GiftTradeJournalError.consumed }
                try intent.checkTime(now)
                guard evidence.context == original.context, evidence.intentId == intent.id, evidence.stateHash == intent.stateHash,
                      ["software", "hardware"].contains(evidence.accountKind), evidence.allowed, !evidence.cancelled,
                      evidence.observedAt >= 0, evidence.observedAt <= now, now - evidence.observedAt <= 15 else { throw GiftTradeJournalError.staleEvidence }
                phase = "handed-off"
            }
        } catch {
            let shouldRelease = locked { () -> Bool in if phase == "checking" { phase = "closed"; return true }; return false }
            if shouldRelease { try? release() } // Preserve the original failure; uncertain storage remains locked.
            throw error
        }
        // Any failure after this point is uncertain. Never auto-release/retry after an executor call.
        return try execute(intent)
    }
}

public final class GiftTradeJournal: Sendable {
    private let store: GiftTradeJournalStore
    public init(store: GiftTradeJournalStore) { self.store = store }
    public func prepare(_ intent: GiftTradeBoundIntent, now: Int64) throws -> GiftTradeReservation {
        try intent.checkTime(now)
        let context = try GiftTradeJournalContext(account: intent.account, network: intent.network)
        let row = GiftTradePending(intentId: intent.id, context: context, reference: intent.reference, action: intent.action,
            createdAt: now, updatedAt: now, reservationId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        try GiftTradeJournalCodec.validate([row])
        let committed: GiftTradePending = try store.transact { records in
            var clean = try GiftTradeJournalCodec.validate(records)
            guard !clean.contains(where: { $0.intentId == row.intentId || ($0.context == row.context && $0.reference.nft == row.reference.nft && ["uncertain", "submitted"].contains($0.state)) }) else { throw GiftTradeJournalError.conflict }
            if clean.count == GiftTradeJournalCodec.capacity {
                guard let oldest = clean.filter({ ["settled", "failed"].contains($0.state) }).min(by: { $0.updatedAt < $1.updatedAt }) else { throw GiftTradeJournalError.capacity }
                clean.removeAll { $0.intentId == oldest.intentId }
            }
            clean.append(row); return (try GiftTradeJournalCodec.validate(clean), row)
        }
        return GiftTradeReservation(intent: intent, original: committed, store: store)
    }
    public func list(_ context: GiftTradeJournalContext) throws -> [GiftTradePending] {
        try GiftTradeJournalCodec.validate(store.read()).filter { $0.context == context }
    }
    /// Only independently verified receipts may call this. Timeouts/absence are not terminal failure.
    public func reconcile(_ context: GiftTradeJournalContext, intentId: String, next: String, messageHash: String, now: Int64) throws {
        try GiftTradeJournalCodec.checkTime(now)
        guard ["submitted", "settled", "failed"].contains(next), GiftTradeJournalCodec.matches(messageHash, "[a-f0-9]{64}") else { throw GiftTradeJournalError.invalidRecord }
        try store.transact { records in
            var clean = try GiftTradeJournalCodec.validate(records)
            guard let at = clean.firstIndex(where: { $0.intentId == intentId && $0.context == context }) else { throw GiftTradeJournalError.conflict }
            let old = clean[at]
            guard ["uncertain", "submitted"].contains(old.state), now >= old.updatedAt, old.messageHash == nil || old.messageHash == messageHash else { throw GiftTradeJournalError.conflict }
            clean[at] = GiftTradePending(intentId: old.intentId, context: old.context, reference: old.reference, action: old.action,
                createdAt: old.createdAt, updatedAt: now, state: next, messageHash: messageHash, reservationId: old.reservationId)
            return (try GiftTradeJournalCodec.validate(clean), ())
        }
    }
}
