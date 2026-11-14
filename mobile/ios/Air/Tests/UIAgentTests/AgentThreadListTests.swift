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
            ("2026-10-18T23:59:00Z", "23:59", "Sun"),
            ("2026-10-13T10:15:00Z", "10:15", "Tue"),
            ("2026-10-12T10:15:00Z", "10:15", "12 Oct"),
            ("2026-01-02T08:05:00Z", "08:05", "2 Jan"),
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

    /// Another year's day goes without the year's abbreviated word, as "7 ноября 2025", and a month abbreviated with dots
    /// inside keeps them all, as Telegram writes dates
    func testDatesLeaveOutTheYearWordAndKeepAMonthsInnerDots() {
        let now = date("2026-11-07T12:00:00Z")
        let russian = Locale(identifier: "ru_RU")
        XCTAssertEqual(
            AgentThreadDateFormatting.formatDay(for: date("2025-11-07T10:00:00Z"), relativeTo: now, calendar: calendar, locale: russian),
            "7 ноября 2025"
        )
        XCTAssertEqual(
            AgentThreadDateFormatting.formatDay(for: date("2026-11-03T10:00:00Z"), relativeTo: now, calendar: calendar, locale: russian),
            "3 ноября"
        )
        func formatShortDay(_ identifier: String) -> String {
            AgentThreadDateFormatting.makeDotlessFormatter(template: "MMMd", calendar: calendar, locale: Locale(identifier: identifier))
                .string(from: date("2026-10-07T10:00:00Z"))
        }
        // A word after the year that joins it to the time, as English's "at", stays
        let english = Locale(identifier: "en_US")
        let systemFormatter = DateFormatter()
        systemFormatter.calendar = calendar
        systemFormatter.locale = english
        systemFormatter.timeZone = calendar.timeZone
        systemFormatter.setLocalizedDateFormatFromTemplate("yMMMdjmm")
        let lastYear = date("2025-07-20T15:38:00Z")
        XCTAssertEqual(
            AgentThreadDateFormatting.makeDotlessFormatter(template: "yMMMdjmm", calendar: calendar, locale: english)
                .string(from: lastYear),
            systemFormatter.string(from: lastYear)
        )
        let german = formatShortDay("de_DE")
        XCTAssertTrue(german.contains("Okt"), german)
        XCTAssertFalse(german.contains("Okt."), german)
        XCTAssertTrue(formatShortDay("th_TH").contains("ต.ค."))
    }

    /// A day later than now, as a server clock running ahead may stamp it, is today, as on Android and Classic
    func testADayLaterThanNowIsToday() {
        let now = date("2026-11-07T12:00:00Z")
        let tomorrow = date("2026-11-08T09:05:00Z")
        XCTAssertEqual(AgentThreadDateFormatting.dayGroup(for: tomorrow, relativeTo: now, calendar: calendar), .today)
        XCTAssertEqual(
            AgentThreadDateFormatting.formatDay(for: tomorrow, relativeTo: now, calendar: calendar, locale: locale),
            lang("Today")
        )
    }

    /// Pinned rows and News name the weekday for the last seven days, yesterday included, as on every platform
    func testPinnedRowsShowTheWeekdayForTheLastWeek() {
        let format = AgentThreadDateFormatting.DeviceDateTimeFormat(
            isUsing24HourTime: true, dateOrder: .dayFirst, dateSeparator: ".", dateSuffix: "", isFullYearRequired: false
        )
        func formatTimestamp(_ timestamp: String, at now: String) -> String {
            AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: true, relativeTo: date(now),
                calendar: calendar, locale: locale, deviceFormat: format
            )
        }
        // Today's time, up to midnight
        XCTAssertEqual(formatTimestamp("2026-10-28T00:00:00Z", at: "2026-10-28T00:00:00Z"), "00:00")
        XCTAssertEqual(formatTimestamp("2026-10-28T23:59:00Z", at: "2026-10-28T23:59:30Z"), "23:59")
        // Yesterday is a weekday as soon as the day turns, however recent
        XCTAssertEqual(formatTimestamp("2026-10-27T23:57:00Z", at: "2026-10-28T00:57:00Z"), "Tue")
        XCTAssertEqual(formatTimestamp("2026-10-27T00:00:00Z", at: "2026-10-28T23:59:00Z"), "Tue")
        // Six days back keep the weekday, and a week back is a date with the short month
        XCTAssertEqual(formatTimestamp("2026-10-26T23:00:00Z", at: "2026-10-28T01:00:00Z"), "Mon")
        XCTAssertEqual(formatTimestamp("2026-10-22T10:00:00Z", at: "2026-10-28T10:00:00Z"), "Thu")
        XCTAssertEqual(formatTimestamp("2026-10-21T10:00:00Z", at: "2026-10-28T10:00:00Z"), "21 Oct")
        // Every Russian month is cut to three letters
        for (timestamp, text) in [("2026-09-04T10:00:00Z", "4 сен"), ("2026-02-04T10:00:00Z", "4 фев")] {
            XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
                for: date(timestamp), shouldShowDateWhenNotToday: true, relativeTo: date("2026-10-28T10:00:00Z"),
                calendar: calendar, locale: Locale(identifier: "ru_RU"), deviceFormat: format
            ), text)
        }
        // The last week names its weekdays across a new year too, and an older day of the last year has its year
        XCTAssertEqual(formatTimestamp("2026-12-31T23:30:00Z", at: "2027-01-01T00:30:00Z"), "Thu")
        XCTAssertEqual(formatTimestamp("2026-12-20T08:00:00Z", at: "2027-01-01T20:00:00Z"), "20.12.26")
        // Rows under the day headers keep the time
        XCTAssertEqual(AgentThreadDateFormatting.formatRowTimestamp(
            for: date("2026-10-27T08:00:00Z"), shouldShowDateWhenNotToday: false, relativeTo: date("2026-10-28T20:00:00Z"),
            calendar: calendar, locale: locale, deviceFormat: format
        ), "08:00")
    }

    /// A chat's date lines and News' day capsules name the day as every platform does: today and yesterday by name, then
    /// the day and the month, with the year only for another year, and never a weekday
    @MainActor
    func testDayIsTodayYesterdayOrTheDateWithoutAWeekday() throws {
        let now = date("2026-10-19T12:00:00Z")
        func formatDay(_ timestamp: String, in locale: Locale) -> String {
            AgentThreadDateFormatting.formatDay(for: date(timestamp), relativeTo: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(formatDay("2026-10-19T00:00:00Z", in: locale), lang("Today"))
        XCTAssertEqual(formatDay("2026-10-18T23:59:00Z", in: locale), lang("Yesterday"))
        XCTAssertEqual(formatDay("2026-10-13T10:15:00Z", in: locale), "13 October")
        XCTAssertEqual(formatDay("2026-01-02T10:15:00Z", in: locale), "2 January")
        XCTAssertEqual(formatDay("2025-11-07T10:15:00Z", in: locale), "7 November 2025")
        let russian = Locale(identifier: "ru")
        XCTAssertEqual(formatDay("2026-10-13T10:15:00Z", in: russian), "13 октября")
        XCTAssertTrue(formatDay("2025-11-07T10:15:00Z", in: russian).hasPrefix("7 ноября 2025"))

        // A chat's date line adds the time on the device's clock, and the menu of a message names its day the same way
        let appCalendar = LocalizationSupport.shared.calendar
        let today = Date()
        let yesterday = try XCTUnwrap(appCalendar.date(byAdding: .day, value: -1, to: today))
        let fourDaysAgo = try XCTUnwrap(appCalendar.date(byAdding: .day, value: -4, to: today))
        XCTAssertEqual(AgentModel.formatChatDate(for: today, relativeTo: today).date, lang("Today"))
        XCTAssertEqual(AgentModel.formatChatDate(for: yesterday, relativeTo: today).date, lang("Yesterday"))
        let dayText = AgentModel.formatChatDate(for: fourDaysAgo, relativeTo: today).date
        XCTAssertEqual(dayText, AgentThreadDateFormatting.formatDay(for: fourDaysAgo, relativeTo: today))
        XCTAssertNotEqual(
            dayText,
            AgentThreadDateFormatting.headerText(for: fourDaysAgo, relativeTo: today),
            "A weekday heads the chat list's day sections only"
        )
        XCTAssertEqual(
            AgentModel.formatChatDate(for: today, relativeTo: today).time,
            BaseAgentModel.formattedTime(today, locale: LocalizationSupport.shared.locale)
        )
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
        // A date of this year names its month in the app's language; an older one is numeric in the device's order
        XCTAssertEqual(formatTimestamp("2026-10-12T10:15:00Z"), "12 Oct")
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

    /// A first load that fails without chats to show marks the list failed until a load brings them; a refresh that
    /// fails keeps the chats shown without a failure, and none of it shows a toast
    @MainActor
    func testFailedLoadWithoutChatsMarksTheListFailedAndAFailedRefreshKeepsRows() async throws {
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
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.hasLoadFailed)
        XCTAssertEqual(model.sections().map(\.id), [.news])
        XCTAssertEqual(errorCount, 0)

        client.listError = nil
        client.pages = [try makePage([original], cursor: "next-page")]
        await model.refresh()
        XCTAssertFalse(model.hasLoadFailed)
        client.listError = error

        await model.refresh()

        XCTAssertEqual(model.items, [original])
        XCTAssertEqual(model.nextCursor, "next-page")
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasLoadFailed)
        XCTAssertFalse(model.hasPageLoadFailed)
        XCTAssertEqual(errorCount, 0)
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, nil, nil])
    }

    /// A page that fails to load keeps the rows and the cursor, and ends the list with its failure line until the page
    /// loads, without a toast
    @MainActor
    func testFailedPaginationEndsTheListWithAFailureLineUntilThePageLoads() async throws {
        let client = ThreadListClient()
        let original = try makeItem("thread", date: "2026-10-19T10:00:00Z")
        let older = try makeItem("older", date: "2026-10-18T10:00:00Z")
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
        XCTAssertTrue(model.hasPageLoadFailed)
        XCTAssertFalse(model.hasLoadFailed)
        XCTAssertEqual(model.sections().last?.id, .pageFailure)
        XCTAssertEqual(model.sections().last?.itemIdentifiers, [AgentThreadListSection.pageFailureItemId])
        XCTAssertEqual(errorCount, 0)

        client.listError = nil
        client.pages = [try makePage([older])]
        await model.loadMore()

        XCTAssertEqual(model.items.map(\.thread.id), ["thread", "older"])
        XCTAssertFalse(model.hasPageLoadFailed)
        XCTAssertFalse(model.sections().contains { $0.id == .pageFailure })
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, "next-page", "next-page"])
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

    /// The SDK's copy of the first page stands in for it while it loads, without unread baselines or pagination, and
    /// the first page replaces it
    @MainActor
    func testCachedChatsShowWhileTheFirstPageLoadsAndTheFirstPageReplacesThem() async throws {
        let suite = "AgentThreadListTests.Cache.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let readState = AgentThreadReadState(userDefaults: defaults)
        let client = ThreadListClient()
        client.cachedThreadItems = [
            try makeItem("chat", date: "2026-10-19T10:00:00Z", messageCount: 2),
            try makeItem("cached-only", date: "2026-10-18T10:00:00Z"),
        ]
        client.suspendNextList = true
        let model = AgentThreadListModel(client: client, threadReadState: readState)

        let refresh = Task { await model.refresh() }
        await waitForCondition { model.isShowingCachedThreads }
        XCTAssertEqual(model.items.map(\.thread.id), ["chat", "cached-only"])
        XCTAssertTrue(model.hasLoaded)
        XCTAssertFalse(model.hasLoadFailed)
        XCTAssertNil(model.nextCursor)

        let fresh = try makeItem("chat", date: "2026-10-19T11:00:00Z", revision: 2, messageCount: 4)
        client.resumeList(with: try makePage([fresh, try makeItem("new", date: "2026-10-17T10:00:00Z")], cursor: "next"))
        await refresh.value

        XCTAssertFalse(model.isShowingCachedThreads)
        XCTAssertEqual(model.items.map(\.thread.id), ["chat", "new"])
        XCTAssertEqual(model.nextCursor, "next")
        // The unread baseline is the first page's, not the copy's older message count
        XCTAssertFalse(model.isUnread(fresh.thread))
    }

    /// A copy arrives too late once the first page has loaded or another load has started, and an empty copy is none
    @MainActor
    func testCachedChatsArrivingLateOrEmptyLeaveTheListAsItWas() async throws {
        let cached = try makeItem("cached", date: "2026-10-19T10:00:00Z")

        let loadedClient = ThreadListClient()
        loadedClient.cachedThreadItems = [cached]
        loadedClient.blocksCachedThreads = true
        loadedClient.pages = [try makePage([])]
        let loadedModel = AgentThreadListModel(client: loadedClient)
        await loadedModel.refresh()
        loadedClient.resumeCachedThreads()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(loadedModel.items.isEmpty)
        XCTAssertFalse(loadedModel.isShowingCachedThreads)

        let supersededClient = ThreadListClient()
        supersededClient.cachedThreadItems = [cached]
        supersededClient.blocksCachedThreads = true
        supersededClient.suspendNextList = true
        let supersededModel = AgentThreadListModel(client: supersededClient)
        let refresh = Task { await supersededModel.refresh() }
        await waitForCondition { supersededClient.listRequests.count == 1 }
        supersededModel.removeThread(id: cached.thread.id)
        supersededClient.resumeCachedThreads()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(supersededModel.items.isEmpty)
        supersededClient.resumeList(with: try makePage([]))
        await refresh.value

        // A copy that comes after the first page failed leaves the failure and its Retry
        let failedClient = ThreadListClient()
        failedClient.cachedThreadItems = [cached]
        failedClient.blocksCachedThreads = true
        failedClient.listError = ThreadListError.unavailable
        let failedModel = AgentThreadListModel(client: failedClient)
        await failedModel.refresh()
        XCTAssertTrue(failedModel.hasLoadFailed)
        failedClient.resumeCachedThreads()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(failedModel.hasLoadFailed)
        XCTAssertTrue(failedModel.items.isEmpty)

        let emptyClient = ThreadListClient()
        emptyClient.cachedThreadItems = []
        emptyClient.listError = ThreadListError.unavailable
        let emptyModel = AgentThreadListModel(client: emptyClient)
        await emptyModel.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(emptyModel.hasLoadFailed)
        XCTAssertFalse(emptyModel.isShowingCachedThreads)
    }

    /// Once a first page has loaded, even an empty one, the SDK's older copy isn't read again until the wallets reset;
    /// a list whose first page failed still reads it
    @MainActor
    func testCachedChatsAreReadOnlyUntilAFirstPageLoads() async throws {
        let cached = try makeItem("deleted", date: "2026-10-19T10:00:00Z")
        let client = ThreadListClient()
        client.cachedThreadItems = [cached]
        client.pages = [try makePage([]), try makePage([])]
        let model = AgentThreadListModel(client: client)
        await model.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.cachedThreadsRequestCount, 1)
        await model.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.cachedThreadsRequestCount, 1)
        XCTAssertTrue(model.items.isEmpty)

        model.handleAccountsReset()
        client.pages = [try makePage([])]
        await model.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.cachedThreadsRequestCount, 2)

        let failingClient = ThreadListClient()
        failingClient.listError = ThreadListError.unavailable
        let failingModel = AgentThreadListModel(client: failingClient)
        await failingModel.refresh()
        for _ in 0..<20 { await Task.yield() }
        await failingModel.refresh()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(failingClient.cachedThreadsRequestCount, 2)
    }

    /// A first page that fails keeps the copy on screen without the failure, and the next refresh reads the first page
    /// alone, as the copy has no pages after it
    @MainActor
    func testCachedChatsStayWhenTheFirstPageFailsUntilARefreshLoadsIt() async throws {
        let client = ThreadListClient()
        client.cachedThreadItems = [
            try makeItem("a", date: "2026-10-19T10:00:00Z"),
            try makeItem("b", date: "2026-10-18T10:00:00Z"),
        ]
        client.suspendNextList = true
        let model = AgentThreadListModel(client: client)
        let refresh = Task { await model.refresh() }
        await waitForCondition { model.isShowingCachedThreads }
        client.failList(with: ThreadListError.unavailable)
        await refresh.value

        XCTAssertEqual(model.items.map(\.thread.id), ["a", "b"])
        XCTAssertTrue(model.isShowingCachedThreads)
        XCTAssertFalse(model.hasLoadFailed)
        await model.loadMore()
        XCTAssertEqual(client.listRequests.count, 1)

        client.pages = [try makePage([try makeItem("c", date: "2026-10-19T12:00:00Z")], cursor: "next")]
        await model.refresh()
        XCTAssertEqual(client.listRequests.map(\.cursor), [nil, nil])
        XCTAssertEqual(model.items.map(\.thread.id), ["c"])
        XCTAssertFalse(model.isShowingCachedThreads)
    }

    @MainActor
    func testOperatorRepliesStayUnreadUntilTheirHistoryIsShown() throws {
        let suite = "AgentThreadListTests.SupportReadState.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let readState = AgentThreadReadState(userDefaults: defaults)
        let firstTimestamp = "2026-11-09T10:00:00.500Z"
        let nextTimestamp = "2026-11-09T10:00:01.500Z"
        let first = try makeItem("support", date: firstTimestamp, support: .init(
            state: .operator, lastOperatorMessageAt: firstTimestamp
        )).thread
        readState.observe([first], answeringThreadIds: [])
        XCTAssertTrue(readState.isUnread(first))

        readState.chatDidAppear(threadId: first.id)
        XCTAssertTrue(readState.isUnread(first))
        readState.markOperatorMessagesSeen(threadId: first.id, loadedOperatorMessageAt: firstTimestamp)
        XCTAssertFalse(readState.isUnread(first))
        readState.chatDidDisappear(threadId: first.id, seenMessageCount: first.messageCount)
        let restarted = AgentThreadReadState(userDefaults: defaults)
        XCTAssertFalse(restarted.isUnread(first))

        let next = try makeItem(first.id, date: nextTimestamp, support: .init(
            state: .operator, lastOperatorMessageAt: nextTimestamp
        )).thread
        restarted.observe([next], answeringThreadIds: [])
        restarted.chatDidAppear(threadId: next.id)
        restarted.markOperatorMessagesSeen(threadId: next.id, loadedOperatorMessageAt: firstTimestamp)
        XCTAssertTrue(restarted.isUnread(next))
        restarted.markOperatorMessagesSeen(threadId: next.id, loadedOperatorMessageAt: nextTimestamp)
        XCTAssertFalse(restarted.isUnread(next))
        let closed = try makeItem(first.id, date: nextTimestamp, support: .init(
            state: .closed, lastOperatorMessageAt: nextTimestamp
        )).thread
        XCTAssertFalse(restarted.isUnread(closed))
        restarted.chatDidDisappear(threadId: next.id, seenMessageCount: next.messageCount)
        XCTAssertFalse(restarted.isUnread(closed))
    }

    @MainActor
    func testLoadedOperatorHistoryIsSeenOnlyInAVisibleForegroundChat() async throws {
        let threadId = "support-\(UUID().uuidString)"
        let firstTimestamp = "2026-11-09T10:00:00.500Z"
        let nextTimestamp = "2026-11-09T10:00:01.500Z"
        let first = try makeItem(threadId, date: firstTimestamp, support: .init(
            state: .operator, lastOperatorMessageAt: firstTimestamp
        )).thread
        let next = try makeItem(threadId, date: nextTimestamp, revision: 2, messageCount: 3, support: .init(
            state: .operator, lastOperatorMessageAt: nextTimestamp
        )).thread
        let author = ["operatorId": "alex", "name": "Alex"]
        var messages: [[String: Any]] = [
            ["id": "question", "role": "user", "content": ["kind": "markdown", "text": "Help"]],
            ["id": "event", "role": "event", "code": "operator_joined", "author": author],
            ["id": "operator-1", "role": "operator", "text": "Hello", "author": author]
        ]
        messages = messages.map { $0.merging([
            "threadId": threadId, "status": "complete", "createdAt": "2026-11-09T10:00:00.100Z"
        ]) { existing, _ in existing } }
        var history: [String: Any] = [
            "thread": try JSONSerialization.jsonObject(with: JSONEncoder().encode(first)), "messages": messages
        ]
        let initial = try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: JSONSerialization.data(withJSONObject: history))
        messages.append([
            "id": "operator-2", "threadId": threadId, "role": "operator", "text": "Another reply", "author": author,
            "status": "complete", "createdAt": "2026-11-09T10:00:01.100Z"
        ])
        history["thread"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(next))
        history["messages"] = messages
        let updated = try JSONDecoder().decode(ApiAgentV2ThreadHydration.self, from: JSONSerialization.data(withJSONObject: history))
        let client = FakeAgentV2Client(hydrationResults: [initial, updated])
        let model = AgentV2Model(client: client, thread: first)
        let readState = AgentThreadReadState.shared
        defer {
            model.stop()
            readState.remove(threadId: threadId)
        }
        await model.waitForInitialLoad()
        let coordinator = try XCTUnwrap(Mirror(reflecting: model).children.first { $0.label == "coordinator" }?.value as? AgentV2Coordinator)
        XCTAssertEqual(coordinator.loadedOperatorMessageAt, firstTimestamp)
        XCTAssertEqual(model.seenMessageCount, 2)
        XCTAssertEqual(coordinator.getFirstUnseenMessageID(seenMessageCount: 1, ignoredIDs: []), "operator-1")
        XCTAssertTrue(readState.isUnread(first))

        model.isActive = true
        XCTAssertFalse(readState.isUnread(first))
        coordinator.walletCore(event: .applicationDidEnterBackground)
        await coordinator.hydrate()
        XCTAssertEqual(coordinator.loadedOperatorMessageAt, nextTimestamp)
        XCTAssertEqual(model.seenMessageCount, 3)
        XCTAssertTrue(readState.isUnread(next))
        model.isActive = false
        coordinator.walletCore(event: .applicationWillEnterForeground)
        XCTAssertTrue(readState.isUnread(next))
        model.isActive = true
        XCTAssertFalse(readState.isUnread(next))
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

    /// A chat the SDK reported stays while the server's first page lacks it, as the server may not have stored a
    /// chat just created, for a minute after the report
    @MainActor
    func testReportedThreadMissingFromTheFirstPageStaysForAMinute() async throws {
        let client = ThreadListClient()
        let listed = try makeItem("listed", date: "2026-10-19T10:00:00Z")
        let reported = try makeItem("reported", date: "2026-10-19T11:00:00Z")
        client.pages = try (0..<4).map { _ in try makePage([listed]) }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AgentThreadListModel(client: client, preloader: AgentPreloader(client: LiveAgentV2Client()), now: { now })
        await model.refresh()
        model.applyThreadChange(reported.thread)

        now += 60
        await model.refresh()
        XCTAssertEqual(model.items.map(\.thread.id), ["reported", "listed"])
        now += 1
        await model.refresh()
        XCTAssertEqual(model.items.map(\.thread.id), ["listed"])
        now -= 61
        await model.refresh()
        XCTAssertEqual(model.items.map(\.thread.id), ["listed"], "Forgotten once gone")
    }

    /// A reset of the accounts forgets the threads the SDK reported into the list and out of it
    @MainActor
    func testAccountsResetForgetsReportedAndLeftThreads() async throws {
        let client = ThreadListClient()
        let left = try makeItem("left", date: "2026-10-19T10:00:00Z", revision: 3)
        let cleared = try makeItem("left", date: "2026-10-19T10:00:00Z", revision: 4, messageCount: 0)
        let reported = try makeItem("reported", date: "2026-10-19T11:00:00Z")
        client.pages = [try makePage([left]), try makePage([left])]
        let model = AgentThreadListModel(client: client, preloader: AgentPreloader(client: LiveAgentV2Client()))
        await model.refresh()
        model.applyThreadChange(cleared.thread)
        model.applyThreadChange(reported.thread)
        XCTAssertEqual(model.items.map(\.thread.id), ["reported"])

        model.handleAccountsReset()
        await model.refresh()
        XCTAssertEqual(model.items.map(\.thread.id), ["left"])
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
        let settings = AgentNewsNotificationSettings.shared
        let savedTime = (hour: settings.digestHour, minute: settings.digestMinute)
        addTeardownBlock { @MainActor in
            _ = await AgentNewsNotificationSettings.shared.setDigestTime(hour: savedTime.hour, minute: savedTime.minute)
        }
        _ = await settings.setDigestTime(hour: 7, minute: 30)

        XCTAssertNil(model.latestNews)
        await model.refreshNews()

        XCTAssertEqual(newsClient.requests.map(\.lang), ["ru-RU"])
        XCTAssertEqual(newsClient.requests.map(\.schedule.hour), [7])
        XCTAssertEqual(newsClient.requests.map(\.schedule.minute), [30])
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
        let news = newsItem(1, deliveredAt: "2026-10-19T11:00:00Z")
        let newsClient = ThreadListNewsClient(items: [news])
        var model: AgentThreadListModel? = AgentThreadListModel(client: client, newsClient: newsClient)
        await model?.refresh()
        await model?.refreshNews()
        let digestId = "en:2026-10-19T18:00:00.000Z"
        let feed = try XCTUnwrap(model?.makeNewsFeedModel(requestedDigestId: digestId))
        XCTAssertEqual(feed.requestedDigestId, digestId)
        XCTAssertEqual(feed.items, [news])
        XCTAssertTrue(feed.hasLoaded)
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

    @MainActor
    private func waitForCondition(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
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
        messageCount: Int = 2,
        support: ApiAgentV2ThreadSupport? = nil
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
        if let support { json["support"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(support)) }
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
    struct Request {
        let lang: String
        let cursor: String?
        let schedule: AgentNewsDigestSchedule
    }

    var locale = "en"
    var items: [ApiAgentV2NewsFeedItem]
    var digests: [ApiAgentV2NewsFeedDigest]?
    var shouldFail = false
    private(set) var requests: [Request] = []

    init(items: [ApiAgentV2NewsFeedItem] = []) {
        self.items = items
    }

    func getNewsFeed(lang: String, cursor: String?, schedule: AgentNewsDigestSchedule, view: ApiAgentV2NewsFeedView = .all) async throws -> ApiAgentV2NewsFeedPage {
        requests.append(Request(lang: lang, cursor: cursor, schedule: schedule))
        if shouldFail { throw ThreadListError.unavailable }
        return ApiAgentV2NewsFeedPage(locale: locale, items: items, digests: digests)
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
    /// The SDK's copy of the first page, which `blocksCachedThreads` holds back until `resumeCachedThreads()`
    var cachedThreadItems: [ApiAgentV2ThreadListItem]?
    var blocksCachedThreads = false
    private var cachedThreadsContinuation: CheckedContinuation<Void, Never>?
    private var listContinuation: CheckedContinuation<ApiAgentV2ThreadListResponse, Error>?
    private(set) var listRequests: [ApiAgentV2ThreadListRequest] = []
    private(set) var updateRequests: [(id: String, update: ApiAgentV2ThreadUpdate)] = []
    private(set) var deletedThreadIds: [String] = []

    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        let request = ApiAgentV2ThreadListRequest(cursor: cursor, limit: limit, query: query)
        listRequests.append(request)
        if suspendNextList {
            suspendNextList = false
            return try await withCheckedThrowingContinuation { continuation in
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

    func failList(with error: Error) {
        listContinuation?.resume(throwing: error)
        listContinuation = nil
    }

    private(set) var cachedThreadsRequestCount = 0
    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? {
        cachedThreadsRequestCount += 1
        if blocksCachedThreads {
            await withCheckedContinuation { cachedThreadsContinuation = $0 }
        }
        return cachedThreadItems
    }

    func resumeCachedThreads() {
        blocksCachedThreads = false
        cachedThreadsContinuation?.resume()
        cachedThreadsContinuation = nil
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
