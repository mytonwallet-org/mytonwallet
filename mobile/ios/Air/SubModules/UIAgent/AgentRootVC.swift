import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
final class AgentRootVC: WViewController, WalletCoreData.EventsObserver {
    private let client: AgentV2Client
    private let thread: ApiAgentV2ThreadSummary?
    private let preloader: AgentPreloader?
    private let showError: (String) -> Void
    private let sessionGeneration: Int?
    private let skeletonView = AgentMessagesSkeletonView()
    private let composerView = AgentComposerView()
    /// The placeholder composer rests where the chat's composer will
    private lazy var composerBottomConstraint = composerView.bottomAnchor.constraint(
        equalTo: view.bottomAnchor,
        constant: composerBottomConstant
    )
    private var composerBottomConstant: CGFloat {
        AgentComposerMetrics.threadVerticalInset - AgentComposerMetrics.getFieldBottomInset(safeAreaBottom: view.safeAreaInsets.bottom)
    }
    private let chatTitleView = AgentChatTitleView()
    /// Consent was found missing before the chat was on screen, where the consent sheet asks for it
    private var isConsentPending = false
    /// A chat that couldn't load shows the failure in its middle with Retry, as the News feed does
    private let loadErrorView = AgentLoadErrorView()
    private let contentLayoutGuide = UILayoutGuide()
    private let backSwipe = AgentChatBackSwipe()
    private var transitionTask: Task<Void, Never>?
    private var preparingModel: AgentV2Model?
    private var isTransferringModel = false
    private var isModelPrepared = false
    private var selectedThreadId: String?
    private var isThreadDeleted = false
    /// The thread's summary is the SDK's copy, so the chat shows only its loaded history
    private let isSummaryCached: Bool
    /// The new chat asks for a support operator, from the starter hints, once it has loaded
    private let shouldRequestSupport: Bool
    /// How many times the chat has gone from the screen while it loads: one the user left drops its support request
    private var disappearanceCount = 0

    convenience init(
        client: AgentV2Client = LiveAgentV2Client(),
        preloader: AgentPreloader? = nil,
        shouldRequestSupport: Bool = false,
        showError: @escaping (String) -> Void = {
            AppActions.showError(error: DisplayError(text: $0))
        }
    ) {
        self.init(
            client: client, thread: nil, preloader: preloader, showError: showError, isSummaryCached: false,
            shouldRequestSupport: shouldRequestSupport
        )
    }

    convenience init(thread: ApiAgentV2ThreadSummary, preloader: AgentPreloader, isSummaryCached: Bool = false) {
        self.init(
            client: preloader.client, thread: thread, preloader: preloader,
            showError: { AppActions.showError(error: DisplayError(text: $0)) }, isSummaryCached: isSummaryCached
        )
    }

    private init(
        client: AgentV2Client,
        thread: ApiAgentV2ThreadSummary?,
        preloader: AgentPreloader?,
        showError: @escaping (String) -> Void,
        isSummaryCached: Bool,
        shouldRequestSupport: Bool = false
    ) {
        self.client = client
        self.thread = thread
        self.isSummaryCached = isSummaryCached
        self.shouldRequestSupport = shouldRequestSupport
        self.preloader = preloader
        sessionGeneration = preloader?.sessionGeneration
        self.showError = showError
        selectedThreadId = thread?.id
        super.init(nibName: nil, bundle: nil)
        WalletCoreData.addImmediately(eventObserver: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        transitionTask?.cancel()
        if let preparingModel {
            Task { @MainActor in preparingModel.releasePresentation() }
        }
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.isThreadDeleted {
                    AgentEntryPoint.removeDeletedChat(self)
                } else {
                    self.presentPreparedModelIfPossible()
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.main.async { [weak self] in
            self?.presentPreparedModelIfPossible()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        composerBottomConstraint.constant = composerBottomConstant
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        AgentChatNavigation.installThreadsButton(in: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        backSwipe.install(for: self)
        if isConsentPending {
            showConsent()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        disappearanceCount += 1
        backSwipe.restore()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = AgentV2Model.chatTitle(thread: thread)
        view.backgroundColor = .air.background
        navigationItem.rightBarButtonItems = makeNavigationPlaceholders()
        chatTitleView.setTitle(
            AgentV2Model.chatTitleText(thread: thread),
            icon: AgentV2Model.chatIcon(thread: thread),
            animated: false
        )
        // A chat that support has keeps the header and field it shows once loaded
        let supportState = AgentSupportPresentation.getState(for: thread?.support)
        chatTitleView.setSubtitle(AgentSupportPresentation.getSubtitle(for: supportState))
        composerView.placeholder = AgentSupportPresentation.getComposerPlaceholder(for: supportState)

        // A chat that is not cached yet shows Telegram's bubble skeleton under the same chrome it will have
        skeletonView.translatesAutoresizingMaskIntoConstraints = false
        skeletonView.isHidden = thread == nil
        composerView.translatesAutoresizingMaskIntoConstraints = false
        composerView.isUserInteractionEnabled = false
        composerView.accessibilityElementsHidden = true
        view.addSubview(skeletonView)
        view.addSubview(composerView)
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        let composerBottom = composerBottomConstraint
        let composerWidth = composerView.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        composerWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            skeletonView.topAnchor.constraint(equalTo: view.topAnchor),
            skeletonView.leadingAnchor.constraint(equalTo: composerView.leadingAnchor),
            skeletonView.trailingAnchor.constraint(equalTo: composerView.trailingAnchor),
            skeletonView.bottomAnchor.constraint(equalTo: composerView.topAnchor, constant: -4),
            composerView.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            composerView.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            composerView.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor),
            composerWidth,
            composerBottom,
        ])
        AgentChatNavigation.installHeader(in: self, titleView: chatTitleView)
        view.addLayoutGuide(contentLayoutGuide)
        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: composerView.topAnchor),
            contentLayoutGuide.leadingAnchor.constraint(equalTo: composerView.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(equalTo: composerView.trailingAnchor),
        ])
        loadErrorView.onRetry = { [weak self] in
            self?.loadErrorView.show(nil)
            self?.loadConsent()
        }
        loadErrorView.install(in: view, column: contentLayoutGuide, centerY: contentLayoutGuide.centerYAnchor)
        loadConsent()
    }

    private func loadConsent() {
        guard !isThreadDeleted else { return }
        transitionTask?.cancel()
        transitionTask = Task { [weak self] in
            guard let self else { return }
            let hasConsent: Bool
            do {
                hasConsent = try await self.client.consent()
            } catch {
                // A failed lookup is not a denial: the chat offers to retry instead of asking for consent again
                guard !Task.isCancelled, self.isSessionCurrent else { return }
                self.transitionTask = nil
                self.skeletonView.isHidden = true
                self.loadErrorView.show(AgentV2Copy.displayError(error)?.text ?? lang("$agent_error_generic"))
                return
            }
            guard !Task.isCancelled, self.isSessionCurrent else { return }
            if hasConsent {
                await self.showAgent()
            } else {
                self.showConsent()
            }
            self.transitionTask = nil
        }
    }

    /// The chat waits under the consent sheet with its skeleton: Allow records consent and opens it, and closing the
    /// sheet leaves it
    private func showConsent() {
        guard view.window != nil, presentedViewController == nil,
              navigationController?.transitionCoordinator == nil else {
            isConsentPending = true
            return
        }
        isConsentPending = false
        AgentConsentPrompt.present(
            from: self,
            accept: { [client] in try await client.acceptConsent() },
            onError: { [weak self] error in
                // A chat already left keeps its errors to itself
                guard let self, parent != nil else { return }
                showError(error.text)
            },
            onCancel: { [weak self] in
                guard let self else { return }
                AgentEntryPoint.removeDeletedChat(self, animated: true)
            },
            onAllow: { [weak self] in
                guard let self, isSessionCurrent else { return }
                transitionTask = Task { [weak self] in
                    await self?.showAgent()
                    self?.transitionTask = nil
                }
            }
        )
    }

    private func showAgent() async {
        composerView.isHidden = false
        skeletonView.isHidden = thread == nil
        // The placeholder shown from the start stays: a header transition may be drawing over it, hiding it, and a new
        // one would show its glass under the transition's
        if AgentChatNavigation.findButton(in: navigationItem.rightBarButtonItem)?.accessibilityIdentifier
            != AgentChatNavigation.menuButtonIdentifier {
            navigationItem.rightBarButtonItems = makeNavigationPlaceholders()
        }
        do {
            let selectedThread: ApiAgentV2ThreadSummary
            if let thread {
                selectedThread = thread
            } else {
                selectedThread = try await client.createThread().thread
                guard !Task.isCancelled, isSessionCurrent else { return }
                AgentSearchProvider.shared.notifyConversationChanged()
            }
            selectedThreadId = selectedThread.id
            let model: AgentV2Model
            if let preloader {
                guard let acquiredModel = preloader.acquireModel(thread: selectedThread, isSummaryCached: isSummaryCached) else {
                    closeDeletedThread()
                    return
                }
                model = acquiredModel
            } else {
                model = AgentV2Model(client: client, thread: selectedThread)
            }
            model.retainPresentation()
            preparingModel = model
            // A chat with unread messages opens at the first of them, which only its loaded history places
            let isCacheAllowed = thread != nil && !isSummaryCached && !AgentThreadReadState.shared.isUnread(selectedThread)
            if isCacheAllowed {
                await model.waitForInitialContent()
            } else {
                await model.waitForInitialLoad()
            }
            guard !Task.isCancelled, isSessionCurrent else {
                releasePreparingModel()
                return
            }
            // Nor does its cached history show when the history fails to load: the failure shows here with Retry
            if !isCacheAllowed, model.isShowingCachedMessages {
                releasePreparingModel()
                skeletonView.isHidden = true
                loadErrorView.show(model.initialLoadFailure ?? lang("$agent_error_generic"))
                return
            }
            // The request goes from a chat the user has stayed on since it opened, not from one left, as by going back
            // or switching tabs, while its history loaded
            if shouldRequestSupport, disappearanceCount == 0 {
                model.requestSupportOnceLoaded()
            }
            isModelPrepared = true
            presentPreparedModelIfPossible()
        } catch {
            guard !Task.isCancelled, isSessionCurrent else { return }
            skeletonView.isHidden = true
            loadErrorView.show(AgentV2Copy.displayError(error)?.text ?? lang("$agent_error_generic"))
        }
    }

    /// The chat's "…" button while the chat loads, which an existing chat shows from the start, as the loaded chat
    /// does, and the headset before it in a chat that offers Contact Support. A new chat that offers it shows both, as
    /// its loaded header has them, so neither moves in.
    private func makeNavigationPlaceholders() -> [UIBarButtonItem] {
        let isSupportVisible = AgentV2HostContextProvider.supportsSupportHandoff
            && !AgentSupportPresentation.getState(for: thread?.support).isActive
        guard thread != nil || isSupportVisible else { return [] }
        let menu = AgentChatNavigation.makeMenuItem(menu: nil)
        guard isSupportVisible else { return [menu] }
        let support = AgentChatNavigation.makeSupportItem(primaryAction: nil)
        AgentChatNavigation.findCircle(in: support)?.isUserInteractionEnabled = false
        AgentChatNavigation.findButton(in: support)?.isAccessibilityElement = false
        return [menu, support]
    }

    private var isSessionCurrent: Bool {
        !isThreadDeleted && sessionGeneration == preloader?.sessionGeneration
    }

    func walletCore(event: WalletCoreData.Event) {
        guard case .agentThreadDeleted(let threadId) = event, selectedThreadId == threadId else { return }
        closeDeletedThread()
    }

    private func closeDeletedThread() {
        isThreadDeleted = true
        transitionTask?.cancel()
        preparingModel?.stop()
        releasePreparingModel()
        AgentEntryPoint.removeDeletedChat(self)
    }

    private func presentPreparedModelIfPossible() {
        guard !isTransferringModel, isModelPrepared, isSessionCurrent,
              let model = preparingModel,
              let navigationController,
              let index = navigationController.viewControllers.firstIndex(of: self) else { return }
        // A chat that loads while it is pushed or popped takes its place once the screens settle: replacing it
        // midway would swap the header the transition is moving to and jump the messages into place
        if let coordinator = navigationController.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                DispatchQueue.main.async { self?.presentPreparedModelIfPossible() }
            }
            return
        }
        guard AgentHeaderTransitionTracker.isIdle else {
            AgentHeaderTransitionTracker.runWhenIdle { [weak self] in self?.presentPreparedModelIfPossible() }
            return
        }
        isTransferringModel = true
        var viewControllers = navigationController.viewControllers
        viewControllers[index] = AgentVC(model: model)
        preloader?.keepRecent(model)
        releasePreparingModel()
        let chat = viewControllers[index]
        let replace = { navigationController.setViewControllers(viewControllers, animated: false) }
        // The real surfaces take over the placeholder geometry in the same frame. Keeping a fading copy underneath
        // would leave stationary bubbles for the growing messages to cross.
        guard view.window != nil, navigationController.topViewController === self, !UIAccessibility.isReduceMotionEnabled,
              !skeletonView.isHidden, let container = navigationController.view else {
            replace()
            return
        }
        let placeholders = skeletonView.placeholdersInWindow()
        replace()
        container.layoutIfNeeded()
        if let chat = chat as? AgentVC, chat.view.isDescendant(of: container) {
            chat.revealMessagesFromSkeleton(placeholders: placeholders)
        }
    }

    private func releasePreparingModel() {
        preparingModel?.releasePresentation()
        preparingModel = nil
        isModelPrepared = false
    }
}

extension AgentRootVC: AgentComposerHandoffTarget {
    func setComposerHandoffHidden(_ isHidden: Bool) {
        composerView.alpha = isHidden ? 0 : 1
    }
}

extension AgentRootVC: AgentChatNavigationHandoff {
    var navigationHandoffLeadingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.leftBarButtonItem)
    }

    var navigationHandoffTrailingView: UIView? {
        AgentChatNavigation.findCircle(in: navigationItem.rightBarButtonItem)
    }

    func setNavigationHandoffHidden(_ isHidden: Bool) {
        AgentChatNavigation.setButtonsHidden(isHidden, in: navigationItem)
    }
}
