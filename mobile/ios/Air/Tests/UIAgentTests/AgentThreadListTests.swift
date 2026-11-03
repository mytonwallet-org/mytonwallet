@preconcurrency import Combine
import XCTest
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

final class AgentThreadListTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    @MainActor
    func testSectionsGroupPinnedAndActivityDaysInDescendingOrder() async throws {
        let client = ThreadListClient()
        let pinned = try makeItem("pinned", date: "2025-12-31T10:15:00Z", pinned: true)
        let today = try makeItem("today", date: "2026-10-19T10:15:00Z")
        let yesterday = try makeItem("yesterday", date: "2026-10-18T10:15:00Z")
        let weekday = try makeItem("weekday", date: "2026-10-13T10:15:00Z")
        let older = try makeItem("older", date: "2026-10-12T10:15:00Z")
        client.pages = [try makePage([older, yesterday, pinned, today, weekday])]
        let model = AgentThreadListModel(client: client)

        await model.refresh()
        let now = date("2026-10-19T12:00:00Z")
        let sections = model.sections(relativeTo: now, calendar: calendar, locale: locale)

        XCTAssertEqual(sections.map { $0.items.map(\.thread.id) }, [[], ["pinned"], ["today"], ["yesterday"], ["weekday"], ["older"]])
        XCTAssertEqual(sections.map(\.id), [
            .news,
            .pinned,
            .day(date("2026-10-19T00:00:00Z")),
            .day(date("2026-10-18T00:00:00Z")),
            .day(date("2026-10-13T00:00:00Z")),
            .day(date("2026-10-12T00:00:00Z"))
        ])
        XCTAssertEqual(sections[4].title, "Tuesday")
        XCTAssertEqual(sections[5].title, "12 October")
    }

    func testDayGroupingUsesCalendarDays() {
        let now = date("2026-10-19T12:00:00Z")
        let values: [(String, AgentThreadDateFormatting.DayGroup)] = [
            ("2026-10-19T10:15:00Z", .today),
            ("2026-10-18T23:59:00Z", .yesterday),
            ("2026-10-13T10:15:00.000Z", .weekday),
            ("2026-10-12T10:15:00Z", .date),
            ("2025-12-31T10:15:00Z", .date)
        ]
        for (timestamp, expectedGroup) in values {
            XCTAssertEqual(AgentThreadDateFormatting.dayGroup(for: date(timestamp), relativeTo: now, calendar: calendar), expectedGroup)
        }

        var moscow = calendar
        moscow.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60)!
        XCTAssertEqual(AgentThreadDateFormatting.dayGroup(
            for: date("2026-10-18T22:15:00Z"), relativeTo: now, calendar: moscow
        ), .today)
    }

    func testRowTimestampsShowTimeUnderDayHeadersAndDatesForPinnedRows() {
        let now = date("2026-10-19T12:00:00Z")
        let format = AgentThreadDateFormatting.DeviceDateTimeFormat(
            isUsing24HourTime: true, dateOrder: .dayFirst, dateSeparator: ".", dateSuffix: "", isFullYearRequired: false
        )
        let values: [(String, String, String)] = [
            ("2026-10-19T10:15:00Z", "10:15", "10:15"),
            ("2026-10-18T23:59:00Z", "23:59", lang("Yesterday")),
            ("2026-10-13T10:15:00Z", "10:15", "Tue"),
            ("2026-10-12T10:15:00Z", "10:15", "12.10"),
            ("2026-01-02T08:05:00Z", "08:05", "02.01"),
            ("2025-12-31T10:15:00Z", "10:15", "31.12.25")
        ]
        for (timestamp, dayRow, pinnedRow) in values {
            XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: false, relativeTo: now,
                calendar: calendar, locale: locale, deviceFormat: format
            ), dayRow, timestamp)
            XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: true, relativeTo: now,
                calendar: calendar, locale: locale, deviceFormat: format
            ), pinnedRow, timestamp)
        }

        var moscow = calendar
        moscow.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60)!
        XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
            for: date("2026-10-18T22:15:00Z"), shouldShowDateWhenNotToday: true, relativeTo: now,
            calendar: moscow, locale: locale, deviceFormat: format
        ), "01:15")
    }

    func testPinnedRowsShowYesterdaysTimeForTwelveHours() {
        let format = AgentThreadDateFormatting.DeviceDateTimeFormat(
            isUsing24HourTime: true, dateOrder: .dayFirst, dateSeparator: ".", dateSuffix: "", isFullYearRequired: false
        )
        func formatTimestamp(_ timestamp: String, at now: String) -> String {
            AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: true, relativeTo: date(now),
                calendar: calendar, locale: locale, deviceFormat: format
            )
        }
        // News an hour before midnight, seen just after it
        XCTAssertEqual(formatTimestamp("2026-10-27T23:57:00Z", at: "2026-10-28T00:57:00Z"), "23:57")
        XCTAssertEqual(formatTimestamp("2026-10-27T23:59:59Z", at: "2026-10-28T00:00:00Z"), "23:59")
        XCTAssertEqual(formatTimestamp("2026-10-28T00:00:00Z", at: "2026-10-28T00:00:00Z"), "00:00")
        // Just under and at 12 hours
        XCTAssertEqual(formatTimestamp("2026-10-27T20:00:01Z", at: "2026-10-28T08:00:00Z"), "20:00")
        XCTAssertEqual(formatTimestamp("2026-10-27T20:00:00Z", at: "2026-10-28T08:00:00Z"), lang("Yesterday"))
        XCTAssertEqual(formatTimestamp("2026-10-27T00:00:00Z", at: "2026-10-28T23:59:00Z"), lang("Yesterday"))
        // Two days back and a week back keep the weekday and the date
        XCTAssertEqual(formatTimestamp("2026-10-26T23:00:00Z", at: "2026-10-28T01:00:00Z"), "Mon")
        XCTAssertEqual(formatTimestamp("2026-10-22T10:00:00Z", at: "2026-10-28T10:00:00Z"), "Thu")
        XCTAssertEqual(formatTimestamp("2026-10-21T10:00:00Z", at: "2026-10-28T10:00:00Z"), "21.10")
        // Yesterday follows the same hours across a new year
        XCTAssertEqual(formatTimestamp("2026-12-31T23:30:00Z", at: "2027-01-01T00:30:00Z"), "23:30")
        XCTAssertEqual(formatTimestamp("2026-12-31T08:00:00Z", at: "2027-01-01T20:00:00Z"), lang("Yesterday"))
        // Rows under the day headers keep the time
        XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
            for: date("2026-10-27T08:00:00Z"), shouldShowDateWhenNotToday: false, relativeTo: date("2026-10-28T20:00:00Z"),
            calendar: calendar, locale: locale, deviceFormat: format
        ), "08:00")
    }

    func testRowTimestampsFollowTheDeviceClockAndDateOrder() {
        let now = date("2026-10-19T12:00:00Z")
        let american = AgentThreadDateFormatting.DeviceDateTimeFormat(
            isUsing24HourTime: false, dateOrder: .monthFirst, dateSeparator: "/", dateSuffix: "", isFullYearRequired: false
        )
        func formatTimestamp(_ timestamp: String, shouldHideDate: Bool = false) -> String {
            AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: !shouldHideDate, relativeTo: now,
                calendar: calendar, locale: locale, deviceFormat: american
            )
        }
        XCTAssertEqual(formatTimestamp("2026-10-19T00:30:00Z"), "12:30\u{00a0}AM")
        XCTAssertEqual(formatTimestamp("2026-10-19T11:05:00Z"), "11:05\u{00a0}AM")
        XCTAssertEqual(formatTimestamp("2026-10-19T12:00:00Z"), "12:00\u{00a0}PM")
        XCTAssertEqual(formatTimestamp("2026-10-18T13:05:00Z", shouldHideDate: true), "1:05\u{00a0}PM")
        XCTAssertEqual(formatTimestamp("2026-10-12T10:15:00Z"), "10/12")
        XCTAssertEqual(formatTimestamp("2025-12-31T10:15:00Z"), "12/31/25")

        let dotted = AgentThreadDateFormatting.DeviceDateTimeFormat(
            isUsing24HourTime: true, dateOrder: .dayFirst, dateSeparator: ".", dateSuffix: ".", isFullYearRequired: true
        )
        XCTAssertEqual(dotted.formatDate(day: 31, month: 12, year: 2025), "31.12.2025.")
        XCTAssertEqual(dotted.formatDate(day: 2, month: 1, year: nil), "02.01.")
        XCTAssertEqual(dotted.formatTime(hour: 9, minute: 7), "09:07")
    }

    @MainActor
    func testCursorPaginationMergesByThreadIdAndRefreshPreservesLoadedDepth() async throws {
        let client = ThreadListClient()
        let first = try makeItem("first", date: "2026-10-19T10:00:00Z", preview: "Old preview")
        let updatedFirst = try makeItem("first", date: "2026-10-19T10:00:00Z", preview: "New preview")
        let second = try makeItem("second", date: "2026-10-18T10:00:00Z")
        client.pages = [
            try makePage([first], cursor: "next-page"),
            try makePage([updatedFirst, second]),
            try makePage([second], cursor: "refreshed-page"),
            try makePage([updatedFirst], cursor: "remaining-page")
        ]
        let model = AgentThreadListModel(client: client)

        await model.refresh()
        XCTAssertEqual(model.nextCursor, "next-page")
        await model.loadMore()
        XCTAssertEqual(model.items.map(\.thread.id), ["first", "second"])
        XCTAssertEqual(model.items.first?.preview, "New preview")
        XCTAssertNil(model.nextCursor)
        await model.loadMore()
        XCTAssertEqual(client.listRequests.count, 2)
        await model.refresh()

        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, "next-page", nil, "refreshed-page"])
        XCTAssertTrue(client.listRequests.allSatisfy { $0.limit == 30 && $0.query == nil })
        XCTAssertEqual(model.items.map(\.thread.id), ["first", "second"])
        XCTAssertEqual(model.nextCursor, "remaining-page")
    }

    @MainActor
    func testRefreshReplacesLoadedPagesAndStopsAtTheNewEndOfTheList() async throws {
        let client = ThreadListClient()
        let original = try (0..<60).map {
            try makeItem("thread-\($0)", date: "2026-10-19T10:00:00Z", preview: "Old answer")
        }
        let current = try (15..<60).map {
            try makeItem("thread-\($0)", date: "2026-10-19T10:00:00Z", preview: "Fresh answer")
        }
        client.pages = [
            try makePage(Array(original.prefix(30)), cursor: "old-second"),
            try makePage(Array(original.suffix(30)), cursor: "old-third"),
            try makePage(Array(current.prefix(30)), cursor: "new-second"),
            try makePage(Array(current.dropFirst(30)))
        ]
        let model = AgentThreadListModel(client: client)
        await model.refresh()
        await model.loadMore()
        XCTAssertEqual(model.items.count, 60)

        await model.refresh()

        XCTAssertEqual(model.items.count, 45)
        XCTAssertEqual(Set(model.items.map(\.thread.id)), Set(current.map(\.thread.id)))
        XCTAssertTrue(model.items.allSatisfy { $0.preview == "Fresh answer" })
        XCTAssertNil(model.nextCursor)
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, "old-second", nil, "new-second"])
        XCTAssertTrue(client.listRequests.allSatisfy { $0.limit == 30 })
    }

    @MainActor
    func testRepeatedCursorStopsPagination() async throws {
        let client = ThreadListClient()
        client.pages = [try makePage([], cursor: "same"), try makePage([], cursor: "same")]
        let model = AgentThreadListModel(client: client)

        await model.refresh()
        await model.loadMore()
        await model.loadMore()

        XCTAssertNil(model.nextCursor)
        XCTAssertEqual(client.listRequests.count, 2)
    }

    @MainActor
    func testFailedInitialLoadAndRefreshStaySilentAndPreserveRows() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        let error = try makeMutationError(.networkError)
        client.listError = error
        let model = AgentThreadListModel(client: client)
        var errorCount = 0
        model.onError = { _ in errorCount += 1 }

        await model.refresh()

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.nextCursor)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(errorCount, 0)

        client.listError = nil
        client.pages = [try makePage([original], cursor: "next-page")]
        await model.refresh()
        client.listError = error

        await model.refresh()

        XCTAssertEqual(model.items, [original])
        XCTAssertEqual(model.nextCursor, "next-page")
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(errorCount, 0)
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, nil, nil])
    }

    @MainActor
    func testFailedPaginationStaysSilentAndPreservesRowsAndCursor() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        client.pages = [try makePage([original], cursor: "next-page")]
        let model = AgentThreadListModel(client: client)
        var errorCount = 0
        model.onError = { _ in errorCount += 1 }
        await model.refresh()
        client.listError = try makeMutationError(.networkError)

        await model.loadMore()

        XCTAssertEqual(model.items, [original])
        XCTAssertEqual(model.nextCursor, "next-page")
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(errorCount, 0)
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, "next-page"])
    }

    @MainActor
    func testRenameResetPinUnpinAndDeleteUseServerSummaries() async throws {
        var notificationCount = 0
        let subscription = AgentSearchProvider.shared.conversationChanged.sink { notificationCount += 1 }
        defer { subscription.cancel() }
        let client = ThreadListClient()
        let original = try makeItem("older", date: "2026-10-18T10:00:00Z", preview: "Answer preview")
        let newer = try makeItem("newer", date: "2026-10-19T10:00:00Z")
        let renamed = try makeItem("older", date: "2026-10-18T10:00:00Z", title: "Server title", customTitle: true)
        let reset = try makeItem("older", date: "2026-10-18T10:00:00Z", title: "Agent title", customTitle: false)
        let pinned = try makeItem("older", date: "2026-10-18T10:00:00Z", pinned: true, title: "Agent title")
        client.pages = [try makePage([original, newer])]
        client.updatedThreads = [renamed.thread, reset.thread, pinned.thread, reset.thread]
        let model = AgentThreadListModel(client: client)
        await model.refresh()

        await model.rename(original.thread, title: "  My title \n")
        XCTAssertEqual(client.updateRequests[0].update, .init(title: "My title"))
        XCTAssertEqual(model.items.last?.thread.title, "Server title")
        XCTAssertEqual(model.items.last?.thread.hasCustomTitle, true)
        XCTAssertEqual(model.items.last?.preview, "Answer preview")

        await model.rename(renamed.thread, title: " \n ")
        XCTAssertEqual(client.updateRequests[1].update, .init(title: nil))
        let resetJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(client.updateRequests[1].update)) as? [String: Any])
        XCTAssertTrue(resetJSON["title"] is NSNull)
        XCTAssertEqual(model.items.last?.thread.title, "Agent title")
        XCTAssertEqual(model.items.last?.thread.hasCustomTitle, false)

        await model.setPinned(reset.thread, isPinned: true)
        XCTAssertEqual(client.updateRequests[2].update, .init(isPinned: true))
        XCTAssertEqual(model.items.map(\.thread.id), ["older", "newer"])
        XCTAssertEqual(model.sections().map(\.id).prefix(2), [.news, .pinned])

        await model.setPinned(pinned.thread, isPinned: false)
        XCTAssertEqual(client.updateRequests[3].update, .init(isPinned: false))
        XCTAssertEqual(model.items.map(\.thread.id), ["newer", "older"])

        await model.delete(reset.thread)
        XCTAssertEqual(client.deletedThreadIds, ["older"])
        XCTAssertEqual(model.items.map(\.thread.id), ["newer"])
        XCTAssertEqual(client.listRequests.count, 1)
        XCTAssertEqual(notificationCount, 5)
    }

    @MainActor
    func testFailedMutationsKeepRowsAndReportLocalizedErrors() async throws {
        var notificationCount = 0
        let subscription = AgentSearchProvider.shared.conversationChanged.sink { notificationCount += 1 }
        defer { subscription.cancel() }
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        client.pages = [try makePage([original])]
        let model = AgentThreadListModel(client: client)
        var errorTexts: [String] = []
        model.onError = { errorTexts.append($0.text) }
        await model.refresh()

        let errors: [(Error, String)] = [
            (try makeMutationError(.networkError), AgentV2Copy.error(.networkError)),
            (ThreadListError.unavailable, lang("$agent_error_generic"))
        ]
        for (error, expectedText) in errors {
            client.mutationError = error
            errorTexts = []

            await model.rename(original.thread, title: "New title")
            await model.setPinned(original.thread, isPinned: true)
            await model.delete(original.thread)

            XCTAssertEqual(model.items, [original])
            XCTAssertEqual(errorTexts, Array(repeating: expectedText, count: 3))
        }

        XCTAssertEqual(notificationCount, 0)
    }

    @MainActor
    func testReadRecordsPreservePendingBaselinesAcrossRestart() throws {
        let suite = "AgentThreadListTests.ReadState.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("""
        {"records":{
            "known":{"seenMessageCount":2,"needsBaseline":false,"isMarkedUnread":false},
            "pending":{"seenMessageCount":3,"needsBaseline":true,"isMarkedUnread":false}
        },"order":["known","pending"]}
        """.utf8), forKey: "agent-thread-read-state")
        let readState = AgentThreadReadState(userDefaults: defaults)
        let known = try makeItem("known", date: "2026-10-19T10:00:00Z", messageCount: 3).thread
        let unknown = try makeItem("unknown", date: "2026-10-19T10:00:00Z", messageCount: 3).thread
        let pending = try makeItem("pending", date: "2026-10-19T10:00:00Z", messageCount: 5).thread

        XCTAssertFalse(readState.isUnread(pending))
        readState.observe([known, unknown, pending], answeringThreadIds: [])

        XCTAssertTrue(readState.isUnread(known))
        XCTAssertFalse(readState.isUnread(unknown))
        XCTAssertFalse(readState.isUnread(pending))
        var changes = 0
        let subscription = NotificationCenter.default.publisher(for: AgentThreadReadState.didChangeNotification)
            .sink { _ in changes += 1 }
        defer { subscription.cancel() }

        readState.chatDidAppear(threadId: known.id)

        XCTAssertFalse(readState.isUnread(known))
        XCTAssertEqual(changes, 1)

        readState.chatDidAppear(threadId: unknown.id)
        let completed = try makeItem(unknown.id, date: "2026-10-19T10:00:00Z", messageCount: 5).thread
        let restarted = AgentThreadReadState(userDefaults: defaults)

        XCTAssertFalse(restarted.isUnread(completed))
        restarted.observe([completed], answeringThreadIds: [])
        XCTAssertFalse(restarted.isUnread(completed))
    }

    @MainActor
    func testDeletionEventRemovesThreadAndReadStateWithoutServerAccess() async throws {
        let suite = "AgentThreadListTests.Deletion.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let readState = AgentThreadReadState(userDefaults: defaults)
        let client = ThreadListClient()
        let item = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        client.pages = [try makePage([item])]
        let model = AgentThreadListModel(client: client, threadReadState: readState)
        await model.refresh()
        readState.answerDidComplete(threadId: item.thread.id)
        XCTAssertTrue(readState.isUnread(item.thread))
        client.listError = ThreadListError.unavailable
        client.mutationError = ThreadListError.unavailable
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {})
        var changes = 0
        model.onChange = { changes += 1 }

        controller.walletCore(event: .agentThreadDeleted(threadId: item.thread.id))

        XCTAssertFalse(model.sections().flatMap(\.items).contains { $0.thread.id == item.thread.id })
        XCTAssertFalse(AgentThreadReadState(userDefaults: defaults).isUnread(item.thread))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(client.listRequests.count, 1)
        XCTAssertTrue(client.deletedThreadIds.isEmpty)
    }

    @MainActor
    func testFailedPinKeepsThreadUpdatesReceivedDuringTheRequest() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z", title: "Old title", preview: "Old preview")
        let updated = try makeItem(
            "thread", date: "2026-10-19T11:00:00Z", pinned: true, title: "New title", preview: "New preview",
            revision: 2, messageCount: 4
        )
        client.pages = [try makePage([original]), try makePage([updated])]
        client.mutationError = ThreadListError.unavailable
        let model = AgentThreadListModel(client: client)
        await model.refresh()
        client.onUpdate = { [weak model] in
            XCTAssertEqual(model?.items.first?.thread.isPinned, true)
            await model?.refresh()
        }

        await model.setPinned(original.thread, isPinned: true)

        XCTAssertEqual(model.items.first?.thread, updated.thread.makeCopy(isPinned: false))
        XCTAssertEqual(model.items.first?.preview, "New preview")
        XCTAssertEqual(client.updateRequests.count, 1)
    }

    @MainActor
    func testCancelledMutationsKeepRowsAndStaySilent() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        client.pages = [try makePage([original])]
        let model = AgentThreadListModel(client: client)
        var errorCount = 0
        model.onError = { _ in errorCount += 1 }
        await model.refresh()
        let errors: [Error] = [CancellationError(), try makeMutationError(.runInterrupted)]

        for error in errors {
            client.mutationError = error

            await model.rename(original.thread, title: "New title")
            await model.setPinned(original.thread, isPinned: true)
            await model.delete(original.thread)

            XCTAssertEqual(model.items, [original])
            XCTAssertEqual(errorCount, 0)
        }
    }

    @MainActor
    func testNewerRefreshDiscardsAnOlderInflightResponse() async throws {
        let client = ThreadListClient()
        let old = try makePage([makeItem("old", date: "2026-10-19T10:00:00Z")])
        let current = try makePage([makeItem("current", date: "2026-10-19T11:00:00Z")])
        client.pages = [current]
        client.suspendNextList = true
        let started = expectation(description: "Old request started")
        client.onList = { _ in started.fulfill() }
        let model = AgentThreadListModel(client: client)
        let oldRefresh = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 1)
        client.onList = nil

        await model.refresh()
        client.resumeList(with: old)
        await oldRefresh.value

        XCTAssertEqual(model.items.map(\.thread.id), ["current"])
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(client.listRequests.allSatisfy { $0.query == nil })
    }

    @MainActor
    func testMutationDiscardsAnInflightListResponse() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        let pinned = try makeItem("thread", date: "2026-10-19T10:00:00Z", pinned: true)
        let originalPage = try makePage([original])
        client.pages = [originalPage]
        client.updatedThreads = [pinned.thread]
        let model = AgentThreadListModel(client: client)
        await model.refresh()
        client.suspendNextList = true
        let started = expectation(description: "Refresh started")
        client.onList = { _ in started.fulfill() }
        let refresh = Task { await model.refresh() }
        await fulfillment(of: [started], timeout: 1)

        await model.setPinned(original.thread, isPinned: true)
        client.resumeList(with: originalPage)
        await refresh.value

        XCTAssertEqual(model.items.first?.thread.isPinned, true)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testNewsIsFirstWithNoChats() async throws {
        let client = ThreadListClient()
        client.pages = [try makePage([])]
        let model = AgentThreadListModel(client: client)

        await model.refresh()

        XCTAssertEqual(model.sections().map(\.id), [.news])
        XCTAssertEqual(model.sections().first?.itemIdentifiers, [AgentThreadListSection.newsItemId])
    }

    @MainActor
    func testFirstNewsLoadInitializesReadThroughAndUsesApplicationLanguage() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgentThreadListTests.\(UUID().uuidString)"))
        let readState = AgentNewsReadState(userDefaults: defaults)
        let newsClient = ThreadListNewsClient(items: [
            newsItem(1, deliveredAt: "2026-10-19T10:00:00Z"),
            newsItem(2, deliveredAt: "2026-10-19T11:00:00Z")
        ])
        let model = AgentThreadListModel(newsClient: newsClient, readState: readState, language: { "ru-RU" })

        XCTAssertNil(model.latestNews)
        await model.refreshNews()

        XCTAssertEqual(newsClient.requests.map(\.lang), ["ru-RU"])
        XCTAssertEqual(newsClient.requests.map(\.cursor), [nil])
        XCTAssertEqual(model.latestNews?.eventId, 2)
        XCTAssertEqual(readState.readThrough, "2026-10-19T11:00:00Z")
        XCTAssertEqual(model.newsUnreadCount, 0)
    }

    @MainActor
    func testNewsUnreadCountUsesReadThrough() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgentThreadListTests.\(UUID().uuidString)"))
        let readState = AgentNewsReadState(userDefaults: defaults)
        let baseline = newsItem(0, deliveredAt: "2026-10-18T10:00:00Z")
        readState.markRead(items: [baseline])
        let newsClient = ThreadListNewsClient(items: [
            newsItem(1, deliveredAt: "2026-10-19T10:00:00Z"),
            baseline,
            newsItem(2, deliveredAt: "2026-10-19T11:00:00Z")
        ])
        let model = AgentThreadListModel(newsClient: newsClient, readState: readState)

        await model.refreshNews()
        XCTAssertEqual(model.newsUnreadCount, 2)

        newsClient.items = (1...30).map { newsItem($0, deliveredAt: "2026-10-19T10:00:00Z") }
        await model.refreshNews()
        XCTAssertEqual(model.newsUnreadCount, 30)

        await model.makeNewsFeedModel().refresh()
        XCTAssertEqual(model.newsUnreadCount, 0)
    }

    @MainActor
    func testNewsFeedFindsThreadsFromEveryLoadedPageWithoutRetainingTheList() async throws {
        let client = ThreadListClient()
        let first = try makeItem("first", date: "2026-10-19T11:00:00Z")
        let older = try makeItem("older", date: "2026-10-19T10:00:00Z")
        client.pages = [try makePage([first], cursor: "older"), try makePage([older])]
        var model: AgentThreadListModel? = AgentThreadListModel(client: client)
        await model?.refresh()
        let feed = try XCTUnwrap(model?.makeNewsFeedModel())
        XCTAssertEqual(feed.findThread("first"), first.thread)
        XCTAssertNil(feed.findThread("older"))

        await model?.loadMore()

        XCTAssertEqual(feed.findThread("older"), older.thread)
        XCTAssertNil(feed.findThread("unloaded"))
        weak var weakModel = model
        model = nil
        XCTAssertNil(weakModel)
        XCTAssertNil(feed.findThread("first"))
    }

    @MainActor
    func testNewsRefreshFailureKeepsLastSuccessfulPreview() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgentThreadListTests.\(UUID().uuidString)"))
        let newsClient = ThreadListNewsClient(items: [newsItem(1, deliveredAt: "2026-10-19T10:00:00Z")])
        let model = AgentThreadListModel(newsClient: newsClient, readState: AgentNewsReadState(userDefaults: defaults))
        await model.refreshNews()

        newsClient.shouldFail = true
        await model.refreshNews()

        XCTAssertEqual(model.latestNews?.eventId, 1)
        XCTAssertEqual(model.sections().map(\.id), [.news])
    }

    // MARK: - Answering status

    @MainActor
    func testRunUpdatesShowEachStepThenTheWritingUntilTheAnswerCompletes() throws {
        var tracker = AgentThreadActivityTracker()
        let now = date("2026-10-19T12:00:00Z")
        let analyzing = lang("$agent_activity_analyzing_request")

        XCTAssertEqual(tracker.handle(try update("runStarted", thread: "a", extra: ["threadRevision": 2]), now: now), ["a"])
        XCTAssertEqual(tracker.getText(threadId: "a"), analyzing)
        XCTAssertNil(tracker.getText(threadId: "b"))

        let planning = try makeActivityUpdate(thread: "a", code: "request.planning", status: "active")
        XCTAssertEqual(tracker.handle(planning, now: now), ["a"])
        XCTAssertEqual(tracker.getText(threadId: "a"), lang("$agent_activity_planning"))
        XCTAssertEqual(tracker.handle(planning, now: now), [])

        let delta = try update("textDelta", thread: "a", extra: ["messageId": "answer", "delta": "Hi"])
        XCTAssertEqual(tracker.handle(delta, now: now), ["a"])
        XCTAssertEqual(tracker.getText(threadId: "a"), lang("$agent_activity_writing"))
        XCTAssertEqual(tracker.handle(delta, now: now), [], "Streaming text does not change the status again")
        XCTAssertEqual(tracker.handle(try update("followupsAvailable", thread: "a", extra: [
            "messageId": "answer", "items": [] as [Any],
        ]), now: now), [])

        let completed = try update("messageCompleted", thread: "a", extra: ["messageId": "answer", "finishReason": "complete"])
        XCTAssertEqual(tracker.handle(completed, now: now), ["a"])
        XCTAssertNil(tracker.getText(threadId: "a"))
        XCTAssertEqual(tracker.handle(try makeActivityUpdate(thread: "a", code: "answer.writing", status: "completed"), now: now), [])
        XCTAssertNil(tracker.getText(threadId: "a"))

        XCTAssertEqual(tracker.handle(try update("runStarted", thread: "a", run: "run-2", extra: ["threadRevision": 3]), now: now), ["a"])
        XCTAssertEqual(tracker.getText(threadId: "a"), analyzing)
    }

    @MainActor
    func testFailedCancelledAndRevokedRunsEndTheirStatusButAnOlderRunKeepsANewerOne() throws {
        var tracker = AgentThreadActivityTracker()
        let now = date("2026-10-19T12:00:00Z")
        for thread in ["a", "b", "c", "d"] {
            _ = tracker.handle(try update("runStarted", thread: thread, run: "run-\(thread)", extra: ["threadRevision": 2]), now: now)
        }

        XCTAssertEqual(tracker.handle(try update("runFailed", thread: "a", run: "run-a", extra: [
            "code": "network_error", "retryable": true,
        ]), now: now), ["a"])
        XCTAssertEqual(tracker.handle(try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "runFailed", "clientRunId": "client-b", "threadId": "b", "code": "internal_error", "retryable": false,
        ])), now: now), ["b"])
        XCTAssertEqual(tracker.handle(try update("runCancelled", thread: "c", run: "run-c"), now: now), ["c"])
        XCTAssertEqual(Set(tracker.entries.keys), ["d"])

        // A newer run of the thread keeps its status when an older one completes
        _ = tracker.handle(try update("runStarted", thread: "d", run: "run-d2", extra: ["threadRevision": 3]), now: now)
        XCTAssertEqual(tracker.handle(try update("messageCompleted", thread: "d", run: "run-d", extra: [
            "messageId": "old", "finishReason": "complete",
        ]), now: now), [])
        XCTAssertNotNil(tracker.getText(threadId: "d"))

        let preserving = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "walletAuthorityChanged", "preservesActiveRuns": true,
        ]))
        XCTAssertEqual(tracker.handle(preserving, now: now), [])
        let revoked = try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: [
            "kind": "walletAuthorityChanged",
        ]))
        XCTAssertEqual(tracker.handle(revoked, now: now), ["d"])
        XCTAssertTrue(tracker.entries.isEmpty)
    }

    @MainActor
    func testLoadedChatsShowRunsTheListMissedAndEndOnesThatWentQuiet() throws {
        var tracker = AgentThreadActivityTracker()
        let start = date("2026-10-19T12:00:00Z")
        _ = tracker.handle(try makeActivityUpdate(thread: "tracked", code: "web.searching", status: "active"), now: start)
        _ = tracker.handle(try update("runStarted", thread: "quiet", run: "run-quiet", extra: ["threadRevision": 2]), now: start)
        _ = tracker.handle(try update("runStarted", thread: "done", run: "run-done", extra: ["threadRevision": 2]), now: start)

        let changed = tracker.sync(with: [
            .init(threadId: "missed", isAnswering: true, text: "Checking market data…"),
            .init(threadId: "tracked", isAnswering: true, text: lang("$agent_activity_analyzing_request")),
            .init(threadId: "done", isAnswering: false, text: nil),
            .init(threadId: "settling", isAnswering: true, text: nil),
        ], now: start)
        XCTAssertEqual(changed, ["missed", "done"])
        XCTAssertEqual(tracker.getText(threadId: "missed"), "Checking market data…")
        XCTAssertEqual(tracker.getText(threadId: "tracked"), lang("$agent_activity_web_searching"), "The run's own updates win")
        XCTAssertNil(tracker.getText(threadId: "done"))
        XCTAssertNil(tracker.getText(threadId: "settling"))

        let later = start.addingTimeInterval(AgentThreadActivityTracker.staleInterval + 1)
        XCTAssertEqual(tracker.sync(with: [.init(threadId: "tracked", isAnswering: true, text: nil)], now: later), ["missed", "quiet"])
        XCTAssertEqual(Set(tracker.entries.keys), ["tracked"])
    }

    @MainActor
    func testListModelReportsAnsweringStatusChangesAndDropsThemForDeletedThreads() throws {
        let model = AgentThreadListModel(client: ThreadListClient(), preloader: AgentPreloader(client: LiveAgentV2Client()))
        var reported: [Set<String>] = []
        model.onActivityChange = { reported.append($0) }

        model.handleAgentUpdate(try update("runStarted", thread: "a", extra: ["threadRevision": 2]))
        model.handleAgentUpdate(try update("textDelta", thread: "a", extra: ["messageId": "answer", "delta": "Hi"]))
        model.handleAgentUpdate(try update("textDelta", thread: "a", extra: ["messageId": "answer", "delta": "!"]))
        XCTAssertEqual(model.getActivityText(threadId: "a"), lang("$agent_activity_writing"))
        model.removeActivity(threadId: "a")
        model.removeActivity(threadId: "a")

        XCTAssertEqual(reported, [["a"], ["a"], ["a"]])
        XCTAssertNil(model.getActivityText(threadId: "a"))
    }

    private func update(
        _ kind: String,
        thread: String,
        run: String = "run-1",
        extra: [String: Any] = [:]
    ) throws -> ApiAgentV2ClientUpdate {
        var update: [String: Any] = ["kind": kind, "clientRunId": "client-\(run)", "runId": run, "threadId": thread]
        update.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: update))
    }

    private func makeActivityUpdate(thread: String, code: String, status: String, run: String = "run-1") throws -> ApiAgentV2ClientUpdate {
        try update("runActivityChanged", thread: thread, run: run, extra: [
            "event": ["protocolVersion": 2, "runId": run, "sequence": 1, "code": code, "status": status],
        ])
    }

    private func newsItem(_ id: Int, deliveredAt: String) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(eventId: id, deliveredAt: deliveredAt, headline: "Headline \(id)", body: "News body")
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var locale: Locale { Locale(identifier: "en_GB") }

    private func date(_ value: String) -> Date {
        AgentV2DateParser.date(value)
    }

    private func makeMutationError(_ code: ApiAgentV2ErrorCode) throws -> ApiAgentV2MutationError {
        try JSONDecoder().decode(ApiAgentV2MutationError.self, from: JSONSerialization.data(withJSONObject: [
            "code": code.rawValue, "retryable": true
        ]))
    }

    private func makeItem(
        _ id: String,
        date: String,
        pinned: Bool = false,
        title: String? = nil,
        customTitle: Bool = false,
        preview: String? = nil,
        revision: Int = 1,
        messageCount: Int = 2
    ) throws -> ApiAgentV2ThreadListItem {
        var json: [String: Any] = [
            "id": id,
            "revision": revision,
            "createdAt": date,
            "updatedAt": date,
            "lastActivityAt": date,
            "messageCount": messageCount,
            "isPinned": pinned,
            "hasCustomTitle": customTitle
        ]
        json["title"] = title
        let thread = try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: json))
        return ApiAgentV2ThreadListItem(thread: thread, preview: preview)
    }

    private func makePage(_ items: [ApiAgentV2ThreadListItem], cursor: String? = nil) throws -> ApiAgentV2ThreadListResponse {
        var json: [String: Any] = [
            "protocolVersion": 3,
            "threads": try JSONSerialization.jsonObject(with: JSONEncoder().encode(items))
        ]
        json["nextCursor"] = cursor
        return try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

@MainActor
final class ThreadListNewsClient: AgentNewsFeedClient {
    var items: [ApiAgentV2NewsFeedItem]
    var shouldFail = false
    private(set) var requests: [(lang: String, cursor: String?)] = []

    init(items: [ApiAgentV2NewsFeedItem] = []) {
        self.items = items
    }

    func getNewsFeed(lang: String, cursor: String?) async throws -> ApiAgentV2NewsFeedPage {
        requests.append((lang, cursor))
        if shouldFail { throw ThreadListError.unavailable }
        return ApiAgentV2NewsFeedPage(locale: "en", items: items)
    }
}

private enum ThreadListError: Error {
    case unavailable
}

@MainActor
private final class ThreadListClient: AgentThreadListClient {
    var pages: [ApiAgentV2ThreadListResponse] = []
    var updatedThreads: [ApiAgentV2ThreadSummary] = []
    var listError: Error?
    var mutationError: Error?
    var onList: ((ApiAgentV2ThreadListRequest) -> Void)?
    var onUpdate: (() async -> Void)?
    var suspendNextList = false
    private var listContinuation: CheckedContinuation<ApiAgentV2ThreadListResponse, Never>?
    private(set) var listRequests: [ApiAgentV2ThreadListRequest] = []
    private(set) var updateRequests: [(id: String, update: ApiAgentV2ThreadUpdate)] = []
    private(set) var deletedThreadIds: [String] = []

    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        let request = ApiAgentV2ThreadListRequest(cursor: cursor, limit: limit, query: query)
        listRequests.append(request)
        if suspendNextList {
            suspendNextList = false
            return await withCheckedContinuation { continuation in
                listContinuation = continuation
                onList?(request)
            }
        }
        if let listError { throw listError }
        guard !pages.isEmpty else { throw ThreadListError.unavailable }
        let page = pages.removeFirst()
        onList?(request)
        return page
    }

    func resumeList(with page: ApiAgentV2ThreadListResponse) {
        listContinuation?.resume(returning: page)
        listContinuation = nil
    }

    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        updateRequests.append((id, update))
        await onUpdate?()
        if let mutationError { throw mutationError }
        guard !updatedThreads.isEmpty else { throw ThreadListError.unavailable }
        let json: [String: Any] = [
            "protocolVersion": 3,
            "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(updatedThreads.removeFirst()))
        ]
        return try JSONDecoder().decode(ApiAgentV2ThreadUpdateResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        deletedThreadIds.append(id)
        if let mutationError { throw mutationError }
        return try JSONDecoder().decode(ApiAgentV2ThreadDeleteResponse.self, from: JSONSerialization.data(withJSONObject: [
            "protocolVersion": 3, "threadId": id, "duplicate": false
        ]))
    }
}
