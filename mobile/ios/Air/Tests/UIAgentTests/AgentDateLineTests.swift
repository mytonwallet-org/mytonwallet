import ContextMenuKit
import XCTest
import UIKit
@testable import UIAgent
import WalletContext
import WalletCore
import WalletResources

/// The date lines of chats and of the News feed
@MainActor
final class AgentDateLineTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    /// A date line's menu is centred under the line, as Telegram's date menu is, while a message's keeps to its side
    func testDateLineMenuIsCentredUnderTheLine() async throws {
        let chat = AgentTestChat(messages: [
            AgentMessage(role: .user, text: "A question", isStreaming: false),
            AgentMessage(role: .assistant, text: "An answer", isStreaming: false),
        ])
        defer { chat.close() }
        try await chat.waitForStableLayout()
        let cells = chat.collectionView.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        let dateLine = try XCTUnwrap(cells.compactMap { $0 as? AgentSystemMessageCell }.first)
        XCTAssertEqual(try XCTUnwrap(dateLine.contextMenuConfigurationProvider?()).style.horizontalAlignment, .center)
        let messages = cells.compactMap { $0 as? AgentMessageCell }
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(try XCTUnwrap(messages[0].contextMenuConfigurationProvider?()).style.horizontalAlignment, .trailing)
        XCTAssertEqual(try XCTUnwrap(messages[1].contextMenuConfigurationProvider?()).style.horizontalAlignment, .leading)
    }

    /// The feed heads each day's news with Telegram's date capsule: the day's name in 13 pt text, 6 pt in from the ends
    /// of a 22 pt capsule centred in the column, a heading for VoiceOver with a chat's centred Copy menu
    func testFeedHeadsEachDayWithTelegramsDateCapsule() async throws {
        let items = [
            makeNewsItem(1), makeNewsItem(2),
            ApiAgentV2NewsFeedItem(eventId: 3, deliveredAt: "2026-10-22T09:00:00Z", headline: "Two days later", body: "Body"),
        ]
        let feed = TestFeed(page: .init(locale: "en", items: items.reversed()))
        defer { feed.close() }
        try await feed.waitUntil { feed.controller.collectionView.visibleCells.contains { $0 is AgentNewsFeedCardCell } }
        let rows = feed.controller.collectionView.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
        let dateLines = rows.compactMap { $0 as? AgentSystemMessageCell }
        XCTAssertEqual(dateLines.count, 2)
        XCTAssertTrue(rows.first is AgentSystemMessageCell)
        let calendar = LocalizationSupport.shared.calendar
        let firstDay = calendar.startOfDay(for: AgentV2DateParser.date(items[0].deliveredAt))
        let dayText = AgentThreadDateFormatting.formatDay(for: firstDay)
        XCTAssertEqual(dateLines[0].contextMenuCopyText, dayText)

        let capsule = try XCTUnwrap(findDescendants(of: dateLines[0]).compactMap { $0 as? AgentDateCapsuleView }.first)
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(capsule.alpha, 1)
        XCTAssertEqual(capsule.text, dayText)
        XCTAssertEqual(capsule.bounds.height, AgentDateCapsuleView.height, accuracy: 0.5)
        XCTAssertEqual(capsule.layer.cornerRadius, capsule.bounds.height / 2, accuracy: 0.01)
        XCTAssertEqual(capsule.bounds.width, capsule.label.intrinsicContentSize.width + 12, accuracy: 1)
        XCTAssertEqual(capsule.label.font.pointSize, 13, accuracy: 0.01)
        XCTAssertEqual(dateLines[0].bounds.height, capsule.bounds.height, accuracy: 0.5)
        let view = try XCTUnwrap(feed.controller.view)
        XCTAssertEqual(capsule.convert(capsule.bounds, to: view).midX, view.bounds.midX, accuracy: 0.5)
        // The row shows the capsule alone
        func isShown(_ view: UIView) -> Bool {
            sequence(first: view, next: \.superview).prefix { $0 !== dateLines[0] }.allSatisfy { !$0.isHidden }
        }
        XCTAssertTrue(findDescendants(of: dateLines[0]).compactMap { $0 as? UILabel }.filter(isShown).allSatisfy {
            $0 === capsule.label
        })

        XCTAssertTrue(capsule.label.accessibilityTraits.contains(.header))
        let menu = try XCTUnwrap(dateLines[0].contextMenuConfigurationProvider?())
        XCTAssertEqual(menu.style.horizontalAlignment, .center)
        let titles = menu.rootPage.items.compactMap { item -> String? in
            guard case .action(let action) = item else { return nil }
            return action.title
        }
        XCTAssertEqual(titles, [lang("Copy")])
    }

    /// The capsule of the day at the feed's top sticks under the header while that day's news scroll under it, in place
    /// of its row's. It shows while the user scrolls and fades a moment after, and the next day's capsule pushes it up
    /// and takes its place, as in a Telegram chat.
    func testDayCapsuleSticksUnderTheHeaderWhileItsNewsScrollUnderIt() async throws {
        let firstDay = (1...8).map { makeDayItem($0, day: 20) }
        let nextDay = (9...16).map { makeDayItem($0, day: 22) }
        let feed = TestFeed(page: .init(locale: "en", items: (firstDay + nextDay).reversed()))
        defer { feed.close() }
        try await feed.waitUntil {
            !feed.model.isLoading && !feed.controller.isScrollToBottomButtonHeld
                && feed.controller.collectionView.visibleCells.contains { $0 is AgentNewsFeedCardCell }
        }
        try await feed.waitForStableLayout()
        let controller = feed.controller
        let list = controller.collectionView
        let view = try XCTUnwrap(controller.view)
        let capsule = controller.stickyDayCapsule
        let calendar = LocalizationSupport.shared.calendar
        func formatDay(of item: ApiAgentV2NewsFeedItem) -> String {
            AgentThreadDateFormatting.formatDay(for: calendar.startOfDay(for: AgentV2DateParser.date(item.deliveredAt)))
        }
        let nextDayPath = IndexPath(item: firstDay.count + 1, section: 0)
        func scroll(toContentY y: CGFloat) async throws {
            list.contentOffset.y = y - list.adjustedContentInset.top
            try await feed.waitForStableLayout()
            view.layoutIfNeeded()
        }
        /// The header's edge in the list, where the stuck capsule's area starts
        func getHeaderEdgeY() -> CGFloat {
            list.convert(CGPoint(x: 0, y: view.safeAreaInsets.top), from: view).y
        }
        /// Scrolls until the next day's capsule settles `distance` below the header's edge. The rows the list hasn't
        /// shown yet stand at their estimated height until they come into view and take their own, which moves the
        /// capsule after the scroll, so the scroll is repeated with the settled frames.
        func scrollNextDay(toDistance distance: CGFloat) async throws -> CGRect {
            for _ in 0..<6 {
                let frame = try XCTUnwrap(list.layoutAttributesForItem(at: nextDayPath)).frame
                let shift = frame.minY - getHeaderEdgeY() - distance
                guard abs(shift) > 0.5 else { return frame }
                list.contentOffset.y += shift
                try await feed.waitForStableLayout()
                view.layoutIfNeeded()
            }
            let frame = try XCTUnwrap(list.layoutAttributesForItem(at: nextDayPath)).frame
            XCTAssertEqual(frame.minY - getHeaderEdgeY(), distance, accuracy: 0.5, "The list settles where the test puts it")
            return frame
        }

        // At the top every capsule stands in its row
        try await scroll(toContentY: 0)
        XCTAssertEqual(capsule.alpha, 0)

        // With the first day's news under the header, its capsule stands under the header's switch in place of its
        // row's, as far under it as under the pinned digests' bar, and hides while nothing scrolls
        let restingSpacing = AgentNewsPinnedDigestBar.bottomSpacing + AgentDateCapsuleView.verticalSpacing
        let viewSwitch = try XCTUnwrap(controller.navigationHandoffTitlePill)
        let restingY = viewSwitch.convert(viewSwitch.bounds, to: view).maxY + restingSpacing
        try await scroll(toContentY: try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))).frame.minY)
        XCTAssertEqual(capsule.text, formatDay(of: firstDay[0]))
        XCTAssertEqual(capsule.alpha, 0)
        XCTAssertEqual(capsule.convert(capsule.bounds, to: view).minY, restingY, accuracy: 0.5)
        if let row = list.cellForItem(at: IndexPath(item: 0, section: 0)) {
            XCTAssertTrue(findDescendants(of: row).compactMap { $0 as? AgentDateCapsuleView }.allSatisfy { $0.alpha == 0 })
        }
        // Pushed up, it fades as it goes under the header, rather than being cut at the header's edge: whole where it
        // stands, gone where the switch ends
        let area = try XCTUnwrap(capsule.superview)
        let mask = try XCTUnwrap(area.layer.mask as? CAGradientLayer)
        XCTAssertEqual(area.convert(area.bounds, to: view).minY, restingY - restingSpacing, accuracy: 0.5)
        XCTAssertEqual(mask.startPoint.y, 0)
        XCTAssertEqual(mask.endPoint.y * area.bounds.height, capsule.frame.minY, accuracy: 0.5)

        // It shows while the user scrolls, and a moment after, then fades away
        controller.scrollViewWillBeginDragging(list)
        XCTAssertEqual(capsule.alpha, 1)
        controller.scrollViewDidEndDragging(list, willDecelerate: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(capsule.alpha, 1, "The capsule stays a moment after the scroll ends")
        try await feed.waitUntil { capsule.alpha == 0 }

        // The next day's capsule pushes it up as it comes, a header's spacing above it
        let nextFrame = try await scrollNextDay(toDistance: 20)
        XCTAssertEqual(capsule.text, formatDay(of: firstDay[0]))
        XCTAssertEqual(
            capsule.convert(capsule.bounds, to: list).maxY,
            nextFrame.minY - 2 * AgentDateCapsuleView.verticalSpacing,
            accuracy: 0.5
        )

        // Past the header's edge the next day's capsule sticks in its turn, and its row's own gives way to it
        _ = try await scrollNextDay(toDistance: -10)
        XCTAssertEqual(capsule.text, formatDay(of: nextDay[0]))
        XCTAssertEqual(capsule.convert(capsule.bounds, to: view).minY, restingY, accuracy: 0.5)
        if let row = list.cellForItem(at: nextDayPath) {
            XCTAssertTrue(findDescendants(of: row).compactMap { $0 as? AgentDateCapsuleView }.allSatisfy { $0.alpha == 0 })
        }
    }

    private func makeDayItem(_ id: Int, day: Int) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: id,
            deliveredAt: String(format: "2026-10-%02dT10:%02d:00Z", day, id),
            headline: "Headline \(id)",
            body: Array(repeating: "News **market** text.", count: 6).joined(separator: "\n")
        )
    }
}
