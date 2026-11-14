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

    /// A source without a name shows its site without "www.", whatever the letters' case
    func testSourceWithoutANameShowsItsSiteWithoutWww() {
        let sources = AgentNewsPostView.Content.makeSources([
            .init(url: "https://WWW.Decrypt.co/news"),
            .init(url: "https://decrypt.co/other"),
        ])
        XCTAssertEqual(sources, [.init(name: "Decrypt.co", url: "https://WWW.Decrypt.co/news")])
    }

    /// Sources lists the sources the app can open, each by its name or its site, and opens the one picked; Copy gives
    /// the full post, and Share its headline and its short link in the language it was shown in
    func testNewsMenuListsTheSourcesCopiesTheFullPostAndSharesTheHeadlineWithItsLink() throws {
        let news = makeNews()
        var openedSources: [String] = []
        var sharedItems: [Any]?
        let items = AgentMessageMenuItems.makeItems(
            for: AgentNewsPostView.Content(news: news),
            locale: "ru",
            openSource: { openedSources.append($0) },
            share: { sharedItems = $0 }
        )
        guard case .submenu(let sources) = items.first else { return XCTFail("The menu has no Sources") }
        XCTAssertEqual(sources.title, lang("$agent_news_sources"))
        let sourceActions = sources.makePage().items.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item else { return nil }
            return action
        }
        XCTAssertEqual(sourceActions.map(\.title), ["Market Source", "example.com"])
        sourceActions[1].handler?()
        XCTAssertEqual(openedSources, ["https://www.example.com/second"])

        let actions = items.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item else { return nil }
            return action
        }
        XCTAssertEqual(actions.map(\.title), [lang("Copy"), lang("Share")])
        let pasteboard = UIPasteboard.withUniqueName()
        AgentClipboard.pasteboard = pasteboard
        defer {
            AgentClipboard.pasteboard = .general
            UIPasteboard.remove(withName: pasteboard.name)
        }
        actions[0].handler?()
        XCTAssertEqual(pasteboard.string, "Headline\n\nA bold report.\nSecond paragraph.\n\nhttps://example.com/first")
        actions[1].handler?()
        let shared = try XCTUnwrap(sharedItems)
        XCTAssertEqual(shared.count, 2)
        XCTAssertEqual(shared.first as? String, "Headline")
        XCTAssertEqual(shared.last as? URL, URL(string: "https://my.tt/agent?news=3&lang=ru&utm_source=pulse_share"))
        let text = "Headline\n\nA bold report.\nSecond paragraph.\n\nhttps://example.com/first"
        XCTAssertEqual(AgentNewsPostView.Content(news: news).copyText, text)

        let oldNews = makeNews(body: nil, sourceURL: "ton://transfer/EQaddress", hasSecondSource: false)
        let oldItems = AgentMessageMenuItems.makeItems(
            for: AgentNewsPostView.Content(news: oldNews), locale: "en", openSource: { _ in }, share: { sharedItems = $0 }
        )
        let oldActions = oldItems.compactMap { item -> ContextMenuAction? in
            guard case .action(let action) = item else { return nil }
            return action
        }
        XCTAssertEqual(oldActions.map(\.title), [lang("Copy"), lang("Share")])
        XCTAssertEqual(oldItems.count, 2)
        oldActions[1].handler?()
        XCTAssertEqual(sharedItems?.last as? URL, URL(string: "https://my.tt/agent?news=3&lang=en&utm_source=pulse_share"))
        XCTAssertEqual(AgentNewsPostView.Content(news: oldNews).copyText, "Headline\n\nExcerpt\n\nton://transfer/EQaddress")
    }

    /// VoiceOver reads the post and its time without the source's name, and Copy keeps the first source's link
    func testAccessibilityReadsThePostWithoutItsSourceAndCopyKeepsTheFirstSource() throws {
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
            "\(lang("News")), Headline, A bold report.\nSecond paragraph., \(AgentNewsMetaView.formatDiscussionTime(for: news.publishedAt))"
        )
        XCTAssertEqual(bubble.accessibilityCustomActions?.map(\.name), [lang("$agent_news_open_source"), lang("More actions")])
        XCTAssertEqual(cell.contextMenuCopyText, "Headline\n\nA bold report.\nSecond paragraph.\n\nhttps://example.com/first")
        var openedSources = 0
        cell.openSourceAction = { openedSources += 1 }
        let openSource = try XCTUnwrap(bubble.accessibilityCustomActions?.first)
        XCTAssertEqual(openSource.actionHandler?(openSource), true)
        XCTAssertEqual(openedSources, 1)
    }

    func testUnsupportedSourceHasNoOpenSourceActionAndOldCardsUseExcerpt() throws {
        let cell = AgentNewsPostCell(frame: .zero)
        cell.configure(with: makeNews(body: nil, sourceURL: "ton://transfer/EQaddress"))
        let bubble = try XCTUnwrap((cell.accessibilityElements as? [UIView])?.first)
        XCTAssertEqual(bubble.accessibilityCustomActions?.map(\.name), [lang("More actions")])
        XCTAssertEqual(cell.contextMenuCopyText, "Headline\n\nExcerpt\n\nton://transfer/EQaddress")
    }

    /// A digest's post is the news post with the digest's card: its time in the header, its title and its headlines
    /// listed as on the card, each opening its news item, and the news it leaves out, without a picture or a source to
    /// open, keeping the post's menu
    func testDigestPostListsTheDigestsHeadlinesWithoutSourceOrPicture() throws {
        let digest = try JSONDecoder().decode(ApiAgentV2ThreadDigestCard.self, from: Data("""
        {"id":"en:2026-11-08T18:00:00.000Z","windowEnd":"2026-11-08T18:00:00.000Z","total":26,
         "top":[{"eventId":1,"headline":"Binance restored its tokens"},{"eventId":2,"headline":"BlackRock sold Bitcoin"}]}
        """.utf8))
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 600))
        cell.configure(with: AgentNewsPostView.Content(digest: digest))
        cell.layoutIfNeeded()
        let bubble = try XCTUnwrap((cell.accessibilityElements as? [UIView])?.first)
        let header = lang("News")
        let remainder = L10n.agentDigestMore(count: 24)
        XCTAssertTrue(descendants(cell).compactMap { $0 as? UILabel }.contains { $0.text == header })
        XCTAssertTrue(descendants(cell).compactMap { $0 as? UILabel }.contains { $0.text == remainder && !$0.isHidden })
        XCTAssertEqual(bubble.accessibilityIdentifier, "AgentDigestPost-\(digest.id)")
        XCTAssertEqual(
            bubble.accessibilityLabel,
            "\(header), \(lang("$agent_digest_title")), Binance restored its tokens, BlackRock sold Bitcoin, \(remainder), "
                + AgentNewsMetaView.formatDiscussionTime(for: digest.windowEnd)
        )
        XCTAssertEqual(
            bubble.accessibilityCustomActions?.map(\.name),
            [lang("More actions"), "Binance restored its tokens", "BlackRock sold Bitcoin"]
        )
        XCTAssertEqual(
            cell.contextMenuCopyText,
            "\(lang("$agent_digest_title"))\n\n• Binance restored its tokens\n• BlackRock sold Bitcoin"
        )
        XCTAssertTrue(try XCTUnwrap(descendants(cell).compactMap { $0 as? WImageView }.first).isHidden)

        let headlines = descendants(cell).compactMap { $0 as? UIButton }
            .filter { $0.accessibilityIdentifier?.hasPrefix("AgentNewsDigestHeadline-") == true }
        XCTAssertEqual(headlines.map(\.accessibilityLabel), ["Binance restored its tokens", "BlackRock sold Bitcoin"])
        var openedEventIds: [Int] = []
        cell.onDigestHeadlineTap = { openedEventIds.append($0) }
        headlines[1].sendActions(for: .touchUpInside)
        XCTAssertEqual(openedEventIds, [2])
        // The arrows are gray and end as far from the bubble's edge as the Discuss strip's arrow box
        let arrows = descendants(cell).compactMap { $0 as? UIImageView }.filter { $0.image == AgentNewsDiscussionStrip.arrowImage }
        XCTAssertEqual(arrows.count, 2)
        for arrow in arrows {
            XCTAssertEqual(arrow.tintColor, UIColor.air.secondaryLabel)
            let frame = arrow.convert(arrow.bounds, to: cell.postView)
            XCTAssertEqual(cell.postView.bounds.width - frame.maxX, AgentNewsDiscussionMetrics.arrowTrailingInset, accuracy: 0.5)
        }
        // A tap on the arrow, past the text's inset, still opens its row
        let arrowCenter = arrows[0].convert(CGPoint(x: arrows[0].bounds.midX, y: arrows[0].bounds.midY), to: cell)
        XCTAssertTrue(cell.hitTest(arrowCenter, with: nil) === headlines[0])
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
        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay + 0.65))
        XCTAssertTrue(cell.showsFollowupPlaceholders)
        cell.configureFollowups(followups)
        layOut(cell)
        let replacementButtons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        let replacementStarts = try replacementButtons.map { try XCTUnwrap($0.contentAppearance).beginTime }
        XCTAssertEqual(replacementStarts.count, 2)
        XCTAssertEqual(replacementStarts[1] - replacementStarts[0], 0, accuracy: 0.02)
    }

    /// Suggestions that come within `followupPlaceholderDelay` come in on their own, with no placeholder before them,
    /// and a post that stops waiting for them sooner, through a failure or a reuse, never gets placeholders
    func testSuggestionsWithinASecondComeInWithoutPlaceholders() async throws {
        let (cell, window) = try makeHostedCell()
        defer { window.isHidden = true }
        let tailOverflow = AgentBubbleBackgroundView.tailBottomOverflow
        cell.configureFollowups([], isLoading: true)
        layOut(cell)
        XCTAssertFalse(cell.showsFollowupPlaceholders)
        XCTAssertTrue(placeholders(in: cell).isEmpty)
        XCTAssertEqual(cell.postTailOverflow, tailOverflow, "Nothing hangs from the post while the suggestions are due")

        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay / 2))
        cell.configureFollowups(makeFollowups(), isLoading: true)
        layOut(cell)
        let buttons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(placeholders(in: cell).isEmpty)
        XCTAssertEqual(cell.postTailOverflow, 0)
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertTrue(buttons.allSatisfy { $0.layer.animation(forKey: "agentFollowupRevealOpacity") != nil },
                          "The suggestions come in with their own entrance")
            XCTAssertTrue(buttons.allSatisfy { $0.contentAppearance == nil && $0.pillFrameOverride == nil },
                          "No placeholder turns into them")
        }
        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay))
        XCTAssertTrue(placeholders(in: cell).isEmpty, "The delay ends with the wait")

        // A failure before the delay: the post stops waiting and keeps its tail, with nothing coming in after it
        let failed = AgentNewsPostCell(frame: cell.frame)
        cell.superview?.addSubview(failed)
        failed.configure(with: makeNews())
        failed.configureFollowups([], isLoading: true)
        // Leaving the chat before the delay: the cell goes back to the pool
        let left = AgentNewsPostCell(frame: cell.frame)
        cell.superview?.addSubview(left)
        left.configure(with: makeNews())
        left.configureFollowups([], isLoading: true)
        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay / 2))
        failed.configureFollowups([], isLoading: false)
        left.prepareForReuse()
        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay))
        for post in [failed, left] {
            XCTAssertFalse(post.showsFollowupPlaceholders)
            XCTAssertTrue(placeholders(in: post).isEmpty)
            XCTAssertEqual(post.postTailOverflow, tailOverflow)
        }
    }

    /// Suggestions that take longer than `followupPlaceholderDelay` get placeholders then, which come in one by one out of
    /// a blur and turn into the suggestions once they arrive
    func testPlaceholdersShowOnceTheSuggestionsTakeASecondAndGiveWayToThem() async throws {
        let (cell, window) = try makeHostedCell()
        defer { window.isHidden = true }
        var heightChanges = 0
        cell.onPreferredHeightChanged = { heightChanges += 1 }
        cell.configureFollowups([], isLoading: true)
        layOut(cell)
        try await Task.sleep(for: .seconds(AgentNewsPostCell.followupPlaceholderDelay * 0.8))
        XCTAssertTrue(placeholders(in: cell).isEmpty, "Not before the delay")
        // The chat configures the post again on its updates meanwhile, which keeps the delay running
        cell.configureFollowups([], isLoading: true)

        var shown: [AgentSuggestionButton] = []
        for _ in 0..<100 where shown.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
            shown = placeholders(in: cell)
        }
        XCTAssertEqual(shown.count, 3)
        XCTAssertTrue(cell.showsFollowupPlaceholders)
        // Each is a suggestion's pill, with its fill and border, and the passing light inside it alone
        layOut(cell)
        for placeholder in shown {
            XCTAssertEqual(placeholder.bounds.height, AgentSuggestionButton.height, accuracy: 0.5)
            XCTAssertEqual(descendants(placeholder).compactMap { $0 as? AgentSuggestionBackgroundView }.count, 1)
            let light = try XCTUnwrap(placeholder.pillOverlayView as? AgentMessagesSkeletonView)
            let pill = try XCTUnwrap(light.superview)
            XCTAssertEqual(light.frame, pill.bounds)
            XCTAssertFalse(placeholder.isUserInteractionEnabled)
            XCTAssertFalse(placeholder.isAccessibilityElement)
        }
        XCTAssertEqual(cell.postTailOverflow, 0)
        layOut(cell)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(heightChanges, 1, "The chat measures the post's row again for its placeholders")
        if !UIAccessibility.isReduceMotionEnabled {
            let starts = try shown.map { try XCTUnwrap($0.layer.animation(forKey: "agentFollowupRevealOpacity")).beginTime }
            XCTAssertEqual(starts[1] - starts[0], 0.15, accuracy: 0.01, "The placeholders come in one by one")
            // Each comes into focus out of its own blur and rises into place, as a suggestion does
            for placeholder in shown {
                let blur = try XCTUnwrap(placeholder.layer.animation(forKey: "agentFollowupRevealBlur") as? CABasicAnimation)
                XCTAssertEqual(blur.fromValue as? CGFloat, AgentBlurTransition.radius)
                XCTAssertNotNil(placeholder.layer.animation(forKey: "agentFollowupRevealOffset"))
            }
        }

        try await Task.sleep(for: .milliseconds(700))
        cell.configureFollowups(makeFollowups(), isLoading: true)
        layOut(cell)
        XCTAssertFalse(cell.showsFollowupPlaceholders)
        XCTAssertTrue(placeholders(in: cell).isEmpty)
        let buttons = descendants(cell).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Why does it matter?", "What happens next?"])
        // The suggestions fill the placeholders' own pills, so the fill and the border stay as they are
        XCTAssertEqual(buttons.map(ObjectIdentifier.init), shown.prefix(2).map(ObjectIdentifier.init))
        XCTAssertTrue(buttons.allSatisfy { $0.isUserInteractionEnabled && $0.isAccessibilityElement })
        if !UIAccessibility.isReduceMotionEnabled {
            // Only the titles come in, as each pill goes from its placeholder's width to its title's
            XCTAssertTrue(buttons.allSatisfy { $0.contentAppearance != nil }, "The titles fade in")
            XCTAssertEqual(try XCTUnwrap(buttons[0].pillFrameOverride).width, 230, accuracy: 0.5)
            XCTAssertEqual(try XCTUnwrap(buttons[1].pillFrameOverride).width, 270, accuracy: 0.5)
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTAssertTrue(buttons.allSatisfy { $0.pillFrameOverride == nil && $0.pillOverlayView == nil })
        XCTAssertTrue(buttons.allSatisfy { abs($0.bounds.width - $0.intrinsicContentSize.width) < 1 })
    }

    /// The time alone ends the post in the bubble's trailing corner, as a chat message's time does, with no source
    func testTimeAloneSitsInTheBubblesTrailingCorner() throws {
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
        XCTAssertEqual(meta.timeLabel.text, AgentNewsMetaView.formatDiscussionTime(for: news.publishedAt))
        XCTAssertEqual(descendants(meta).compactMap { $0 as? UILabel }, [meta.timeLabel])
        XCTAssertFalse(descendants(cell).compactMap { $0 as? UILabel }.contains { $0.text?.contains("Market Source") == true })
        // 12 pt from the bubble's trailing edge, as on Android and the web, nearer than the text
        let timeFrame = meta.timeLabel.convert(meta.timeLabel.bounds, to: bubble)
        XCTAssertEqual(AgentNewsMetaView.trailingInset, 12)
        XCTAssertEqual(timeFrame.maxX, bubble.bounds.width - AgentNewsMetaView.trailingInset, accuracy: 0.5)
        let headline = try XCTUnwrap(descendants(cell).compactMap { $0 as? UILabel }.first { $0.text == news.headline })
        XCTAssertEqual(headline.convert(headline.bounds, to: bubble).maxX, bubble.bounds.width - 16, accuracy: 0.5)
    }

    func testDiscussionTimeShowsTheDateForEarlierNews() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = AgentV2DateParser.date("2026-10-24T12:00:00Z")
        let russian = Locale(identifier: "ru_RU")
        XCTAssertEqual(
            AgentNewsMetaView.formatDiscussionTime(
                for: "2026-10-24T09:05:00Z", relativeTo: now, calendar: calendar, locale: russian, hourCycle: .zeroToTwentyThree
            ),
            "09:05"
        )
        let earlier = AgentNewsMetaView.formatDiscussionTime(
            for: "2026-07-20T15:38:00Z", relativeTo: now, calendar: calendar, locale: russian, hourCycle: .zeroToTwentyThree
        )
        XCTAssertTrue(earlier.contains("20"))
        XCTAssertTrue(earlier.contains("июл"))
        XCTAssertFalse(earlier.contains("июл."))
        XCTAssertTrue(earlier.hasSuffix("15:38"))
        let lastYear = AgentNewsMetaView.formatDiscussionTime(
            for: "2025-07-20T15:38:00Z", relativeTo: now, calendar: calendar, locale: russian, hourCycle: .zeroToTwentyThree
        )
        XCTAssertTrue(lastYear.contains("2025"))
        XCTAssertFalse(lastYear.contains("г"), "The year goes without its abbreviated word")
        let september = AgentNewsMetaView.formatDiscussionTime(
            for: "2026-09-04T15:38:00Z", relativeTo: now, calendar: calendar, locale: russian, hourCycle: .zeroToTwentyThree
        )
        XCTAssertTrue(september.hasPrefix("4 сен"))
    }

    /// The discussion's time is on the device's 12- or 24-hour clock in the app's language, as the feed's cards are
    func testDiscussionTimeFollowsTheHourCycle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = AgentV2DateParser.date("2026-10-24T18:00:00Z")
        let english = Locale(identifier: "en")
        func format(_ timestamp: String, _ hourCycle: Locale.HourCycle) -> String {
            AgentNewsMetaView.formatDiscussionTime(
                for: timestamp, relativeTo: now, calendar: calendar, locale: english, hourCycle: hourCycle
            )
        }
        XCTAssertEqual(format("2026-10-24T15:38:00Z", .zeroToTwentyThree), "15:38")
        let today = format("2026-10-24T15:38:00Z", .oneToTwelve)
        XCTAssertTrue(today.hasPrefix("3:38"))
        XCTAssertTrue(today.contains("PM"))
        let earlier = format("2026-07-20T15:38:00Z", .zeroToTwentyThree)
        XCTAssertTrue(earlier.contains("Jul"))
        XCTAssertTrue(earlier.hasSuffix("15:38"))
        let earlierOnTwelveHours = format("2026-07-20T15:38:00Z", .oneToTwelve)
        XCTAssertTrue(earlierOnTwelveHours.contains("3:38"))
        XCTAssertTrue(earlierOnTwelveHours.contains("PM"))
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
        imageURL: String? = nil,
        hasSecondSource: Bool = true
    ) -> ApiAgentV2ThreadNewsCard {
        .init(
            eventId: 3,
            headline: "Headline",
            excerpt: "Excerpt",
            imageUrl: imageURL,
            publishedAt: "2026-10-20T10:30:00Z",
            source: "Old source",
            body: body,
            sources: [.init(name: "Market Source", url: sourceURL)]
                + (hasSecondSource ? [.init(url: "https://www.example.com/second")] : [])
        )
    }

    private func makeFollowups() -> [AgentMessageControl] {
        [
            AgentMessageControl(id: "followup:why", title: "Why does it matter?", isEnabled: true, kind: .followup),
            AgentMessageControl(id: "followup:next", title: "What happens next?", isEnabled: true, kind: .followup),
        ]
    }

    /// A post in a window, where its suggestions' entrances play
    private func makeHostedCell() throws -> (AgentNewsPostCell, UIWindow) {
        let host = UIViewController()
        let window = makeKeyWindow(showing: host)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window.windowScene = scene
        }
        window.makeKeyAndVisible()
        let cell = AgentNewsPostCell(frame: CGRect(x: 0, y: 0, width: 402, height: 100))
        host.view.addSubview(cell)
        cell.configure(with: makeNews())
        cell.configureFollowups([])
        layOut(cell)
        return (cell, window)
    }

    /// The suggestions' pills that stand in for them while they load
    private func placeholders(in cell: AgentNewsPostCell) -> [AgentSuggestionButton] {
        descendants(cell).compactMap { $0 as? AgentSuggestionButton }.filter {
            !$0.isHidden && $0.accessibilityIdentifier == AgentFollowupView.placeholderIdentifier
        }
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
