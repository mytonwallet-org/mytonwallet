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

    /// The feed's date lines are a chat's, one for each day: the same cell, a heading for VoiceOver, and the same
    /// centred Copy menu
    func testFeedShowsAChatsDateLineForEachDay() async throws {
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
        XCTAssertEqual(dateLines[0].contextMenuCopyText, AgentThreadDateFormatting.headerText(for: firstDay))
        let label = try XCTUnwrap(findDescendants(of: dateLines[0]).compactMap { $0 as? UILabel }.first { !$0.isHidden })
        XCTAssertTrue(label.accessibilityTraits.contains(.header))
        let menu = try XCTUnwrap(dateLines[0].contextMenuConfigurationProvider?())
        XCTAssertEqual(menu.style.horizontalAlignment, .center)
        let titles = menu.rootPage.items.compactMap { item -> String? in
            guard case .action(let action) = item else { return nil }
            return action.title
        }
        XCTAssertEqual(titles, [lang("Copy")])
    }
}
