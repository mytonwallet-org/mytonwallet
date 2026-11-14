import UIKit
import XCTest
@testable import UIAgent
@testable import WalletCore
import WalletContext

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

        client.shouldSuspend = false
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "older")),
            .success(page([item(0, hour: 9)]))
        ]
        await model.refresh()
        client.shouldSuspend = true
        let prefetch = try XCTUnwrap(model.prefetchTask)
        try await waitUntil { client.pendingResponse != nil }
        let requestCount = client.requests.count
        model.cancelPrefetch()
        client.shouldSuspend = false
        client.resume(with: page([item(1, hour: 11)], cursor: "oldest"))
        await prefetch.value

        XCTAssertEqual(client.requests.count, requestCount)
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
        let naming = ApiAgentV2NewsFeedItem.DiscussionNaming(title: "Discuss news", icon: "📰", followups: ["What changed?"])
        let older = ApiAgentV2NewsFeedItem(
            eventId: 1,
            deliveredAt: "2026-10-20T10:00:00Z",
            headline: "News 1",
            body: "**Body** 1",
            discussionNaming: naming
        )
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
        XCTAssertEqual(model.items.first?.discussionNaming, naming)
        var updates = 0
        model.onChange = { updates += 1 }

        model.removeDiscussion(threadId: thread.id)

        XCTAssertEqual(updates, 1)
        XCTAssertNil(model.items.first?.discussion)
        XCTAssertEqual(model.items.first?.discussionNaming, naming)
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

    func testDigestsViewLoadsFirstAndOlderPagesUntilHistoryEnds() async throws {
        let client = NewsFeedTestClient()
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let newest = try makeDigest(day: 20)
        let older = try makeDigest(day: 19)
        client.shouldSuspendNext = true
        client.pages = [.success(page([], digests: [older]))]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), digestSettings: settings, timeZone: { "UTC" })
        let refresh = Task { await model.refresh() }
        try await waitUntil { client.pendingResponse != nil }
        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.entries.isEmpty)
        client.resume(with: page([], cursor: "older-digests", digests: [newest]))
        await refresh.value
        await model.prefetchTask?.value
        XCTAssertEqual(model.entries, [.digest(newest)])
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(model.nextCursor, "older-digests")

        await model.loadMore()
        XCTAssertEqual(model.entries, [.digest(older), .digest(newest)])
        XCTAssertNil(model.nextCursor)
        await model.loadMore()
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older-digests"])
        XCTAssertEqual(client.requests.map(\.view), [.digests, .digests])
        XCTAssertEqual(client.requests.map(\.digestHour), [21, 21])
        XCTAssertEqual(client.requests.map(\.timeZone), ["UTC", "UTC"])
    }

    func testDigestsFailedRefreshKeepsTheLoadedListAndItsCursor() async throws {
        let client = NewsFeedTestClient()
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let digest = try makeDigest(day: 20)
        client.pages = [
            .success(page([], cursor: "older", digests: [digest])),
            .failure(NewsFeedTestError.unavailable)
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), digestSettings: settings)
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(model.entries, [.digest(digest)])
        XCTAssertEqual(model.nextCursor, "older")
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(client.requests.map(\.cursor), [nil, nil])
    }

    func testDigestsReloadAfterTimeOrTimeZoneChangesAndDiscardAnOlderResponse() async throws {
        for change in ["hour", "minute", "timeZone"] {
            let client = NewsFeedTestClient()
            let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
            settings.setNewsFeedView(.digests)
            var timeZone = "UTC"
            let evening = try makeDigest(day: 20)
            let morning = ApiAgentV2NewsFeedDigest(id: "en:morning", deliveredAt: "2026-10-20T06:00:00Z", top: [], total: 1)
            client.pages = [.success(page([], cursor: "old-schedule", digests: [evening]))]
            let model = AgentNewsFeedModel(
                client: client, readState: makeReadState(), digestSettings: settings, timeZone: { timeZone }
            )
            await model.refresh()
            client.shouldSuspendNext = true
            let older = Task { await model.loadMore() }
            try await waitUntil { client.pendingResponse != nil }
            switch change {
            case "hour": _ = await settings.setDigestTime(hour: 9, minute: 0)
            case "minute": _ = await settings.setDigestTime(hour: 21, minute: 45)
            default: timeZone = "Europe/Moscow"
            }
            client.pages = [.failure(NewsFeedTestError.unavailable)]
            await model.refresh()
            XCTAssertEqual(model.digests, [evening], change)
            XCTAssertNotNil(model.error, change)
            let requestCount = client.requests.count
            await model.loadMore()
            XCTAssertEqual(client.requests.count, requestCount, change)
            client.pages = [.success(page([], digests: [morning]))]
            await model.refresh()
            client.resume(with: page([], cursor: "stale", digests: [try makeDigest(day: 19)]))
            await older.value
            XCTAssertEqual(model.digests, [morning], change)
            XCTAssertNil(model.nextCursor, change)
            XCTAssertNil(model.error, change)
            XCTAssertEqual(client.requests.last?.cursor, nil, change)
            XCTAssertEqual(client.requests.last?.digestHour, settings.digestHour, change)
            XCTAssertEqual(client.requests.last?.digestMinute, settings.digestMinute, change)
            XCTAssertEqual(client.requests.last?.timeZone, timeZone, change)
        }
    }

    func testDigestsKeepAllNewsUnreadAndSwitchBackToTheCachedLists() async throws {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        let read = item(1, hour: 10)
        let unread = item(2, hour: 12)
        state.markRead(items: [read])
        let digest = try makeDigest(day: 20)
        let allPage = page([unread, read], digests: [digest])
        client.pages = [.success(allPage), .success(page([], digests: [digest]))]
        let threads = AgentThreadListModel(newsClient: client, readState: state)
        await threads.refreshNews()
        XCTAssertEqual(threads.newsUnreadCount, 1)
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let model = AgentNewsFeedModel(
            client: client, readState: state,
            cachedPage: .init(page: allPage, language: "en", schedule: .init(hour: 21, minute: 0, timeZone: "UTC")),
            digestSettings: settings, timeZone: { "UTC" }
        )
        XCTAssertTrue(model.entries.isEmpty)
        await model.refresh()
        XCTAssertEqual(threads.newsUnreadCount, 1)
        XCTAssertEqual(state.readThrough, read.deliveredAt)
        XCTAssertNil(model.unreadEventId)
        XCTAssertEqual(model.entries, [.digest(digest)])
        model.setView(.all)
        XCTAssertEqual(model.entries, [.news(read), .digest(digest), .news(unread)])
        XCTAssertEqual(model.unreadEventId, unread.eventId)
        XCTAssertEqual(threads.newsUnreadCount, 0)
        let newlyDelivered = item(3, hour: 13)
        let newAllPage = page([newlyDelivered, unread, read], digests: [digest])
        client.shouldSuspendNext = true
        let allRefresh = Task { await model.refresh() }
        try await waitUntil { client.pendingResponse != nil }
        model.setView(.digests)
        XCTAssertEqual(model.entries, [.digest(digest)])
        client.resume(with: newAllPage)
        await allRefresh.value
        client.pages = [.success(newAllPage)]
        await threads.refreshNews()
        XCTAssertEqual(threads.newsUnreadCount, 1)
        XCTAssertEqual(state.readThrough, unread.deliveredAt)
        client.pages = [.success(page([], digests: [digest]))]
        await model.refresh()
        model.setView(.all)
        client.pages = [.success(newAllPage)]
        await model.refresh()
        XCTAssertEqual(model.unreadEventId, unread.eventId)
        XCTAssertEqual(threads.newsUnreadCount, 0)
    }

    /// The Digests view puts the "New" line before the first digest delivered after those read, keeps it while the
    /// feed is open and reads the digests it shows, as the All view does its news
    func testDigestsViewMarksTheFirstNewDigestAndReadsTheDigests() async throws {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        let read = try makeDigest(day: 18)
        let first = try makeDigest(day: 19)
        let latest = try makeDigest(day: 20)
        state.markDigestsRead([read])
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let digestsPage = page([], digests: [latest, first, read])
        client.pages = [.success(digestsPage), .success(digestsPage)]
        let model = AgentNewsFeedModel(client: client, readState: state, digestSettings: settings, timeZone: { "UTC" })
        await model.refresh()
        XCTAssertEqual(client.requests.last?.view, .digests)
        XCTAssertEqual(model.unreadDigestId, first.id)
        XCTAssertNil(model.unreadEventId)
        XCTAssertEqual(state.digestsReadThrough, latest.deliveredAt)
        await model.refresh()
        XCTAssertEqual(model.unreadDigestId, first.id, "The line stays while the feed is open")
        model.setView(.all)
        XCTAssertNil(model.unreadDigestId)

        settings.setNewsFeedView(.digests)
        client.pages = [.success(digestsPage)]
        let reopened = AgentNewsFeedModel(client: client, readState: state, digestSettings: settings, timeZone: { "UTC" })
        await reopened.refresh()
        XCTAssertNil(reopened.unreadDigestId, "A feed opened again has no new digests")
    }

    /// The Digests view opens with the page behind the News row, as the All view does, so its cards are there before
    /// the feed slides in
    func testDigestsViewOpensWithTheListsDigestsPage() async throws {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        let read = try makeDigest(day: 18)
        let first = try makeDigest(day: 19)
        let latest = try makeDigest(day: 20)
        state.markDigestsRead([read])
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let schedule = AgentNewsDigestSchedule(
            hour: settings.digestHour, minute: settings.digestMinute, timeZone: "UTC"
        )
        let digestsPage = page([], digests: [latest, first, read])
        let model = AgentNewsFeedModel(
            client: client, readState: state,
            cachedDigestsPage: .init(page: digestsPage, language: "en", schedule: schedule),
            digestSettings: settings, timeZone: { "UTC" }
        )
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.entries, [.digest(read), .digest(first), .digest(latest)])
        XCTAssertEqual(model.unreadDigestId, first.id)
        XCTAssertEqual(state.digestsReadThrough, latest.deliveredAt)
        client.pages = [.success(digestsPage)]
        await model.refresh()
        XCTAssertEqual(client.requests.last?.view, .digests)
        XCTAssertEqual(model.unreadDigestId, first.id, "The line stays after the refresh")

        settings.setNewsFeedView(.all)
        let allView = AgentNewsFeedModel(
            client: client, readState: state,
            cachedDigestsPage: .init(page: digestsPage, language: "en", schedule: schedule),
            digestSettings: settings, timeZone: { "UTC" }
        )
        allView.setView(.digests)
        XCTAssertEqual(
            allView.entries, [.digest(read), .digest(first), .digest(latest)], "The switch shows them at once"
        )

        let otherSchedule = AgentNewsDigestSchedule(
            hour: (settings.digestHour + 1) % 24, minute: settings.digestMinute, timeZone: "UTC"
        )
        let anotherSchedules = AgentNewsFeedModel(
            client: client, readState: state,
            cachedDigestsPage: .init(page: digestsPage, language: "en", schedule: otherSchedule),
            digestSettings: settings, timeZone: { "UTC" }
        )
        XCTAssertFalse(anotherSchedules.hasLoaded, "Another schedule's digests load behind the skeleton")
        XCTAssertTrue(anotherSchedules.entries.isEmpty)
    }

    /// Digests the All view shows are read: the Digests view doesn't show them as new
    func testDigestsTheAllViewShowedAreNotNew() async throws {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        let read = try makeDigest(day: 18)
        let shown = try makeDigest(day: 19)
        state.markDigestsRead([read])
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        client.pages = [
            .success(page([item(1, hour: 10, day: 19)], digests: [shown])),
            .success(page([], digests: [shown, read])),
        ]
        let model = AgentNewsFeedModel(client: client, readState: state, digestSettings: settings, timeZone: { "UTC" })
        await model.refresh()
        XCTAssertEqual(state.digestsReadThrough, shown.deliveredAt)
        model.setView(.digests)
        await model.refresh()
        XCTAssertNil(model.unreadDigestId)
    }

    /// In the Digests view the News row loads the digests, shows the latest and counts those delivered after the read
    /// ones, while the All view's row keeps its news
    func testNewsRowFollowsTheDigestsView() async throws {
        let client = NewsFeedTestClient()
        let state = makeReadState()
        var view = ApiAgentV2NewsFeedView.all
        let threads = AgentThreadListModel(newsClient: client, readState: state, newsView: { view })
        let news = item(1, hour: 10, day: 19)
        let read = try makeDigest(day: 19)
        client.pages = [.success(page([news], digests: [read]))]
        await threads.refreshNews()
        XCTAssertNil(client.requests.last?.view, "The All view's request names no view")
        XCTAssertEqual(state.digestsReadThrough, read.deliveredAt, "The first digests are read")

        view = .digests
        let latest = try makeDigest(day: 21)
        client.pages = [.success(page([], digests: [latest, try makeDigest(day: 20), read]))]
        await threads.refreshNews()
        XCTAssertEqual(client.requests.last?.view, .digests)
        XCTAssertEqual(threads.newsView, .digests)
        XCTAssertEqual(threads.latestDigest, latest)
        XCTAssertEqual(threads.newsUnreadCount, 2)
        XCTAssertEqual(threads.latestNews, news)
        view = .all
        XCTAssertEqual(threads.newsUnreadCount, 0)
    }

    func testDigestDiscussionsComeFromPagesAndAreRemovedInBothViews() async throws {
        let client = NewsFeedTestClient()
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        let shown = try makeDigest(day: 20)
        let digest = ApiAgentV2NewsFeedDigest(
            id: shown.id, deliveredAt: shown.deliveredAt, top: shown.top, total: shown.total,
            discussion: .init(threadId: "digest-thread", icon: "📰")
        )
        client.pages = [
            .success(page([], digests: [digest])), .success(page([], digests: [digest])),
            .success(page([], digests: [shown])), .success(page([], digests: [shown]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), digestSettings: settings)
        await model.refresh()
        XCTAssertEqual(model.digests.first?.discussion, digest.discussion)
        model.setView(.digests)
        await model.refresh()
        XCTAssertEqual(model.digests.first?.discussion, digest.discussion)
        model.removeDiscussion(threadId: "digest-thread")
        XCTAssertNil(model.digests.first?.discussion)
        model.setView(.all)
        XCTAssertNil(model.digests.first?.discussion)

        // The thread a digest's first message creates is its discussion in both views, also after pages without it
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: Data("""
        {"id":"created-digest-thread","revision":1,"createdAt":"2026-10-20T12:00:00Z","updatedAt":"2026-10-20T12:00:00Z",
         "lastActivityAt":"2026-10-20T12:00:00Z","messageCount":1,"icon":"🗞"}
        """.utf8))
        model.markDigestDiscussion(id: shown.id, thread: thread)
        XCTAssertEqual(model.digests.first?.discussion, .init(threadId: thread.id, icon: "🗞"))
        await model.refresh()
        XCTAssertEqual(model.digests.first?.discussion?.threadId, thread.id)
        model.setView(.digests)
        await model.refresh()
        XCTAssertEqual(model.digests.first?.discussion?.threadId, thread.id)
        model.removeDiscussion(threadId: thread.id)
        XCTAssertNil(model.digests.first?.discussion)
    }

    func testDigestEntriesMergeByDeliveryTimeAndRequestsCarryDeviceSchedule() async throws {
        let client = NewsFeedTestClient()
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-20T11:00:00Z","deliveredAt":"2026-10-20T11:00:00Z", "total":2,
         "top":[{"eventId":1,"headline":"News 1"}]}
        """.utf8))
        client.pages = [
            .success(ApiAgentV2NewsFeedPage(locale: "en", items: [item(2, hour: 12)], nextCursor: "older", digests: [digest])),
            .success(page([item(1, hour: 10)]))
        ]
        let model = AgentNewsFeedModel(
            client: client, readState: makeReadState(), requestedDigestId: digest.id,
            timeZone: { "Europe/Moscow" }
        )
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.entries, [.news(item(1, hour: 10)), .digest(digest), .news(item(2, hour: 12))])
        XCTAssertEqual(model.requestedDigestId, digest.id)
        XCTAssertEqual(client.requests.map(\.digestHour), [21, 21])
        XCTAssertEqual(client.requests.map(\.timeZone), ["Europe/Moscow", "Europe/Moscow"])
    }

    /// Older pages may bring the requested digest until it comes, the pages run out or they reach back past its window
    func testRequestedDigestKeepsLoadingUntilFoundExhaustedOrOlderThanTheDigest() async throws {
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-20T11:00:00.000Z","deliveredAt":"2026-10-20T11:00:00.000Z","total":3,"top":[]}
        """.utf8))
        let client = NewsFeedTestClient()
        client.pages = [
            .success(page([item(3, hour: 13)], cursor: "older")),
            .success(ApiAgentV2NewsFeedPage(locale: "en", items: [item(2, hour: 10)], nextCursor: "oldest", digests: [digest])),
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), requestedDigestId: digest.id)
        await model.refresh()
        XCTAssertTrue(model.canLoadRequestedDigest)
        await model.loadMore()
        XCTAssertEqual(model.digests, [digest])
        XCTAssertFalse(model.canLoadRequestedDigest)

        let older = NewsFeedTestClient()
        older.pages = [.success(page([item(2, hour: 12), item(1, hour: 10)], cursor: "older"))]
        let pastTheDigest = AgentNewsFeedModel(client: older, readState: makeReadState(), requestedDigestId: digest.id)
        await pastTheDigest.refresh()
        XCTAssertFalse(pastTheDigest.canLoadRequestedDigest)

        let exhausted = NewsFeedTestClient()
        exhausted.pages = [.success(page([item(2, hour: 12)]))]
        let lastPage = AgentNewsFeedModel(client: exhausted, readState: makeReadState(), requestedDigestId: digest.id)
        await lastPage.refresh()
        XCTAssertFalse(lastPage.canLoadRequestedDigest)
        XCTAssertFalse(AgentNewsFeedModel(client: exhausted, readState: makeReadState()).canLoadRequestedDigest)

        let digestsClient = NewsFeedTestClient()
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        settings.setNewsFeedView(.digests)
        let requested = try makeDigest(day: 19)
        digestsClient.pages = [
            .success(page([], cursor: "requested-digest", digests: [try makeDigest(day: 20)])),
            .success(page([], cursor: "unneeded", digests: [requested]))
        ]
        let digestsModel = AgentNewsFeedModel(
            client: digestsClient, readState: makeReadState(), requestedDigestId: requested.id, digestSettings: settings
        )
        await digestsModel.refresh()
        await digestsModel.prefetchTask?.value
        XCTAssertTrue(digestsModel.digests.contains { $0.id == requested.id })
        XCTAssertFalse(digestsModel.canLoadRequestedDigest)
        XCTAssertEqual(digestsClient.requests.map(\.cursor), [nil, "requested-digest"])
        XCTAssertEqual(digestsClient.requests.map(\.view), [.digests, .digests])

        // A time the ID doesn't carry readably can't be placed among the pages: the digest counts as not found
        let unreadable = NewsFeedTestClient()
        unreadable.pages = [.success(page([item(3, hour: 13)], cursor: "older"))]
        let unreadableId = AgentNewsFeedModel(client: unreadable, readState: makeReadState(), requestedDigestId: "en:yesterday")
        await unreadableId.refresh()
        XCTAssertEqual(unreadableId.nextCursor, "older")
        XCTAssertFalse(unreadableId.canLoadRequestedDigest)
    }

    /// A new digest hour keeps the digests shown until its first page comes, so the cards and the pinned bar don't blink
    /// out and back; the page replaces them, and a failed one takes them away
    func testNewDigestHourKeepsTheDigestsUntilItsPageComes() async throws {
        func digest(_ time: String) throws -> ApiAgentV2NewsFeedDigest {
            try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
            {"id":"en:\(time)","deliveredAt":"\(time)","total":3,"top":[]}
            """.utf8))
        }
        let evening = try digest("2026-10-20T11:00:00.000Z")
        let morning = try digest("2026-10-20T06:00:00.000Z")
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        let client = NewsFeedTestClient()
        client.pages = [.success(ApiAgentV2NewsFeedPage(locale: "en", items: [item(1, hour: 10)], digests: [evening]))]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), digestSettings: settings)
        await model.refresh()
        XCTAssertEqual(model.digests, [evening])

        _ = await settings.setDigestTime(hour: 9, minute: 0)
        client.shouldSuspend = true
        let refresh = Task { await model.refresh() }
        try await waitUntil { client.pendingResponse != nil }
        XCTAssertEqual(model.digests, [evening])
        client.resume(with: ApiAgentV2NewsFeedPage(locale: "en", items: [item(1, hour: 10)], digests: [morning]))
        await refresh.value
        XCTAssertEqual(model.digests, [morning])
        XCTAssertEqual(client.requests.last?.digestHour, 9)
        XCTAssertEqual(client.requests.last?.digestMinute, 0)

        client.shouldSuspend = false
        _ = await settings.setDigestTime(hour: 9, minute: 30)
        await model.refresh()
        XCTAssertTrue(model.digests.isEmpty)
        XCTAssertEqual(model.items.map(\.eventId), [1])
    }

    /// A first page loaded elsewhere for another digest time or time zone shows its news without its digests
    func testCachedPageOfAnotherDigestScheduleShowsNoDigests() throws {
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-20T11:00:00.000Z","deliveredAt":"2026-10-20T11:00:00.000Z","total":3,"top":[]}
        """.utf8))
        let cached = ApiAgentV2NewsFeedPage(locale: "en", items: [item(1, hour: 10)], nextCursor: "older", digests: [digest])
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        func makeModel(hour: Int, minute: Int = 0, timeZone: String) -> AgentNewsFeedModel {
            AgentNewsFeedModel(
                client: NewsFeedTestClient(), readState: makeReadState(),
                cachedPage: AgentNewsCachedPage(
                    page: cached, language: "en", schedule: AgentNewsDigestSchedule(hour: hour, minute: minute, timeZone: timeZone)
                ),
                digestSettings: settings, timeZone: { "Europe/Moscow" }
            )
        }
        let same = makeModel(hour: 21, timeZone: "Europe/Moscow")
        XCTAssertEqual(same.digests, [digest])
        XCTAssertEqual(same.nextCursor, "older")
        for other in [
            makeModel(hour: 9, timeZone: "Europe/Moscow"), makeModel(hour: 21, minute: 15, timeZone: "Europe/Moscow"),
            makeModel(hour: 21, timeZone: "UTC"),
        ] {
            XCTAssertEqual(other.items.map(\.eventId), [1])
            XCTAssertTrue(other.digests.isEmpty)
            XCTAssertNil(other.nextCursor)
        }
    }

    /// Each choice of the sheet and its time go to the settings and show at once; a choice turned down gives way to the
    /// previous one, and the last choice or time picked while another is applied goes next
    func testDigestSheetAppliesChoicesAndTimeAndKeepsThePreviousChoiceWhenOneFails() async throws {
        let settings = DigestSettingsStub()
        var errors = 0
        let sheet = AgentDigestSettingsModel(settings: settings, pendingState: .init(), showError: { errors += 1 })
        XCTAssertEqual(sheet.mode, .off)
        XCTAssertEqual(sheet.hint(of: .digest), L10n.agentDigestNotificationsDailyHint(time: "21:00"))

        await sheet.selectMode(.digest)
        await sheet.selectMode(.news)
        await sheet.selectMode(.off)
        XCTAssertEqual(settings.modes, [.digest, .news, .off])
        XCTAssertEqual(sheet.mode, .off)
        await sheet.selectHour(7)
        XCTAssertEqual(settings.hours, [7])
        XCTAssertEqual(sheet.digestHour, 7)
        XCTAssertEqual(sheet.hint(of: .digest), L10n.agentDigestNotificationsDailyHint(time: "07:00"))
        // The wheel's minutes turn in quarter hours, and the time's row tells the picked minute
        let controller = AgentDigestSettingsSheetVC(model: sheet)
        controller.loadViewIfNeeded()
        let picker = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UIPickerView }.first {
            $0.accessibilityIdentifier == "AgentDigestHourPicker"
        })
        XCTAssertEqual(controller.pickerView(picker, numberOfRowsInComponent: 1), 4)
        XCTAssertEqual(controller.pickerView(picker, titleForRow: 3, forComponent: 1), "45")
        controller.pickerView(picker, didSelectRow: 3, inComponent: 1)
        try await waitUntil { settings.times.count == 2 && !sheet.isApplyingTime }
        let timeRow = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier == "AgentDigestHour" })
        XCTAssertEqual(timeRow.accessibilityValue, "07:45")
        XCTAssertEqual(picker.selectedRow(inComponent: 1), 3)
        XCTAssertEqual(settings.times, [.init(hour: 7, minute: 0), .init(hour: 7, minute: 45)])
        XCTAssertEqual(sheet.digestMinute, 45)
        XCTAssertEqual(AgentDigestSettingsModel.formatTime(.init(hour: 21, minute: 45)), "21:45")
        XCTAssertEqual(sheet.hint(of: .digest), L10n.agentDigestNotificationsDailyHint(time: "07:45"))

        settings.outcome = .permissionDenied
        await sheet.selectMode(.news)
        XCTAssertEqual(sheet.mode, .off)
        XCTAssertTrue(sheet.isPermissionDenied)
        XCTAssertEqual(errors, 0)

        settings.outcome = .failed
        await sheet.selectMode(.digest)
        XCTAssertEqual(sheet.mode, .off)
        XCTAssertFalse(sheet.isPermissionDenied)
        XCTAssertEqual(errors, 1)

        settings.outcome = .ok
        settings.isSuspended = true
        let pending = Task { await sheet.selectMode(.digest) }
        try await waitUntil { settings.pending != nil }
        XCTAssertEqual(sheet.pendingMode, .digest)
        // The mark moves to the choice at once, without waiting for the settings, and so does it to the next choices,
        // the last of which goes next
        XCTAssertEqual(sheet.mode, .digest)
        await sheet.selectMode(.off)
        await sheet.selectMode(.news)
        XCTAssertEqual(sheet.mode, .news)
        XCTAssertEqual(sheet.pendingMode, .digest)
        settings.isSuspended = false
        settings.resume()
        await pending.value
        XCTAssertEqual(settings.modes, [.digest, .news, .off, .news, .digest, .digest, .news])
        XCTAssertEqual(sheet.mode, .news)
        XCTAssertNil(sheet.pendingMode)

        // Hours picked while one is applied show at once and the last of them goes next; one that fails to apply stays,
        // as the settings keep it
        settings.outcome = .failed
        settings.isSuspended = true
        let pendingHour = Task { await sheet.selectHour(8) }
        try await waitUntil { settings.pending != nil }
        XCTAssertTrue(sheet.isApplyingTime)
        await sheet.selectHour(9)
        await sheet.selectHour(10)
        XCTAssertEqual(sheet.digestHour, 10)
        settings.isSuspended = false
        settings.resume()
        await pendingHour.value
        XCTAssertEqual(settings.hours, [7, 7, 8, 10])
        XCTAssertEqual(sheet.digestHour, 10)
        XCTAssertFalse(sheet.isApplyingTime)
        XCTAssertEqual(errors, 2)
    }

    /// An hour and a minute picked while another time is applied go next together, as one time
    func testDigestSheetReportsOnlyTheLastQueuedTimesOutcome() async throws {
        let settings = DigestSettingsStub()
        settings.outcome = .failed
        settings.isSuspended = true
        var errors = 0
        let sheet = AgentDigestSettingsModel(settings: settings, pendingState: .init(), showError: { errors += 1 })
        let pendingHour = Task { await sheet.selectHour(8) }
        try await waitUntil { settings.pending != nil }
        await sheet.selectHour(10)
        await sheet.selectMinute(15)
        XCTAssertEqual(sheet.hint(of: .digest), L10n.agentDigestNotificationsDailyHint(time: "10:15"))
        settings.resume()
        try await waitUntil { settings.times.count == 2 && settings.pending != nil }
        XCTAssertEqual(settings.times, [.init(hour: 8, minute: 0), .init(hour: 10, minute: 15)])
        settings.outcome = .ok
        settings.resume()
        await pendingHour.value

        XCTAssertEqual(sheet.digestHour, 10)
        XCTAssertEqual(sheet.digestMinute, 15)
        XCTAssertFalse(sheet.isApplyingTime)
        XCTAssertEqual(errors, 0)
    }

    func testDigestSheetKeepsTheLastModeAcrossPresentations() async throws {
        let settings = DigestSettingsStub()
        settings.isSuspended = true
        let pendingState = AgentDigestSettingsModel.PendingState()
        let sheet = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        var changes = 0
        sheet.onChange = { changes += 1 }
        let pending = Task { await sheet.selectMode(.digest) }
        try await waitUntil { settings.pending != nil }
        await sheet.selectMode(.news)
        sheet.clearCallbacks()
        let changesAtDismissal = changes

        let reopened = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        var reopenedChanges = 0
        reopened.onChange = { reopenedChanges += 1 }
        sheet.clearCallbacks()
        settings.isSuspended = false
        await reopened.selectMode(.digest)
        XCTAssertEqual(settings.modes, [.digest])
        XCTAssertEqual(reopened.mode, .digest)
        let changesBeforeCompletion = reopenedChanges
        settings.resume()
        await pending.value

        XCTAssertEqual(settings.modes, [.digest, .digest])
        XCTAssertEqual(settings.mode, .digest)
        XCTAssertEqual(reopened.mode, .digest)
        XCTAssertNil(reopened.pendingMode)
        XCTAssertEqual(changes, changesAtDismissal)
        XCTAssertGreaterThan(reopenedChanges, changesBeforeCompletion)
    }

    func testDigestSheetKeepsTheLastHourAcrossPresentations() async throws {
        let settings = DigestSettingsStub()
        settings.outcome = .failed
        settings.isSuspended = true
        let pendingState = AgentDigestSettingsModel.PendingState()
        var errors = 0
        let sheet = AgentDigestSettingsModel(settings: settings, pendingState: pendingState, showError: { errors += 1 })
        let pending = Task { await sheet.selectHour(8) }
        try await waitUntil { settings.pending != nil }
        await sheet.selectHour(9)
        sheet.clearCallbacks()

        var reopenedErrors = 0
        let reopened = AgentDigestSettingsModel(settings: settings, pendingState: pendingState, showError: { reopenedErrors += 1 })
        sheet.clearCallbacks()
        settings.isSuspended = false
        await reopened.selectHour(10)
        XCTAssertEqual(settings.hours, [8])
        XCTAssertEqual(reopened.digestHour, 10)
        settings.resume()
        await pending.value

        XCTAssertEqual(settings.hours, [8, 10])
        XCTAssertEqual(settings.digestHour, 10)
        XCTAssertEqual(reopened.digestHour, 10)
        XCTAssertFalse(reopened.isApplyingTime)
        XCTAssertEqual(errors, 0)
        XCTAssertEqual(reopenedErrors, 1)
    }

    func testDigestSheetShowsPendingChoicesAcrossPresentations() async throws {
        let settings = DigestSettingsStub()
        settings.isSuspended = true
        let pendingState = AgentDigestSettingsModel.PendingState()
        let sheet = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        let pendingMode = Task { await sheet.selectMode(.digest) }
        try await waitUntil { settings.pending != nil }
        let reopened = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        XCTAssertEqual(reopened.mode, .digest)
        XCTAssertEqual(reopened.pendingMode, .digest)
        await sheet.selectMode(.news)
        XCTAssertEqual(reopened.mode, .news)
        settings.isSuspended = false
        settings.resume()
        await pendingMode.value

        settings.isSuspended = true
        let pendingHour = Task { await reopened.selectHour(8) }
        try await waitUntil { settings.pending != nil }
        let nextSheet = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        XCTAssertEqual(nextSheet.digestHour, 8)
        XCTAssertTrue(nextSheet.isApplyingTime)
        await reopened.selectHour(10)
        let latestSheet = AgentDigestSettingsModel(settings: settings, pendingState: pendingState)
        XCTAssertEqual(latestSheet.digestHour, 10)
        settings.isSuspended = false
        settings.resume()
        await pendingHour.value
    }

    func testPrefetchStopsAtTwoDigestsEvenWhenTheLastPageAddsNoNews() async throws {
        let client = NewsFeedTestClient()
        let firstDigest = try makeDigest(day: 19)
        let secondDigest = try makeDigest(day: 18)
        let older = item(2, hour: 12, day: 19)
        client.pages = [
            .success(page([item(3, hour: 12)], cursor: "first")),
            .success(page([older], cursor: "second", digests: [firstDigest])),
            .success(page([older], cursor: "unneeded", digests: [secondDigest])),
            .success(page([item(1, hour: 12, day: 17)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())

        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "first", "second"])
        XCTAssertEqual(Set(model.digests.map(\.id)), [firstDigest.id, secondDigest.id])
        XCTAssertEqual(model.nextCursor, "unneeded")
        XCTAssertFalse(model.isLoadingMore)
    }

    func testExhaustedHistoryIsNotPrefetchedAgainAfterRefreshOrReachingADigest() async throws {
        let client = NewsFeedTestClient()
        let digest = try makeDigest(day: 20)
        let first = page([item(2, hour: 12)], cursor: "p2", digests: [digest])
        client.pages = [
            .success(first),
            .success(page([item(1, hour: 10)])),
            .success(first),
            .success(first),
            .success(first)
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.prefetchTask?.value

        await model.refresh()
        model.markDigestReached(digest.id)
        await model.prefetchTask?.value
        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "p2", nil, nil])
        XCTAssertEqual(model.items.map(\.eventId), [1, 2])
        XCTAssertEqual(model.nextCursor, "p2")
        XCTAssertNil(model.error)
    }

    func testRefreshWithAGapPrefetchesOnlyTheConnectedCursorChain() async throws {
        let client = NewsFeedTestClient()
        let oldDigest = try makeDigest(day: 20)
        let freshDigest = try makeDigest(day: 26)
        let freshPage = page([item(10, hour: 12, day: 26)], cursor: "fresh-second", digests: [freshDigest])
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "old-second", digests: [oldDigest])),
            .success(page([item(1, hour: 12, day: 18)], digests: try [makeDigest(day: 19), makeDigest(day: 18)])),
            .success(freshPage),
            .success(page([item(9, hour: 12, day: 25)], cursor: "fresh-third", digests: [try makeDigest(day: 25)])),
            .success(page([item(8, hour: 12, day: 24)], cursor: "fresh-fourth", digests: [try makeDigest(day: 24)])),
            .success(page([item(7, hour: 12, day: 23)], cursor: "fresh-fifth", digests: [try makeDigest(day: 23)])),
            .success(page([item(6, hour: 12, day: 22)], cursor: "fresh-sixth", digests: [try makeDigest(day: 22)])),
            .success(page([item(5, hour: 12, day: 21)], digests: [try makeDigest(day: 21)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.prefetchTask?.value
        model.markDigestReached(oldDigest.id)
        await model.prefetchTask?.value

        await model.refresh()
        await model.prefetchTask?.value
        XCTAssertNil(model.reachedDigestId)
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "old-second", nil, "fresh-second"])
        XCTAssertEqual(model.nextCursor, "fresh-third")

        model.markDigestReached(freshDigest.id)
        await model.prefetchTask?.value
        XCTAssertEqual(model.reachedDigestId, freshDigest.id)
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "old-second", nil, "fresh-second", "fresh-third"])
        XCTAssertEqual(model.nextCursor, "fresh-fourth")

        client.pages = [.success(freshPage)]
        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "old-second", nil, "fresh-second", "fresh-third", nil])
        XCTAssertEqual(model.items.map(\.eventId), [1, 2, 8, 9, 10])
        XCTAssertEqual(model.nextCursor, "fresh-second")
    }

    func testPrefetchWithoutDigestsStopsAtExactly48Hours() async {
        let client = NewsFeedTestClient()
        client.pages = [
            .success(page([item(4, hour: 12)], cursor: "first")),
            .success(page([item(3, hour: 12, day: 19)], cursor: "second")),
            .success(page([item(2, hour: 12, day: 18)], cursor: "unneeded")),
            .success(page([item(1, hour: 12, day: 17)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())

        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "first", "second"])
        XCTAssertEqual(model.items.map(\.eventId), [2, 3, 4])
        XCTAssertEqual(model.nextCursor, "unneeded")
    }

    func testReachingOlderDigestsExtendsPrefetchAndNeverMovesTheReferenceForward() async throws {
        let client = NewsFeedTestClient()
        let digests = try [20, 19, 18, 17].map { try makeDigest(day: $0) }
        client.pages = [
            .success(page([item(4, hour: 12)], cursor: "first", digests: Array(digests.prefix(2)))),
            .success(page([item(3, hour: 12, day: 18)], cursor: "second", digests: [digests[2]])),
            .success(page([item(2, hour: 12, day: 17)], cursor: "unneeded", digests: [digests[3]])),
            .success(page([item(1, hour: 12, day: 16)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.prefetchTask?.value
        XCTAssertEqual(client.requests.count, 1)

        model.markDigestReached(digests[0].id)
        await model.prefetchTask?.value
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "first"])
        model.markDigestReached(digests[1].id)
        await model.prefetchTask?.value
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "first", "second"])

        model.markDigestReached(digests[0].id)
        model.markDigestReached(digests[1].id)
        await model.prefetchTask?.value
        XCTAssertEqual(model.reachedDigestId, digests[1].id)
        XCTAssertEqual(client.requests.count, 3)
    }

    func testPrefetchFailureStopsUntilLoadMoreRetriesTheSameCursor() async throws {
        let client = NewsFeedTestClient()
        let newest = item(2, hour: 12)
        client.pages = [
            .success(page([newest], cursor: "older")),
            .failure(NewsFeedTestError.unavailable),
            .success(page([item(1, hour: 12, day: 19)], digests: try [makeDigest(day: 19), makeDigest(day: 18)]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older"])
        XCTAssertEqual(model.items, [newest])
        XCTAssertEqual(model.nextCursor, "older")
        XCTAssertNil(model.error)
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.isLoadingMore)

        await model.loadMore()
        await model.prefetchTask?.value
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older", "older"])
        XCTAssertEqual(model.items.map(\.eventId), [1, 2])
    }

    func testRefreshDiscardsOlderResponseAndReachedDigestAfterLanguageHourOrTimeZoneChanges() async throws {
        for change in ["language", "hour", "minute", "timeZone"] {
            let client = NewsFeedTestClient()
            let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
            let digests = try [20, 19, 18, 17].map { try makeDigest(day: $0) }
            var language = "en"
            var timeZone = "UTC"
            client.pages = [.success(page([item(5, hour: 12)], cursor: "older", digests: digests))]
            let model = AgentNewsFeedModel(
                client: client, readState: makeReadState(), language: { language },
                digestSettings: settings, timeZone: { timeZone }
            )
            await model.refresh()
            model.markDigestReached(digests[1].id)
            await model.prefetchTask?.value
            client.shouldSuspendNext = true
            let older = Task { await model.loadMore() }
            try await waitUntil { client.pendingResponse != nil }

            switch change {
            case "language": language = "ru"
            case "hour": _ = await settings.setDigestTime(hour: 9, minute: 0)
            case "minute": _ = await settings.setDigestTime(hour: 21, minute: 45)
            default: timeZone = "Europe/Moscow"
            }
            client.pages = [
                .success(.init(locale: language, items: [item(6, hour: 13)], nextCursor: "new-schedule")),
                .success(.init(
                    locale: language, items: [item(4, hour: 12, day: 19)], nextCursor: "unneeded",
                    digests: Array(digests.prefix(2))
                ))
            ]
            await model.refresh()
            client.resume(with: page([item(1, hour: 12, day: 16)], cursor: "stale", digests: [try makeDigest(day: 16)]))
            await older.value
            await model.prefetchTask?.value

            XCTAssertNil(model.reachedDigestId, change)
            XCTAssertFalse(model.items.contains { $0.eventId == 1 }, change)
            XCTAssertFalse(model.digests.contains { $0.id == "en:2026-10-16T11:00:00Z" }, change)
            XCTAssertEqual(model.nextCursor, "unneeded", change)
            XCTAssertEqual(client.requests.map(\.cursor), [nil, "older", nil, "new-schedule"], change)
            XCTAssertEqual(client.maximumActiveOlderRequests, 1, change)
            XCTAssertEqual(client.requests.last?.lang, language, change)
            XCTAssertEqual(client.requests.last?.digestHour, settings.digestHour, change)
            XCTAssertEqual(client.requests.last?.digestMinute, settings.digestMinute, change)
            XCTAssertEqual(client.requests.last?.timeZone, timeZone, change)
        }
    }

    func testPrefetchAndConcurrentLoadMoreShareOneOlderPageRequest() async throws {
        let client = NewsFeedTestClient()
        let reached = try makeDigest(day: 20)
        let olderPage = page([item(1, hour: 12, day: 19)], digests: try [makeDigest(day: 19), makeDigest(day: 18)])
        client.pages = [
            .success(page([item(2, hour: 12)], cursor: "older", digests: [reached])),
            .success(olderPage)
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState())
        await model.refresh()
        client.shouldSuspendNext = true
        try await waitUntil { client.pendingResponse != nil }
        var hasStartedLoadMore = false
        let scrolling = Task {
            hasStartedLoadMore = true
            await model.loadMore()
        }
        model.markDigestReached(reached.id)
        try await waitUntil { hasStartedLoadMore }
        client.resume(with: olderPage)
        await scrolling.value
        await model.prefetchTask?.value

        XCTAssertEqual(client.maximumActiveOlderRequests, 1)
        XCTAssertEqual(client.requests.map(\.cursor), [nil, "older"])
        XCTAssertEqual(model.items.map(\.eventId), [1, 2])
    }

    func testRequestedDigestContinuesTheSamePrefetchCycleBeyondItsNormalLimit() async throws {
        let client = NewsFeedTestClient()
        let requested = try makeDigest(day: 17)
        client.pages = [
            .success(page([item(3, hour: 12)], cursor: "first")),
            .success(page([item(2, hour: 12, day: 18)], cursor: "second", digests: try [makeDigest(day: 19), makeDigest(day: 18)])),
            .success(page([item(1, hour: 10, day: 17)], cursor: "unneeded", digests: [requested]))
        ]
        let model = AgentNewsFeedModel(client: client, readState: makeReadState(), requestedDigestId: requested.id)

        await model.refresh()
        await model.prefetchTask?.value

        XCTAssertEqual(client.requests.map(\.cursor), [nil, "first", "second"])
        XCTAssertTrue(model.digests.contains { $0.id == requested.id })
        XCTAssertFalse(model.canLoadRequestedDigest)
        XCTAssertEqual(model.nextCursor, "unneeded")
    }

    /// The digest sheet's content fits only when it is no taller than the sheet can grow, which an iPad's form sheet never
    /// tells, nor than what the sheet shows, which is left out while the sheet animates
    func testDigestSheetContentFitsTheTallestAndTheVisibleHeight() {
        let isFitting = AgentDigestSettingsSheetVC.isContentFitting
        XCTAssertTrue(isFitting(400, nil, nil))
        XCTAssertTrue(isFitting(400, 500, 400.4))
        XCTAssertFalse(isFitting(400, nil, 380))
        XCTAssertFalse(isFitting(400, 380, 500))
        XCTAssertFalse(isFitting(600, 800, 500))
        XCTAssertTrue(isFitting(600, 800, nil))
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
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

    private func makeDigest(day: Int) throws -> ApiAgentV2NewsFeedDigest {
        let timestamp = String(format: "2026-10-%02dT11:00:00Z", day)
        return try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:\(timestamp)","deliveredAt":"\(timestamp)","total":1,"top":[]}
        """.utf8))
    }

    private func item(_ id: Int, hour: Int, day: Int = 20, discussion: ApiAgentV2NewsFeedItem.Discussion? = nil) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: id,
            deliveredAt: String(format: "2026-10-%02dT%02d:00:00Z", day, hour),
            headline: "News \(id)",
            body: "**Body** \(id)",
            sources: [],
            discussion: discussion
        )
    }

    private func page(_ items: [ApiAgentV2NewsFeedItem], cursor: String? = nil, digests: [ApiAgentV2NewsFeedDigest]? = nil) -> ApiAgentV2NewsFeedPage {
        ApiAgentV2NewsFeedPage(locale: "en", items: items, nextCursor: cursor, digests: digests)
    }
}

@MainActor
private final class DigestSettingsStub: AgentDigestNotificationSettings {
    private(set) var mode: AgentNewsNotificationSettings.Mode = .off
    private(set) var digestHour = 21
    private(set) var digestMinute = 0
    var outcome: AgentNewsNotificationSettings.Outcome = .ok
    var isSuspended = false
    private(set) var modes: [AgentNewsNotificationSettings.Mode] = []
    private(set) var times: [AgentDigestSettingsModel.DigestTime] = []
    var hours: [Int] { times.map(\.hour) }
    private(set) var pending: CheckedContinuation<Void, Never>?

    func setMode(_ mode: AgentNewsNotificationSettings.Mode) async -> AgentNewsNotificationSettings.Outcome {
        modes.append(mode)
        if isSuspended { await withCheckedContinuation { pending = $0 } }
        if outcome == .ok { self.mode = mode }
        return outcome
    }

    func setDigestTime(hour: Int, minute: Int) async -> AgentNewsNotificationSettings.Outcome {
        times.append(.init(hour: hour, minute: minute))
        digestHour = hour
        digestMinute = minute
        if isSuspended { await withCheckedContinuation { pending = $0 } }
        return outcome
    }

    func resume() {
        pending?.resume()
        pending = nil
    }
}

private enum NewsFeedTestError: Error {
    case unavailable
}

@MainActor
private final class NewsFeedTestClient: AgentNewsFeedClient {
    var pages: [Result<ApiAgentV2NewsFeedPage, Error>] = []
    var requests: [ApiAgentV2NewsFeedRequest] = []
    var shouldSuspend = false
    var shouldSuspendNext = false
    var pendingResponse: CheckedContinuation<ApiAgentV2NewsFeedPage, Never>?
    private var activeOlderRequests = 0
    private(set) var maximumActiveOlderRequests = 0

    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
        requests.append(.init(
            lang: lang, cursor: cursor, digestHour: schedule.hour, digestMinute: schedule.minute, timeZone: schedule.timeZone, view: view
        ))
        if cursor != nil {
            activeOlderRequests += 1
            maximumActiveOlderRequests = max(maximumActiveOlderRequests, activeOlderRequests)
        }
        defer { if cursor != nil { activeOlderRequests -= 1 } }
        if shouldSuspend || shouldSuspendNext {
            shouldSuspendNext = false
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
