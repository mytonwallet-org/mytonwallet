import ContextMenuKit
import MetalKit
import XCTest
import UIKit
@testable import UIAgent
import UIComponents
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class AgentThreadListUITests: XCTestCase {
    func testThreadCellHidesPreviewUsedAsTitleAndRestoresItAfterReuse() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 88))
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        let previewLabel = try XCTUnwrap(labels.first { $0.numberOfLines == 2 })
        let preview = "Your portfolio includes TON and BTC."
        let titles: [String?] = [nil, "", "My portfolio", nil, "My portfolio"]

        for title in titles {
            cell.prepareForReuse()
            cell.configure(with: try makeThreadListItem(title: title, preview: preview))

            let hasTitle = title?.isEmpty == false
            XCTAssertEqual(previewLabel.isHidden, !hasTitle)
            XCTAssertEqual(previewLabel.text, hasTitle ? preview : nil)
            XCTAssertEqual(labels.filter { !$0.isHidden && $0.text == preview }.count, 1)
            XCTAssertEqual(cell.accessibilityLabel?.components(separatedBy: preview).count, 2)
            if hasTitle {
                XCTAssertTrue(labels.contains { !$0.isHidden && $0.text == title })
                XCTAssertTrue(cell.accessibilityLabel?.hasPrefix("My portfolio, ") == true)
            } else {
                XCTAssertTrue(cell.accessibilityLabel?.hasPrefix(preview) == true)
            }
        }
    }

    func testEmptyThreadCellShowsNewChatWithoutPreview() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 88))
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        let previewLabel = try XCTUnwrap(labels.first { $0.numberOfLines == 2 })
        let titles: [String?] = [nil, ""]

        for title in titles {
            cell.configure(with: try makeThreadListItem(title: title, preview: ""))

            XCTAssertTrue(previewLabel.isHidden)
            XCTAssertNil(previewLabel.text)
            XCTAssertTrue(labels.contains { !$0.isHidden && $0.text == lang("New Chat") })
            XCTAssertTrue(cell.accessibilityLabel?.hasPrefix(lang("New Chat")) == true)
        }
    }

    func testThreadRowShowsTheAgentsStepInPlaceOfThePreviewLikeTelegramsTypingStatus() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let item = try makeThreadListItem(title: "My portfolio", preview: "Preview")
        cell.configure(with: item)
        cell.layoutIfNeeded()
        XCTAssertNil(cell.activityText)
        XCTAssertEqual(cell.previewLabel.alpha, 1)
        // The animated status joins the row only while it shows
        XCTAssertNil(cell.activityView.superview)
        XCTAssertFalse(cell.activityIndicatorView.isAnimating)

        let analyzing = lang("$agent_activity_analyzing_request")
        cell.configure(with: item, activity: analyzing)
        cell.layoutIfNeeded()
        XCTAssertEqual(cell.activityText, analyzing)
        XCTAssertEqual(cell.activityLabel.text, analyzing)
        XCTAssertTrue(cell.activityView.superview === cell.contentView)
        XCTAssertEqual(cell.previewLabel.alpha, 0)
        XCTAssertEqual(cell.activityView.alpha, 1)
        XCTAssertTrue(cell.activityIndicatorView.isAnimating)
        let font = try XCTUnwrap(cell.activityLabel.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, 15)
        // Telegram's layout: the dots start 3 pt before the preview, the text 24 pt after them, on the preview's first line
        let dotsFrame = cell.activityIndicatorView.convert(cell.activityIndicatorView.bounds, to: cell.contentView)
        let labelFrame = cell.activityLabel.convert(cell.activityLabel.bounds, to: cell.contentView)
        XCTAssertEqual(dotsFrame.minX, AgentThreadRowMetrics.textLeading - 3, accuracy: 0.5)
        XCTAssertEqual(labelFrame.minX, AgentThreadRowMetrics.textLeading + 21, accuracy: 0.5)
        XCTAssertEqual(labelFrame.minY, AgentThreadRowMetrics.previewTop, accuracy: 0.5)
        XCTAssertEqual(labelFrame.height, AgentThreadRowMetrics.previewLineHeight, accuracy: 0.5)
        XCTAssertEqual(dotsFrame.midY, labelFrame.midY, accuracy: 0.5)
        XCTAssertLessThanOrEqual(labelFrame.maxX, cell.bounds.width - AgentThreadRowMetrics.horizontalInset + 0.5)
        XCTAssertEqual(cell.accessibilityLabel?.contains(analyzing), true)
        XCTAssertEqual(cell.accessibilityLabel?.contains("Preview"), false)

        cell.setActivity(lang("$agent_activity_writing"), animated: false)
        XCTAssertEqual(cell.activityLabel.text, lang("$agent_activity_writing"))
        cell.setActivity(nil, animated: false)
        XCTAssertEqual(cell.previewLabel.alpha, 1)
        XCTAssertNil(cell.activityView.superview)
        XCTAssertFalse(cell.activityIndicatorView.isAnimating)
        XCTAssertEqual(cell.accessibilityLabel?.contains("Preview"), true)

        cell.configure(with: item, activity: analyzing)
        cell.prepareForReuse()
        XCTAssertNil(cell.activityText)
        XCTAssertNil(cell.activityView.superview)
        XCTAssertEqual(cell.previewLabel.alpha, 1)
    }

    func testThreadAvatarDrawsItsEmojiAtTelegramsSize() throws {
        _ = WalletResourcesBundle.bundle.load()
        for side: CGFloat in [AgentThreadRowMetrics.avatarSize, 26] {
            let avatar = AgentThreadAvatarView()
            avatar.frame = CGRect(x: 0, y: 0, width: side, height: side)
            avatar.configure(seed: "thread", emoji: "📊")
            avatar.layoutIfNeeded()
            let emoji = try XCTUnwrap(descendants(avatar).compactMap { $0 as? AgentAvatarEmojiLabel }.first)
            XCTAssertFalse(emoji.isHidden)
            XCTAssertEqual(emoji.text, "📊")
            XCTAssertEqual(emoji.font.pointSize, side * 26 / 60, accuracy: 0.001)
            XCTAssertEqual(emoji.frame, avatar.bounds)
        }
    }

    func testRunUpdatesShowTheAgentsStepOnTheThreadRowUntilTheAnswerCompletes() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(
            client: client,
            newsClient: ThreadListNewsClient(),
            preloader: AgentPreloader(client: LiveAgentV2Client())
        )
        let (controller, _, window, collection) = try await showLoadedList(of: model)
        defer { window.isHidden = true }
        collection.layoutIfNeeded()
        let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? AgentThreadCell)
        XCTAssertNil(cell.activityText)
        let threadId = client.thread.id

        controller.walletCore(event: .agentV2(try runUpdate("runStarted", threadId: threadId, extra: ["threadRevision": 2])))
        XCTAssertEqual(cell.activityText, lang("$agent_activity_analyzing_request"))
        XCTAssertEqual(model.getActivityText(threadId: threadId), lang("$agent_activity_analyzing_request"))

        controller.walletCore(event: .agentV2(try runUpdate("runActivityChanged", threadId: threadId, extra: [
            "event": ["protocolVersion": 2, "runId": "run-1", "sequence": 1, "code": "web.searching", "status": "active"],
        ])))
        XCTAssertEqual(cell.activityText, lang("$agent_activity_web_searching"))

        controller.walletCore(event: .agentV2(try runUpdate("textDelta", threadId: threadId, extra: [
            "messageId": "answer", "delta": "Your",
        ])))
        XCTAssertEqual(cell.activityText, lang("$agent_activity_writing"))

        controller.walletCore(event: .agentV2(try runUpdate("messageCompleted", threadId: threadId, extra: [
            "messageId": "answer", "finishReason": "complete",
        ])))
        // The row keeps the status until the list has the answer's preview, rather than showing the question again
        XCTAssertEqual(cell.activityText, lang("$agent_activity_writing"))

        // A step reported after the answer completed does not change the status
        controller.walletCore(event: .agentV2(try runUpdate("runActivityChanged", threadId: threadId, extra: [
            "event": ["protocolVersion": 2, "runId": "run-1", "sequence": 2, "code": "answer.writing", "status": "completed"],
        ])))
        XCTAssertEqual(cell.activityText, lang("$agent_activity_writing"))

        await model.refresh()
        XCTAssertNil(cell.activityText)
        XCTAssertEqual(cell.previewLabel.alpha, 1)
        XCTAssertNil(model.getActivityText(threadId: threadId))
    }

    func testPinnedHeadersAndTheTopChromeShareTheListBackgroundThroughTabPaging() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, _, window, collection) = try await showLoadedList(of: model)
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertTrue(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 1)
        ) is AgentThreadSectionHeaderView)
        // Without Liquid Glass's edge effect, a solid band from the top of the screen to the safe area, where the pinned
        // headers continue it
        let chrome = try XCTUnwrap(controller.navigationBarBackground)
        XCTAssertEqual(chrome.isHidden, AgentThreadListVC.shouldUseScrollEdgeEffect)
        XCTAssertGreaterThan(controller.view.safeAreaInsets.top, 0)
        XCTAssertEqual(chrome.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(chrome.frame.width, controller.view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(chrome.frame.maxY, controller.view.safeAreaInsets.top, accuracy: 0.5)
        XCTAssertFalse(chrome is UIVisualEffectView)
        XCTAssertTrue(chrome.subviews.isEmpty)
        // Scrolled past its place under News, the day header stays at the top of the visible list
        let visibleTop = collection.adjustedContentInset.top
        collection.setContentOffset(CGPoint(x: 0, y: -visibleTop + 150), animated: false)
        collection.layoutIfNeeded()
        let pinnedHeader = try XCTUnwrap(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 1)
        ))
        XCTAssertEqual(pinnedHeader.frame.minY, collection.contentOffset.y + visibleTop, accuracy: 0.5)
        collection.setContentOffset(CGPoint(x: 0, y: -visibleTop), animated: false)
        collection.layoutIfNeeded()
        let traits = controller.traitCollection

        func resolve(_ color: UIColor?) -> UIColor? { color?.resolvedColor(with: traits) }
        for progress: CGFloat in [1, 0, 0.5, 1] {
            controller.setTabTransitionProgress(progress)
            let expected = controller.getBackgroundColor(for: progress).resolvedColor(with: traits)
            let visibleHeader = try XCTUnwrap(collection.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 1)
            ))
            XCTAssertEqual(resolve(chrome.backgroundColor), expected)
            if AgentThreadListVC.shouldUseScrollEdgeEffect {
                XCTAssertEqual(visibleHeader.backgroundColor, .clear)
            } else {
                XCTAssertEqual(resolve(visibleHeader.backgroundColor), expected)
            }
            XCTAssertEqual(resolve(controller.view.backgroundColor), expected)
        }
    }

    func testListSelectionAndNewQuestionShareNavigation() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let threadChat = UIViewController()
        let newChat = UIViewController()
        let newsFeed = UIViewController()
        var selectedThreadId: String?
        var newQuestion: String?
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { true },
            acceptConsent: {},
            makeThreadChat: { thread in
                selectedThreadId = thread.id
                return threadChat
            },
            makeNewChat: { question in
                newQuestion = question
                return newChat
            },
            makeNewsFeed: { _ in newsFeed },
            loadSuggestions: { [] }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await waitUntil { !model.isLoading && model.items.count == 1 }
        window.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { collection.numberOfSections == 2 && collection.numberOfItems(inSection: 1) == 1 }
        XCTAssertFalse(collection.isHidden)
        XCTAssertEqual(collection.numberOfSections, 2)
        XCTAssertEqual(collection.numberOfItems(inSection: 0), 1)
        XCTAssertFalse(descendants(controller.view).contains { $0 is UISearchBar })
        XCTAssertNil(controller.navigationItem.rightBarButtonItem)
        XCTAssertGreaterThan(collection.bounds.height, 300)
        collection.layoutIfNeeded()
        XCTAssertTrue(collection.cellForItem(at: IndexPath(item: 0, section: 0)) is AgentNewsCell)

        controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 0))
        XCTAssertTrue(navigation.topViewController === newsFeed)
        navigation.popViewController(animated: false)
        try await waitUntil { navigation.topViewController === controller }

        // Chats are found through the app-wide search, so the list never filters its own
        XCTAssertTrue(client.queries.allSatisfy { $0 == nil })

        controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 1))
        XCTAssertEqual(selectedThreadId, "portfolio-thread")
        XCTAssertTrue(navigation.topViewController === threadChat)
        try await waitUntil { navigation.transitionCoordinator == nil }
        navigation.popViewController(animated: false)
        try await waitUntil { navigation.topViewController === controller }

        // Without a hosting root the list lays out its own question field, a bare composer with dictation
        let bar = controller.bottomBar
        XCTAssertTrue(bar.superview === controller.view)
        XCTAssertFalse(bar.isHidden)
        let composer = try XCTUnwrap(descendants(bar).compactMap { $0 as? AgentComposerView }.first)
        XCTAssertTrue(composer === bar.composerView)
        XCTAssertEqual(composer.style, .bare)
        XCTAssertEqual(descendants(controller.view).compactMap { $0 as? AgentComposerView }.count, 1)
        XCTAssertNotNil(composer.dictationController)
        let microphone = try XCTUnwrap(descendants(composer).compactMap { $0 as? AgentDictationButton }.first)
        XCTAssertFalse(microphone.isHidden)
        XCTAssertTrue(microphone.isEnabled)
        let microphoneGesture = try XCTUnwrap(microphone.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.first)
        XCTAssertTrue(microphoneGesture.isEnabled)
        let send = try XCTUnwrap(descendants(composer).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == lang("Send")
        })
        XCTAssertTrue(send.isHidden)
        XCTAssertFalse(send.isEnabled)
        composer.setDraftText("  Explain my portfolio  ", focus: false)
        XCTAssertFalse(send.isHidden)
        XCTAssertTrue(send.isEnabled)
        XCTAssertTrue(microphone.isHidden)
        XCTAssertEqual(bar.draftText, "Explain my portfolio")
        composer.onSend?()
        XCTAssertEqual(newQuestion, "Explain my portfolio")
        XCTAssertTrue(navigation.topViewController === newChat)
        XCTAssertTrue(composer.draftText?.isEmpty != false)
        XCTAssertFalse(send.isEnabled)
    }

    func testConsentIsRecheckedAfterAnotherChatAcceptsIt() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        var hasConsent = false
        var consentLoads = 0
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: {
                consentLoads += 1
                return hasConsent
            },
            acceptConsent: {},
            loadSuggestions: { [] }
        )
        controller.loadViewIfNeeded()
        try await waitUntil { consentLoads == 1 && self.descendants(controller.view).contains { $0 is AgentConsentView } }
        XCTAssertTrue(client.queries.isEmpty)

        hasConsent = true
        controller.viewWillAppear(false)
        try await waitUntil { model.items.count == 1 }

        XCTAssertEqual(consentLoads, 2)
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentConsentView })
    }

    func testNewsCellShowsFallbackAndUnreadCounterWithoutThreadActions() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        cell.configure(latestNews: nil, unreadCount: 0)
        let labels = descendants(cell).compactMap { $0 as? UILabel }
        let badge = try XCTUnwrap(descendants(cell).compactMap { $0 as? AgentUnreadBadgeView }.first)
        XCTAssertTrue(labels.contains { $0.text == lang("News") })
        XCTAssertFalse(labels.contains { $0.text == "MyPulse" })
        XCTAssertTrue(labels.contains { $0.text == lang("Crypto Market News") })
        XCTAssertNotNil(descendants(cell).compactMap { $0 as? AgentThreadAvatarView }.first)
        XCTAssertTrue(badge.isHidden)
        XCTAssertNil(cell.unreadMark)
        XCTAssertTrue(cell.accessibilityLabel?.hasPrefix("\(lang("News")), ") == true)
        XCTAssertNil(cell.accessibilityCustomActions)

        let item = ApiAgentV2NewsFeedItem(
            eventId: 10,
            deliveredAt: "2026-10-19T10:00:00Z",
            headline: "Latest market headline",
            body: "News body"
        )
        let now = AgentV2DateParser.date("2026-10-23T12:00:00Z")
        func getTimeColor() -> UIColor? {
            cell.timeLabel.attributedText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        }
        cell.configure(latestNews: item, unreadCount: 0, now: now)
        let readTimeColor = try XCTUnwrap(getTimeColor())
        cell.configure(latestNews: item, unreadCount: 2, now: now)
        cell.layoutIfNeeded()
        let time = AgentThreadDateFormatting.formatRowTimestamp(for: item.deliveredAt, shouldShowDateWhenNotToday: true, relativeTo: now)
        XCTAssertTrue(labels.contains { $0.text == item.headline })
        XCTAssertTrue(labels.contains { $0.text == time && !$0.isHidden })
        // Unread news is counted in Telegram's counter, and the time keeps its color and weight
        let countLabel = try XCTUnwrap(descendants(badge).compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(countLabel.text, "2")
        XCTAssertFalse(countLabel.isHidden)
        XCTAssertEqual(countLabel.textColor, .white)
        XCTAssertEqual(countLabel.font, UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold))
        XCTAssertEqual(getTimeColor(), readTimeColor)
        XCTAssertEqual(getTimeColor(), AgentThreadRowMetrics.secondaryTextColor)
        XCTAssertEqual(
            cell.timeLabel.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont,
            .systemFont(ofSize: 15)
        )
        XCTAssertFalse(badge.isHidden)
        XCTAssertEqual(cell.unreadMark, .count("2"))
        // A single digit makes a 20 pt circle where the dot's centre was, and the preview ends 8 pt before it
        let dotCenterY = AgentThreadRowMetrics.previewTop + AgentThreadRowMetrics.unreadDotTopOffset
            + AgentThreadRowMetrics.unreadDotSize / 2
        let badgeMaxX = cell.bounds.width - AgentThreadRowMetrics.horizontalInset
        XCTAssertEqual(badge.frame.minX, badgeMaxX - 20, accuracy: 0.5)
        XCTAssertEqual(badge.frame.midY, dotCenterY, accuracy: 0.5)
        XCTAssertEqual(badge.frame.size, CGSize(width: 20, height: 20))
        XCTAssertEqual(badge.layer.sublayers?.first?.cornerRadius, 10)
        XCTAssertEqual(cell.previewLabel.frame.maxX, badge.frame.minX - AgentThreadRowMetrics.unreadDotSpacing, accuracy: 0.5)
        XCTAssertTrue(cell.accessibilityLabel?.contains(L10n.agentNewsUnreadCount(count: 2)) == true)
        XCTAssertNil(cell.accessibilityCustomActions)

        // A count reads "30+" from a feed page's worth, 5 pt clear of each end of the capsule
        for (count, text) in [(9, "9"), (29, "29"), (30, "30+"), (1_234, "30+")] {
            cell.configure(latestNews: item, unreadCount: count, now: now)
            cell.layoutIfNeeded()
            XCTAssertEqual(countLabel.text, text)
            let textWidth = ceil((text as NSString).size(withAttributes: [.font: AgentThreadRowMetrics.unreadCounterFont]).width)
            XCTAssertEqual(badge.frame.width, max(20, textWidth + 10), accuracy: 0.5, text)
            XCTAssertEqual(badge.frame.height, 20)
            XCTAssertEqual(badge.frame.maxX, badgeMaxX, accuracy: 0.5)
            XCTAssertEqual(cell.previewLabel.frame.maxX, badge.frame.minX - AgentThreadRowMetrics.unreadDotSpacing, accuracy: 0.5)
        }

        cell.configure(latestNews: nil, unreadCount: 0)
        XCTAssertTrue(badge.isHidden)
        XCTAssertFalse(cell.accessibilityLabel?.contains(item.headline) == true)
        XCTAssertFalse(cell.accessibilityLabel?.contains(L10n.agentNewsUnreadCount(count: 2)) == true)
    }

    func testThreadRowRevealsRenamePinAndDeleteFromItsTrailingEdge() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        cell.configure(with: try makeThreadListItem(title: "My portfolio", preview: "Preview", isPinned: true))
        cell.layoutIfNeeded()
        let buttons = descendants(cell).compactMap { $0 as? AgentThreadSwipeButton }
        XCTAssertEqual(buttons.map(\.accessibilityLabel), [lang("Rename"), lang("Unpin"), lang("Delete")])
        XCTAssertTrue(buttons.allSatisfy { !$0.isDescendant(of: cell.contentView) })
        XCTAssertTrue(buttons.allSatisfy { $0.alpha == 0 && !$0.isUserInteractionEnabled })
        XCTAssertFalse(cell.isShowingSwipeActions)
        XCTAssertEqual(cell.contentView.transform, .identity)
        XCTAssertFalse(cell.pinView.isHidden)
        XCTAssertEqual(cell.accessibilityCustomActions?.map(\.name), [lang("Unpin"), lang("Rename"), lang("Delete")])

        var actions: [String] = []
        cell.renameAction = { actions.append("rename") }
        cell.pinAction = { actions.append("pin") }
        cell.deleteAction = { actions.append("delete") }
        for button in buttons {
            button.sendActions(for: .touchUpInside)
        }
        XCTAssertEqual(actions, ["rename", "pin", "delete"])
        XCTAssertFalse(cell.isShowingSwipeActions)

        cell.configure(with: try makeThreadListItem(title: "My portfolio", preview: "Preview"))
        cell.layoutIfNeeded()
        XCTAssertEqual(buttons[1].accessibilityLabel, lang("Pin"))
        XCTAssertTrue(cell.pinView.isHidden)
        cell.prepareForReuse()
        XCTAssertNil(cell.renameAction)
        XCTAssertNil(cell.pinAction)
        XCTAssertNil(cell.deleteAction)
        XCTAssertNil(cell.onSwipeBegan)
    }

    func testShortSwipeOpensTheActionsAndALongOneStretchesDeleteAndRunsItOnRelease() {
        var motion = AgentThreadSwipeMotion()
        motion.configure(AgentThreadSwipeParameters(width: 402, count: 3, displayScale: 3))
        XCTAssertEqual(motion.parameters.openDistance, 190)
        XCTAssertEqual(motion.parameters.confirmationDistance, 373)

        motion.begin()
        motion.change(translation: -50, velocity: 0, distanceFromCommitEdge: 380, isReduceMotionEnabled: true)
        XCTAssertEqual(motion.body.value, -pow(50, 0.7), accuracy: 0.001)
        motion.change(translation: 120, velocity: 0, distanceFromCommitEdge: 280, isReduceMotionEnabled: true)
        XCTAssertFalse(motion.isArmed)
        XCTAssertFalse(motion.end(translation: 120, velocity: 0, isCancelled: false, animated: false))
        XCTAssertEqual(motion.state, .open)
        XCTAssertEqual(motion.body.value, 190)
        let open = motion.buttonGeometry
        XCTAssertEqual(open.map(\.center), [35, 95, 155])
        XCTAssertEqual(open.map(\.width), [50, 50, 50])
        XCTAssertEqual(open.map(\.opacity), [1, 1, 1])
        // Past the open distance the other actions fade from full opacity, without a jump, to 30% where delete arms
        let justPast = AgentThreadSwipeButtonGeometry.calculate(reveal: 191, parameters: motion.parameters)
        XCTAssertEqual(justPast[1].opacity, 1 - 0.7 / 183, accuracy: 0.001)
        let halfway = AgentThreadSwipeButtonGeometry.calculate(reveal: 190 + 183 / 2, parameters: motion.parameters)
        XCTAssertEqual(halfway[2].opacity, 0.65, accuracy: 0.001)

        motion.begin()
        motion.change(translation: 190, velocity: 0, distanceFromCommitEdge: 20, isReduceMotionEnabled: true)
        XCTAssertTrue(motion.isArmed)
        XCTAssertGreaterThan(motion.body.value, 373)
        let armed = motion.buttonGeometry
        XCTAssertEqual(armed[0].width, 50 + motion.body.value - 190, accuracy: 0.001)
        XCTAssertEqual(armed[0].center, 10 + armed[0].width / 2, accuracy: 0.001)
        XCTAssertEqual(armed[0].opacity, 1)
        XCTAssertEqual(armed[1].opacity, 0.3, accuracy: 0.001)
        XCTAssertTrue(motion.end(translation: 190, velocity: 0, isCancelled: false, animated: false))
    }

    func testSwipeNearTheLeadingEdgeArmsDeleteEarlyAndACancelledSwipeDoesNotRunIt() {
        var motion = AgentThreadSwipeMotion()
        motion.configure(AgentThreadSwipeParameters(width: 402, count: 3, displayScale: 3))

        motion.begin()
        motion.change(translation: 300, velocity: 0, distanceFromCommitEdge: 200, isReduceMotionEnabled: true)
        XCTAssertFalse(motion.isArmed)
        motion.change(translation: 300, velocity: 0, distanceFromCommitEdge: 30, isReduceMotionEnabled: true)
        XCTAssertTrue(motion.isArmed)
        XCTAssertEqual(motion.body.value, 373, accuracy: 0.001)
        XCTAssertFalse(motion.end(translation: 300, velocity: 0, isCancelled: true, animated: false))
        XCTAssertEqual(motion.state, .open)
    }

    func testSwipeSettlesOnASpringAndCloses() {
        var motion = AgentThreadSwipeMotion()
        motion.configure(AgentThreadSwipeParameters(width: 402, count: 3, displayScale: 3))
        motion.settle(to: motion.parameters.openDistance, velocity: 0, animated: true)
        XCTAssertTrue(motion.isOpenOrOpening)
        XCTAssertEqual(motion.state, .settling(isOpening: true))
        for _ in 0..<600 where !motion.isAtRest {
            motion.advance(by: 1 / 120)
        }
        XCTAssertEqual(motion.state, .open)
        XCTAssertEqual(motion.body.value, 190)
        XCTAssertEqual(motion.surfaceOpacity.value, 1)

        motion.settle(to: 0, velocity: 0, animated: true)
        XCTAssertFalse(motion.isOpenOrOpening)
        for _ in 0..<600 where !motion.isAtRest {
            motion.advance(by: 1 / 120)
        }
        XCTAssertEqual(motion.state, .closed)
        XCTAssertEqual(motion.buttonGeometry.map(\.opacity), [0, 0, 0])
    }

    func testRowSeparatorStartsAtTheTextAndALiftedRowHidesIt() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        cell.configure(with: try makeThreadListItem(title: "My portfolio", preview: "Preview"))
        cell.layoutIfNeeded()
        let separator = cell.separatorView
        XCTAssertEqual(separator.alpha, 0)
        XCTAssertTrue(separator.backgroundColor == UIColor.separator || separator.backgroundColor == UIColor.air.separator)
        // As in Telegram's chat list, the line between rows starts at the text's leading edge
        XCTAssertEqual(separator.frame.minX, AgentThreadRowMetrics.textLeading)
        XCTAssertEqual(separator.frame.maxX, cell.bounds.width - AgentThreadRowMetrics.horizontalInset, accuracy: 0.001)
        XCTAssertEqual(separator.frame.maxY, cell.bounds.height, accuracy: 0.001)
        XCTAssertEqual(
            separator.frame.height,
            AgentThreadRowMetrics.getSeparatorThickness(displayScale: cell.traitCollection.displayScale),
            accuracy: 0.001
        )

        cell.isBottomSeparatorShown = true
        XCTAssertEqual(separator.alpha, 1)
        cell.liftProgress = 0.25
        XCTAssertEqual(separator.alpha, 0.75, accuracy: 0.001)
        cell.liftProgress = 0
        cell.isBottomSeparatorShown = false
        XCTAssertEqual(separator.alpha, 0)
    }

    func testMenuLiftsTheRowIntoACardInsetFromTheScreenEdges() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        cell.configure(with: try makeThreadListItem(title: "My portfolio", preview: "Preview"))
        cell.isBottomSeparatorShown = true
        cell.layoutIfNeeded()
        let card = try XCTUnwrap(cell.contentView.subviews.first)
        XCTAssertEqual(card.alpha, 0)
        XCTAssertEqual(cell.avatarView.frame.minX, 16)
        XCTAssertEqual(cell.timeLabel.frame.maxX, 386)

        cell.setMenuCardVisible(true, animated: true)
        cell.layoutIfNeeded()
        XCTAssertEqual(card.frame, CGRect(x: 16, y: 0, width: 370, height: 92))
        XCTAssertEqual(card.alpha, 1)
        XCTAssertEqual(card.layer.cornerRadius, AgentThreadMenuMetrics.cardCornerRadius)
        XCTAssertEqual(cell.avatarView.frame.minX, 32)
        XCTAssertEqual(cell.timeLabel.frame.maxX, 370)
        XCTAssertEqual(cell.separatorView.alpha, 0)

        cell.setMenuCardVisible(false, animated: true)
        cell.layoutIfNeeded()
        XCTAssertEqual(card.alpha, 0)
        XCTAssertEqual(cell.avatarView.frame.minX, 16)
        XCTAssertEqual(cell.separatorView.alpha, 1)
    }

    func testRowMenuOffersRenamePinThenDeleteAndRenameOpensTheRenameDialog() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, navigation, window, collection) = try await showLoadedList(of: model)
        defer {
            navigation.dismiss(animated: false)
            window.isHidden = true
        }
        collection.layoutIfNeeded()
        let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? AgentThreadCell)
        let menu = try XCTUnwrap(cell.contextMenuConfigurationProvider?())
        let titles = menu.rootPage.items.map { item -> String? in
            guard case .action(let action) = item else { return nil }
            return action.title
        }
        XCTAssertEqual(titles, [lang("Rename"), lang("Unpin"), nil, lang("Delete")])
        XCTAssertEqual(menu.style.sourceSpacing, AgentThreadMenuMetrics.menuSpacing)
        XCTAssertEqual(menu.style.panelCornerRadius, AgentThreadMenuMetrics.menuCornerRadius)
        guard case let .untintedBlur(radius, dimAlpha) = menu.backdrop else {
            return XCTFail("The menu blurs the list behind the lifted row")
        }
        XCTAssertEqual(radius, AgentThreadMenuMetrics.backdropBlurRadius)
        XCTAssertEqual(dimAlpha, AgentThreadMenuMetrics.backdropDimAlpha)
        // No line follows the last row of a section, and each row here is alone in its section
        let news = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? AgentNewsCell)
        XCTAssertFalse(news.isBottomSeparatorShown)
        XCTAssertFalse(cell.isBottomSeparatorShown)

        cell.renameAction?()
        let alert = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.preferredStyle, .alert)
        XCTAssertEqual(alert.title, lang("Rename Chat"))
        let field = try XCTUnwrap(alert.textFields?.first)
        XCTAssertEqual(field.text, "My portfolio")
        XCTAssertEqual(field.placeholder, lang("New Chat"))
        XCTAssertEqual(field.autocapitalizationType, .sentences)
        XCTAssertEqual(field.clearButtonMode, .whileEditing)
        XCTAssertEqual(field.returnKeyType, .done)
        XCTAssertEqual(alert.actions.map(\.title), [lang("Cancel"), lang("Save")])
        XCTAssertEqual(alert.actions.first?.style, .cancel)
        XCTAssertTrue(alert.preferredAction === alert.actions.last)
    }

    func testRootCanHostTheQuestionFieldAndHandItBack() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { false }, acceptConsent: {}, loadSuggestions: { [] })
        controller.loadViewIfNeeded()
        XCTAssertTrue(controller.bottomBar.superview === controller.view)
        XCTAssertFalse(controller.bottomBar.isHidden)
        try await waitUntil { controller.isConsentRequired }
        XCTAssertTrue(controller.bottomBar.isHidden)

        controller.setBottomBarHostedExternally(true)
        XCTAssertNil(controller.bottomBar.superview)
        controller.setBottomBarHostedExternally(false)
        XCTAssertTrue(controller.bottomBar.superview === controller.view)
    }

    func testFailedConsentCheckDoesNotPresentConsentOrHideTheQuestionField() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        var didCheck = false
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: {
                didCheck = true
                throw URLError(.notConnectedToInternet)
            },
            acceptConsent: {},
            loadSuggestions: { [] }
        )
        controller.loadViewIfNeeded()
        try await waitUntil { didCheck }
        XCTAssertFalse(controller.isConsentRequired)
        XCTAssertFalse(controller.bottomBar.isHidden)
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentConsentView })
        XCTAssertFalse(model.hasLoaded)
    }

    func testDelayedConsentDoesNotRevealExternallyHostedFoldedBar() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        var consentResponse: CheckedContinuation<Bool, Never>?
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { await withCheckedContinuation { consentResponse = $0 } },
            acceptConsent: {},
            loadSuggestions: { [] }
        )
        // Preloading starts consent without ever showing the Agent page.
        controller.setBottomBarHostedExternally(true)
        controller.loadViewIfNeeded()
        try await waitUntil { consentResponse != nil }
        XCTAssertNil(controller.view.window)

        // The root owns this bar, folds it to the plus, and hides it on another page.
        let toolbarContainer = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 48))
        let bar = controller.bottomBar
        toolbarContainer.addSubview(bar)
        bar.frame = CGRect(x: 28, y: 0, width: 346, height: 48)
        bar.setMorphProgress(0)
        bar.isHidden = true
        bar.layoutIfNeeded()
        let plus = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIImageView }.first)
        XCTAssertEqual(plus.alpha, 1)
        XCTAssertEqual(bar.composerView.contentAlpha, 0)

        // Navigation has already hidden the root toolbar when the bridge responds.
        consentResponse?.resume(returning: true)
        consentResponse = nil
        try await waitUntil { !model.items.isEmpty }
        XCTAssertNil(controller.view.window)
        XCTAssertEqual(plus.alpha, 1)
        XCTAssertTrue(bar.isHidden, "Late consent must not override the root toolbar's visibility")
    }

    func testLoadingListPreservesExternallyHostedBarVisibility() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        // The root may install and show the bar before loading the selected Agent page.
        controller.setBottomBarHostedExternally(true)
        controller.bottomBar.isHidden = false
        controller.loadViewIfNeeded()
        XCTAssertFalse(controller.bottomBar.isHidden)
        try await waitUntil { !model.items.isEmpty }
        XCTAssertFalse(controller.bottomBar.isHidden)
    }

    func testConsentShowsLocalBarAndReturningOwnershipRestoresItsVisibility() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        controller.loadViewIfNeeded()
        XCTAssertFalse(controller.bottomBar.isHidden)
        try await waitUntil { !model.items.isEmpty }
        XCTAssertFalse(controller.bottomBar.isHidden)

        controller.setBottomBarHostedExternally(true)
        controller.bottomBar.isHidden = true
        controller.setBottomBarHostedExternally(false)
        XCTAssertTrue(controller.bottomBar.superview === controller.view)
        XCTAssertFalse(controller.bottomBar.isHidden)
    }

    func testHeldConsentTopCapturesAndRefractsItsActualTitle() async throws {
        _ = WalletResourcesBundle.bundle.load()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("The consent Metal backdrop requires an application host with a window scene")
        }
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { false }, acceptConsent: {}, loadSuggestions: { [] })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await waitUntil { self.descendants(controller.view).contains { $0 is AgentConsentView } }
        window.layoutIfNeeded()
        let consent = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentConsentView }.first)
        defer { consent.isActive = false }
        let top = try XCTUnwrap(descendants(consent).compactMap { $0 as? AgentSpinningTopView }.first)
        let title = try XCTUnwrap(descendants(consent).compactMap { $0 as? UILabel }.first { $0.text == lang("Agent") })
        let metal = try XCTUnwrap(top.subviews.compactMap { $0 as? MTKView }.first)
        let queue = try XCTUnwrap(Mirror(reflecting: metal).children.first { $0.label == "queue" }?.value as? MTLCommandQueue)
        metal.framebufferOnly = false
        let titleFrame = title.convert(title.bounds, to: window)
        let restingFrame = top.convert(top.bounds, to: window)
        XCTAssertEqual(restingFrame.midX, titleFrame.midX, accuracy: 0.5)
        try await Task.sleep(for: .milliseconds(500))
        attachConsentWindow(window, name: "Consent resting")

        let center = CGPoint(x: top.bounds.midX, y: top.bounds.midY)
        top.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(state: .began, point: center))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(metal.superview === window)
        attachConsentWindow(window, name: "Consent held")
        let neutral = try consentMetalFrame(metal, queue: queue)
        attachConsentTexture(neutral.bytes, width: neutral.width, height: neutral.height, name: "Neutral held consent Metal frame")
        var left = neutral.width
        var right = -1
        for offset in stride(from: 3, to: neutral.bytes.count, by: 4) where neutral.bytes[offset] > 200 {
            let x = (offset / 4) % neutral.width
            left = min(left, x)
            right = max(right, x)
        }
        XCTAssertGreaterThan(right, left, "The held top must have a visible silhouette")
        let neutralCanvas = metal.convert(metal.bounds, to: window)
        let opticalCenterX = neutralCanvas.minX + CGFloat(left + right + 1) / 2 / CGFloat(neutral.width) * neutralCanvas.width
        XCTAssertEqual(opticalCenterX, titleFrame.midX, accuracy: 8, "Neutral hold stays centred while allowing natural precession")
        // Tilt the real top far enough for the title to enter the lens, rather than only touch its frosted rim.
        top.perform(NSSelectorFromString("handlePress:"), with: ConsentTopTestPress(
            state: .changed, point: CGPoint(x: center.x, y: center.y + 220)
        ))
        try await Task.sleep(for: .milliseconds(650))
        attachConsentWindow(window, name: "Consent held and tilted over Agent")
        metal.isPaused = true

        let backdrop = try XCTUnwrap(Mirror(reflecting: metal).children.first { $0.label == "backdrop" }?.value as? MTLTexture)
        // The owner rectangle stays in the original view's coordinates while the Metal canvas resizes on hold.
        let ownerRect = try XCTUnwrap(Mirror(reflecting: top).children.first { $0.label == "backdropRect" }?.value as? CGRect)
        let backdropFrame = top.convert(ownerRect, to: window)
        XCTAssertTrue(backdropFrame.contains(titleFrame), "The captured area must contain the real consent title")
        XCTAssertEqual(top.convert(top.bounds, to: window), restingFrame)
        XCTAssertEqual(title.convert(title.bounds, to: window), titleFrame)

        var actual = consentTextureBytes(backdrop)
        attachConsentTexture(actual, width: backdrop.width, height: backdrop.height, name: "Actual consent backdrop texture")
        let titlePixels = CGRect(
            x: (titleFrame.minX - backdropFrame.minX) / backdropFrame.width * CGFloat(backdrop.width),
            y: (titleFrame.minY - backdropFrame.minY) / backdropFrame.height * CGFloat(backdrop.height),
            width: titleFrame.width / backdropFrame.width * CGFloat(backdrop.width),
            height: titleFrame.height / backdropFrame.height * CGFloat(backdrop.height)
        ).integral
        var titlePixelCount = 0
        var withoutTitle = actual
        for y in max(0, Int(titlePixels.minY))..<min(backdrop.height, Int(titlePixels.maxY)) {
            for x in max(0, Int(titlePixels.minX))..<min(backdrop.width, Int(titlePixels.maxX)) {
                let offset = (y * backdrop.width + x) * 4
                if actual[offset + 3] > 200, (0..<3).allSatisfy({ actual[offset + $0] < 150 }) { titlePixelCount += 1 }
                for channel in 0..<4 { withoutTitle[offset + channel] = 255 }
            }
        }
        XCTAssertGreaterThan(titlePixelCount, 100, "The real Agent UILabel must be present in the captured texture")

        // Compare two actual component frames, changing only the title pixels in its captured background. The
        // clear-title frame separates transmitted lettering from the top's own coloured coating and highlights.
        let shown = try consentMetalFrame(metal, queue: queue)
        backdrop.replace(region: MTLRegionMake2D(0, 0, backdrop.width, backdrop.height), mipmapLevel: 0,
                         withBytes: &withoutTitle, bytesPerRow: backdrop.width * 4)
        defer {
            backdrop.replace(region: MTLRegionMake2D(0, 0, backdrop.width, backdrop.height), mipmapLevel: 0,
                             withBytes: &actual, bytesPerRow: backdrop.width * 4)
        }
        let blank = try consentMetalFrame(metal, queue: queue)
        attachConsentTexture(shown.bytes, width: shown.width, height: shown.height, name: "Actual held consent Metal frame")
        attachConsentTexture(blank.bytes, width: blank.width, height: blank.height, name: "Held consent without captured title")
        let canvasFrame = metal.convert(metal.bounds, to: window)
        var transmittedPixels = 0
        var displacedPixels = 0
        for y in 0..<shown.height {
            for x in 0..<shown.width {
                let offset = (y * shown.width + x) * 4
                guard shown.bytes[offset + 3] > 250, blank.bytes[offset + 3] > 250 else { continue }
                let point = CGPoint(
                    x: canvasFrame.minX + (CGFloat(x) + 0.5) / CGFloat(shown.width) * canvasFrame.width,
                    y: canvasFrame.minY + (CGFloat(y) + 0.5) / CGFloat(shown.height) * canvasFrame.height
                )
                guard titleFrame.insetBy(dx: -20, dy: -20).contains(point),
                      (0..<3).contains(where: { Int(blank.bytes[offset + $0]) - Int(shown.bytes[offset + $0]) > 35 }) else { continue }
                transmittedPixels += 1
                let bx = Int((point.x - backdropFrame.minX) / backdropFrame.width * CGFloat(backdrop.width))
                let by = Int((point.y - backdropFrame.minY) / backdropFrame.height * CGFloat(backdrop.height))
                guard (0..<backdrop.width).contains(bx), (0..<backdrop.height).contains(by) else { continue }
                let source = (by * backdrop.width + bx) * 4
                if (0..<3).allSatisfy({ actual[source + $0] > 235 }) { displacedPixels += 1 }
            }
        }
        let details = XCTAttachment(string: """
        Resting top: \(restingFrame); title: \(titleFrame)
        Neutral held silhouette center: \(opticalCenterX)
        Owner backdrop: \(ownerRect); window backdrop: \(backdropFrame)
        Canvas: \(canvasFrame); texture: \(backdrop.width)x\(backdrop.height)
        Dark title pixels in capture: \(titlePixelCount)
        Title pixels transmitted through actual top: \(transmittedPixels)
        Transmitted pixels outside the original lettering: \(displacedPixels)
        """)
        details.name = "Consent capture and refraction geometry"
        details.lifetime = .keepAlways
        add(details)
        XCTAssertGreaterThan(transmittedPixels, 80, "The captured title must affect the held top's rendered pixels")
        XCTAssertGreaterThan(displacedPixels, 25, "The held top must bend or frost the title beyond its original lettering")
    }

    func testListBottomBarComesOutOfTheToolbarSearchFieldAndWidensForAChat() {
        _ = WalletResourcesBundle.bundle.load()
        let width: CGFloat = 346
        let bar = AgentListBottomBar(frame: CGRect(x: 0, y: 0, width: width, height: AgentListBottomBar.height))
        bar.layoutIfNeeded()
        let field = bar.composerView
        XCTAssertEqual(field.style, .bare)
        XCTAssertEqual(field.frame.minX, AgentListBottomBar.height + AgentListBottomBar.spacing, accuracy: 0.5)
        XCTAssertEqual(field.frame.maxX, width, accuracy: 0.5)
        XCTAssertTrue(field.isUserInteractionEnabled)
        XCTAssertEqual(field.contentAlpha, 1, accuracy: 0.001)

        bar.setMorphProgress(0)
        XCTAssertEqual(field.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(field.frame.maxX, width, accuracy: 0.5)
        // The toolbar's search field, beside its trailing button
        XCTAssertEqual(
            field.inputBackgroundFrame.width,
            width - AgentListBottomBar.height - AgentListBottomBar.spacing,
            accuracy: 0.5
        )
        XCTAssertEqual(field.contentAlpha, 0)
        XCTAssertFalse(field.isUserInteractionEnabled)
        XCTAssertTrue(bar.accessibilityElementsHidden)
        XCTAssertFalse(bar.point(inside: CGPoint(x: width - 10, y: AgentListBottomBar.height / 2), with: nil))

        bar.setMorphProgress(1)
        bar.setExpansion(1)
        bar.layoutIfNeeded()
        XCTAssertEqual(field.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(field.frame.maxX, width, accuracy: 0.5)
        XCTAssertTrue(field.isUserInteractionEnabled)
        XCTAssertFalse(bar.accessibilityElementsHidden)
    }

    @MainActor
    func testListBottomBarMicrophoneStandsInForTheToolbarButtonAndItsGlassMovesIntoTheHost() throws {
        _ = WalletResourcesBundle.bundle.load()
        let width: CGFloat = 346
        let host = UIView(frame: CGRect(x: 0, y: 0, width: width, height: AgentListBottomBar.height))
        let container = UIView(frame: host.frame)
        container.addSubview(host)
        let bar = AgentListBottomBar(frame: host.frame)
        container.addSubview(bar)
        bar.composerView.dictationController = AgentDictationController(
            scheduler: AgentDictationTestScheduler(),
            requestPermission: { true },
            makeRecorder: { AgentDictationTestRecorder() },
            transcribe: { _ in .init(outcome: .noSpeech) },
            haptic: {},
            gestureFeedback: {},
            observeLifecycle: false
        )
        bar.layoutIfNeeded()
        let composer = bar.composerView
        let reserve = AgentComposerMetrics.microphoneSize + AgentComposerMetrics.microphoneSpacing
        XCTAssertEqual(composer.inputBackgroundFrame.width, composer.bounds.width - reserve, accuracy: 0.5)

        bar.setMorphProgress(0)
        XCTAssertEqual(composer.inputBackgroundFrame.width, composer.bounds.width - reserve, accuracy: 0.5)
        bar.setMorphProgress(1)

        let hostGlass = UIView()
        host.addSubview(hostGlass)
        bar.setGlassHost(host)
        XCTAssertFalse(bar.point(inside: CGPoint(x: width - 10, y: AgentListBottomBar.height / 2), with: nil))
        XCTAssertEqual(bar.hostedGlassViews.count, 2)
        for glass in bar.hostedGlassViews {
            XCTAssertTrue(glass.superview === host)
        }
        // The host's own glass stays above, for its field's content to show where the bar's field grows out of it
        XCTAssertTrue(host.subviews.last === hostGlass)
        let field = try XCTUnwrap(bar.hostedGlassViews.first)
        XCTAssertEqual(field.frame.minX, composer.frame.minX, accuracy: 0.5)
        XCTAssertEqual(field.frame.width, composer.inputBackgroundFrame.width, accuracy: 0.5)

        bar.isHidden = true
        XCTAssertTrue(bar.hostedGlassViews.isEmpty)
        XCTAssertTrue(field.isHidden)
        bar.isHidden = false
        bar.setGlassHost(nil)
        XCTAssertTrue(field.isDescendant(of: composer))
    }

    func testFocusedQuestionFieldShowsSuggestionsThatStartANewChat() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let hints = (0..<2).map {
            AgentHint(id: "hint:\($0)", title: "Suggestion \($0)", subtitle: "Learn", prompt: "Tell me the news \($0)")
        }
        let newChat = UIViewController()
        var newQuestion: String?
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { true },
            acceptConsent: {},
            makeNewChat: { question in
                newQuestion = question
                return newChat
            },
            loadSuggestions: { hints }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil {
            !model.isLoading && self.descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }.count == hints.count
        }
        XCTAssertTrue(suggestions.isHidden)
        XCTAssertEqual(collection.alpha, 1)
        XCTAssertFalse(collection.accessibilityElementsHidden)

        controller.bottomBar.onEditingChange?(true)

        XCTAssertFalse(suggestions.isHidden)
        XCTAssertTrue(suggestions.isUserInteractionEnabled)
        XCTAssertEqual(suggestions.alpha, 1)
        XCTAssertEqual(collection.alpha, 0)
        XCTAssertTrue(collection.accessibilityElementsHidden)
        // The suggestions stand 26 pt above the field, wherever the field is
        controller.view.layoutIfNeeded()
        let barFrame = controller.bottomBar.convert(controller.bottomBar.bounds, to: controller.view)
        XCTAssertEqual(suggestions.frame.maxY, barFrame.minY - 26, accuracy: 0.5)
        let buttons = descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(buttons.map(\.accessibilityLabel), hints.map(\.title))

        buttons[1].sendActions(for: .touchUpInside)
        XCTAssertEqual(newQuestion, hints[1].prompt)
        XCTAssertTrue(navigation.topViewController === newChat)

        controller.bottomBar.onEditingChange?(false)
        XCTAssertFalse(suggestions.isUserInteractionEnabled)
        XCTAssertEqual(collection.alpha, 1)
        XCTAssertFalse(collection.accessibilityElementsHidden)
    }

    func testAnswerBroughtByALoadUnderWayEndsTheRowsStatusAsTheRowMoves() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(
            client: client,
            newsClient: ThreadListNewsClient(),
            preloader: AgentPreloader(client: LiveAgentV2Client())
        )
        let (controller, _, window, collection) = try await showLoadedList(of: model)
        defer { window.isHidden = true }
        let threadId = client.thread.id
        controller.walletCore(event: .agentV2(try runUpdate("runStarted", threadId: threadId, extra: ["threadRevision": 2])))

        // A load is under way when the answer completes, and it already has the answer
        client.heldResponseCount = 2
        controller.walletCore(event: .agentV2(.threadChanged(threadId: threadId, thread: client.thread)))
        try await waitUntil { client.pendingResponse != nil }
        controller.walletCore(event: .agentV2(try runUpdate("messageCompleted", threadId: threadId, extra: [
            "messageId": "answer", "finishReason": "complete",
        ])))
        XCTAssertEqual(model.getActivityText(threadId: threadId), lang("$agent_activity_analyzing_request"))
        client.response = try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: Data("""
        {
            "protocolVersion": 2,
            "threads": [{
                "thread": {
                    "id": "portfolio-thread",
                    "revision": 3,
                    "createdAt": "2026-10-19T10:00:00Z",
                    "updatedAt": "2026-10-19T10:05:00Z",
                    "lastActivityAt": "2026-10-19T10:05:00Z",
                    "messageCount": 4,
                    "title": "My portfolio",
                    "icon": "📊",
                    "isPinned": true
                },
                "preview": "TON is up 3% today."
            }]
        }
        """.utf8))
        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil

        // The answer's preview takes the status's place in that load, before the refresh the answer asked for
        try await waitUntil { client.pendingResponse != nil }
        XCTAssertNil(model.getActivityText(threadId: threadId))
        collection.layoutIfNeeded()
        let cell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? AgentThreadCell)
        XCTAssertNil(cell.activityText)
        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { !model.isLoading && client.pendingResponse == nil }
    }

    func testThreadChangeDuringRefreshQueuesAnotherRefresh() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.shouldHoldFirstResponse = true
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        controller.loadViewIfNeeded()
        try await waitUntil { client.queries.count == 1 && client.pendingResponse != nil }

        controller.walletCore(event: .agentV2(.threadChanged(threadId: client.thread.id, thread: client.thread)))
        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { client.queries.count == 2 && !model.isLoading }

        XCTAssertEqual(model.items.map { $0.thread.id }, ["portfolio-thread"])
    }

    func testEmptyChatsKeepNewsAndSuggestionsVisibleWithoutFocus() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: Data("""
        {"protocolVersion":3,"threads":[]}
        """.utf8))
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let hint = AgentHint(id: "starter", title: "Explain TON", subtitle: "", prompt: "Explain TON")
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [hint] })
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil {
            model.hasLoaded && !model.isLoading && collection.numberOfSections == 1 && collection.numberOfItems(inSection: 0) == 1
        }
        collection.layoutIfNeeded()

        XCTAssertTrue(collection.cellForItem(at: IndexPath(item: 0, section: 0)) is AgentNewsCell)
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil { !suggestions.isHidden && suggestions.alpha == 1 }
        XCTAssertFalse(controller.bottomBar.isEditing)
        XCTAssertEqual(collection.alpha, 1)
        XCTAssertFalse(collection.accessibilityElementsHidden)
        XCTAssertTrue(suggestions.isUserInteractionEnabled)
        XCTAssertFalse(descendants(controller.view).contains { ($0 as? UILabel)?.text == lang("Ask a question to start a new chat.") })
        controller.bottomBar.onEditingChange?(false)
        XCTAssertFalse(suggestions.isHidden)
        XCTAssertTrue(suggestions.isUserInteractionEnabled)
    }

    func testRefreshingChatsAndNewsKeepsTheListHiddenWhileComposing() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, _, window, collection) = try await showLoadedList(of: model)
        defer { window.isHidden = true }
        controller.bottomBar.focus()
        try await waitUntil { controller.bottomBar.isEditing }
        XCTAssertEqual(collection.alpha, 0)

        await model.refresh()
        await model.refreshNews()
        window.layoutIfNeeded()
        XCTAssertTrue(controller.bottomBar.isEditing)
        XCTAssertEqual(collection.alpha, 0)
        XCTAssertTrue(collection.accessibilityElementsHidden)

        controller.bottomBar.resignEditing()
        try await waitUntil { !controller.bottomBar.isEditing }
        XCTAssertEqual(collection.alpha, 1)
        XCTAssertFalse(collection.accessibilityElementsHidden)
    }

    func testLoadingListKeepsTheSkeletonVisibleAndReplacesNewsWithTheFirstPlaceholder() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.shouldHoldFirstResponse = true
        let news = ApiAgentV2NewsFeedItem(
            eventId: 730, deliveredAt: "2026-10-30T12:00:00Z",
            headline: "News that arrived before the chat list", body: "News body"
        )
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient(items: [news]))
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        let window = makeKeyWindow(showing: ThreadListTestNavigationController(rootViewController: controller))
        defer {
            client.pendingResponse?.resume(returning: client.response)
            client.pendingResponse = nil
            window.isHidden = true
        }
        try await waitUntil { client.pendingResponse != nil && model.latestNews?.eventId == news.eventId }
        controller.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentThreadListSkeletonView }.first)
        skeleton.layoutIfNeeded()

        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(skeleton.isShowing)
        XCTAssertEqual(effectiveOpacity(of: skeleton), 1, accuracy: 0.001,
                       "Hiding the collection must not hide the skeleton through its ancestor hierarchy")
        XCTAssertEqual(effectiveOpacity(of: collection), 0, accuracy: 0.001)
        XCTAssertEqual(collection.numberOfSections, 0, "The real News row must not appear above the loading rows")
        XCTAssertFalse(descendants(collection).contains { $0 is AgentNewsCell })
        let firstRowTop = collection.frame.minY + collection.adjustedContentInset.top
        XCTAssertEqual(skeleton.frame.minY, firstRowTop, accuracy: 0.5)
        let shapeLayers = (skeleton.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        let shapes: CGPath = try XCTUnwrap(shapeLayers.first?.path)
        let avatarCenter = CGPoint(
            x: AgentThreadRowMetrics.horizontalInset + AgentThreadRowMetrics.avatarSize / 2,
            y: AgentThreadRowMetrics.avatarTop + AgentThreadRowMetrics.avatarSize / 2
        )
        XCTAssertTrue(shapes.contains(avatarCenter), "The News position gets the same avatar placeholder as every other row")

        controller.bottomBar.focus()
        try await waitUntil { controller.bottomBar.isEditing && skeleton.isHidden }
        await model.refreshNews()
        XCTAssertFalse(skeleton.isShowing, "Loading rows must also stay away while a new question is being composed")
        XCTAssertEqual(collection.alpha, 0)
        controller.bottomBar.resignEditing()
        try await waitUntil { !controller.bottomBar.isEditing }
        XCTAssertTrue(skeleton.isShowing)
        XCTAssertEqual(collection.alpha, 0)
    }

    func testLoadedListCrossfadesWithItsSkeletonAndKeepsFadingWhenNewsRefreshes() async throws {
        _ = WalletResourcesBundle.bundle.load()
        try XCTSkipIf(UIAccessibility.isReduceMotionEnabled, "This checks the animated reveal")
        let client = try ThreadListUIClient()
        client.shouldHoldFirstResponse = true
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        let window = makeKeyWindow(showing: ThreadListTestNavigationController(rootViewController: controller))
        defer {
            client.pendingResponse?.resume(returning: client.response)
            client.pendingResponse = nil
            window.isHidden = true
        }
        try await waitUntil { client.pendingResponse != nil }
        controller.view.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentThreadListSkeletonView }.first)
        XCTAssertEqual(effectiveOpacity(of: skeleton), 1, accuracy: 0.001)
        XCTAssertEqual(collection.alpha, 0)

        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { model.hasLoaded && !model.isLoading }
        let fadeIn = try XCTUnwrap(opacityAnimation(on: collection.layer), "Loaded rows must fade in")
        let fadeOut = try XCTUnwrap(opacityAnimation(on: skeleton.layer), "Skeleton rows must fade out")
        XCTAssertEqual((fadeIn.fromValue as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((fadeIn.toValue as? NSNumber)?.floatValue ?? collection.layer.opacity, 1)
        XCTAssertEqual((fadeOut.fromValue as? NSNumber)?.doubleValue, 1)
        XCTAssertEqual((fadeOut.toValue as? NSNumber)?.floatValue ?? skeleton.layer.opacity, 0)
        XCTAssertEqual(fadeIn.duration, 0.3, accuracy: 0.001)
        XCTAssertEqual(fadeOut.duration, fadeIn.duration, accuracy: 0.001)
        XCTAssertEqual(fadeOut.beginTime, fadeIn.beginTime, accuracy: 0.02)
        XCTAssertEqual(fadeOut.timingFunction, fadeIn.timingFunction)

        // News resolves independently of the chats. Its update must not cut short the reveal already on screen.
        await model.refreshNews()
        XCTAssertNotNil(opacityAnimation(on: collection.layer))
        XCTAssertNotNil(opacityAnimation(on: skeleton.layer))
        try await Task.sleep(for: .milliseconds(100))
        let rowOpacity = try XCTUnwrap(collection.layer.presentation()?.opacity)
        let skeletonOpacity = try XCTUnwrap(skeleton.layer.presentation()?.opacity)
        XCTAssertGreaterThan(rowOpacity, 0)
        XCTAssertLessThan(rowOpacity, 1)
        XCTAssertGreaterThan(skeletonOpacity, 0)
        XCTAssertLessThan(skeletonOpacity, 1)
        XCTAssertEqual(rowOpacity + skeletonOpacity, 1, accuracy: 0.12)
        XCTAssertFalse(skeleton.isHidden)

        try await waitUntil { skeleton.isHidden }
        XCTAssertEqual(effectiveOpacity(of: collection), 1, accuracy: 0.001)
        XCTAssertEqual(effectiveOpacity(of: skeleton), 0)
        collection.layoutIfNeeded()
        XCTAssertTrue(collection.cellForItem(at: IndexPath(item: 0, section: 0)) is AgentNewsCell)
    }

    func testChatMovingUpWithANewMessageLeavesTheRowsOnScreenInPlaceAsInTelegram() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try makeThreadListResponse(count: 30)
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (_, _, window, collection) = try await showLoadedList(of: model, rowCount: 30)
        defer { window.isHidden = true }
        collection.layoutIfNeeded()

        let topInset = collection.adjustedContentInset.top
        collection.contentOffset.y = -topInset + 600
        collection.layoutIfNeeded()
        func getScreenFrames() -> [(id: String, frame: CGRect)] {
            let visibleTop = collection.contentOffset.y + collection.adjustedContentInset.top
            return collection.indexPathsForVisibleItems.compactMap { indexPath -> (id: String, frame: CGRect)? in
                guard indexPath.section == 1, let frame = collection.layoutAttributesForItem(at: indexPath)?.frame,
                      frame.maxY > visibleTop else { return nil }
                return ("thread-\(indexPath.item)", frame.offsetBy(dx: 0, dy: -collection.contentOffset.y))
            }.sorted { $0.frame.minY < $1.frame.minY }
        }
        let before = getScreenFrames()
        XCTAssertGreaterThan(before.count, 3)
        let moving = before[0]
        let movingIndex = try XCTUnwrap(Int(moving.id.dropFirst("thread-".count)))

        // The top chat on screen gets a new message and goes to the top of the list, above the screen
        client.response = try makeThreadListResponse(count: 30, latest: movingIndex)
        await model.refresh()
        collection.layoutIfNeeded()

        let moved = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: 0, section: 1))?.frame)
        XCTAssertLessThanOrEqual(moved.maxY, collection.contentOffset.y + topInset)
        // The rows under it close up its place on screen, and the rest stay as they were
        let nextFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: movingIndex + 1, section: 1))?.frame)
        XCTAssertEqual(nextFrame.minY - collection.contentOffset.y, max(moving.frame.minY, topInset), accuracy: 0.5)
        let laterFrame = try XCTUnwrap(collection.layoutAttributesForItem(at: IndexPath(item: movingIndex + 2, section: 1))?.frame)
        XCTAssertEqual(laterFrame.minY - nextFrame.minY, before[2].frame.minY - before[1].frame.minY, accuracy: 0.5)

        // At the top of the list, the rows make way for the chat coming in above them
        collection.contentOffset.y = -topInset
        collection.layoutIfNeeded()
        client.response = try makeThreadListResponse(count: 30, latest: 5)
        await model.refresh()
        collection.layoutIfNeeded()
        XCTAssertEqual(collection.contentOffset.y, -topInset, accuracy: 0.5)
        let first = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? AgentThreadCell)
        XCTAssertEqual(first.titleLabel.text, "Chat 5")
    }

    /// `count` chats, the first the latest, or `latest` latest of all
    private func makeThreadListResponse(count: Int, latest: Int? = nil) throws -> ApiAgentV2ThreadListResponse {
        let threads = (0..<count).map { index -> [String: Any] in
            let minute = index == latest ? 59 : 50 - index
            let date = String(format: "2026-10-19T10:%02d:00Z", max(0, minute))
            return [
                "thread": [
                    "id": "thread-\(index)",
                    "revision": 1,
                    "createdAt": "2026-10-19T09:00:00Z",
                    "updatedAt": date,
                    "lastActivityAt": date,
                    "messageCount": 2,
                    "title": "Chat \(index)",
                    "isPinned": false,
                ] as [String: Any],
                "preview": "Message \(index)",
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: ["protocolVersion": 2, "threads": threads])
        return try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: data)
    }

    private func makeThreadListItem(title: String?, preview: String?, isPinned: Bool = false) throws -> ApiAgentV2ThreadListItem {
        let thread: [String: Any] = [
            "id": "portfolio-thread",
            "revision": 1,
            "createdAt": "2026-10-19T10:00:00Z",
            "updatedAt": "2026-10-19T10:00:00Z",
            "lastActivityAt": "2026-10-19T10:00:00Z",
            "messageCount": 2,
            "isPinned": isPinned,
            "title": title as Any? ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: [
            "thread": thread,
            "preview": preview as Any? ?? NSNull()
        ])
        return try JSONDecoder().decode(ApiAgentV2ThreadListItem.self, from: data)
    }

    private func runUpdate(_ kind: String, threadId: String, extra: [String: Any] = [:]) throws -> ApiAgentV2ClientUpdate {
        var update: [String: Any] = ["kind": kind, "clientRunId": "client-1", "runId": "run-1", "threadId": threadId]
        update.merge(extra) { _, new in new }
        return try JSONDecoder().decode(ApiAgentV2ClientUpdate.self, from: JSONSerialization.data(withJSONObject: update))
    }

    /// Shows the list of `model` on the test phone's screen and waits until its `rowCount` chats are on it
    private func showLoadedList(
        of model: AgentThreadListModel,
        rowCount: Int = 1
    ) async throws -> (AgentThreadListVC, ThreadListTestNavigationController, UIWindow, UICollectionView) {
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            window.rootViewController = navigation
            window.makeKeyAndVisible()
        } else {
            window = makeKeyWindow(showing: navigation)
        }
        do {
            let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
            try await waitUntil {
                window.layoutIfNeeded()
                navigation.view.layoutIfNeeded()
                controller.view.layoutIfNeeded()
                collection.layoutIfNeeded()
                guard !model.isLoading && collection.numberOfSections == 2
                        && collection.numberOfItems(inSection: 1) == rowCount else { return false }
                // A diffable snapshot is ready before UIKit has necessarily created its visible cells.
                return rowCount == 0 || collection.cellForItem(at: IndexPath(item: 0, section: 1)) != nil
            }
            return (controller, navigation, window, collection)
        } catch {
            window.isHidden = true
            throw error
        }
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Thread list did not settle within 2 seconds")
        throw ThreadListUITestError.timedOut
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func attachConsentWindow(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func consentTextureBytes(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(&bytes, bytesPerRow: texture.width * 4,
                         from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        return bytes
    }

    private func consentMetalFrame(_ metal: MTKView, queue: MTLCommandQueue) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let drawable = try XCTUnwrap(metal.currentDrawable)
        metal.draw()
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: drawable.texture.width, height: drawable.texture.height, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let copy = try XCTUnwrap(metal.device?.makeTexture(descriptor: descriptor))
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: drawable.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: copy.width, height: copy.height, depth: 1),
                  to: copy, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        return (consentTextureBytes(copy), copy.width, copy.height)
    }

    private func attachConsentTexture(_ bytes: [UInt8], width: Int, height: Int, name: String) {
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let attachment = XCTAttachment(image: UIImage(cgImage: image))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func effectiveOpacity(of view: UIView) -> CGFloat {
        var opacity: CGFloat = 1
        var current: UIView? = view
        while let ancestor = current {
            if ancestor.isHidden { return 0 }
            opacity *= ancestor.alpha
            current = ancestor.superview
        }
        return opacity
    }

    private func opacityAnimation(on layer: CALayer) -> CABasicAnimation? {
        layer.animationKeys()?.compactMap { layer.animation(forKey: $0) as? CABasicAnimation }
            .first { $0.keyPath == "opacity" }
    }
}

private final class ConsentTopTestPress: UILongPressGestureRecognizer {
    private let reportedState: UIGestureRecognizer.State
    private let point: CGPoint

    init(state: UIGestureRecognizer.State, point: CGPoint) {
        reportedState = state
        self.point = point
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { reportedState }
        set { }
    }

    override func location(in view: UIView?) -> CGPoint { point }
}

@MainActor
private final class ThreadListTestNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
    }
}

private enum ThreadListUITestError: Error {
    case timedOut
}

@MainActor
private final class ThreadListUIClient: AgentThreadListClient {
    var response: ApiAgentV2ThreadListResponse
    var thread: ApiAgentV2ThreadSummary { response.threads[0].thread }
    var queries: [String?] = []
    var shouldHoldFirstResponse = false
    /// How many of the next responses wait in `pendingResponse` until resumed
    var heldResponseCount = 0
    var pendingResponse: CheckedContinuation<ApiAgentV2ThreadListResponse, Never>?

    init() throws {
        response = try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: Data("""
        {
            "protocolVersion": 2,
            "threads": [{
                "thread": {
                    "id": "portfolio-thread",
                    "revision": 1,
                    "createdAt": "2026-10-19T10:00:00Z",
                    "updatedAt": "2026-10-19T10:00:00Z",
                    "lastActivityAt": "2026-10-19T10:00:00Z",
                    "messageCount": 2,
                    "title": "My portfolio",
                    "icon": "📊",
                    "isPinned": true
                },
                "preview": "Your portfolio includes TON and BTC."
            }]
        }
        """.utf8))
    }

    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        queries.append(query)
        if shouldHoldFirstResponse, queries.count == 1 {
            return await withCheckedContinuation { pendingResponse = $0 }
        }
        if heldResponseCount > 0 {
            heldResponseCount -= 1
            return await withCheckedContinuation { pendingResponse = $0 }
        }
        return response
    }

    func updateThread(id: String, update: ApiAgentV2ThreadUpdate) async throws -> ApiAgentV2ThreadUpdateResponse {
        fatalError("This UI flow does not update threads")
    }

    func deleteThread(id: String) async throws -> ApiAgentV2ThreadDeleteResponse {
        fatalError("This UI flow does not delete threads")
    }
}
