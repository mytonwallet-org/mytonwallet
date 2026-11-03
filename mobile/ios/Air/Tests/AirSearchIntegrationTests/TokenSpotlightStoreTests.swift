import Foundation
import ImageIO
import Testing
import WalletResources
@testable import WalletCoreTypes

@Suite("Token Spotlight catalog")
struct TokenSpotlightStoreTests {
    @Test
    @MainActor
    func nativeLogosAreIncludedInIndexedAttributes() throws {
        guard #available(iOS 18.4, *) else { return }
        _ = WalletResourcesBundle.bundle.load()
        for chain in ApiChain.allCases {
            let entity = TokenEntity(token: chain.nativeToken)
            let data = try #require(entity.attributeSet.thumbnailData)
            let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width > 0 && image.width <= 120)
            #expect(image.height > 0 && image.height <= 120)
        }
    }

    @Test(arguments: [nil, 0, 1] as [Int?])
    func oldIndexedContentIsRefreshedOnlyOnce(version: Int?) async throws {
        guard #available(iOS 18.4, *) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let token = TokenEntity(token: ApiChain.solana.nativeToken)
        let entries = [TokenSpotlightEntry(entity: token, priority: 2)]
        let index = RecordingTokenIndex()
        let store = TokenSpotlightStore(fileURL: url, index: index)
        try await store.update(entries)
        try await store.recordOpened(token)

        var saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        saved["indexedContentVersion"] = version
        try JSONSerialization.data(withJSONObject: saved).write(to: url, options: .atomic)

        let restarted = TokenSpotlightStore(fileURL: url, index: index)
        // A system request for one item must not acknowledge a whole-catalog migration.
        try await restarted.reindex(identifiers: [token.id])
        await index.clearEvents()
        try await restarted.resume()
        #expect(await index.events == ["reset", "index:\(token.id)"])
        #expect(await restarted.recentEntities().map(\.id) == [token.id])

        await index.clearEvents()
        try await restarted.update(entries)
        try await restarted.resume()
        let nextLaunch = TokenSpotlightStore(fileURL: url, index: index)
        try await nextLaunch.resume()
        try await nextLaunch.update(entries)
        #expect(await index.events.isEmpty)
    }

    @Test
    func queriesReadUpdatesFromAnotherStoreInstance() async throws {
        guard #available(iOS 18.4, *) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("catalog.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = TokenSpotlightStore(fileURL: url, index: RecordingTokenIndex())
        let reader = TokenSpotlightStore(fileURL: url, index: RecordingTokenIndex())
        let token = ApiToken(slug: "non-default-token", name: "Saved Token", symbol: "SAVED", decimals: 6, chain: .ton)
        try await writer.update([.init(entity: .init(token: token), priority: 8)])
        #expect(await reader.entities().contains { $0.id == token.slug })
        try await writer.update([])
        #expect(await reader.entities().allSatisfy { $0.id != token.slug })
    }

    @Test
    func metadataChangesAndDeletionsAreIndexedButPricesAreNot() async throws {
        guard #available(iOS 18.4, *) else { return }
        let index = RecordingTokenIndex()
        let store = TokenSpotlightStore(fileURL: nil, index: index)
        var token = ApiToken(slug: "test-token", name: "Example", symbol: "EX", decimals: 6, chain: .ton, priceUsd: 1)
        func entry() -> TokenSpotlightEntry { .init(entity: .init(token: token), priority: 8) }
        try await store.update([entry(), entry()])
        #expect(await index.ids == [token.slug])
        await index.clearEvents()
        token.priceUsd = 2
        try await store.update([entry()])
        #expect(await index.events.isEmpty)
        var prepared = entry().entity
        prepared.indexedThumbnailData = Data([1, 2, 3])
        try await store.update([.init(entity: prepared, priority: 8)])
        #expect(await index.events.isEmpty)
        let restored = try JSONDecoder().decode(TokenEntity.self, from: JSONEncoder().encode(prepared))
        #expect(restored.indexedThumbnailData == nil)
        token.name = "Renamed"
        try await store.update([entry()])
        #expect(await index.events == ["index:test-token"])
        await index.clearEvents()
        try await store.update([])
        #expect(await index.ids.isEmpty)
        #expect(await index.events == ["delete:test-token"])
    }

    @Test
    func coldReindexUsesPersistedMetadataAndRemovesMissingIDs() async throws {
        guard #available(iOS 18.4, *) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let token = TokenEntity(token: ApiChain.solana.nativeToken)
        let store = TokenSpotlightStore(fileURL: url, index: RecordingTokenIndex())
        try await store.update([.init(entity: token, priority: 2)])
        let index = RecordingTokenIndex()
        let coldStore = TokenSpotlightStore(fileURL: url, index: index)
        try await coldStore.reindex(identifiers: [token.id, "removed-token"])
        #expect(await index.ids == [token.id])
        #expect(await index.events.contains("delete:removed-token"))
        #expect(await coldStore.entities().contains { $0.id == token.id && $0.name == token.name })
        await index.clearEvents()
        try await coldStore.reindex()
        #expect(await index.events.first == "reset")
        #expect(await index.ids == [token.id])
    }

    @Test
    func interruptedDonationIsRepairedAfterRestart() async throws {
        guard #available(iOS 18.4, *) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let index = RecordingTokenIndex()
        let store = TokenSpotlightStore(fileURL: url, index: index)
        await index.failNextDonation()
        do {
            try await store.update([.init(entity: .init(token: ApiChain.solana.nativeToken), priority: 2)])
            Issue.record("Expected the simulated partial donation to fail")
        } catch {}
        let restarted = TokenSpotlightStore(fileURL: url, index: index)
        await index.clearEvents()
        try await restarted.update([])
        #expect(await index.ids.isEmpty)
        #expect(await index.events == ["reset"])
    }

    @Test
    func recentsAreBoundedDeduplicatedAndClearable() async throws {
        guard #available(iOS 18.4, *) else { return }
        let store = TokenSpotlightStore(fileURL: nil, index: RecordingTokenIndex())
        for n in 0..<25 {
            try await store.recordOpened(.init(token: ApiToken(slug: "token-\(n)", name: "Token", symbol: "T", decimals: 6, chain: .ton)))
        }
        #expect(await store.recentEntities().count == 20)
        let recent = try #require(await store.recentEntities().last)
        try await store.recordOpened(recent)
        #expect(await store.recentEntities().count == 20)
        #expect(await store.recentEntities().first?.id == recent.id)
        try await store.clearRecent()
        #expect(await store.recentEntities().isEmpty)
    }
}

@available(iOS 18.4, *)
private actor RecordingTokenIndex: TokenSpotlightIndex {
    var events: [String] = []
    var ids: Set<String> = []
    private var shouldFail = false

    func clearEvents() { events = [] }
    func failNextDonation() { shouldFail = true }

    func index(_ entries: [TokenSpotlightEntry]) throws {
        for entry in entries {
            events.append("index:\(entry.entity.id)")
            ids.insert(entry.entity.id)
        }
        if shouldFail {
            shouldFail = false
            throw NSError(domain: "TestIndex", code: 1)
        }
    }

    func delete(_ identifiers: [String]) {
        for id in identifiers {
            events.append("delete:\(id)")
            ids.remove(id)
        }
    }

    func reset() {
        events.append("reset")
        ids = []
    }
}
