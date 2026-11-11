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

        // A time the ID doesn't carry readably can't be placed among the pages: the digest counts as not found
        let unreadable = NewsFeedTestClient()
        unreadable.pages = [.success(page([item(3, hour: 13)], cursor: "older"))]
        let unreadableId = AgentNewsFeedModel(client: unreadable, readState: makeReadState(), requestedDigestId: "en:yesterday")
        await unreadableId.refresh()
        XCTAssertEqual(unreadableId.nextCursor, "older")
        XCTAssertFalse(unreadableId.canLoadRequestedDigest)
    }

    /// A first page loaded elsewhere for another digest hour or time zone shows its news without its digests
    func testCachedPageOfAnotherDigestScheduleShowsNoDigests() throws {
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-20T11:00:00.000Z","deliveredAt":"2026-10-20T11:00:00.000Z","total":3,"top":[]}
        """.utf8))
        let cached = ApiAgentV2NewsFeedPage(locale: "en", items: [item(1, hour: 10)], nextCursor: "older", digests: [digest])
        let settings = AgentNewsNotificationSettings(userDefaults: makeDefaults())
        func makeModel(hour: Int, timeZone: String) -> AgentNewsFeedModel {
            AgentNewsFeedModel(
                client: NewsFeedTestClient(), readState: makeReadState(),
                cachedPage: AgentNewsCachedPage(page: cached, language: "en", schedule: AgentNewsDigestSchedule(hour: hour, timeZone: timeZone)),
                digestSettings: settings, timeZone: { "Europe/Moscow" }
            )
        }
        let same = makeModel(hour: 21, timeZone: "Europe/Moscow")
        XCTAssertEqual(same.digests, [digest])
        XCTAssertEqual(same.nextCursor, "older")
        for other in [makeModel(hour: 9, timeZone: "Europe/Moscow"), makeModel(hour: 21, timeZone: "UTC")] {
            XCTAssertEqual(other.items.map(\.eventId), [1])
            XCTAssertTrue(other.digests.isEmpty)
            XCTAssertNil(other.nextCursor)
        }
    }

    /// Each choice of the sheet and its hour go to the settings; a choice turned down keeps the previous one, and while
    /// one is applied no other is taken
    func testDigestSheetAppliesChoicesAndHourAndKeepsThePreviousChoiceWhenOneFails() async throws {
        let settings = DigestSettingsStub()
        var errors = 0
        let sheet = AgentDigestSettingsModel(settings: settings, showError: { errors += 1 })
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
        await sheet.selectMode(.news)
        settings.resume()
        await pending.value
        XCTAssertEqual(settings.modes, [.digest, .news, .off, .news, .digest, .digest])
        XCTAssertEqual(sheet.mode, .digest)
        XCTAssertNil(sheet.pendingMode)

        // While an hour is applied no other is taken; one that fails to apply stays, as the settings keep it
        settings.outcome = .failed
        let pendingHour = Task { await sheet.selectHour(8) }
        try await waitUntil { settings.pending != nil }
        XCTAssertTrue(sheet.isApplyingHour)
        await sheet.selectHour(10)
        settings.resume()
        await pendingHour.value
        XCTAssertEqual(settings.hours, [7, 8])
        XCTAssertEqual(sheet.digestHour, 8)
        XCTAssertFalse(sheet.isApplyingHour)
        XCTAssertEqual(errors, 2)
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

@MainActor
private final class DigestSettingsStub: AgentDigestNotificationSettings {
    private(set) var mode: AgentNewsNotificationSettings.Mode = .off
    private(set) var digestHour = 21
    var outcome: AgentNewsNotificationSettings.Outcome = .ok
    var isSuspended = false
    private(set) var modes: [AgentNewsNotificationSettings.Mode] = []
    private(set) var hours: [Int] = []
    private(set) var pending: CheckedContinuation<Void, Never>?

    func setMode(_ mode: AgentNewsNotificationSettings.Mode) async -> AgentNewsNotificationSettings.Outcome {
        modes.append(mode)
        if isSuspended { await withCheckedContinuation { pending = $0 } }
        if outcome == .ok { self.mode = mode }
        return outcome
    }

    func setDigestHour(_ hour: Int) async -> AgentNewsNotificationSettings.Outcome {
        hours.append(hour)
        digestHour = hour
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
    var pendingResponse: CheckedContinuation<ApiAgentV2NewsFeedPage, Never>?

    func getNewsFeed(lang: String, cursor: String?, digestHour: Int, timeZone: String) async throws -> ApiAgentV2NewsFeedPage {
        requests.append(.init(lang: lang, cursor: cursor, digestHour: digestHour, timeZone: timeZone))
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
