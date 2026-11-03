import XCTest
@testable import UIAgent
import WalletCore

@MainActor
final class AgentNewsFeedTests: XCTestCase {
    func testPagesMergeByEventIdKeepingNewerDeliveryAndChronologicalOrder() async {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        let first = item(1, hour: 11)
        let second = item(2, hour: 12)
        let updated = item(1, hour: 13)
        client.pages = [
            .success(page([second, first], cursor: "older")),
            .success(page([item(3, hour: 10), updated, item(2, hour: 9)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: state, language: { "pt-BR" })

        await model.refresh()
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.eventId), [3, 2, 1])
        XCTAssertEqual(model.items.last?.deliveredAt, updated.deliveredAt)
        XCTAssertEqual(model.items.first { $0.eventId == 2 }?.deliveredAt, second.deliveredAt)
        XCTAssertEqual(client.requests.map(\.lang), ["pt-BR", "pt-BR"])
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older"])
    }

    func testOpeningCapturesOldestUnreadBeforeAdvancingPersistentMark() async {
        let state = makeReadState()
        state.markRead(items: [item(1, hour: 10)])
        let client = NewsFeedTestClient()
        client.pages = [.success(page([item(3, hour: 12), item(2, hour: 11), item(1, hour: 10)]))]
        let model = AgentNewsFeedModel(client: client, readState: state)

        await model.refresh()

        XCTAssertEqual(model.unreadEventId, 2)
        XCTAssertEqual(state.readThrough, item(3, hour: 12).deliveredAt)
        XCTAssertEqual(state.unreadCount(items: model.items), 0)
        XCTAssertEqual(model.items.firstIndex { $0.eventId == model.unreadEventId }, 1)
    }

    func testFirstLoadInitializesMarkWithoutUnreadAndNeverMovesItBackwards() async {
        let state = makeReadState()
        let client = NewsFeedTestClient()
        client.pages = [.success(page([item(2, hour: 12), item(1, hour: 11)]))]
        let model = AgentNewsFeedModel(client: client, readState: state)

        await model.refresh()

        XCTAssertNil(model.unreadEventId)
        XCTAssertEqual(state.readThrough, item(2, hour: 12).deliveredAt)
        state.markRead(items: [item(1, hour: 11)])
        XCTAssertEqual(state.readThrough, item(2, hour: 12).deliveredAt)
    }

    func testUnreadCountUsesDeliveryDatesAndUniqueIdsWithoutCap() {
        let state = makeReadState()
        state.markRead(items: [item(0, hour: 10)])
        let mixed = [item(0, hour: 10), item(1, hour: 11), item(1, hour: 12), item(2, hour: 9)]

        XCTAssertEqual(state.unreadCount(items: mixed), 1)
        let longPage = (1...45).map { item($0, hour: 11) }
        XCTAssertEqual(state.unreadCount(items: longPage), 45)
        state.markRead(items: longPage)
        XCTAssertEqual(state.unreadCount(items: longPage), 0)
    }

    func testReadMarkPersistsAcrossReadStateInstances() {
        let defaults = makeDefaults()
        let state = AgentNewsReadState(userDefaults: defaults)
        state.initializeIfNeeded(items: [item(1, hour: 10), item(2, hour: 11)])
        let restored = AgentNewsReadState(userDefaults: defaults)

        XCTAssertEqual(restored.readThrough, item(2, hour: 11).deliveredAt)
        XCTAssertEqual(restored.unreadCount(items: [item(3, hour: 12)]), 1)
    }

    func testRefreshAddsNewsAtBottomAndTracksUnreadCutoffAcrossOlderPages() async {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        state.markRead(items: [item(1, hour: 9)])
        client.pages = [
            .success(page([item(3, hour: 12)], cursor: "older")),
            .success(page([item(2, hour: 11)])),
            .success(page([item(4, hour: 13), item(3, hour: 12)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: state)
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.unreadEventId, 2)
        await model.refresh()

        XCTAssertEqual(model.items.map(\.eventId), [2, 3, 4])
        XCTAssertEqual(model.unreadEventId, 2)
        XCTAssertEqual(state.readThrough, item(4, hour: 13).deliveredAt)
    }

    func testOlderPagesAdvanceReadMarkWithoutChangingOriginalUnreadCutoff() async {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        state.markRead(items: [item(0, hour: 10)])
        client.pages = [
            .success(page([item(3, hour: 12)], cursor: "older")),
            .success(page([item(3, hour: 13), item(2, hour: 11)], cursor: "oldest")),
            .success(page([item(1, hour: 9)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: state)

        await model.refresh()
        XCTAssertEqual(state.readThrough, item(3, hour: 12).deliveredAt)
        XCTAssertEqual(model.unreadEventId, 3)

        await model.loadMore()
        XCTAssertEqual(state.readThrough, item(3, hour: 13).deliveredAt)
        XCTAssertEqual(model.unreadEventId, 2)

        await model.loadMore()
        XCTAssertEqual(state.readThrough, item(3, hour: 13).deliveredAt)
        XCTAssertEqual(model.unreadEventId, 2)
        XCTAssertEqual(model.items.map(\.eventId), [1, 2, 3])
    }

    func testOlderPageFailureIsSilentAndCanRetrySameCursor() async {
        let client = NewsFeedTestClient()
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "older")),
            .failure(NewsFeedTestError.unavailable),
            .success(page([item(1, hour: 11)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.loadMore()
        XCTAssertNil(model.error)
        XCTAssertEqual(model.nextCursor, "older")
        XCTAssertFalse(model.isLoadingMore)

        await model.loadMore()

        XCTAssertEqual(model.items.map(\.eventId), [1, 2])
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older", "older"])
    }

    func testInitialFailureCanRetryAndRefreshFailureKeepsCachedItems() async {
        let client = NewsFeedTestClient()
        client.pages = [
            .failure(NewsFeedTestError.unavailable),
            .success(page([item(1, hour: 12)])),
            .failure(NewsFeedTestError.unavailable)
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isLoading)
        await model.refresh()
        XCTAssertNil(model.error)
        // A failed refresh keeps the news shown, and the feed shows the failure under them
        await model.refresh()
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.items.map(\.eventId), [1])
    }

    func testRefreshPaginationTraversesDuplicatePagesAndStopsRepeatedCursor() async {
        let client = NewsFeedTestClient()
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "first")),
            .success(page([item(1, hour: 11)])),
            .success(page([item(3, hour: 13)], cursor: "first")),
            .success(page([item(2, hour: 12)], cursor: "second")),
            .success(page([item(1, hour: 11)], cursor: "second"))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.loadMore()
        await model.refresh()
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.eventId), [1, 2, 3])
        XCTAssertNil(model.nextCursor)
        XCTAssertEqual(client.requests.count, 5)
    }

    func testCancellationClearsLoadingAndKeepsCursorForRetry() async throws {
        let client = NewsFeedTestClient()
        client.shouldSuspend = true
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        let refresh = Task { await model.refresh() }
        try await waitUntil { client.pendingResponse != nil }
        refresh.cancel()
        client.resume(with: page([item(2, hour: 12)], cursor: "older"))
        await refresh.value
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.items.isEmpty)

        client.pages = [.success(page([item(2, hour: 12)], cursor: "older"))]
        client.shouldSuspend = false
        await model.refresh()
        client.shouldSuspend = true
        let older = Task { await model.loadMore() }
        try await waitUntil { client.pendingResponse != nil }
        older.cancel()
        client.resume(with: page([item(1, hour: 11)]))
        await older.value

        XCTAssertFalse(model.isLoadingMore)
        XCTAssertEqual(model.nextCursor, "older")
        XCTAssertEqual(model.items.map(\.eventId), [2])
    }

    func testPaginationKeepsLanguageOfItsCursorUntilRefresh() async {
        let client = NewsFeedTestClient()
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "older")),
            .success(page([item(1, hour: 11)])),
            .success(ApiAgentV2NewsFeedPage(locale: "ru", items: [item(3, hour: 13)]))
        ]
        var language = "en"
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), language: { language })
        await model.refresh()
        XCTAssertEqual(model.locale, "en")
        language = "ru-RU"
        await model.loadMore()
        XCTAssertEqual(model.locale, "en")
        await model.refresh()

        XCTAssertEqual(client.requests.map(\.lang), ["en", "en", "ru-RU"])
        XCTAssertEqual(model.items.map(\.eventId), [3])
        XCTAssertEqual(model.locale, "ru")
    }

    func testLocaleChangeClearsLocallyOpenedDiscussion() async throws {
        let client = NewsFeedTestClient()
        let news = item(1, hour: 12)
        client.pages = [
            .success(page([news])),
            .success(ApiAgentV2NewsFeedPage(locale: "ru", items: [news]))
        ]
        var language = "en"
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), language: { language })
        await model.refresh()
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"discussion-thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
         "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":1}
        """.utf8))
        model.markDiscussion(eventId: news.eventId, thread: thread)
        XCTAssertEqual(model.items.first?.discussion?.threadId, thread.id)

        language = "ru"
        await model.refresh()

        XCTAssertEqual(model.locale, "ru")
        XCTAssertEqual(model.items.map(\.eventId), [news.eventId])
        XCTAssertNil(model.items.first?.discussion)
    }

    func testOpeningDiscussionOnOlderPageUpdatesLocallyAndSurvivesStaleRefresh() async throws {
        let client = NewsFeedTestClient()
        let older = item(1, hour: 10)
        client.pages = [
            .success(page([item(3, hour: 12)], cursor: "older")),
            .success(page([older])),
            .success(page([item(4, hour: 13), item(3, hour: 12)])),
            .success(page([item(1, hour: 10, discussion: .init(threadId: "discussion-thread", icon: "📰")), item(3, hour: 12)])),
            .success(page([older, item(3, hour: 12)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.loadMore()
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"discussion-thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
         "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":0}
        """.utf8))
        var updates = 0
        model.onChange = { updates += 1 }

        model.markDiscussion(eventId: older.eventId, thread: thread)

        XCTAssertEqual(updates, 1)
        XCTAssertEqual(model.items.first?.discussion, .init(threadId: thread.id))
        XCTAssertEqual(model.items.first?.headline, older.headline)
        XCTAssertEqual(model.items.first?.body, older.body)
        await model.refresh()
        XCTAssertEqual(model.items.map(\.eventId), [1, 3, 4])
        XCTAssertEqual(model.items.first?.discussion?.threadId, thread.id)
        await model.refresh()
        XCTAssertEqual(model.items.first?.discussion, .init(threadId: thread.id, icon: "📰"))
        await model.refresh()
        XCTAssertEqual(model.items.first?.discussion, .init(threadId: thread.id, icon: "📰"))
    }

    func testThreadDeletionClearsLocalAndServerDiscussionsAndRefreshDoesNotRestoreOverlay() async throws {
        let client = NewsFeedTestClient()
        let older = item(1, hour: 10)
        let retained = item(3, hour: 12, discussion: .init(threadId: "retained-thread", icon: "💡"))
        client.pages = [
            .success(page([retained, item(2, hour: 11, discussion: .init(threadId: "server-thread", icon: "🛡️"))], cursor: "older")),
            .success(page([older])),
            .success(page([retained, item(2, hour: 11)])),
            .success(page([retained, item(2, hour: 11), older]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.loadMore()
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"local-thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
         "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":0,"icon":"📰"}
        """.utf8))
        model.markDiscussion(eventId: older.eventId, thread: thread)
        var updates = 0
        model.onChange = { updates += 1 }

        model.removeDiscussion(threadId: thread.id)

        XCTAssertEqual(updates, 1)
        XCTAssertNil(model.items.first?.discussion)
        XCTAssertEqual(model.items.first { $0.eventId == 2 }?.discussion?.threadId, "server-thread")
        model.removeDiscussion(threadId: "server-thread")
        XCTAssertEqual(updates, 2)
        XCTAssertNil(model.items.first { $0.eventId == 2 }?.discussion)
        XCTAssertEqual(model.items.last?.discussion, retained.discussion)

        await model.refresh()
        XCTAssertNil(model.items.first?.discussion)
        XCTAssertNil(model.items.first { $0.eventId == 2 }?.discussion)
        await model.refresh()
        XCTAssertNil(model.items.first?.discussion)
        XCTAssertNil(model.items.first { $0.eventId == 2 }?.discussion)
        XCTAssertEqual(model.items.last?.discussion, retained.discussion)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("News request did not start within 1 second")
        throw NewsFeedTestError.unavailable
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AgentNewsFeedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeReadState() -> AgentNewsReadState {
        AgentNewsReadState(userDefaults: makeDefaults())
    }

    private func item(_ id: Int, hour: Int, discussion: ApiAgentV2NewsFeedItem.Discussion? = nil) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: id,
            deliveredAt: String(format: "2026-10-20T%02d:00:00Z", hour),
            headline: "News \(id)",
            body: "**Body** \(id)",
            sources: [],
            discussion: discussion
        )
    }

    private func page(_ items: [ApiAgentV2NewsFeedItem], cursor: String? = nil) -> ApiAgentV2NewsFeedPage {
        ApiAgentV2NewsFeedPage(locale: "en", items: items, nextCursor: cursor)
    }
}

private enum NewsFeedTestError: Error {
    case unavailable
}

@MainActor
private final class NewsFeedTestClient: AgentNewsFeedClient {
    var pages: [Result<ApiAgentV2NewsFeedPage, Error>] = []
    var requests: [(lang: String, cursor: String?)] = []
    var shouldSuspend = false
    var pendingResponse: CheckedContinuation<ApiAgentV2NewsFeedPage, Never>?

    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage {
        requests.append((lang, cursor))
        if shouldSuspend {
            return await withCheckedContinuation { pendingResponse = $0 }
        }
        guard !pages.isEmpty else { throw NewsFeedTestError.unavailable }
        return try pages.removeFirst().get()
    }

    func resume(with page: ApiAgentV2NewsFeedPage) {
        pendingResponse?.resume(returning: page)
        pendingResponse = nil
    }
}
