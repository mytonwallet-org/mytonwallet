import ContextMenuKit
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

    func testThreadCellLabelsAChatWithSupportBeforeItsPreview() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentThreadCell(frame: CGRect(x: 0, y: 0, width: 402, height: 88))
        let supportLabel = lang("$agent_support_label")
        let cases: [(ApiAgentV2ThreadSupport.State?, AgentSupportPresentation.LabelStyle?)] = [
            (.operator, .active), (.waiting, .muted), (.closed, nil), (nil, nil)
        ]

        for (state, style) in cases {
            cell.configure(with: try makeThreadListItem(
                title: "Transfer", preview: "Where is my transfer?", support: state.map { .init(state: $0) }
            ))

            XCTAssertEqual(cell.supportLabelStyle, style)
            XCTAssertEqual(cell.supportLabelView.isHidden, style == nil)
            XCTAssertEqual(
                cell.accessibilityLabel?.hasPrefix("Transfer, \(supportLabel), Where is my transfer?"),
                style != nil
            )
        }
    }

    /// Contact Support confirmed before consent waits for the server's chats; opening News meanwhile drops it, so no
    /// support chat comes over the screen the user went to
    func testContactSupportWaitingForTheChatsIsDroppedOnceTheListIsLeft() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.heldResponseCount = 1
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        var hasConsent = false
        var sheets: [UIAlertController] = []
        var supportChatCount = 0
        let newsFeed = UIViewController()
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { hasConsent },
            acceptConsent: { hasConsent = true },
            makeThreadChat: { _, _ in UIViewController() },
            makeNewChat: { _ in UIViewController() },
            makeSupportChat: {
                supportChatCount += 1
                return UIViewController()
            },
            hasWalletAccount: { true },
            presentConfirmation: { alert, _ in sheets.append(alert) },
            makeNewsFeed: { _ in newsFeed },
            loadSuggestions: { [] }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil { self.descendants(suggestions).contains { $0.accessibilityIdentifier == "agent_support_hint" } }
        let support = try XCTUnwrap(descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }.last)
        support.sendActions(for: .touchUpInside)
        performAlertAction(titled: lang("$agent_support_confirm_action"), in: try XCTUnwrap(sheets.last))
        let sheet = try await waitForConsentSheet(over: controller, in: self)
        sheet.consentView.onContinue?()
        try await waitUntil { client.pendingResponse != nil && presentation.presentedViewController(of: controller) == nil }

        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 0))
        try await waitUntil { navigation.topViewController === newsFeed }
        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { model.serverListState == .loaded }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(supportChatCount, 0)
        XCTAssertTrue(navigation.topViewController === newsFeed)
    }

    func testContactSupportHintShowsBeforeTheSuggestionsLoad() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let hint = AgentHint(id: "hint:0", title: "Suggestion", subtitle: "Learn", prompt: "Tell me the news")
        var pendingSuggestions: CheckedContinuation<[AgentHint], Never>?
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { false },
            acceptConsent: {},
            loadSuggestions: { await withCheckedContinuation { pendingSuggestions = $0 } }
        )
        let window = makeKeyWindow(showing: ThreadListTestNavigationController(rootViewController: controller))
        defer {
            pendingSuggestions?.resume(returning: [])
            window.isHidden = true
        }
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        func titles() -> [String?] {
            descendants(suggestions).compactMap { ($0 as? AgentSuggestionButton)?.accessibilityLabel }
        }

        // Contact Support shows while the suggestions load, and they come before it
        try await waitUntil { pendingSuggestions != nil }
        XCTAssertEqual(titles(), [lang("$agent_support_contact")])
        pendingSuggestions?.resume(returning: [hint])
        pendingSuggestions = nil
        try await waitUntil { titles().count == 2 }
        XCTAssertEqual(titles(), ["Suggestion", lang("$agent_support_contact")])
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

    /// A row of the SDK's copy of the list opens its chat as one whose summary is cached, and the same row of the
    /// loaded list as an ordinary chat
    func testCachedRowsOpenTheirChatsWithACachedSummary() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.cachedItems = client.response.threads
        client.heldResponseCount = 1
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        var openedSummaryKinds: [Bool] = []
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { true },
            acceptConsent: {},
            makeThreadChat: { _, isSummaryCached in
                openedSummaryKinds.append(isSummaryCached)
                return UIViewController()
            },
            makeNewChat: { _ in UIViewController() },
            makeNewsFeed: { _ in UIViewController() },
            loadSuggestions: { [] }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        try await waitUntil { model.isShowingCachedThreads }
        window.layoutIfNeeded()
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        try await waitUntil { collection.numberOfSections == 2 && collection.numberOfItems(inSection: 1) == 1 }
        controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 1))
        try await waitUntil { navigation.transitionCoordinator == nil }
        navigation.popViewController(animated: false)
        try await waitUntil { navigation.topViewController === controller }

        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { !model.isShowingCachedThreads && !model.isLoading }
        controller.collectionView(collection, didSelectItemAt: IndexPath(item: 0, section: 1))
        XCTAssertEqual(openedSummaryKinds, [true, false])
    }

    /// A toast, such as the denied microphone's, stands above the question field, as the chat's toasts stand above its
    /// composer
    func testToastStandsAboveTheQuestionField() throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { false }, acceptConsent: {}, loadSuggestions: { [] })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = ThreadListTestNavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        controller.showToast(ToastConfig(style: .overlay, message: "Toast", duration: 5, transition: .scale))
        let toastView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ToastView }.first)
        controller.view.layoutIfNeeded()
        let fieldTop = controller.bottomBar.convert(controller.bottomBar.fieldFrame, to: controller.view).minY
        XCTAssertEqual(toastView.frame.maxY, fieldTop - AgentVCLayout.toastSpacingToComposer, accuracy: 0.5)
    }

    /// While the root that hosts the question field has it away from the list's window, a toast rests above the safe
    /// area instead of on the field
    func testToastRestsAboveTheSafeAreaWhileTheHostedFieldIsAway() throws {
        _ = WalletResourcesBundle.bundle.load()
        let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { false }, acceptConsent: {}, loadSuggestions: { [] })
        controller.setBottomBarHostedExternally(true)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = ThreadListTestNavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        XCTAssertNil(controller.bottomBar.window)

        controller.showToast(ToastConfig(style: .overlay, message: "Toast", duration: 5, transition: .scale))
        let toastView = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ToastView }.first)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(toastView.frame.maxY, controller.view.safeAreaLayoutGuide.layoutFrame.maxY - 12, accuracy: 0.5)
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
            makeThreadChat: { thread, _ in
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
        try await waitUntil { consentLoads == 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(client.queries.isEmpty, "Without consent the list asks the Agent for nothing")
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentConsentView }, "Nor does it ask for consent")

        hasConsent = true
        controller.viewWillAppear(false)
        try await waitUntil { model.items.count == 1 }

        XCTAssertEqual(consentLoads, 2)
    }

    /// The top tabs mount the list into a hidden page before it is chosen, already in the window: there it loads News
    /// once, and the refresh timer runs only while the list is on screen
    func testListPreparedOutOfSightRefreshesOnlyWhileOnScreen() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let newsClient = ThreadListNewsClient()
        let list = AgentThreadListVC(
            model: AgentThreadListModel(client: try ThreadListUIClient(), newsClient: newsClient),
            loadConsent: { true },
            acceptConsent: {},
            loadSuggestions: { [] },
            refreshInterval: 0.05
        )
        let pager = WPagerViewController(pages: [
            .init(id: "wallet", makeViewController: { UIViewController() }),
            .init(id: "agent", makeViewController: { list }),
        ], preloadsPages: true)
        let window = makeKeyWindow(showing: pager)
        defer { window.isHidden = true }

        try await waitUntil { list.viewIfLoaded?.window != nil && newsClient.requests.count == 1 }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(newsClient.requests.count, 1, "Out of sight the list keeps the News it loaded")

        pager.select(index: 1, animated: false)
        try await waitUntil { newsClient.requests.count >= 4 }

        pager.select(index: 0, animated: false)
        try await Task.sleep(for: .milliseconds(100))
        let requestCount = newsClient.requests.count
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(newsClient.requests.count, requestCount, "Nor does it refresh once it has left the screen")
    }

    /// A reset of the accounts deletes the consent: the app forgets that it knew it, and a list on screen through the
    /// reset reads it again, as a new list does
    func testAccountsResetForgetsTheKnownConsent() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let agentClient = FakeAgentV2Client()
        agentClient.isConsentKnownGiven = true
        var hasConsent = true
        var consentLoads = 0
        func makeList(client: ThreadListUIClient) -> AgentThreadListVC {
            AgentThreadListVC(
                model: AgentThreadListModel(client: client, newsClient: ThreadListNewsClient()),
                loadConsent: {
                    consentLoads += 1
                    return hasConsent
                },
                acceptConsent: {},
                isConsentKnownGiven: { agentClient.isConsentKnownGiven },
                loadSuggestions: { [] }
            )
        }
        let shownList = makeList(client: try ThreadListUIClient())
        shownList.loadViewIfNeeded()
        try await waitUntil { consentLoads == 1 }

        hasConsent = false
        AgentPreloader(client: agentClient).walletCore(event: .accountsReset)
        XCTAssertFalse(agentClient.isConsentKnownGiven)
        shownList.walletCore(event: .accountsReset)
        try await waitUntil { consentLoads == 2 }

        let newListClient = try ThreadListUIClient()
        let newList = makeList(client: newListClient)
        newList.loadViewIfNeeded()
        newList.viewWillAppear(false)
        try await waitUntil { consentLoads == 3 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(newListClient.queries.isEmpty, "Without consent the new list asks the Agent for nothing")
    }

    /// A list on screen keeps its rows while its chats load: News with the suggestions before consent stays, without
    /// the skeleton, as consent given in another chat brings the chats, which then come in as any update's do, and a
    /// later reload keeps the list too. Only a list with nothing to show yet loads under the skeleton.
    func testListOnScreenKeepsItsRowsWithoutTheSkeletonWhileItsChatsLoad() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let news = ApiAgentV2NewsFeedItem(
            eventId: 731, deliveredAt: "2026-10-30T12:00:00Z", headline: "Markets calm", body: "Little moved today"
        )
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient(items: [news]))
        var hasConsent = false
        let controller = AgentThreadListVC(
            model: model, loadConsent: { hasConsent }, acceptConsent: {}, loadSuggestions: { [] }
        )
        let window = makeKeyWindow(showing: ThreadListTestNavigationController(rootViewController: controller))
        defer {
            client.pendingResponse?.resume(returning: client.response)
            client.pendingResponse = nil
            window.isHidden = true
        }
        try await waitUntil { self.descendants(controller.view).contains { $0 is AgentNewsCell && !$0.isHidden } }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentThreadListSkeletonView }.first)

        hasConsent = true
        client.shouldHoldFirstResponse = true
        controller.viewWillAppear(false)
        try await waitUntil { client.pendingResponse != nil }
        controller.view.layoutIfNeeded()
        XCTAssertFalse(model.hasLoaded)
        XCTAssertFalse(skeleton.isShowing, "No skeleton over the list on screen")
        XCTAssertEqual(collection.alpha, 1)
        XCTAssertTrue(descendants(collection).contains { $0 is AgentNewsCell && !$0.isHidden }, "News stays")

        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { model.items.count == 1 }
        try await waitUntil { self.descendants(collection).contains { $0 is AgentThreadRowCell && !$0.isHidden } }
        XCTAssertFalse(skeleton.isShowing)
        XCTAssertEqual(collection.alpha, 1)

        controller.viewWillAppear(false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(skeleton.isShowing, "A reload keeps the list")
        XCTAssertEqual(collection.alpha, 1)
    }

    /// Before consent the list shows News, which the SDK serves without consent, and loads its latest post, while it
    /// asks for no chats
    func testNewsShowsBeforeConsent() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let newsClient = ThreadListNewsClient(items: [ApiAgentV2NewsFeedItem(
            eventId: 1, deliveredAt: "2026-11-05T01:00:00Z", headline: "Markets calm", body: "Little moved today"
        )])
        let model = AgentThreadListModel(client: client, newsClient: newsClient)
        let controller = AgentThreadListVC(model: model, loadConsent: { false }, acceptConsent: {}, loadSuggestions: { [] })
        let window = makeKeyWindow(showing: ThreadListTestNavigationController(rootViewController: controller))
        defer { window.isHidden = true }
        try await waitUntil { !newsClient.requests.isEmpty && model.latestNews != nil }
        window.layoutIfNeeded()
        try await waitUntil { self.descendants(controller.view).contains { $0 is AgentNewsCell && !$0.isHidden } }
        XCTAssertTrue(client.queries.isEmpty, "No chats are asked for before consent")
        XCTAssertFalse(descendants(controller.view).contains { $0 is AgentConsentView })
    }

    /// Without consent the list shows its suggestions and field and asks nothing until the first question: Send, a
    /// suggestion and the microphone each open the consent sheet. Closing it sends nothing and keeps the typed question;
    /// Allow records consent and sends the question once, and later questions don't ask.
    func testFirstQuestionAsksForConsentInASheet() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let hint = AgentHint(id: "hint:0", title: "Suggestion", subtitle: "Learn", prompt: "Tell me the news")
        var hasConsent = false
        var accepts = 0
        var questions: [String?] = []
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { hasConsent },
            acceptConsent: {
                accepts += 1
                hasConsent = true
            },
            makeNewChat: { question in
                questions.append(question)
                return UIViewController()
            },
            loadSuggestions: { [hint] }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil { self.descendants(suggestions).contains { $0 is AgentSuggestionButton } }
        XCTAssertTrue(presentation.presentedSheets.isEmpty, "No sheet before an action")
        XCTAssertTrue(client.queries.isEmpty, "Nor any call that needs consent")

        func closeSheet() async throws {
            let sheet = try await waitForConsentSheet(over: controller, in: self)
            XCTAssertTrue(sheet.accessibilityPerformEscape())
            try await waitUntil { presentation.presentedViewController(of: controller) == nil }
        }

        // Send, closed: the sheet takes the keyboard, and closed, the field gets it back with the question
        let bar = controller.bottomBar
        bar.composerView.setDraftText("Explain my portfolio", focus: true)
        XCTAssertTrue(bar.isEditing)
        bar.composerView.onSend?()
        let sendSheet = try await waitForConsentSheet(over: controller, in: self)
        XCTAssertFalse(bar.isEditing, "The keyboard leaves all of the sheet in sight")
        XCTAssertTrue(sendSheet.accessibilityPerformEscape())
        try await waitUntil { presentation.presentedViewController(of: controller) == nil }
        XCTAssertTrue(questions.isEmpty)
        XCTAssertEqual(bar.draftText, "Explain my portfolio", "The question stays in the field")
        XCTAssertTrue(bar.isEditing, "With the keyboard back")
        bar.resignEditing()

        // A suggestion, closed
        let button = try XCTUnwrap(descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }.first)
        button.sendActions(for: .touchUpInside)
        try await closeSheet()
        XCTAssertTrue(questions.isEmpty)

        // The microphone, closed: nothing records
        bar.composerView.clearDraft()
        let microphone = try XCTUnwrap(descendants(bar).compactMap { $0 as? AgentDictationButton }.first)
        XCTAssertTrue(microphone.accessibilityActivate())
        try await closeSheet()
        XCTAssertEqual(bar.composerView.dictationController?.state.phase, .idle)
        XCTAssertEqual(accepts, 0)

        // Send, allowed: sent once
        bar.composerView.setDraftText("Explain my portfolio", focus: false)
        bar.composerView.onSend?()
        let sheet = try await waitForConsentSheet(over: controller, in: self)
        sheet.consentView.onContinue?()
        sheet.consentView.onContinue?()
        try await waitUntil { questions.count == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(questions, ["Explain my portfolio"], "Sent once")
        XCTAssertEqual(accepts, 1)
        XCTAssertEqual(presentation.presentedSheets.count, 4, "Send, the suggestion, the microphone and Send again asked")

        // Later questions don't ask
        try await waitUntil { navigation.transitionCoordinator == nil }
        navigation.popToRootViewController(animated: false)
        bar.composerView.setDraftText("Another question", focus: false)
        bar.composerView.onSend?()
        XCTAssertEqual(questions, ["Explain my portfolio", "Another question"])
        XCTAssertEqual(presentation.presentedSheets.count, 4, "Later questions don't ask")
        XCTAssertEqual(accepts, 1)
    }

    /// Contact Support follows the suggestions. Before consent it asks for consent after the sheet, then waits for the
    /// server's chats, not the SDK's copy, and opens the chat support has that was active last; a list that fails to
    /// load drops it. With consent and no chat support has, it opens a new chat that asks for support.
    func testContactSupportHintWaitsForTheServersChatsAndOpensTheChatSupportHas() async throws {
        let presentation = AgentTestConsentSheetPresentation.install(in: self)
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.cachedItems = [try makeSupportListItem(id: "cached-support", minute: 58, state: .operator)]
        client.response = try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: JSONSerialization.data(withJSONObject: [
            "protocolVersion": 2,
            "threads": try [
                makeSupportListItem(id: "ordinary", minute: 59, state: nil),
                makeSupportListItem(id: "operator-support", minute: 40, state: .operator),
                makeSupportListItem(id: "waiting-support", minute: 50, state: .waiting),
                makeSupportListItem(id: "closed-support", minute: 57, state: .closed),
            ].map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        ]))
        client.listError = ThreadListUITestError.unavailable
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let hint = AgentHint(id: "hint:0", title: "Suggestion", subtitle: "Learn", prompt: "Tell me the news")
        var hasConsent = false
        var openedThreadIds: [String] = []
        var supportChatCount = 0
        var sheets: [UIAlertController] = []
        let controller = AgentThreadListVC(
            model: model,
            loadConsent: { hasConsent },
            acceptConsent: { hasConsent = true },
            makeThreadChat: { thread, _ in
                openedThreadIds.append(thread.id)
                return UIViewController()
            },
            makeNewChat: { _ in UIViewController() },
            makeSupportChat: {
                supportChatCount += 1
                return UIViewController()
            },
            hasWalletAccount: { true },
            presentConfirmation: { alert, _ in sheets.append(alert) },
            makeNewsFeed: { _ in UIViewController() },
            loadSuggestions: { [hint] }
        )
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = makeKeyWindow(showing: navigation)
        defer { window.isHidden = true }
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil { self.descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }.count == 2 }
        let buttons = descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }
        XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Suggestion", lang("$agent_support_contact")])
        let support = try XCTUnwrap(buttons.last)
        XCTAssertEqual(support.accessibilityIdentifier, "agent_support_hint")
        XCTAssertTrue(support.isEnabled, "Without consent, the hint waits for no chats")

        // Allowed in the sheet, the request waits for the list, which fails: nothing opens, then or later
        support.sendActions(for: .touchUpInside)
        let noWallet = try XCTUnwrap(sheets.last)
        XCTAssertEqual(noWallet.title, lang("$agent_support_confirm_title"))
        XCTAssertEqual(noWallet.message, lang("$agent_support_confirm_text_no_wallet"))
        performAlertAction(titled: lang("$agent_support_confirm_action"), in: noWallet)
        let sheet = try await waitForConsentSheet(over: controller, in: self)
        sheet.consentView.onContinue?()
        try await waitUntil { model.hasLoaded && !model.isLoading && client.queries.count == 1 }
        try await waitUntil { presentation.presentedViewController(of: controller) == nil }
        XCTAssertFalse(support.isEnabled, "With consent, the hint waits for the server's chats")
        client.listError = nil
        await model.refresh()
        try await waitUntil { model.serverListState == .loaded && support.isEnabled }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(openedThreadIds.isEmpty)
        XCTAssertEqual(supportChatCount, 0)

        // The SDK's copy stands in while the server's list comes, and the request waits for the server's list
        let freshModel = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        hasConsent = false
        let freshController = AgentThreadListVC(
            model: freshModel,
            loadConsent: { hasConsent },
            acceptConsent: { hasConsent = true },
            makeThreadChat: { thread, _ in
                openedThreadIds.append(thread.id)
                return UIViewController()
            },
            makeNewChat: { _ in UIViewController() },
            makeSupportChat: {
                supportChatCount += 1
                return UIViewController()
            },
            hasWalletAccount: { true },
            presentConfirmation: { alert, _ in sheets.append(alert) },
            makeNewsFeed: { _ in UIViewController() },
            loadSuggestions: { [] }
        )
        window.rootViewController = ThreadListTestNavigationController(rootViewController: freshController)
        let freshSuggestions = try XCTUnwrap(descendants(freshController.view).compactMap { $0 as? AgentHintsSectionView }.first)
        try await waitUntil { self.descendants(freshSuggestions).contains { $0.accessibilityIdentifier == "agent_support_hint" } }
        let freshSupport = try XCTUnwrap(descendants(freshSuggestions).compactMap { $0 as? AgentSuggestionButton }.last)
        client.heldResponseCount = 1
        freshSupport.sendActions(for: .touchUpInside)
        performAlertAction(titled: lang("$agent_support_confirm_action"), in: try XCTUnwrap(sheets.last))
        let freshSheet = try await waitForConsentSheet(over: freshController, in: self)
        freshSheet.consentView.onContinue?()
        try await waitUntil { freshModel.isShowingCachedThreads && client.pendingResponse != nil }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(openedThreadIds.isEmpty, "The SDK's copy doesn't choose the chat")
        client.pendingResponse?.resume(returning: client.response)
        client.pendingResponse = nil
        try await waitUntil { !openedThreadIds.isEmpty }
        XCTAssertEqual(openedThreadIds, ["waiting-support"])
        XCTAssertEqual(supportChatCount, 0)

        // With consent and no chat support has, a new chat asks for support, and the sheet tells of the addresses
        try await waitUntil { freshController.navigationController?.transitionCoordinator == nil }
        freshController.navigationController?.popToRootViewController(animated: false)
        client.response = try makeThreadListResponse(count: 1)
        await freshModel.refresh()
        try await waitUntil { freshModel.supportThread == nil && freshSupport.isEnabled }
        freshSupport.sendActions(for: .touchUpInside)
        let withAddresses = try XCTUnwrap(sheets.last)
        XCTAssertEqual(withAddresses.message, lang("$agent_support_confirm_text"))
        performAlertAction(titled: lang("$agent_support_confirm_action"), in: withAddresses)
        try await waitUntil { supportChatCount == 1 }
        XCTAssertEqual(openedThreadIds, ["waiting-support"])
    }

    private func makeSupportListItem(
        id: String,
        minute: Int,
        state: ApiAgentV2ThreadSupport.State?
    ) throws -> ApiAgentV2ThreadListItem {
        let date = String(format: "2026-10-19T10:%02d:00Z", minute)
        var thread: [String: Any] = [
            "id": id, "revision": 1, "createdAt": "2026-10-19T09:00:00Z", "updatedAt": date, "lastActivityAt": date,
            "messageCount": 2, "title": id,
        ]
        if let state {
            thread["support"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ApiAgentV2ThreadSupport(state: state)))
        }
        return try JSONDecoder().decode(
            ApiAgentV2ThreadListItem.self,
            from: JSONSerialization.data(withJSONObject: ["thread": thread, "preview": "Message"])
        )
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

        // The counter shows up to 10 unread news, 5 pt clear of each end of the capsule
        for (count, text) in [(1, "1"), (9, "9"), (10, "10")] {
            cell.configure(latestNews: item, unreadCount: count, now: now)
            cell.layoutIfNeeded()
            XCTAssertEqual(cell.unreadMark, .count(text))
            XCTAssertEqual(countLabel.text, text)
            let textWidth = ceil((text as NSString).size(withAttributes: [.font: AgentThreadRowMetrics.unreadCounterFont]).width)
            XCTAssertEqual(badge.frame.width, max(20, textWidth + 10), accuracy: 0.5, text)
            XCTAssertEqual(badge.frame.height, 20)
            XCTAssertEqual(badge.frame.maxX, badgeMaxX, accuracy: 0.5)
            XCTAssertEqual(cell.previewLabel.frame.maxX, badge.frame.minX - AgentThreadRowMetrics.unreadDotSpacing, accuracy: 0.5)
        }
        // More show the unread dot of a chat, in the dot's place, and VoiceOver still reads the count
        for count in [11, 30, 1_234] {
            cell.configure(latestNews: item, unreadCount: count, now: now)
            cell.layoutIfNeeded()
            XCTAssertEqual(cell.unreadMark, .dot, "\(count)")
            XCTAssertTrue(countLabel.isHidden)
            XCTAssertEqual(badge.frame.size, CGSize(width: AgentThreadRowMetrics.unreadDotSize, height: AgentThreadRowMetrics.unreadDotSize))
            XCTAssertEqual(badge.frame.maxX, badgeMaxX, accuracy: 0.5)
            XCTAssertEqual(badge.frame.midY, dotCenterY, accuracy: 0.5)
            XCTAssertTrue(cell.accessibilityLabel?.contains(L10n.agentNewsUnreadCount(count: count)) == true)
        }

        cell.configure(latestNews: nil, unreadCount: 0)
        XCTAssertTrue(badge.isHidden)
        XCTAssertFalse(cell.accessibilityLabel?.contains(item.headline) == true)
        XCTAssertFalse(cell.accessibilityLabel?.contains(L10n.agentNewsUnreadCount(count: 2)) == true)
    }

    /// In the Digests view the News row shows the latest digest's first headline at the digest's time, and VoiceOver
    /// reads the unread digests
    func testNewsCellShowsTheLatestDigest() throws {
        _ = WalletResourcesBundle.bundle.load()
        let cell = AgentNewsCell(frame: CGRect(x: 0, y: 0, width: 402, height: 92))
        let digest = try JSONDecoder().decode(ApiAgentV2NewsFeedDigest.self, from: Data("""
        {"id":"en:2026-10-22T06:00:00Z","deliveredAt":"2026-10-22T06:00:00Z","total":12,"top":[
        {"eventId":1,"headline":"First headline","imageUrl":"https://example.com/first.png"},
        {"eventId":2,"headline":"Second headline","imageUrl":"https://example.com/second.png"}]}
        """.utf8))
        let now = AgentV2DateParser.date("2026-10-23T12:00:00Z")
        cell.configure(latestDigest: digest, unreadCount: 2, now: now)
        cell.layoutIfNeeded()
        let time = AgentThreadDateFormatting.formatRowTimestamp(
            for: digest.deliveredAt, shouldShowDateWhenNotToday: true, relativeTo: now
        )
        XCTAssertEqual(cell.previewLabel.text, "First headline")
        XCTAssertEqual(cell.timeLabel.text, time)
        XCTAssertEqual(cell.unreadMark, .count("2"))
        XCTAssertTrue(cell.accessibilityLabel?.contains(L10n.agentNewsUnreadDigestsCount(count: 2)) == true)
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
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(controller.bottomBar.isHidden, "Without consent the field stays, to ask at the first question")

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

    /// A list that goes from the screen while the microphone's consent read is under way doesn't record when the read
    /// finds the consent, whether it is back by then or not, and it still shows its chats; shown, it records at once
    func testRecordingDoesNotStartInAListLeftWhileItsConsentIsRead() async throws {
        _ = WalletResourcesBundle.bundle.load()
        for isBack in [false, true] {
            let model = AgentThreadListModel(client: try ThreadListUIClient(), newsClient: ThreadListNewsClient())
            var consentReads = 0
            var consentResponse: CheckedContinuation<Bool, Never>?
            let controller = AgentThreadListVC(
                model: model,
                loadConsent: {
                    consentReads += 1
                    guard consentReads > 1 else { return false }
                    return await withCheckedContinuation { consentResponse = $0 }
                },
                acceptConsent: {},
                loadSuggestions: { [] }
            )
            let navigation = ThreadListTestNavigationController(rootViewController: controller)
            let window = makeKeyWindow(showing: navigation)
            defer { window.isHidden = true }
            var recordingStarts = 0
            let composer = controller.bottomBar.composerView
            composer.dictationController = AgentDictationController(
                scheduler: AgentDictationTestScheduler(),
                requestPermission: { true },
                makeRecorder: {
                    recordingStarts += 1
                    return AgentDictationTestRecorder()
                },
                transcribe: { _ in .init(outcome: .noSpeech) },
                haptic: {},
                gestureFeedback: {},
                observeLifecycle: false
            )
            try await waitUntil { consentReads == 1 }
            for _ in 0..<20 { await Task.yield() }

            XCTAssertEqual(composer.shouldStartDictation?(), false)
            try await waitUntil { consentResponse != nil }
            navigation.pushViewController(UIViewController(), animated: false)
            try await waitUntil {
                window.layoutIfNeeded()
                return controller.view.window == nil
            }
            if isBack {
                navigation.popViewController(animated: false)
                try await waitUntil {
                    window.layoutIfNeeded()
                    return controller.view.window != nil
                }
            }
            consentResponse?.resume(returning: true)
            consentResponse = nil
            try await waitUntil { !model.items.isEmpty }
            for _ in 0..<20 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertEqual(recordingStarts, 0, "isBack: \(isBack)")
            XCTAssertEqual(composer.dictationController?.state.phase, .idle, "isBack: \(isBack)")
            XCTAssertEqual(composer.shouldStartDictation?(), true, "isBack: \(isBack): with consent, it records at once")
        }
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
        // Contact Support follows the suggestions
        try await waitUntil {
            !model.isLoading && self.descendants(suggestions).compactMap { $0 as? AgentSuggestionButton }.count == hints.count + 1
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
        XCTAssertEqual(buttons.map(\.accessibilityLabel), hints.map(\.title) + [lang("$agent_support_contact")])

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

    /// Chats that failed to load leave the News row and, in place of the suggestions that would say there are none,
    /// the failure with Retry in the middle of the list, which loads them
    func testFailedLoadWithoutChatsShowsTheFailureUnderNewsAndRetryLoadsTheChats() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.listError = ThreadListUITestError.unavailable
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let hint = AgentHint(id: "starter", title: "Explain TON", subtitle: "", prompt: "Explain TON")
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [hint] })
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let failure = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentLoadErrorView }.first)
        try await waitUntil {
            model.hasLoadFailed && !model.isLoading && collection.numberOfSections == 1
        }
        window.layoutIfNeeded()
        collection.layoutIfNeeded()

        let news = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? AgentNewsCell)
        XCTAssertFalse(failure.isHidden)
        XCTAssertEqual(failure.alpha, 1)
        XCTAssertEqual(failure.label.text, lang("$agent_chats_unavailable"))
        XCTAssertFalse(failure.retryButton.isHidden)
        XCTAssertGreaterThan(failure.frame.minY, news.convert(news.bounds, to: controller.view).maxY)
        XCTAssertEqual(failure.frame.midX, collection.frame.midX, accuracy: 1)
        let suggestions = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentHintsSectionView }.first)
        XCTAssertTrue(suggestions.isHidden)
        let skeleton = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? AgentThreadListSkeletonView }.first)
        XCTAssertFalse(skeleton.isShowing)

        client.listError = nil
        let retry = failure.retryButton
        let action = try XCTUnwrap(retry.actions(forTarget: failure, forControlEvent: .touchUpInside)?.first)
        failure.perform(NSSelectorFromString(action), with: retry)
        try await waitUntil {
            !model.hasLoadFailed && !model.isLoading && collection.numberOfSections == 2
        }
        XCTAssertTrue(failure.isHidden)
        XCTAssertEqual(model.items.map { $0.thread.id }, ["portfolio-thread"])
    }

    /// A page that failed to load leaves the chats in place and ends the list with a chat's failure line, which waits
    /// for its Retry rather than asking again as the rows come on screen
    func testFailedPageEndsTheListWithAFailureLineWhoseRetryLoadsIt() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try makeThreadListResponse(count: 1, nextCursor: "older")
        client.pageError = ThreadListUITestError.unavailable
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let controller = AgentThreadListVC(model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] })
        let navigation = ThreadListTestNavigationController(rootViewController: controller)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let collection = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? UICollectionView }.first)
        let lastRow = IndexPath(item: 0, section: 1)
        let lineIndexPath = IndexPath(item: 0, section: 2)
        try await waitUntil {
            collection.layoutIfNeeded()
            return model.hasPageLoadFailed && !model.isLoading && collection.numberOfSections == 3
                && collection.cellForItem(at: lineIndexPath) != nil
        }

        let line = try XCTUnwrap(collection.cellForItem(at: lineIndexPath) as? AgentSystemMessageCell)
        XCTAssertEqual(line.accessibilityIdentifier, "AgentThreadListPageFailure")
        let caption = try XCTUnwrap(descendants(line).compactMap { $0 as? UITextView }.first { !$0.isHidden })
        XCTAssertTrue(caption.text.hasPrefix(lang("$agent_chats_unavailable")), caption.text)
        XCTAssertTrue(caption.text.hasSuffix(lang("Retry")), caption.text)
        XCTAssertEqual(model.items.map { $0.thread.id }, ["thread-0"])
        XCTAssertEqual(client.cursors, [nil, "older"])
        XCTAssertTrue(descendants(controller.view).compactMap { $0 as? AgentLoadErrorView }.allSatisfy(\.isHidden))

        let row = try XCTUnwrap(collection.cellForItem(at: lastRow))
        controller.collectionView(collection, willDisplay: row, forItemAt: lastRow)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(client.cursors, [nil, "older"])

        client.pageError = nil
        client.olderResponse = try makeThreadListResponse(count: 1, firstIndex: 1)
        let retryURL = try XCTUnwrap(URL(string: "agent-control:retry-load"))
        _ = line.textView(caption, shouldInteractWith: retryURL, in: NSRange(location: 0, length: 1))
        try await waitUntil {
            !model.hasPageLoadFailed && !model.isLoading && collection.numberOfSections == 2
        }
        XCTAssertEqual(model.items.map { $0.thread.id }, ["thread-0", "thread-1"])
        XCTAssertEqual(client.cursors, [nil, "older", "older"])
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

    /// A chat started while the list is away, under the chat, is in the list from the first frame it is back: the SDK's
    /// report of its first message puts its row in the list at once, and a load that doesn't have it yet keeps it
    func testChatStartedWhileTheListIsAwayIsInItFromItsFirstFrameBack() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, navigation, window, collection) = try await showLoadedList(of: model)
        defer { window.isHidden = true }
        navigation.pushViewController(UIViewController(), animated: false)
        try await waitUntil {
            window.layoutIfNeeded()
            return controller.view.window == nil
        }
        let queryCount = client.queries.count

        let started = try makeThread(id: "new-thread", title: "New question", lastActivityAt: "2026-10-19T11:00:00Z")
        controller.walletCore(event: .agentV2(.threadChanged(threadId: started.id, thread: started)))
        XCTAssertEqual(model.items.first { $0.thread.id == started.id }?.thread, started, "In the list's model at once")
        XCTAssertEqual(collection.numberOfSections, 3, "News, Pinned and the new chat's day")
        try await waitUntil { client.queries.count > queryCount && !model.isLoading }
        XCTAssertTrue(model.items.contains { $0.thread.id == started.id }, "A load the server answers without it keeps it")

        navigation.popViewController(animated: false)
        window.layoutIfNeeded()
        collection.layoutIfNeeded()
        let titles = collection.visibleCells.compactMap { ($0 as? AgentThreadCell)?.titleLabel.text }
        XCTAssertTrue(titles.contains("New question"), "Its row shows from the first frame back")
    }

    /// On screen at the top of the list, a chat coming in moves the rows below it on the list's spring as it fades in,
    /// or the list cross-fades with Reduce Motion; a change to what a row shows reconfigures it in place
    func testChatComingInOnScreenMovesTheRowsAndAChangeReconfiguresTheRowInPlace() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try makeThreadListResponse(count: 3)
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, _, window, collection) = try await showLoadedList(of: model, rowCount: 3)
        defer { window.isHidden = true }
        collection.layoutIfNeeded()
        func findCell(titled title: String) -> AgentThreadCell? {
            collection.visibleCells.compactMap { $0 as? AgentThreadCell }.first { $0.titleLabel.text == title }
        }
        let firstRow = try XCTUnwrap(findCell(titled: "Chat 0"))
        let firstRowY = firstRow.frame.minY

        let started = try makeThread(id: "new-thread", title: "New question", lastActivityAt: "2026-10-19T10:59:00Z")
        controller.walletCore(event: .agentV2(.threadChanged(threadId: started.id, thread: started)))
        collection.layoutIfNeeded()
        let newRow = try XCTUnwrap(findCell(titled: "New question"), "The new chat comes in at the top")
        XCTAssertLessThan(newRow.frame.minY, firstRow.frame.minY)
        XCTAssertGreaterThan(firstRow.frame.minY, firstRowY, "The rows below make way")
        if UIAccessibility.isReduceMotionEnabled {
            XCTAssertFalse(collection.layer.animationKeys()?.isEmpty ?? true, "The list cross-fades")
        } else {
            XCTAssertTrue(firstRow.layer.animationKeys()?.contains { $0.hasPrefix("position") } == true,
                          "A row below moves on the spring")
            XCTAssertFalse(newRow.layer.animationKeys()?.isEmpty ?? true, "The new row comes in animated")
        }
        try await Task.sleep(for: .milliseconds(600))

        // A new title for a row on screen changes the row where it is
        let renamedRow = try XCTUnwrap(findCell(titled: "Chat 1"))
        let thread = try XCTUnwrap(model.items.first { $0.thread.id == "thread-1" }?.thread)
        let renamed = try makeThread(id: thread.id, title: "Renamed", lastActivityAt: thread.lastActivityAt, revision: thread.revision + 1)
        controller.walletCore(event: .agentV2(.threadChanged(threadId: renamed.id, thread: renamed)))
        collection.layoutIfNeeded()
        XCTAssertTrue(findCell(titled: "Renamed") === renamedRow, "The same row, reconfigured")
        XCTAssertNil(renamedRow.layer.animationKeys()?.first { $0.hasPrefix("position") || $0.hasPrefix("opacity") },
                     "Not inserted again")
    }

    /// As the SDK's list does, the list has a chat while the user has written in it and it has messages: a chat cleared
    /// of its messages leaves the list at once, and loads the server answers from before the clearing don't bring it
    /// back, until it is written in again. A news discussion left with its post alone leaves it too, and a change that
    /// keeps a chat in the list updates its row in place.
    func testClearedChatOrUntouchedDiscussionLeavesTheListAndALoadDoesNotBringItBack() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try makeThreadListResponse(count: 3)
        let model = AgentThreadListModel(client: client, newsClient: ThreadListNewsClient())
        let (controller, _, window, collection) = try await showLoadedList(of: model, rowCount: 3)
        defer { window.isHidden = true }
        func isListed(_ id: String) -> Bool { model.items.contains { $0.thread.id == id } }
        let listed = try XCTUnwrap(model.items.first { $0.thread.id == "thread-1" }?.thread)

        let cleared = try makeThread(
            id: listed.id, title: "Chat 1", lastActivityAt: listed.lastActivityAt, revision: listed.revision + 1, messageCount: 0
        )
        let queryCount = client.queries.count
        controller.walletCore(event: .agentV2(.threadChanged(threadId: cleared.id, thread: cleared)))
        XCTAssertFalse(isListed(listed.id), "A cleared chat leaves the list")
        collection.layoutIfNeeded()
        XCTAssertEqual(collection.numberOfItems(inSection: 1), 2)
        // The server still has it as it was before the clearing
        try await waitUntil { client.queries.count > queryCount && !model.isLoading }
        XCTAssertFalse(isListed(listed.id), "The load the change started doesn't bring it back")
        await model.refresh()
        XCTAssertFalse(isListed(listed.id), "Nor does a later one")
        let stale = try makeThread(id: listed.id, title: "Chat 1", lastActivityAt: listed.lastActivityAt, revision: listed.revision)
        controller.walletCore(event: .agentV2(.threadChanged(threadId: stale.id, thread: stale)))
        XCTAssertFalse(isListed(listed.id), "Nor a report from before the clearing")

        let rewritten = try makeThread(
            id: listed.id, title: "Chat 1", lastActivityAt: "2026-10-19T10:58:00Z", revision: listed.revision + 2, messageCount: 1
        )
        controller.walletCore(event: .agentV2(.threadChanged(threadId: rewritten.id, thread: rewritten)))
        XCTAssertTrue(isListed(listed.id), "Written in again, it comes back")
        await model.refresh()
        XCTAssertTrue(isListed(listed.id), "And stays through a load the server answers from before")

        // A news discussion with the user's message gone, its post alone left
        let discussion = try makeThread(
            id: "discussion", title: "News of the day", lastActivityAt: "2026-10-19T10:57:00Z", messageCount: 3,
            isNewsDiscussion: true
        )
        controller.walletCore(event: .agentV2(.threadChanged(threadId: discussion.id, thread: discussion)))
        XCTAssertTrue(isListed(discussion.id), "Written in, a discussion is in the list")
        let untouched = try makeThread(
            id: discussion.id, title: "News of the day", lastActivityAt: discussion.lastActivityAt, revision: 2, messageCount: 1,
            isNewsDiscussion: true
        )
        controller.walletCore(event: .agentV2(.threadChanged(threadId: untouched.id, thread: untouched)))
        XCTAssertFalse(isListed(discussion.id), "With its post alone it leaves the list")
        await model.refresh()
        XCTAssertFalse(isListed(discussion.id))

        // A chat that keeps its messages changes in place
        try await Task.sleep(for: .milliseconds(600))
        collection.layoutIfNeeded()
        let row = try XCTUnwrap(collection.visibleCells.compactMap { $0 as? AgentThreadCell }.first { $0.titleLabel.text == "Chat 0" })
        let chat = try XCTUnwrap(model.items.first { $0.thread.id == "thread-0" }?.thread)
        let renamed = try makeThread(
            id: chat.id, title: "Renamed", lastActivityAt: chat.lastActivityAt, revision: chat.revision + 1, messageCount: 2
        )
        controller.walletCore(event: .agentV2(.threadChanged(threadId: renamed.id, thread: renamed)))
        collection.layoutIfNeeded()
        XCTAssertEqual(model.items.first { $0.thread.id == chat.id }?.thread, renamed)
        XCTAssertTrue(collection.visibleCells.compactMap { $0 as? AgentThreadCell }.first { $0.titleLabel.text == "Renamed" } === row)
    }

    private func makeThread(
        id: String,
        title: String,
        lastActivityAt: String,
        revision: Int = 1,
        messageCount: Int = 1,
        isNewsDiscussion: Bool = false
    ) throws -> ApiAgentV2ThreadSummary {
        var thread: [String: Any] = [
            "id": id,
            "revision": revision,
            "createdAt": "2026-10-19T09:00:00Z",
            "updatedAt": lastActivityAt,
            "lastActivityAt": lastActivityAt,
            "messageCount": messageCount,
            "title": title,
            "isPinned": false,
        ]
        if isNewsDiscussion {
            thread["news"] = ["eventId": 7, "headline": "News of the day", "publishedAt": "2026-10-19T09:00:00Z"]
        }
        return try JSONDecoder().decode(ApiAgentV2ThreadSummary.self, from: JSONSerialization.data(withJSONObject: thread))
    }

    func testDayChangeUpdatesRetainedHeadersWithoutFetchingOrMovingRows() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        client.response = try makeThreadListResponse(count: 30)
        let newsClient = ThreadListNewsClient()
        let model = AgentThreadListModel(client: client, newsClient: newsClient)
        let calendar = LocalizationSupport.shared.calendar
        let day = calendar.startOfDay(for: AgentV2DateParser.date(client.thread.lastActivityAt))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        var now = nextDay.addingTimeInterval(-1)
        let (_, _, window, collection) = try await showLoadedList(of: model, rowCount: 30, getCurrentDate: { now })
        defer { window.isHidden = true }
        collection.contentOffset.y = -collection.adjustedContentInset.top + 600
        collection.layoutIfNeeded()
        let indexPath = IndexPath(item: 0, section: 1)
        let header = try XCTUnwrap(collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath
        ))
        let label = try XCTUnwrap(descendants(header).compactMap { $0 as? UILabel }.first)
        XCTAssertEqual(label.text, lang("Today"))
        let offset = collection.contentOffset
        let cells = collection.visibleCells
        let threadRequestCount = client.queries.count
        let newsRequestCount = newsClient.requests.count

        now = nextDay
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: UIApplication.shared)
        collection.layoutIfNeeded()
        XCTAssertEqual(label.text, lang("Yesterday"))
        XCTAssertTrue(header === collection.supplementaryView(
            forElementKind: UICollectionView.elementKindSectionHeader, at: indexPath
        ))
        XCTAssertEqual(collection.contentOffset, offset)
        XCTAssertEqual(Set(collection.visibleCells.map(ObjectIdentifier.init)), Set(cells.map(ObjectIdentifier.init)))

        // Let any refresh task scheduled by the notification reach its client before checking the request counts
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(client.queries.count, threadRequestCount)
        XCTAssertEqual(newsClient.requests.count, newsRequestCount)

        // Ordinary model updates also retain the same day's header across midnight
        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: nextDay))
        await model.refresh()
        collection.layoutIfNeeded()
        XCTAssertEqual(label.text, AgentThreadDateFormatting.headerText(for: day, relativeTo: now))
        XCTAssertEqual(collection.contentOffset, offset)
    }

    func testDayChangeUpdatesPinnedAndNewsTimestampsWithoutFetching() async throws {
        _ = WalletResourcesBundle.bundle.load()
        let client = try ThreadListUIClient()
        let newsClient = ThreadListNewsClient(items: [ApiAgentV2NewsFeedItem(
            eventId: 1, deliveredAt: client.thread.lastActivityAt, headline: "News", body: "Market news"
        )])
        let model = AgentThreadListModel(client: client, newsClient: newsClient)
        let calendar = LocalizationSupport.shared.calendar
        let timestamp = AgentV2DateParser.date(client.thread.lastActivityAt)
        var now = timestamp
        let (_, _, window, collection) = try await showLoadedList(of: model, getCurrentDate: { now })
        defer { window.isHidden = true }
        try await waitUntil { model.latestNews != nil }
        collection.layoutIfNeeded()
        let newsCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 0)) as? AgentNewsCell)
        let threadCell = try XCTUnwrap(collection.cellForItem(at: IndexPath(item: 0, section: 1)) as? AgentThreadCell)
        let time = AgentThreadDateFormatting.formatRowTimestamp(for: timestamp, shouldShowDateWhenNotToday: true, relativeTo: now)
        XCTAssertEqual(threadCell.timeLabel.text, time)
        XCTAssertEqual(newsCell.timeLabel.text, time)
        let threadRequestCount = client.queries.count
        let newsRequestCount = newsClient.requests.count

        now = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: timestamp))
        NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: UIApplication.shared)
        collection.layoutIfNeeded()
        // Yesterday's rows name its weekday
        let weekday = AgentThreadDateFormatting.formatRowTimestamp(for: timestamp, shouldShowDateWhenNotToday: true, relativeTo: now)
        XCTAssertNotEqual(weekday, time)
        XCTAssertEqual(threadCell.timeLabel.text, weekday)
        XCTAssertEqual(newsCell.timeLabel.text, weekday)
        XCTAssertTrue(threadCell.accessibilityLabel?.contains(weekday) == true)
        XCTAssertTrue(newsCell.accessibilityLabel?.contains(weekday) == true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(client.queries.count, threadRequestCount)
        XCTAssertEqual(newsClient.requests.count, newsRequestCount)
    }

    /// `count` chats, the first the latest, or `latest` latest of all
    private func makeThreadListResponse(
        count: Int,
        latest: Int? = nil,
        firstIndex: Int = 0,
        nextCursor: String? = nil
    ) throws -> ApiAgentV2ThreadListResponse {
        let threads = (firstIndex..<firstIndex + count).map { index -> [String: Any] in
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
        var json: [String: Any] = ["protocolVersion": 2, "threads": threads]
        json["nextCursor"] = nextCursor
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ApiAgentV2ThreadListResponse.self, from: data)
    }

    private func makeThreadListItem(
        title: String?,
        preview: String?,
        isPinned: Bool = false,
        support: ApiAgentV2ThreadSupport? = nil
    ) throws -> ApiAgentV2ThreadListItem {
        var thread: [String: Any] = [
            "id": "portfolio-thread",
            "revision": 1,
            "createdAt": "2026-10-19T10:00:00Z",
            "updatedAt": "2026-10-19T10:00:00Z",
            "lastActivityAt": "2026-10-19T10:00:00Z",
            "messageCount": 2,
            "isPinned": isPinned,
            "title": title as Any? ?? NSNull()
        ]
        if let support {
            thread["support"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(support))
        }
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
        rowCount: Int = 1,
        getCurrentDate: @escaping () -> Date = { .now }
    ) async throws -> (AgentThreadListVC, ThreadListTestNavigationController, UIWindow, UICollectionView) {
        let controller = AgentThreadListVC(
            model: model, loadConsent: { true }, acceptConsent: {}, loadSuggestions: { [] }, getCurrentDate: getCurrentDate
        )
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

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: @escaping () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Thread list did not settle within 2 seconds", file: file, line: line)
        throw ThreadListUITestError.timedOut
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants($0) }
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

@MainActor
private final class ThreadListTestNavigationController: UINavigationController {
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
    }
}

private enum ThreadListUITestError: Error {
    case timedOut
    case unavailable
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
    /// Fails the first page
    var listError: Error?
    /// Fails further pages
    var pageError: Error?
    /// The page after the first
    var olderResponse: ApiAgentV2ThreadListResponse?
    var cursors: [String?] = []

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

    /// The SDK's copy of the first page
    var cachedItems: [ApiAgentV2ThreadListItem]?
    func cachedThreads() async -> [ApiAgentV2ThreadListItem]? { cachedItems }

    func listThreads(cursor: String?, limit: Int?, query: String?) async throws -> ApiAgentV2ThreadListResponse {
        queries.append(query)
        cursors.append(cursor)
        if cursor == nil, let listError { throw listError }
        if cursor != nil {
            if let pageError { throw pageError }
            if let olderResponse { return olderResponse }
        }
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
