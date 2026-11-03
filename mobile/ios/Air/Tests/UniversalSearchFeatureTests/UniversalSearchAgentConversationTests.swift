import Foundation
import Testing
import UIUniversalSearch
import UniversalSearchCore
import WalletContext
import WalletCore
@testable import UniversalSearchFeature

@MainActor
@Suite("Universal Search Agent threads")
struct UniversalSearchAgentConversationTests {
    private let context = UniversalSearchContext(
        scopeID: "account",
        network: "mainnet",
        localeIdentifier: "en"
    )

    @Test
    func `list source contributes a document for every thread`() async throws {
        let first = try makeThread(id: "first", title: "Portfolio", lastActivityAt: "2026-10-18T10:00:00.250Z")
        let second = try makeThread(id: "second", title: "Staking", lastActivityAt: "2026-10-18T11:00:00Z")
        let loader = ThreadLoader(items: [
            .init(thread: first, preview: "Recent portfolio answer"),
            .init(thread: second),
        ])
        let source = UniversalSearchAgentConversationSource(loader: { query in await loader.load(query: query) })

        let snapshot = try await source.snapshot(for: context)

        #expect(await loader.queries == [nil])
        #expect(snapshot.documents.map(\.id.rawValue) == ["agent-chat:first", "agent-chat:second"])
        let document = try #require(snapshot.documents.first)
        #expect(document.fields == [
            SearchField("Portfolio", kind: .title),
            SearchField("Recent portfolio answer", kind: .description),
        ])
        #expect(document.attributeValue(for: UniversalSearchFeatureAttributeKey.title) == first.title)
        #expect(document.attributeValue(for: UniversalSearchFeatureAttributeKey.subtitle) == "Recent portfolio answer")
        #expect(document.signals.interaction?.lastSelectedAt == date(first.lastActivityAt))
        #expect(snapshot.documents[1].attributeValue(for: UniversalSearchFeatureAttributeKey.subtitle) == "")
    }

    @Test(arguments: ["validator rewards", "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"])
    func `server reply matches survive local filtering and disappear with the query snapshot`(queryText: String) async throws {
        let listedThread = try makeThread(id: "listed", title: "Portfolio")
        let olderThread = try makeThread(id: "older", title: "Staking")
        let listedItem = ApiAgentV2ThreadListItem(thread: listedThread, preview: "Latest answer")
        let remoteItems = [listedItem, ApiAgentV2ThreadListItem(thread: olderThread, preview: "Another answer")]
        let source = UniversalSearchAgentConversationSource(loader: { _ in [listedItem] })
        let coordinator = UniversalSearchCoordinator(sources: [source])
        try await coordinator.refresh(context: context)
        #expect(await coordinator.search(queryText).hits.isEmpty)

        let loader = ThreadLoader(items: remoteItems)
        let querySource = UniversalSearchAgentConversationQuerySource(
            loader: { query in await loader.load(query: query) },
            debounce: .zero
        )
        let query = UniversalSearchQuery(queryText)
        for try await snapshot in querySource.snapshots(for: query, context: context) {
            await coordinator.replace(snapshot)
        }
        let results = await coordinator.search(queryText)
        #expect(await loader.queries == [queryText])
        #expect(Set(results.hits.map(\.id.rawValue)) == ["agent-chat:listed", "agent-chat:older"])
        #expect(results.hits.allSatisfy { $0.match.fieldKind == .keyword })
        let presentation = UniversalSearchResultsPresenter().presentation(for: results, context: context)
        guard case .agentThread(let selectedThread) = try #require(presentation.routesByItemID["agent-chat:older"]) else {
            Issue.record("Expected the server result to open its thread")
            return
        }
        #expect(selectedThread == olderThread)

        await coordinator.remove(sourceID: querySource.sourceID)
        #expect(await coordinator.search(queryText).hits.isEmpty)
        #expect(await coordinator.browse().recentDocuments.map(\.id.rawValue) == ["agent-chat:listed"])
    }

    @Test
    func `changing a query before the debounce avoids a backend request`() async {
        let loader = ThreadLoader(items: [])
        let source = UniversalSearchAgentConversationQuerySource(
            loader: { query in await loader.load(query: query) },
            debounce: .seconds(1)
        )
        let stream = source.snapshots(for: UniversalSearchQuery("staking"), context: context)
        let consumer = Task {
            for try await _ in stream {}
        }
        await Task.yield()
        consumer.cancel()
        _ = await consumer.result

        #expect(await loader.queries.isEmpty)
    }

    @Test
    func `chat result opens its complete thread summary`() throws {
        let thread = try makeThread(id: "chosen", title: "My portfolio", isPinned: true)
        let document = try UniversalSearchAgentConversationSource.document(
            .init(thread: thread, preview: "Latest answer")
        )
        let query = UniversalSearchQuery("portfolio")
        let hits = UniversalSearchEngine().search(query, in: [document])
        let snapshot = UniversalSearchResultSnapshot(
            query: query,
            hits: hits,
            totalHitCount: hits.count,
            corpusRevision: 1,
            rankingPolicyVersion: "test",
            generatedAt: Date()
        )

        let presentation = UniversalSearchResultsPresenter().presentation(for: snapshot, context: context)
        guard case .agentThread(let selectedThread) = try #require(presentation.routesByItemID[document.id.rawValue]) else {
            Issue.record("Expected a thread route")
            return
        }
        #expect(selectedThread == thread)
        let item = try #require(presentation.sections.flatMap(\.items).first { $0.id == document.id.rawValue })
        guard case .chat(let result) = item.content else {
            Issue.record("Expected the existing chat row")
            return
        }
        #expect(result.title == "My portfolio")
        #expect(result.subtitle == "Latest answer")
        #expect(result.icon == "💬")
    }

    @Test
    func `browse lists pinned threads first, then by activity, ignoring selection history`() throws {
        let pinned = try makeThread(id: "pinned", title: "Pinned chat", lastActivityAt: "2026-10-18T10:00:00.250Z", isPinned: true)
        let older = try makeThread(id: "older", title: "Older chat", lastActivityAt: "2026-10-18T10:00:00.500Z")
        let latest = try makeThread(id: "latest", title: "Latest chat", lastActivityAt: "2026-10-18T10:00:00.750Z")
        var olderDocument = try UniversalSearchAgentConversationSource.document(.init(thread: older))
        olderDocument.signals.interaction = .init(lastSelectedAt: .distantFuture, selectionCount: 5)
        let snapshot = UniversalSearchBrowseEngine().snapshot(
            in: [
                olderDocument,
                try UniversalSearchAgentConversationSource.document(.init(thread: latest)),
                try UniversalSearchAgentConversationSource.document(.init(thread: pinned)),
            ],
            corpusRevision: 1
        )
        #expect(snapshot.recentDocuments.first?.id == olderDocument.id)

        let presentation = UniversalSearchResultsPresenter().browsePresentation(for: snapshot, context: context)
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.map(\.id) == ["agent-chat:pinned", "agent-chat:latest", "agent-chat:older"])
        guard case .list = chats.layout else {
            Issue.record("Expected a list layout")
            return
        }
        for thread in [pinned, latest, older] {
            guard case .agentThread(let selectedThread) = try #require(presentation.routesByItemID["agent-chat:\(thread.id)"]) else {
                Issue.record("Expected a thread route for \(thread.id)")
                return
            }
            #expect(selectedThread == thread)
        }
        #expect(presentation.routesByItemID["agent-chat:start"] == nil)
    }

    @Test
    func `browse pages up to nine recent threads`() throws {
        let documents = try (0..<12).map { index in
            try UniversalSearchAgentConversationSource.document(.init(thread: makeThread(
                id: "thread-\(index)",
                title: "Chat \(index)",
                lastActivityAt: String(format: "2026-10-18T10:00:%02dZ", index)
            )))
        }
        let snapshot = UniversalSearchBrowseEngine().snapshot(in: documents, corpusRevision: 1)

        let presentation = UniversalSearchResultsPresenter().browsePresentation(for: snapshot, context: context)
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.map(\.id) == (3..<12).reversed().map { "agent-chat:thread-\($0)" })
        guard case .paged(let rowsPerPage) = chats.layout else {
            Issue.record("Expected a paged layout")
            return
        }
        #expect(rowsPerPage == 3)
    }

    @Test
    func `browse pages from four threads`() throws {
        let documents = try (0..<4).map { index in
            try UniversalSearchAgentConversationSource.document(.init(thread: makeThread(
                id: "thread-\(index)",
                title: "Chat \(index)",
                lastActivityAt: String(format: "2026-10-18T10:00:%02dZ", index)
            )))
        }
        let snapshot = UniversalSearchBrowseEngine().snapshot(in: documents, corpusRevision: 1)

        let presentation = UniversalSearchResultsPresenter().browsePresentation(for: snapshot, context: context)
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.count == 4)
        guard case .paged(let rowsPerPage) = chats.layout else {
            Issue.record("Expected a paged layout")
            return
        }
        #expect(rowsPerPage == 3)
    }

    @Test
    func `untitled threads use New Chat and a single-line preview`() throws {
        for title in [nil, "  "] {
            let document = try UniversalSearchAgentConversationSource.document(.init(
                thread: makeThread(id: "untitled", title: title),
                preview: "  First line\n\nsecond   line "
            ))
            #expect(document.attributeValue(for: UniversalSearchFeatureAttributeKey.title) == lang("New Chat"))
            #expect(document.attributeValue(for: UniversalSearchFeatureAttributeKey.subtitle) == "First line second line")
        }
    }

    @Test
    func `threads without an emoji keep the default chat symbol`() throws {
        for icon in [nil, "", " "] {
            let document = try UniversalSearchAgentConversationSource.document(.init(
                thread: makeThread(id: "plain", title: "Plain chat", icon: icon)
            ))
            let snapshot = UniversalSearchBrowseEngine().snapshot(in: [document], corpusRevision: 1)

            let presentation = UniversalSearchResultsPresenter().browsePresentation(for: snapshot, context: context)
            let item = try #require(presentation.sections.first { $0.id == "chats" }?.items.first)
            guard case .chat(let result) = item.content else {
                Issue.record("Expected a chat row")
                return
            }
            #expect(result.icon == nil)
        }
    }

    @Test
    func `browse with no chats keeps Ask Agent`() throws {
        let snapshot = UniversalSearchBrowseEngine().snapshot(in: [], corpusRevision: 1)
        let presentation = UniversalSearchResultsPresenter().browsePresentation(for: snapshot, context: context)
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.map(\.id) == ["agent-chat:start"])
        guard case .agent(let query, _) = try #require(presentation.routesByItemID["agent-chat:start"]) else {
            Issue.record("Expected the default Agent entry")
            return
        }
        #expect(query == nil)
    }

    @Test
    func `browse switches one chats section between recent chats and suggestions`() async throws {
        let thread = try makeThread(id: "chat", title: "Portfolio")
        let suggestionSource = UniversalSearchAgentSuggestionSource { _ in
            [
                .init(
                    id: "portfolio.performance",
                    catalogVersion: "agent-starter-hints-v1",
                    title: "Track my portfolio",
                    prompt: "Analyze my wallet portfolio."
                )
            ]
        }
        let suggestionDocuments = try await suggestionSource.snapshot(for: context).documents
        let snapshot = UniversalSearchBrowseSnapshot(
            recentDocuments: [try UniversalSearchAgentConversationSource.document(.init(thread: thread))],
            trendingDocuments: suggestionDocuments,
            corpusRevision: 1,
            corpusDocumentCount: 2,
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let presenter = UniversalSearchResultsPresenter()
        let suggestionID = "agent-suggestion:portfolio.performance"

        let recent = presenter.browsePresentation(for: snapshot, context: context)
        #expect(recent.sections.filter { $0.id == "chats" }.count == 1)
        let recentChats = try #require(recent.sections.first)
        #expect(recentChats.id == "chats")
        guard case .toggle(let primary, let secondary, .primary) = recentChats.headerAccessory else {
            Issue.record("Expected Recent to be selected by default")
            return
        }
        #expect(primary == lang("$universal_search_recent"))
        #expect(secondary == lang("Suggest"))
        #expect(recentChats.items.map(\.id) == ["agent-chat:chat"])
        #expect(!recent.sections.flatMap(\.items).contains { $0.id == suggestionID })
        #expect(recent.routesByItemID[suggestionID] == nil)

        let suggested = presenter.browsePresentation(
            for: snapshot,
            selectedModes: ["chats": .trending],
            context: context
        )
        let suggestedChats = try #require(suggested.sections.first)
        #expect(suggestedChats.id == "chats")
        guard case .toggle(_, _, .secondary) = suggestedChats.headerAccessory,
              case .promptPages(let rowsPerPage) = suggestedChats.layout else {
            Issue.record("Expected Suggest to show prompt pages")
            return
        }
        #expect(rowsPerPage == 3)
        #expect(suggestedChats.showsHeader)
        #expect(suggestedChats.items.map(\.id) == [suggestionID])
        #expect(!suggested.sections.flatMap(\.items).contains { $0.id == "agent-chat:chat" })
        guard case .agent(let prompt, _) = try #require(suggested.routesByItemID[suggestionID]) else {
            Issue.record("Expected the suggestion to open Agent")
            return
        }
        #expect(prompt == "Analyze my wallet portfolio.")
        #expect(suggested.routesByItemID["agent-chat:chat"] == nil)
    }

    @Test
    func `browse chats without suggestions label the recent list`() throws {
        let document = try UniversalSearchAgentConversationSource.document(.init(
            thread: makeThread(id: "chat", title: "Portfolio")
        ))
        let snapshot = UniversalSearchBrowseEngine().snapshot(in: [document], corpusRevision: 1)

        let presentation = UniversalSearchResultsPresenter().browsePresentation(
            for: snapshot,
            selectedModes: ["chats": .trending],
            context: context
        )
        let chats = try #require(presentation.sections.first { $0.id == "chats" })
        #expect(chats.items.map(\.id) == ["agent-chat:chat"])
        guard case .text(let text) = chats.headerAccessory else {
            Issue.record("Expected a Recent label")
            return
        }
        #expect(text == lang("$universal_search_recent"))
    }

    private func makeThread(
        id: String,
        title: String?,
        lastActivityAt: String = "2026-10-18T10:00:00Z",
        isPinned: Bool = false,
        icon: String? = "💬"
    ) throws -> ApiAgentV2ThreadSummary {
        var value: [String: Any] = [
            "id": id,
            "revision": 1,
            "createdAt": "2026-10-18T09:00:00Z",
            "updatedAt": lastActivityAt,
            "lastActivityAt": lastActivityAt,
            "messageCount": 2,
            "hasCustomTitle": true,
        ]
        if let title { value["title"] = title }
        if let icon { value["icon"] = icon }
        if isPinned { value["isPinned"] = true }
        return try JSONDecoder().decode(
            ApiAgentV2ThreadSummary.self,
            from: JSONSerialization.data(withJSONObject: value)
        )
    }

    private func date(_ value: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
}

private actor ThreadLoader {
    private let items: [ApiAgentV2ThreadListItem]
    private(set) var queries: [String?] = []

    init(items: [ApiAgentV2ThreadListItem]) {
        self.items = items
    }

    func load(query: String?) -> [ApiAgentV2ThreadListItem] {
        queries.append(query)
        return items
    }
}
