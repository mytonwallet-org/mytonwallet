import ContextMenuKit
import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentNewsPostCellTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        _ = WalletResourcesBundle.bundle.load()
    }

    func testNewsMenuItemsOpenCopyAndShareTheFullPost() {
        let news = makeNews()
        var openedSources = 0
        var sharedText: String?
        let actions = AgentMessageMenuItems.makeItems(
            for: news,
            openSource: { openedSources += 1 },
            share: { sharedText = $0 }
        ).compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item else { return nil }
            return action
        }
        XCTAssertEqual(actions.map(\.title), [lang("$agent_news_open_source"), lang("Copy"), lang("Share")])
        actions[0].handler?()
        actions[2].handler?()
        let text = "Headline\n\nA bold report.\nSecond paragraph.\n\nhttps://example.com/first"
        XCTAssertEqual(openedSources, 1)
        XCTAssertEqual(sharedText, text)
        XCTAssertEqual(AgentMessageMenuItems.copyText(for: news), text)

        let oldNews = makeNews(body: nil, sourceURL: "ton://transfer/EQaddress")
        let oldItems = AgentMessageMenuItems.makeItems(for: oldNews, openSource: {}, share: { _ in })
        XCTAssertEqual(oldItems.compactMap { item -> String? in
            guard case .action(let action) = item else { return nil }
            return action.title
        }, [lang("Copy"), lang("Share")])
        XCTAssertEqual(AgentMessageMenuItems.copyText(for: oldNews), "Headline\n\nExcerpt\n\nton://transfer/EQaddress")
    }

    func testAccessibilityAndCopyIncludeFullPlainPostAndFirstSource() throws {
        let cell = AgentNewsPostCell(frame: .zero)
        let news = makeNews()
        cell.configure(with: news)
        let bubble = try XCTUnwrap((cell.accessibilityElements as? [UIView])?.first)
        XCTAssertFalse(cell.isAccessibilityElement)
        XCTAssertTrue(bubble.isAccessibilityElement)
        XCTAssertTrue(bubble.accessibilityTraits.contains(.staticText))
        XCTAssertEqual(bubble.accessibilityIdentifier, "AgentNewsPost-3")
        XCTAssertEqual(
            bubble.accessibilityLabel,
            "\(lang("News")), Headline, A bold report.\nSecond paragraph., Market Source, \(AgentNewsMetaView.formatDiscussionTime(for: news.publishedAt))"
        )
        XCTAssertEqual(bubble.accessibilityCustomActions?.map(\.name), [lang("$agent_news_open_source"), lang("More actions")])
        XCTAssertEqual(cell.contextMenuCopyText, "Headline\n\nA bold report.\nSecond paragraph.\n\nhttps://example.com/first")
        var openedSources = 0
        cell.openSourceAction = { openedSources += 1 }
        let meta = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsMetaView }.first)
        XCTAssertTrue(meta.sourceLabel.isUserInteractionEnabled)
        meta.onSourceTap?()
        XCTAssertEqual(openedSources, 1)
    }

    func testUnsupportedSourceHasNoOpenSourceActionAndOldCardsUseExcerpt() throws {
        let cell = AgentNewsPostCell(frame: .zero)
        cell.configure(with: makeNews(body: nil, sourceURL: "ton://transfer/EQaddress"))
        let bubble = try XCTUnwrap((cell.accessibilityElements as? [UIView])?.first)
        let meta = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsMetaView }.first)
        XCTAssertNil(meta.onSourceTap)
        XCTAssertFalse(meta.sourceLabel.isUserInteractionEnabled)
        XCTAssertEqual(bubble.accessibilityCustomActions?.map(\.name), [lang("More actions")])
        XCTAssertEqual(cell.contextMenuCopyText, "Headline\n\nExcerpt\n\nton://transfer/EQaddress")
    }

    func testFailedImageIsHiddenAndRequestsHeightUpdate() async throws {
        let cell = AgentNewsPostCell(frame: .zero)
        var heightChanges = 0
        cell.onPreferredHeightChanged = { heightChanges += 1 }
        cell.configure(with: makeNews(imageURL: "invalid-news-image://unavailable"))
        let image = try XCTUnwrap(descendants(cell).compactMap { $0 as? WImageView }.first)
        for _ in 0..<200 {
            if image.isHidden, heightChanges > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(image.isHidden)
        XCTAssertNil(image.image)
        XCTAssertEqual(heightChanges, 1)
    }

    func testPrepareForReuseClearsContentActionsAndImage() throws {
        let cell = AgentNewsPostCell(frame: .zero)
        cell.configure(with: makeNews())
        cell.openSourceAction = {}
        cell.contextMenuConfigurationProvider = { nil }
        cell.onPreferredHeightChanged = {}
        let bubble = try XCTUnwrap((cell.accessibilityElements as? [UIView])?.first)
        let image = try XCTUnwrap(descendants(cell).compactMap { $0 as? WImageView }.first)
        let meta = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsMetaView }.first)

        cell.prepareForReuse()

        XCTAssertNil(cell.contextMenuCopyText)
        XCTAssertNil(cell.openSourceAction)
        XCTAssertNil(cell.contextMenuConfigurationProvider)
        XCTAssertNil(cell.onPreferredHeightChanged)
        XCTAssertNil(bubble.accessibilityLabel)
        XCTAssertNil(bubble.accessibilityIdentifier)
        XCTAssertNil(bubble.accessibilityCustomActions)
        XCTAssertTrue(image.isHidden)
        XCTAssertNil(image.image)
        XCTAssertTrue(meta.sourceLabel.isHidden)
        XCTAssertNil(meta.onSourceTap)
        XCTAssertTrue(descendants(cell).compactMap { $0 as? UILabel }.allSatisfy {
            $0.text == nil || $0.text == lang("News")
        })
    }

    func testFollowupsAppearUnderThePostAndAreClearedOnReuse() throws {
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        cell.configure(with: makeNews())
        cell.configureFollowups([
            AgentMessageControl(id: "action:open", title: "Open Portfolio", isEnabled: true),
            AgentMessageControl(id: "followup:why", title: "Why does it matter?", isEnabled: true, kind: .followup),
            AgentMessageControl(id: "followup:next", title: "What happens next?", isEnabled: false, kind: .followup),
        ])
        var tappedControls: [String] = []
        cell.onFollowupTap = { tappedControls.append($0) }
        let elements = try XCTUnwrap(cell.accessibilityElements as? [UIView])
        XCTAssertEqual(elements.count, 2)
        let followups = elements[1]
        let buttons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }

        XCTAssertFalse(followups.isHidden)
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Why does it matter?", "What happens next?"])
        XCTAssertTrue(buttons.allSatisfy { $0.isDescendant(of: followups) && $0.accessibilityIdentifier == "agent_followup" })
        XCTAssertEqual(buttons.map(\.isEnabled), [true, false])
        buttons[0].sendActions(for: .touchUpInside)
        XCTAssertEqual(tappedControls, ["followup:why"])

        cell.prepareForReuse()

        XCTAssertNil(cell.onFollowupTap)
        XCTAssertTrue(followups.isHidden)
        XCTAssertTrue(descendants(cell).compactMap { $0 as? AgentSuggestionButton }.isEmpty)
    }

    func testNewsHeaderKeepsItsHeightWhenLoadingSuggestionsAreReplaced() throws {
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 900))
        cell.configure(with: makeNews(imageURL: "https://example.invalid/news.png"))
        let image = try XCTUnwrap(descendants(cell).compactMap { $0 as? WImageView }.first)
        let suggestions = [
            AgentMessageControl(id: "followup:why", title: "Why does it matter?", isEnabled: true, kind: .followup),
            AgentMessageControl(id: "followup:next", title: "What happens next?", isEnabled: true, kind: .followup),
        ]
        for state in 0..<3 {
            cell.configureFollowups(state == 1 ? suggestions : [], isLoading: state == 0)
            let proposed = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
            proposed.size = CGSize(width: 402, height: 900)
            cell.frame.size = cell.preferredLayoutAttributesFitting(proposed).size
            cell.layoutIfNeeded()
            let imageTop = image.convert(image.bounds, to: cell.postView).minY
            XCTAssertLessThan(imageTop, 50, "The header must not absorb the row's estimated or previous height")
            XCTAssertGreaterThan(imageTop, 30)
        }
    }

    func testSuggestionsHangFromThePostAsFromAnAnswer() async throws {
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "Reduce Motion shows the suggestions at once")
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("Composed motion requires an app-hosted test")
        }
        let host = UIViewController()
        let window = makeKeyWindow(showing: host)
        window.windowScene = scene
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 100))
        host.view.addSubview(cell)
        cell.configure(with: makeNews())
        cell.configureFollowups([])
        layOut(cell)
        let tailOverflow = AgentBubbleBackgroundView.tailBottomOverflow
        let bodyHeight = cell.postView.bounds.height - tailOverflow
        XCTAssertEqual(cell.postTailOverflow, tailOverflow)

        let followups = [
            AgentMessageControl(id: "followup:why", title: "Why does it matter?", isEnabled: true, kind: .followup),
            AgentMessageControl(id: "followup:next", title: "What happens next?", isEnabled: true, kind: .followup),
        ]
        cell.configureFollowups(followups)
        layOut(cell)
        let buttons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        let frames = buttons.map { $0.convert($0.bounds, to: cell) }.sorted { $0.minY < $1.minY }
        let bubble = cell.postView.convert(cell.postView.bounds, to: cell)

        // The post loses its tail, and the first suggestion stands as far below it as the next below the first
        XCTAssertEqual(cell.postTailOverflow, 0)
        XCTAssertEqual(bubble.height, bodyHeight, accuracy: 0.5)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].minY - bubble.maxY, AgentSuggestionButton.spacing, accuracy: 0.5)
        XCTAssertEqual(frames[1].minY - frames[0].maxY, AgentSuggestionButton.spacing, accuracy: 0.5)
        // Suggestions that arrive for the post on screen rise into place, and configuring the post again, as the chat
        // does on every update, leaves them rising
        XCTAssertTrue(buttons.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })
        cell.configureFollowups(followups)
        XCTAssertTrue(buttons.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })
        buttons.forEach { $0.layer.removeAllAnimations() }
        cell.revealFollowups()
        XCTAssertTrue(buttons.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })

        cell.configureFollowups([])
        layOut(cell)
        XCTAssertEqual(cell.postTailOverflow, tailOverflow)
        XCTAssertEqual(cell.postView.bounds.height, bodyHeight + tailOverflow, accuracy: 0.5)

        // The chat configures its rows in updates without animation, as a news discussion does with its post while it
        // still opens and again once it can be written in: the suggestions rise all the same, and end as enabled as
        // they are by then
        let heldBack = followups.map { AgentMessageControl(id: $0.id, title: $0.title, isEnabled: false, kind: .followup) }
        UIView.performWithoutAnimation {
            cell.configureFollowups(heldBack)
            cell.configureFollowups(followups)
        }
        let arrived = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(arrived.count, 2)
        XCTAssertTrue(arrived.allSatisfy { $0.layer.animationKeys()?.isEmpty == false })
        let revealStarts = try arrived.map {
            try XCTUnwrap($0.layer.animation(forKey: "agentFollowupRevealOpacity")).beginTime
        }
        XCTAssertEqual(revealStarts[1] - revealStarts[0], 0.15, accuracy: 0.01)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(arrived[0].layer.presentation()?.opacity ?? 0, 0.05)
        XCTAssertLessThan(arrived[1].layer.presentation()?.opacity ?? 1, 0.01)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(arrived.allSatisfy { button in
            button.isEnabled && button.alpha == 1 && abs((button.layer.presentation()?.opacity ?? 1) - 1) < 0.01
        })

        // A delayed discussion response does not replay the sequence once its placeholders have appeared.
        cell.configureFollowups([], isLoading: true)
        layOut(cell)
        cell.revealFollowups()
        try await Task.sleep(for: .milliseconds(650))
        cell.configureFollowups(followups)
        layOut(cell)
        let replacementButtons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        let replacementStarts = try replacementButtons.map { button in
            try XCTUnwrap(button.subviews.compactMap {
                $0.layer.animation(forKey: "loadingReveal")
            }.first).beginTime
        }
        XCTAssertEqual(replacementStarts.count, 2)
        XCTAssertEqual(replacementStarts[1] - replacementStarts[0], 0, accuracy: 0.02)
    }

    func testTimeSitsInTheBubblesTrailingCornerRightAfterTheSource() throws {
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 100))
        let news = makeNews()
        cell.configure(with: news)
        cell.frame.size.height = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 402, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        cell.layoutIfNeeded()

        let bubble = cell.postView
        let meta = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentNewsMetaView }.first)
        XCTAssertEqual(meta.sourceLabel.text, "Market Source")
        XCTAssertEqual(meta.timeLabel.text, "•\u{00a0}" + AgentNewsMetaView.formatDiscussionTime(for: news.publishedAt))
        XCTAssertEqual(meta.sourceLabel.textColor, meta.timeLabel.textColor)
        let timeFrame = meta.timeLabel.convert(meta.timeLabel.bounds, to: bubble)
        let sourceFrame = meta.sourceLabel.convert(meta.sourceLabel.bounds, to: bubble)
        XCTAssertEqual(timeFrame.maxX, bubble.bounds.width - 16, accuracy: 0.5)
        XCTAssertEqual(sourceFrame.maxX + 4, timeFrame.minX, accuracy: 0.5)
        XCTAssertEqual(sourceFrame.midY, timeFrame.midY, accuracy: 3)
    }

    func testDiscussionTimeShowsTheDateForEarlierNews() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = AgentV2DateParser.date("2026-10-24T12:00:00Z")
        let russian = Locale(identifier: "ru_RU")
        XCTAssertEqual(
            AgentNewsMetaView.formatDiscussionTime(for: "2026-10-24T09:05:00Z", relativeTo: now, calendar: calendar, locale: russian),
            "09:05"
        )
        let earlier = AgentNewsMetaView.formatDiscussionTime(
            for: "2026-07-20T15:38:00Z", relativeTo: now, calendar: calendar, locale: russian
        )
        XCTAssertTrue(earlier.contains("20"))
        XCTAssertTrue(earlier.contains("июл"))
        XCTAssertFalse(earlier.contains("июл."))
        XCTAssertTrue(earlier.hasSuffix("15:38"))
        let lastYear = AgentNewsMetaView.formatDiscussionTime(
            for: "2025-07-20T15:38:00Z", relativeTo: now, calendar: calendar, locale: russian
        )
        XCTAssertTrue(lastYear.contains("2025"))
    }

    func testBubblesSqueezeAsTheirMenuPressBuilds() {
        let messageCell = AgentMessageCell(frame: CGRect(x: 0, y: 0, width: 402, height: 80))
        messageCell.configure(with: AgentMessage(role: .assistant, text: "An answer", isStreaming: false), onURLTap: { _ in })
        let postCell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        postCell.configure(with: makeNews())
        let cardCell = AgentNewsFeedCardCell(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        for cell in [messageCell, postCell, cardCell] as [UICollectionViewCell] {
            XCTAssertTrue(hasPressAnimation(in: cell.contentView), "\(type(of: cell))")
        }
    }

    /// Whether `view` or a view in it opens a menu with Telegram's press-down
    private func hasPressAnimation(in view: UIView) -> Bool {
        let hasRecognizer = view.gestureRecognizers?.contains {
            String(describing: type(of: $0)) == "ContextMenuPressAnimationGestureRecognizer"
        } ?? false
        return hasRecognizer || view.subviews.contains { hasPressAnimation(in: $0) }
    }

    private func makeNews(
        body: String? = "A **bold** report.\nSecond paragraph.",
        sourceURL: String = "https://example.com/first",
        imageURL: String? = nil
    ) -> ApiAgentV2ThreadNewsCard {
        .init(
            eventId: 3,
            headline: "Headline",
            excerpt: "Excerpt",
            imageUrl: imageURL,
            publishedAt: "2026-10-20T10:30:00Z",
            source: "Old source",
            body: body,
            sources: [.init(name: "Market Source", url: sourceURL), .init(url: "https://example.com/second")]
        )
    }

    /// Gives `cell` the height its content needs at its width and lays it out
    private func layOut(_ cell: AgentNewsPostCell) {
        cell.layoutIfNeeded()
        cell.frame.size.height = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: cell.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        cell.layoutIfNeeded()
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
