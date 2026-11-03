import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentNewsFeedCardTests: XCTestCase {
    func testDiscussionStripHasSeparateAccessibleButtonAndKeepsCardActions() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: .zero)
        let item = makeItem(sources: [.init(url: "https://example.com/news")])
        cell.configure(with: item)
        let button = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first)
        let elements = try XCTUnwrap(cell.accessibilityElements as? [UIView])
        XCTAssertEqual(elements.count, 2)
        XCTAssertFalse(cell.isAccessibilityElement)
        XCTAssertTrue(elements[0].isAccessibilityElement)
        XCTAssertTrue(elements[0] === cell.newsView.accessibilityContentElement)
        // As the post in the discussion: the source and the post's menu, which has Copy and Share
        XCTAssertEqual(elements[0].accessibilityCustomActions?.map(\.name), [lang("$agent_news_open_source"), lang("More actions")])
        XCTAssertTrue(elements[1] === button)
        XCTAssertTrue(button.isAccessibilityElement)
        XCTAssertTrue(button.accessibilityTraits.contains(.button))
        XCTAssertFalse(button.isHidden)
        XCTAssertEqual(button.accessibilityLabel, "\(lang("$agent_news_discuss")), \(item.headline)")
        XCTAssertTrue(descendants(button).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_discuss") })
        let icon = try findDiscussionIcon(in: button)
        XCTAssertTrue(icon.avatar.isHidden)
        XCTAssertFalse(icon.spinningTop.isHidden)
        XCTAssertNotNil(icon.spinningTop.image)
        var taps = 0
        cell.discussionAction = { taps += 1 }
        let action = try XCTUnwrap(button.actions(forTarget: cell, forControlEvent: .touchUpInside)?.first)
        cell.perform(NSSelectorFromString(action), with: button)
        XCTAssertEqual(taps, 1)
        cell.prepareForReuse()
        cell.perform(NSSelectorFromString(action), with: button)
        XCTAssertEqual(taps, 1)
    }

    func testDiscussionStripShowsThreadAvatarAndSpinningTopAfterReconfiguration() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: .zero)
        let item = makeItem(discussion: .init(threadId: "thread", icon: "🛡️"))
        cell.configure(with: item)
        let button = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first)
        let icon = try findDiscussionIcon(in: button)
        XCTAssertFalse(icon.avatar.isHidden)
        XCTAssertTrue(icon.spinningTop.isHidden)
        XCTAssertTrue(descendants(icon.avatar).compactMap { $0 as? UILabel }.contains { $0.text == "🛡️" && !$0.isHidden })
        XCTAssertEqual(button.accessibilityLabel, L10n.agentNewsContinueDiscussionAccessibility(headline: item.headline))
        XCTAssertTrue(descendants(button).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_continue_discussion") })

        cell.configure(with: makeItem(discussion: .init(threadId: "thread", icon: "")))
        // A thread without an emoji shows the Agent's mark, drawn for the avatar's laid-out size
        cell.frame = CGRect(x: 0, y: 0, width: 370, height: preferredHeight(of: cell))
        cell.layoutIfNeeded()
        let symbol = try XCTUnwrap(descendants(icon.avatar).compactMap { $0 as? UIImageView }.first)
        XCTAssertFalse(icon.avatar.isHidden)
        XCTAssertNotNil(symbol.image)
        XCTAssertFalse(symbol.isHidden)
        XCTAssertEqual(symbol.tintColor, .white)
        XCTAssertFalse(descendants(icon.avatar).compactMap { $0 as? UILabel }.contains { !$0.isHidden })

        cell.configure(with: makeItem())
        XCTAssertTrue(icon.avatar.isHidden)
        XCTAssertFalse(icon.spinningTop.isHidden)
        XCTAssertTrue(descendants(button).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_discuss") })

        // A discussion opened without a message from the user is still to be started
        cell.configure(with: makeItem(discussion: .init(threadId: "thread", icon: "🛡️")), isDiscussionStarted: false)
        XCTAssertTrue(icon.avatar.isHidden)
        XCTAssertFalse(icon.spinningTop.isHidden)
        XCTAssertTrue(descendants(button).compactMap { $0 as? UILabel }.contains { $0.text == lang("$agent_news_discuss") })
    }

    /// The source is the first one's name, or its site, as on the post in the discussion
    func testSourceNameComesOnlyFromFirstSource() {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: .zero)
        let unnamedFirst = makeItem(sources: [
            .init(url: "https://www.example.com/first"),
            .init(name: "Second source", url: "https://example.com/second")
        ])
        cell.configure(with: unnamedFirst)
        let element = cell.newsView.accessibilityContentElement
        XCTAssertEqual(element.accessibilityLabel, "Headline, A bold report., example.com, \(AgentNewsFeedCardCell.timeText(for: unnamedFirst.deliveredAt))")

        let namedFirst = makeItem(sources: [
            .init(name: "First source", url: "https://example.com/first"),
            .init(name: "Second source", url: "https://example.com/second")
        ])
        cell.configure(with: namedFirst)
        XCTAssertEqual(element.accessibilityLabel, "Headline, A bold report., First source, \(AgentNewsFeedCardCell.timeText(for: namedFirst.deliveredAt))")
    }

    func testTimeFollowsLocaleAndUpdatesCachedFormatterForTimeZoneChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let timestamp = "2026-10-20T16:30:00Z"
        let american = AgentNewsFeedCardCell.timeText(for: timestamp, calendar: calendar, locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(american, "4:30 PM")
        XCTAssertEqual(AgentNewsFeedCardCell.timeText(for: timestamp, calendar: calendar, locale: Locale(identifier: "ru_RU")), "16:30")
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 60 * 60)!
        XCTAssertEqual(AgentNewsFeedCardCell.timeText(for: timestamp, calendar: calendar, locale: Locale(identifier: "ru_RU")), "19:30")
    }

    func testBodyRendersAgainAndGrowsWhenContentSizeCategoryChanges() async throws {
        guard #available(iOS 17.0, *) else { throw XCTSkip("Trait overrides require iOS 17") }
        _ = WalletResourcesBundle.bundle.load()
        let root = UIViewController()
        root.traitOverrides.preferredContentSizeCategory = .large
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = root
        let cell = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: 600))
        root.view.addSubview(cell)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        cell.configure(with: makeItem())
        window.layoutIfNeeded()
        let body = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first {
            $0.attributedText?.string == "A bold report."
        })
        let originalFont = try bodyFont(in: body)
        let originalHeight = preferredHeight(of: cell)
        var heightChanges = 0
        cell.onPreferredHeightChanged = { heightChanges += 1 }
        root.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        for _ in 0..<200 {
            window.layoutIfNeeded()
            if heightChanges > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let enlargedFont = try bodyFont(in: body)
        XCTAssertGreaterThan(heightChanges, 0)
        XCTAssertGreaterThan(enlargedFont.pointSize, originalFont.pointSize)
        XCTAssertGreaterThan(preferredHeight(of: cell), originalHeight)
        XCTAssertEqual(body.attributedText?.string, "A bold report.")
        let boldIndex = (body.attributedText!.string as NSString).range(of: "bold").location
        let boldFont = try XCTUnwrap(body.attributedText?.attribute(.font, at: boldIndex, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(boldFont.pointSize, enlargedFont.pointSize)

        cell.prepareForReuse()
        heightChanges = 0
        root.traitOverrides.preferredContentSizeCategory = .large
        window.layoutIfNeeded()
        XCTAssertNil(body.attributedText)
        XCTAssertEqual(heightChanges, 0)
    }

    func testCardIsTheDiscussionPostWithATelegramDiscussionStrip() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 370, height: 100))
        let item = makeItem(sources: [.init(name: "First source", url: "https://example.com/first")])
        cell.configure(with: item)
        cell.frame.size.height = preferredHeight(of: cell)
        cell.layoutIfNeeded()

        let bubble = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentBubbleBackgroundView }.first)
        // The tail ends the row, as a chat's message's does, and the bubble stands as far from the sides as the post's
        let bubbleFrame = bubble.convert(bubble.bounds, to: cell.contentView)
        XCTAssertEqual(bubbleFrame.minY, 0)
        XCTAssertEqual(bubbleFrame.maxY, cell.contentView.bounds.height, accuracy: 0.5)
        XCTAssertEqual(bubbleFrame.minX, AgentMessageCellMetrics.horizontalInset, accuracy: 0.5)
        XCTAssertEqual(bubbleFrame.maxX, 370 - AgentMessageCellMetrics.incomingTrailingInset, accuracy: 0.5)
        let meta = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsMetaView }.first)
        XCTAssertEqual(meta.sourceLabel.text, "First source")
        XCTAssertEqual(meta.timeLabel.text, "•\u{00a0}" + AgentNewsFeedCardCell.timeText(for: item.deliveredAt))
        let time = meta.timeLabel
        let source = meta.sourceLabel
        let timeFrame = time.convert(time.bounds, to: bubble)
        let sourceFrame = source.convert(source.bounds, to: bubble)
        XCTAssertEqual(timeFrame.maxX, bubble.bounds.width - 16, accuracy: 0.5)
        XCTAssertEqual(sourceFrame.maxX + 4, timeFrame.minX, accuracy: 0.5)

        // Telegram's comments button: its 30 pt avatar 8 pt from the top and the bottom, a 17 pt regular title and its
        // 24 pt arrow box 9 pt from the edge
        let button = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first)
        XCTAssertEqual(button.bounds.height, AgentNewsDiscussionMetrics.minimumHeight, accuracy: 0.5)
        let title = try XCTUnwrap(descendants(button).compactMap { $0 as? UILabel }.first { $0.text == lang("$agent_news_discuss") })
        XCTAssertEqual(title.font.pointSize, 17)
        XCTAssertFalse(title.font.fontDescriptor.symbolicTraits.contains(.traitBold))
        let arrow = try XCTUnwrap(descendants(button).compactMap { $0 as? UIImageView }.first {
            $0.image?.size == AgentNewsDiscussionMetrics.arrowBoxSize
        })
        let arrowFrame = arrow.convert(arrow.bounds, to: button)
        XCTAssertEqual(arrowFrame.maxX, button.bounds.width - AgentNewsDiscussionMetrics.arrowTrailingInset, accuracy: 0.5)
        XCTAssertEqual(arrowFrame.midY, button.bounds.midY + AgentNewsDiscussionMetrics.verticalOffset, accuracy: 0.5)
    }

    private func makeItem(
        sources: [ApiAgentV2NewsFeedItem.Source] = [],
        discussion: ApiAgentV2NewsFeedItem.Discussion? = nil
    ) -> ApiAgentV2NewsFeedItem {
        ApiAgentV2NewsFeedItem(
            eventId: 1,
            deliveredAt: "2026-10-20T16:30:00Z",
            headline: "Headline",
            body: "A **bold** report.",
            sources: sources,
            discussion: discussion
        )
    }

    /// The strip's 30 pt icon: a discussion's thread avatar, or the Agent's spinning top for a new discussion
    private func findDiscussionIcon(in button: UIButton) throws -> (avatar: AgentThreadAvatarView, spinningTop: UIImageView) {
        let avatar = try XCTUnwrap(descendants(button).compactMap { $0 as? AgentThreadAvatarView }.first)
        let container = try XCTUnwrap(avatar.superview)
        let spinningTop = try XCTUnwrap(container.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(container.subviews.count, 2)
        return (avatar, spinningTop)
    }

    private func bodyFont(in label: UILabel) throws -> UIFont {
        try XCTUnwrap(label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
    }

    private func preferredHeight(of cell: AgentNewsFeedCardCell) -> CGFloat {
        cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 370, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
