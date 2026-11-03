import AppIntents
import CoreSpotlight
import Foundation
import WalletContext

@available(iOS 18.4, *)
public struct TokenSpotlightEntry: Codable, Sendable {
    public let entity: TokenEntity
    public let priority: Int

    public init(entity: TokenEntity, priority: Int) {
        self.entity = entity
        self.priority = priority
    }

    func hasSameContent(as other: Self) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // TokenEntity equality deliberately compares identity only.
        guard let lhs = try? encoder.encode(entity), let rhs = try? encoder.encode(other.entity) else { return false }
        return priority == other.priority && lhs == rhs
    }
}

@available(iOS 18.4, *)
protocol TokenSpotlightIndex: Sendable {
    func index(_ entries: [TokenSpotlightEntry]) async throws
    func delete(_ identifiers: [String]) async throws
    func reset() async throws
}

@available(iOS 18.4, *)
struct SystemTokenSpotlightIndex: TokenSpotlightIndex {
    static let name = "MyTonWallet_Tokens"

    func index(_ entries: [TokenSpotlightEntry]) async throws {
        let index = CSSearchableIndex(name: Self.name)
        for (priority, group) in Dictionary(grouping: entries, by: \.priority) {
            let entities = await entitiesWithThumbnails(group.map(\.entity))
            try await index.indexAppEntities(entities, priority: priority)
        }
    }

    private func entitiesWithThumbnails(_ entities: [TokenEntity]) async -> [TokenEntity] {
        await withTaskGroup(of: TokenEntity.self) { group in
            var pending = entities.makeIterator()
            func enqueue(_ entity: TokenEntity) {
                group.addTask {
                    var entity = entity
                    entity.indexedThumbnailData = await TokenEntityImage.loadData(entity.imageURL, tokenSlug: entity.tokenSlug)
                    return entity
                }
            }
            for _ in 0..<4 {
                if let entity = pending.next() { enqueue(entity) }
            }
            var prepared: [TokenEntity] = []
            for await entity in group {
                prepared.append(entity)
                if let next = pending.next() { enqueue(next) }
            }
            return prepared
        }
    }

    func delete(_ identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        try await CSSearchableIndex(name: Self.name).deleteAppEntities(identifiedBy: identifiers, ofType: TokenEntity.self)
    }

    func reset() async throws {
        try await CSSearchableIndex(name: Self.name).deleteAppEntities(ofType: TokenEntity.self)
    }
}

/// Stores public token metadata only. Queries do not need the wallet runtime,
/// an account, balances, or a network request. Donations may fetch thumbnails.
@available(iOS 18.4, *)
public actor TokenSpotlightStore {
    // Bump when computed Spotlight attributes change without changing entity metadata.
    private static let indexedContentVersion = 2

    public static let shared = TokenSpotlightStore(
        fileURL: (appGroupContainerUrl ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)?
            .appendingPathComponent("token-spotlight-v1.json")
    )

    private struct Snapshot: Codable {
        var entries: [TokenSpotlightEntry] = []
        // nil also migrates installations that used the old append-only index.
        var indexedEntries: [TokenSpotlightEntry]?
        var indexedContentVersion: Int?
        var recent: [TokenEntity] = []
    }

    private let fileURL: URL?
    private let index: any TokenSpotlightIndex
    private var snapshot: Snapshot
    private var operation: Task<Void, Error>?

    init(fileURL: URL?, index: any TokenSpotlightIndex = SystemTokenSpotlightIndex()) {
        self.fileURL = fileURL
        self.index = index
        snapshot = fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot(entries: Self.defaultEntries)
    }

    private static var defaultEntries: [TokenSpotlightEntry] {
        var tokens = ApiToken.defaultTokens
        for chain in ApiChain.allCases { tokens[chain.nativeToken.slug] = chain.nativeToken }
        return tokens.values.sorted { $0.slug < $1.slug }.map { .init(entity: .init(token: $0), priority: 2) }
    }

    /// Repair an interrupted batch, or donate the public baseline on first launch,
    /// without replacing an existing catalog before wallet data has loaded.
    public func resume() async throws {
        let previous = operation
        let next = Task {
            _ = await previous?.result
            self.snapshot = self.readSnapshot() ?? self.snapshot
            if self.snapshot.indexedEntries == nil || self.snapshot.indexedContentVersion != Self.indexedContentVersion {
                try await self.synchronize(self.snapshot.entries)
            }
        }
        operation = next
        try await next.value
    }

    public func entities() -> [TokenEntity] {
        // Queries can outlive the app process that most recently updated the catalog.
        let entries = (readSnapshot() ?? snapshot).entries
        var byID = Dictionary(entries.map { ($0.entity.id, $0.entity) }, uniquingKeysWith: { first, _ in first })
        for token in ApiToken.defaultTokens.values where byID[token.slug] == nil {
            byID[token.slug] = TokenEntity(token: token)
        }
        for chain in ApiChain.allCases where byID[chain.nativeToken.slug] == nil {
            byID[chain.nativeToken.slug] = TokenEntity(token: chain.nativeToken)
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    public func recentEntities() -> [TokenEntity] { (readSnapshot() ?? snapshot).recent }

    public func recordOpened(_ entity: TokenEntity) throws {
        snapshot.recent.removeAll { $0.id == entity.id }
        snapshot.recent.insert(entity, at: 0)
        snapshot.recent = Array(snapshot.recent.prefix(20))
        try persist()
    }

    public func clearRecent() throws {
        snapshot.recent = []
        try persist()
    }

    public func clearPersonalization() async throws {
        let previous = operation
        let next = Task {
            _ = await previous?.result
            self.snapshot.recent = []
            try self.persist()
            try await self.synchronize(Self.defaultEntries)
        }
        operation = next
        try await next.value
    }

    public func update(_ entries: [TokenSpotlightEntry]) async throws {
        // Actor isolation alone does not serialize operations across index awaits.
        // Chain them so a late donation cannot resurrect a deleted token.
        let previous = operation
        let next = Task {
            _ = await previous?.result
            try await self.synchronize(entries)
        }
        operation = next
        try await next.value
    }

    public func reindex(identifiers: [String]? = nil) async throws {
        let previous = operation
        let next = Task {
            _ = await previous?.result
            try await self.restore(identifiers: identifiers)
        }
        operation = next
        try await next.value
    }

    private func synchronize(_ entries: [TokenSpotlightEntry]) async throws {
        let desired = Dictionary(entries.map { ($0.entity.id, $0) }, uniquingKeysWith: { first, second in
            first.priority >= second.priority ? first : second
        }).values.sorted { $0.entity.id < $1.entity.id }
        let previouslyIndexed = snapshot.indexedContentVersion == Self.indexedContentVersion ? snapshot.indexedEntries : nil
        if let previouslyIndexed, previouslyIndexed.count == desired.count,
           zip(previouslyIndexed, desired).allSatisfy({ $0.hasSameContent(as: $1) }) {
            return
        }
        snapshot.entries = desired
        // An interrupted batch may have partially donated new IDs. Mark the index
        // dirty before writing so the next attempt also removes those orphan IDs.
        snapshot.indexedEntries = nil
        snapshot.indexedContentVersion = nil
        try persist()
        if let indexed = previouslyIndexed {
            let old = Dictionary(uniqueKeysWithValues: indexed.map { ($0.entity.id, $0) })
            let desiredIDs = Set(desired.map(\.entity.id))
            try await index.delete(indexed.map(\.entity.id).filter { !desiredIDs.contains($0) })
            try await index.index(desired.filter { entry in
                old[entry.entity.id].map { !entry.hasSameContent(as: $0) } ?? true
            })
        } else {
            try await index.reset()
            try await index.index(desired)
        }
        snapshot.indexedEntries = desired
        snapshot.indexedContentVersion = Self.indexedContentVersion
        try persist()
    }

    private func restore(identifiers: [String]?) async throws {
        snapshot = readSnapshot() ?? snapshot
        let entries = snapshot.entries
        if let identifiers {
            let requested = Set(identifiers)
            let current = Set(entries.map(\.entity.id))
            try await index.delete(identifiers.filter { !current.contains($0) })
            try await index.index(entries.filter { requested.contains($0.entity.id) })
        } else {
            snapshot.indexedEntries = nil
            snapshot.indexedContentVersion = nil
            try persist()
            try await index.reset()
            try await index.index(entries)
            snapshot.indexedEntries = entries
            snapshot.indexedContentVersion = Self.indexedContentVersion
            try persist()
        }
    }

    private func persist() throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private func readSnapshot() -> Snapshot? {
        fileURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }
}
