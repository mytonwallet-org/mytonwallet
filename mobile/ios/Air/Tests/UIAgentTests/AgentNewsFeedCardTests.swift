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
        // As the post in the discussion: the source, the post's menu, which has Copy and Share, and the source by its name
        XCTAssertEqual(
            elements[0].accessibilityCustomActions?.map(\.name),
            [lang("$agent_news_open_source"), lang("More actions"), "example.com"]
        )
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

    /// VoiceOver reads the card's headline, body, source line and time
    func testAccessibilityLabelReadsTheSourceLineBetweenTheBodyAndTheTime() {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: .zero)
        let item = makeItem(sources: [
            .init(url: "https://www.example.com/first"),
            .init(name: "Second source", url: "https://example.com/second")
        ])
        cell.configure(with: item)
        let element = cell.newsView.accessibilityContentElement
        let sources = makeSourcesLineText(["example.com", "Second source"])
        XCTAssertEqual(
            element.accessibilityLabel,
            "Headline, A bold report., \(sources), \(AgentNewsFeedCardCell.timeText(for: item.deliveredAt))"
        )
    }

    /// The API's sources in its order, each named or shown by its site without "www.", without the ones naming nothing or
    /// a source already named, three at most; a thread's news card stored before it had sources names its old source
    func testSourceLineNamesUpToThreeDistinctSourcesAndOnlyLinksTheOpenableOnes() throws {
        _ = WalletResourcesBundle.bundle.load()
        let line = try XCTUnwrap(AgentNewsSourceLine(sources: [
            .init(name: "  CoinDesk \n", url: "https://www.coindesk.com/a"),
            .init(name: " ", url: "not a link"),
            .init(url: "https://WWW.theblock.co/b"),
            .init(name: "COINDESK", url: "https://example.com/duplicate"),
            .init(name: "Transfer", url: "\(SELF_PROTOCOL)transfer?amount=1"),
            .init(name: "Fourth", url: "https://example.com/fourth"),
        ]))
        XCTAssertEqual(line.entries, [
            .init(name: "CoinDesk", url: "https://www.coindesk.com/a"),
            .init(name: "theblock.co", url: "https://WWW.theblock.co/b"),
            .init(name: "Transfer", url: nil),
        ])
        XCTAssertEqual(line.text, makeSourcesLineText(["CoinDesk", "theblock.co", "Transfer"]))
        XCTAssertEqual(line.links.map { (line.text as NSString).substring(with: $0.range) }, ["CoinDesk", "theblock.co"])

        // The links keep to their names with a comma of another length, as Chinese's "、"
        let chinese = try XCTUnwrap(withMessageLanguage("zh-Hans") {
            AgentNewsSourceLine(sources: [
                .init(name: "Plain", url: "javascript:alert(1)"),
                .init(name: "First", url: "https://example.com/first"),
                .init(name: "Second", url: "https://example.com/second"),
            ])
        })
        let chineseComma = withMessageLanguage("zh-Hans") { lang("$joining_comma") }
        XCTAssertNotEqual((chineseComma as NSString).length, (", " as NSString).length)
        XCTAssertTrue(chinese.text.contains(["Plain", "First", "Second"].joined(separator: chineseComma)))
        XCTAssertEqual(chinese.links.map { (chinese.text as NSString).substring(with: $0.range) }, ["First", "Second"])

        for unsafeURL in ["javascript:alert(1)", "https://user:password@example.com/a", "ton://transfer/EQaddress"] {
            XCTAssertEqual(AgentNewsSourceLine(sources: [.init(name: "Site", url: unsafeURL)])?.links, [], unsafeURL)
        }
        let single = try XCTUnwrap(AgentNewsSourceLine(sources: [.init(url: "http://www.example.com/a")]))
        XCTAssertEqual(single.text, L10n.agentNewsSource(sources: "example.com"))
        XCTAssertEqual(single.links.map(\.url), ["http://www.example.com/a"])
        XCTAssertEqual(
            AgentNewsSourceLine(sources: [.init(url: "")], legacySource: "  Old source ")?.entries,
            [.init(name: "Old source", url: nil)]
        )
        XCTAssertEqual(AgentNewsSourceLine(sources: [.init(url: "https://a.example")], legacySource: "Old")?.entries.map(\.name), ["a.example"])
        XCTAssertNil(AgentNewsSourceLine(sources: [], legacySource: " "))
        XCTAssertNil(AgentNewsSourceLine(sources: [.init(url: "")]))
    }

    /// A card shows its time alone, on the device's 12- or 24-hour clock whatever the language, in the device's time zone
    func testTimeFollowsTheDeviceClockAndTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!
        let timestamp = "2026-10-20T16:30:00Z"
        func formatTime(in locale: Locale, _ hourCycle: Locale.HourCycle, timeZone: TimeZone? = nil) -> String {
            AgentNewsFeedCardCell.timeText(for: timestamp, timeZone: timeZone ?? utc, locale: locale, hourCycle: hourCycle)
                .replacingOccurrences(of: "\u{202F}", with: " ")
        }
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        XCTAssertEqual(formatTime(in: english, .oneToTwelve), "4:30 PM")
        XCTAssertEqual(formatTime(in: english, .zeroToTwentyThree), "16:30")
        XCTAssertEqual(formatTime(in: russian, .zeroToTwentyThree), "16:30")
        XCTAssertTrue(formatTime(in: russian, .oneToTwelve).hasPrefix("4:30"), formatTime(in: russian, .oneToTwelve))
        XCTAssertEqual(formatTime(in: russian, .zeroToTwentyThree, timeZone: TimeZone(secondsFromGMT: 3 * 60 * 60)!), "19:30")
        // Whatever the date, as the day capsule above it gives the date
        let lastYear = AgentNewsFeedCardCell.timeText(for: "2025-01-02T08:05:00Z", timeZone: utc, locale: russian, hourCycle: .zeroToTwentyThree)
        XCTAssertTrue(lastYear.hasSuffix("8:05") && !lastYear.contains("2025"), lastYear)
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
        let item = makeItem(sources: [
            .init(name: "First", url: "https://example.com/first"),
            .init(name: "Second", url: "https://example.com/second"),
            .init(name: "Third", url: "javascript:alert(1)"),
        ])
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
        XCTAssertEqual(meta.timeLabel.text, AgentNewsFeedCardCell.timeText(for: item.deliveredAt))
        // The time ends as far from the bubble's trailing edge as a channel post's time in Telegram
        let time = meta.timeLabel
        let timeFrame = time.convert(time.bounds, to: bubble)
        XCTAssertEqual(timeFrame.maxX, bubble.bounds.width - AgentNewsMetaView.trailingInset, accuracy: 0.5)

        // The source line stands under the body where the time stood, in the time's gray, with the time 4 pt under it
        let body = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first { $0.attributedText?.string == "A bold report." })
        let line = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsSourceLineLabel }.first)
        XCTAssertEqual(line.text, makeSourcesLineText(["First", "Second", "Third"]))
        XCTAssertEqual(line.font, time.font)
        XCTAssertEqual(line.textColor, time.textColor)
        XCTAssertEqual(line.textAlignment, .natural)
        XCTAssertEqual(line.numberOfLines, 0)
        let bodyFrame = body.convert(body.bounds, to: bubble)
        let lineFrame = line.convert(line.bounds, to: bubble)
        XCTAssertEqual(lineFrame.minX, 16, accuracy: 0.5)
        XCTAssertEqual(lineFrame.minY - bodyFrame.maxY, 8, accuracy: 0.5)
        XCTAssertEqual(timeFrame.minY - lineFrame.maxY, 4, accuracy: 0.5)
        XCTAssertEqual(lineFrame.height, line.sizeThatFits(CGSize(width: lineFrame.width, height: .infinity)).height, accuracy: 1)
        XCTAssertLessThan(lineFrame.height, line.font.lineHeight * 1.5)

        // A tap opens its entry's own source; the unsafe entry and the label are plain text
        var openedSources: [String] = []
        cell.openSourceAction = { openedSources.append($0) }
        try tap("Second", in: line)
        try tap("Third", in: line)
        try tap(String(XCTUnwrap(line.text?.split(separator: " ").first)), in: line)
        try tap("First", in: line)
        XCTAssertEqual(openedSources, ["https://example.com/second", "https://example.com/first"])

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

        // Without sources there is no line, and the time stands under the body as before
        let height = cell.frame.height
        cell.configure(with: makeItem())
        cell.frame.size.height = preferredHeight(of: cell)
        cell.layoutIfNeeded()
        XCTAssertTrue(line.isHidden)
        XCTAssertEqual(time.convert(time.bounds, to: bubble).minY - body.convert(body.bounds, to: bubble).maxY, 8, accuracy: 0.5)
        XCTAssertEqual(height - cell.frame.height, lineFrame.height + 4, accuracy: 1)
    }

    /// A digest shows its headlines, each opening its news item, the news it leaves out when there are more, and Discuss
    func testDigestCardShowsHeadlinesTheRemainderAndDiscuss() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        let digest = try makeDigest(total: 26, headlines: ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        cell.configure(with: digest)
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        XCTAssertTrue(labels.contains { $0.text == lang("$agent_digest_title") })
        XCTAssertTrue(labels.contains {
            $0.text == L10n.agentDigestMeta(count: 26, time: AgentNewsFeedCardCell.timeText(for: digest.deliveredAt))
        })
        XCTAssertTrue(labels.contains { $0.text == L10n.agentDigestMore(count: 24) })
        XCTAssertTrue(labels.contains { $0.text == lang("$agent_news_discuss") })
        let headlines = descendants(cell).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("AgentNewsDigestHeadline-") == true }
        XCTAssertEqual(headlines.map(\.accessibilityLabel), ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        let discuss = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "AgentNewsDigestDiscussion-\(digest.id)"
        })
        XCTAssertEqual((cell.accessibilityElements as? [UIView])?.count, 5)

        var openedEventIds: [Int] = []
        var discussions = 0
        cell.headlineAction = { openedEventIds.append($0) }
        cell.discussionAction = { discussions += 1 }
        headlines[1].sendActions(for: .touchUpInside)
        discuss.sendActions(for: .touchUpInside)
        XCTAssertEqual(openedEventIds, [2])
        XCTAssertEqual(discussions, 1)

        // A digest whose news are all among its headlines has no remainder line
        cell.prepareForReuse()
        cell.configure(with: try makeDigest(total: 1, headlines: ["Only news"]))
        XCTAssertFalse(descendants(cell).compactMap { $0 as? UILabel }.contains { $0.text == L10n.agentDigestMore(count: 24) })
        XCTAssertEqual((cell.accessibilityElements as? [UIView])?.count, 3)
    }

    private func makeDigest(total: Int, headlines: [String]) throws -> ApiAgentV2NewsFeedDigest {
        let top = headlines.enumerated().map { ["eventId": $0.offset + 1, "headline": $0.element] as [String: Any] }
        return try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: JSONSerialization.data(withJSONObject: [
            "id": "en:2026-11-08T18:00:00.000Z", "deliveredAt": "2026-11-08T18:00:00.000Z", "total": total, "top": top,
        ]))
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
