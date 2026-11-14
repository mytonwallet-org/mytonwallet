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

    /// VoiceOver reads the card's headline, body and time, without its sources' names or sites
    func testAccessibilityLabelLeavesTheSourcesOut() {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsFeedCardCell(frame: .zero)
        let item = makeItem(sources: [
            .init(url: "https://www.example.com/first"),
            .init(name: "Second source", url: "https://example.com/second")
        ])
        cell.configure(with: item)
        let element = cell.newsView.accessibilityContentElement
        XCTAssertEqual(element.accessibilityLabel, "Headline, A bold report., \(AgentNewsFeedCardCell.timeText(for: item.deliveredAt))")
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
        XCTAssertEqual(meta.timeLabel.text, AgentNewsFeedCardCell.timeText(for: item.deliveredAt))
        XCTAssertFalse(descendants(cell).compactMap { $0 as? UILabel }.contains { $0.text?.contains("First source") == true })
        // The time ends as far from the bubble's trailing edge as a channel post's time in Telegram
        let time = meta.timeLabel
        let timeFrame = time.convert(time.bounds, to: bubble)
        XCTAssertEqual(timeFrame.maxX, bubble.bounds.width - AgentNewsMetaView.trailingInset, accuracy: 0.5)

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

    /// A digest shows its headlines, each opening its news item, the news it leaves out when there are more, and Discuss
    func testDigestCardShowsHeadlinesTheRemainderAndDiscuss() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        let digest = try makeDigest(total: 26, headlines: ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        cell.configure(with: digest)
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        XCTAssertTrue(labels.contains { $0.text == lang("$agent_digest_title") })
        XCTAssertTrue(labels.contains { $0.text == L10n.agentDigestMeta(count: 26) })
        // The time stands in the bubble's trailing corner, as on a news card
        XCTAssertTrue(labels.contains { $0.text == AgentNewsFeedCardCell.timeText(for: digest.deliveredAt) })
        XCTAssertTrue(labels.contains { $0.text == L10n.agentDigestMore(count: 24) })
        XCTAssertTrue(labels.contains { $0.text == lang("$agent_news_discuss") })
        let headlines = descendants(cell).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("AgentNewsDigestHeadline-") == true }
        XCTAssertEqual(headlines.map(\.accessibilityLabel), ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        let discuss = try XCTUnwrap(descendants(cell).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "AgentNewsDigestDiscussion-\(digest.id)"
        })
        let elements = try XCTUnwrap(cell.accessibilityElements as? [UIView])
        XCTAssertEqual(elements.count, 5)
        XCTAssertTrue(elements[0].isAccessibilityElement)
        XCTAssertEqual(elements[0].accessibilityCustomActions?.map(\.name), [lang("More actions")])
        // The headlines' arrows are gray and line up with Discuss's
        cell.layoutIfNeeded()
        let arrows = descendants(cell).compactMap { $0 as? UIImageView }.filter { $0.image == AgentNewsDiscussionStrip.arrowImage }
        XCTAssertEqual(arrows.count, 3)
        XCTAssertEqual(arrows.filter { $0.tintColor == UIColor.air.secondaryLabel }.count, 2)
        let arrowEnds = arrows.map { $0.convert($0.bounds, to: cell.bubbleView).maxX }
        XCTAssertEqual(arrowEnds.max()! - arrowEnds.min()!, 0, accuracy: 0.5)

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

    /// In the digests view no news stand above the card, so its remainder line only counts the news it leaves out
    func testDigestCardInTheDigestsViewCountsTheRemainderWithoutPointingAtTheFeed() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        let digest = try makeDigest(total: 26, headlines: ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        cell.configure(with: digest, isInDigestsView: true)
        let texts = descendants(cell).compactMap { ($0 as? UILabel)?.text }
        XCTAssertTrue(texts.contains(L10n.agentDigestMoreCount(count: 24)))
        XCTAssertFalse(texts.contains(L10n.agentDigestMore(count: 24)))
    }

    /// A headline shorter than its picture stands centred on it, and a longer one starts at its top
    func testDigestCardCentresAShortHeadlineOnItsPicture() throws {
        _ = WalletResourcesBundle.bundle.load()
        let short = "Short"
        let long = Array(repeating: "Binance restored the tokens it had frozen", count: 3).joined(separator: " ")
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: JSONSerialization.data(withJSONObject: [
            "id": "en:2026-11-08T18:00:00.000Z", "deliveredAt": "2026-11-08T18:00:00.000Z", "total": 2, "top": [
                ["eventId": 1, "headline": short, "imageUrl": "https://example.com/1.png"],
                ["eventId": 2, "headline": long, "imageUrl": "https://example.com/2.png"],
            ],
        ]))
        let cell = AgentNewsDigestCardCell(frame: CGRect(x: 0, y: 0, width: 375, height: 600))
        cell.configure(with: digest)
        cell.frame.size.height = cell.systemLayoutSizeFitting(
            CGSize(width: 375, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        cell.layoutIfNeeded()
        let view = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsDigestHeadlinesView }.first)
        let labels = descendants(view).compactMap { $0 as? UILabel }
        func getFrame(_ view: UIView) -> CGRect { view.convert(view.bounds, to: cell) }
        let shortLabel = try XCTUnwrap(labels.first { $0.text == short })
        let longLabel = try XCTUnwrap(labels.first { $0.text == long })
        let pictures = view.thumbnails.map { getFrame($0.button) }
        XCTAssertEqual(pictures.count, 2)
        XCTAssertGreaterThan(longLabel.intrinsicContentSize.height, pictures[1].height)
        XCTAssertEqual(getFrame(shortLabel).midY, pictures[0].midY, accuracy: 0.5)
        XCTAssertEqual(getFrame(longLabel).minY, pictures[1].minY, accuracy: 0.5)
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
