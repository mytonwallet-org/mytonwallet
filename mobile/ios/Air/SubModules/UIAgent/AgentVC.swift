import ContextMenuKit
import UIKit
import UIComponents
import WalletContext
import WalletCore

enum AgentVCLayout {
    static let maxContentWidth = AgentContentLayout.maxContentWidth
    static let sectionTopInset: CGFloat = 16
    static let bottomMessageSpacing: CGFloat = 16
    /// The gap between two rows of the chat
    static let rowSpacing: CGFloat = 6
    static let hintsSpacingToMessages: CGFloat = 17
    static let hintsSpacingToComposer: CGFloat = 26

    static func calculateHintsContainerHeight(for hintCount: Int) -> CGFloat {
        let sectionHeight = AgentHintsSectionView.calculateContentHeight(for: hintCount)
        guard sectionHeight > 0 else { return 0 }
        return hintsSpacingToMessages + sectionHeight
    }
    static let nearBottomThreshold: CGFloat = 60
    /// The space at the top within which a list loads what came before its first row
    static let loadOlderThreshold: CGFloat = 120
    static let composerResizeAnimationDuration: TimeInterval = 0.2
    static let bottomAlignmentAnimationDuration: TimeInterval = 0.25
    static let arrivalUserMessageTailInset: CGFloat = 100
    static let scrollToBottomButtonSize: CGFloat = AgentScrollToBottomButton.size
    /// The button stands over the microphone circle: the same gap above as beside it, the same trailing edge
    static let scrollToBottomButtonSpacing: CGFloat = AgentComposerMetrics.microphoneSpacing
    /// Messages fade out under the composer over this height above its field
    static let bottomEdgeFadeHeight: CGFloat = 28
    static let minimumTypingStatusDuration: TimeInterval = 1.2
    static let sentUserMessageFlyUpDuration: TimeInterval = 0.3
    static let typingIndicatorRevealGap: TimeInterval = 0.18
    /// How long Telegram's list takes to close the gap a message turning to dust leaves
    static let dissolvedGapCloseDuration: TimeInterval = 0.8
}

private final class AgentPassthroughContainerView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return false }

        return subviews.contains { subview in
            guard subview.isUserInteractionEnabled, !subview.isHidden, subview.alpha > 0.01 else {
                return false
            }
            let subviewPoint = convert(point, to: subview)
            return subview.point(inside: subviewPoint, with: event)
        }
    }
}

// Self-sizing can finish in a later UIKit layout pass, outside a model update.
final class AgentCollectionView: UICollectionView {
    var preservePositionDuringLayout: ((() -> Void) -> Void)?
    private(set) var isPreservingLayout = false
    var isScrollingToLatest = false

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        // Self-sizing can start UIKit's automatic offset animation. Settle it before restoring
        // the visible row, or that animation will continue moving the question after layout.
        super.setContentOffset(contentOffset, animated: animated && !isPreservingLayout)
    }

    /// A drag that starts on a button in a row scrolls the list, as one on the row's text does, and the button's tap
    /// fires only for a finger that didn't move. UIKit's default keeps such a touch on the control.
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }

    override func layoutSubviews() {
        guard !isPreservingLayout, let preservePositionDuringLayout else {
            super.layoutSubviews()
            return
        }
        isPreservingLayout = true
        defer { isPreservingLayout = false }
        preservePositionDuringLayout { super.layoutSubviews() }
    }
}

public final class AgentVC: WViewController, WalletCoreData.EventsObserver {
    static let streamingReserveSpaceSlack: CGFloat = 80

    struct VisibleRowAnchor {
        let itemID: AgentItemID
        let isDateHeader: Bool
        let minY: CGFloat
        let offsetY: CGFloat
    }

    /// The list moving with the composer from `startComposerY` to `endComposerY`
    struct OcclusionFollow {
        let startOffsetY: CGFloat
        let endOffsetY: CGFloat
        let startComposerY: CGFloat
        let endComposerY: CGFloat
        let startTime: CFTimeInterval
    }

    /// A composer that stops animating without reaching its frame ends the following after this long
    static let coveredAreaFollowTimeout: CFTimeInterval = 1

    enum Section: Hashable {
        case main
    }

    enum ListItemID: Hashable {
        case message(AgentItemID)
        /// "New" over the first message the user hasn't seen
        case unreadDivider
        case bottomSpacer
    }

    let model: AgentModel
    private lazy var chatActions = AgentChatActions(
        model: model, viewController: self,
        cancelDictation: { [weak self] in self?.dictationController.cancel() },
        refreshNavigationItemMenu: { [weak self] in self?.refreshNavigationItemMenu() }
    )
    private lazy var typingStatusPacing = AgentTypingStatusPacing(
        minimumDuration: AgentVCLayout.minimumTypingStatusDuration,
        onUpdate: { [weak self] in self?.updateVisibleTypingIndicator() }
    )
    private let chatTitleView = AgentChatTitleView()
    private var isNavigationTitleVisible = false
    private var displayedTitleThreadID: String?
    let collectionView: AgentCollectionView = {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(76)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = AgentVCLayout.rowSpacing
        section.contentInsets = NSDirectionalEdgeInsets(top: AgentVCLayout.sectionTopInset, leading: 0, bottom: 0, trailing: 0)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let collectionView = AgentCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "agent_messages"
        return collectionView
    }()

    lazy var dataSource = makeDataSource()
    lazy var listScrollAnimator = AgentListScrollAnimator(collectionView: collectionView)
    var occlusionFollow: OcclusionFollow?
    lazy var occlusionFollowClock = GlassMotionClock { [weak self] _ in self?.stepFollowingCoveredArea() }
    /// The composer's top after the last layout, where a change of the covered area starts from
    var lastComposerMinY: CGFloat?

    private let contentLayoutGuide = UILayoutGuide()
    private let hintsContainerView = AgentPassthroughContainerView()
    private let hintsSectionView = AgentHintsSectionView()
    let composerView = AgentComposerView()
    private var consentView: AgentConsentView?
    let dictationController: AgentDictationController
    let scrollToBottomButton = AgentScrollToBottomButton()
    let loadingOlderIndicator = AgentLoadingOlderIndicator()
    /// The failure with Retry for a chat that has nothing to show
    let loadErrorView = AgentLoadErrorView()
    private(set) var navigationBarBackground: UIView?
    private let bottomEdgeEffectView = EdgeEffectView()
    /// Runs around the display's edge while the Agent thinks
    let thinkingGlowView = AgentEdgeGlowView()
    private lazy var contentLayoutGuideWidthConstraint: NSLayoutConstraint = {
        let constraint = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }()
    private lazy var contentLayoutGuideMaxWidthConstraint = contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentVCLayout.maxContentWidth)
    private lazy var hintsContainerHeightConstraint = hintsContainerView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var hintsSectionHeightConstraint = hintsSectionView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var scrollToBottomButtonBottomToComposerConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -AgentVCLayout.scrollToBottomButtonSpacing)
    /// Keeps the button's trailing edge on the microphone circle's, also as the field widens above the keyboard
    private lazy var scrollToBottomButtonTrailingConstraint = scrollToBottomButton.trailingAnchor.constraint(
        equalTo: contentLayoutGuide.trailingAnchor,
        constant: -composerView.horizontalInset
    )
    /// With the keyboard hidden, the field rests where the Agent list's field does
    private lazy var composerEdgeLimitConstraint = composerView.bottomAnchor.constraint(
        lessThanOrEqualTo: view.bottomAnchor,
        constant: composerBottomConstant
    )
    private lazy var composerRestingConstraint: NSLayoutConstraint = {
        let constraint = composerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: composerBottomConstant)
        constraint.priority = .defaultHigh
        return constraint
    }()
    private var composerBottomConstant: CGFloat {
        AgentComposerMetrics.threadVerticalInset - AgentComposerMetrics.getFieldBottomInset(safeAreaBottom: view.safeAreaInsets.bottom)
    }
    /// The field sits 12 pt above a docked keyboard
    private lazy var composerKeyboardConstraint = composerView.bottomAnchor.constraint(
        lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor
    )
    private lazy var scrollToBottomButtonBottomToHintsConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: hintsContainerView.topAnchor, constant: -AgentVCLayout.scrollToBottomButtonSpacing)

    var hasPerformedInitialScroll = false
    let initialOpeningInputItemID: AgentItemID?
    var lastKnownNearBottom = true
    var wasNearBottomBeforeRowResize = false
    private var editingMessageID: AgentItemID?
    var isRevealingSentUserMessage = false
    var revealsSentMessageFromBottom = false
    var isResizingStreamingRow = false
    var isStreamingRowResizeScheduled = false
    var streamingItemIDs: Set<AgentItemID> = []
    var deferredStreamingItemIDs: Set<AgentItemID> = []
    /// Status rows that have come up from transparency once; scrolled back into view they are simply there
    private var revealedTypingIndicatorIDs: Set<AgentItemID> = []
    var renderedNewsPostItemIDs: Set<AgentItemID> = []
    var reserveSpacerHeight: CGFloat = 0
    // A sent question owns the scroll position until it is replaced or removed, including after the reply finishes.
    var pinnedUserMessageID: AgentItemID?
    private var pinnedOffsetBeforeResize: (offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?
    var lastPinnedPosition: (messageID: AgentItemID, offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?
    var lastLayoutViewSize: CGSize = .zero
    var lastLayoutAdjustedContentInset: UIEdgeInsets = .zero
    // Invalidated layout attributes may already contain estimates; retain the last settled geometry.
    var lastVisibleRowAnchor: VisibleRowAnchor?
    var isPreservingVisibleRow = false
    var paginationTask: Task<Void, Never>?
    var paginationOperationID: UUID?
    var paginationReloadGeneration = 0
    var completedPaginationReloadGeneration = 0
    private var requiredPaginationReloadGeneration: Int?
    private var lastAccessibilityStatus: String?
    private var isThreadDeleted = false
    var newsPostArrival: AgentNewsPostArrival?
    /// Rows leaving the chat dissolve in it, over the messages
    var messageDissolveView: AgentMessageDissolveView?
    var dissolvingItemIDs: Set<AgentItemID> = []
    /// The thread this chat reported as on screen to the list's unread state
    private var shownThreadId: String?
    /// How many of the thread's messages the user had seen when the chat opened, for a chat that has more
    private let unreadSeenMessageCount: Int?
    /// The first message the user hadn't seen when the chat opened, which the "New" divider stays over
    private var unreadDividerItemID: AgentItemID?
    private var hasResolvedUnreadDivider = false
    private let backSwipe = AgentChatBackSwipe()

    init(model: AgentModel, dictationController: AgentDictationController = AgentDictationController()) {
        self.model = model
        let openingModel = model as? AgentV2Model
        let initialOpeningInputItemID = openingModel?.isOpening == true ? openingModel?.openingInputItemID : nil
        self.initialOpeningInputItemID = initialOpeningInputItemID
        pinnedUserMessageID = initialOpeningInputItemID
        // A chat with an answer the list marks unread opens at the first message the user hasn't seen
        unreadSeenMessageCount = initialOpeningInputItemID == nil
            ? (model as? AgentV2Model)?.thread.flatMap { AgentThreadReadState.shared.getSeenMessageCount(ifUnread: $0) }
            : nil
        (model as? AgentV2Model)?.retainPresentation()
        self.dictationController = dictationController
        super.init(nibName: nil, bundle: nil)
        title = model.chatTitle
        (model as? AgentV2Model)?.setPresentationModelChangedHandler({ [weak self] _ in
            self?.presentTransferredModelIfNeeded()
        }, owner: ObjectIdentifier(self))
        WalletCoreData.addImmediately(eventObserver: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        paginationTask?.cancel()
        let owner = ObjectIdentifier(self)
        Task { @MainActor [model] in
            if let model = model as? AgentV2Model {
                model.setPresentationModelChangedHandler(nil, owner: owner)
                model.setPresentationActive(false, owner: owner)
                model.releasePresentation()
            } else {
                model.stop()
            }
        }
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        model.delegate = self
        updateStreamingState(for: model.itemIDs)
        setupViews()
        setupObservers()
        updateHintsView(animated: false)
        applySnapshot(animated: false)
        updateSendButtonState()
        updateOpeningConsentView()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent == nil else { return }
                (self.model as? AgentV2Model)?.cancelOpeningIfNeeded()
            }
        }
        if parent != nil, isThreadDeleted {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                AgentEntryPoint.removeDeletedChat(self)
            }
        } else if parent != nil {
            presentTransferredModelIfNeeded()
        }
    }

    private func presentTransferredModelIfNeeded() {
        guard let openingModel = model as? AgentV2Model,
              openingModel.presentationModel !== openingModel,
              let navigationController,
              let index = navigationController.viewControllers.firstIndex(of: self) else { return }
        var viewControllers = navigationController.viewControllers
        viewControllers[index] = AgentVC(model: openingModel.presentationModel)
        navigationController.setViewControllers(viewControllers, animated: false)
    }

    public func walletCore(event: WalletCoreData.Event) {
        guard case .agentThreadDeleted(let threadId) = event,
              (model as? AgentV2Model)?.threadId == threadId else { return }
        isThreadDeleted = true
        paginationTask?.cancel()
        dictationController.cancel()
        model.stop()
        AgentEntryPoint.removeDeletedChat(self, animated: chatActions.isDeletingChat && viewIfLoaded?.window != nil)
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        consentView?.isActive = true
        hintsSectionView.isActive = true
        AgentChatNavigation.installThreadsButton(in: self)
        presentTransferredModelIfNeeded()
        isNavigationTitleVisible = false
        let needsTimelineRefresh = model.delegate !== self
        model.delegate = self
        if needsTimelineRefresh {
            agentModelDidReloadTimeline(animated: false, reconfigureItemIDs: model.itemIDs)
            agentModelDidUpdateState()
        }
        setModelActive(true)
        refreshNavigationTitle()
        updateAccessibilityStatus()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateThinkingGlow()
        refreshNavigationTitle()
        isNavigationTitleVisible = true
        updateAccessibilityStatus()
        backSwipe.install(for: self)
        if let threadId = (model as? AgentV2Model)?.threadId, shownThreadId == nil {
            shownThreadId = threadId
            AgentThreadReadState.shared.chatDidAppear(threadId: threadId)
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        consentView?.isActive = false
        hintsSectionView.isActive = false
        // Everything the chat showed counts as seen, including the thread a new chat created while on screen
        if let threadId = shownThreadId ?? (model as? AgentV2Model)?.threadId {
            AgentThreadReadState.shared.chatDidDisappear(
                threadId: threadId,
                seenMessageCount: (model as? AgentV2Model)?.seenMessageCount
            )
        }
        shownThreadId = nil
        backSwipe.restore()
        thinkingGlowView.setGlowing(false)
        isNavigationTitleVisible = false
        chatTitleView.cancelAnimation()
        dictationController.cancel()
        setModelActive(false)
        lastAccessibilityStatus = nil
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Rows that were dissolving as the chat went are gone when it shows again
        removeMessageDissolveView()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateTheme()
        }
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        pinnedOffsetBeforeResize = nil
        guard view.bounds.size != lastLayoutViewSize,
              canResolveBottomLayoutState,
              let pinnedUserMessageID,
              let pinnedOffsetY = pinnedOffsetY(for: pinnedUserMessageID) else { return }
        // UIKit may clamp the offset as safe-area insets change before this layout callback.
        if let lastPinnedPosition, lastPinnedPosition.messageID == pinnedUserMessageID {
            pinnedOffsetBeforeResize = (lastPinnedPosition.offsetFromPin, lastPinnedPosition.maxOffsetFromPin)
        } else {
            pinnedOffsetBeforeResize = (
                offsetFromPin: collectionView.contentOffset.y - pinnedOffsetY,
                maxOffsetFromPin: maxContentOffsetY - pinnedOffsetY
            )
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        composerEdgeLimitConstraint.constant = composerBottomConstant
        composerRestingConstraint.constant = composerBottomConstant
        updateComposerKeyboardConstraint()
    }

    /// Before iOS 17 the keyboard layout guide can't leave out the safe area, so with no docked keyboard its top is the
    /// safe area's bottom. There the constraint reaches down to where the field rests, as the Agent list's does.
    private func updateComposerKeyboardConstraint() {
        if #unavailable(iOS 17.0) {
            composerKeyboardConstraint.constant = composerView.isAboveKeyboard
                ? 0
                : view.safeAreaInsets.bottom + composerBottomConstant
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let isViewportResizing = lastLayoutViewSize != view.bounds.size
        let offsetBeforeResize = pinnedOffsetBeforeResize
        pinnedOffsetBeforeResize = nil
        lastLayoutViewSize = view.bounds.size
        composerView.layoutIfNeeded()

        guard canResolveBottomLayoutState else { return }
        // Content growth has its own scroll animation; a layout pass must not jump ahead of it.
        let keepBottomVisible = isViewportResizing && pinnedUserMessageID == nil && lastKnownNearBottom
            && !hasActiveStreamingMessage && !isRevealingSentUserMessage
        updateOcclusionInsets()
        restorePinnedOffsetAfterResize(offsetBeforeResize)
        let didOpenAtUnreadDivider = performInitialScrollIfNeeded()
        if keepBottomVisible, !didOpenAtUnreadDivider, !listScrollAnimator.isRunning, occlusionFollow == nil {
            revealLastItemIfNeeded(animated: false)
        }
        lastKnownNearBottom = isNearBottom()
        lastLayoutAdjustedContentInset = collectionView.adjustedContentInset
        lastComposerMinY = composerView.frame.minY
        rememberPinnedPosition()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func updateTheme() {
        view.backgroundColor = .air.background
        bottomEdgeEffectView.updateColor(.air.background)
        composerView.applyTheme()
        scrollToBottomButton.applyTheme()
        updateSendButtonState()
        reconfigureItemsForTheme()
    }

    private func reconfigureItemsForTheme() {
        var snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers
        guard !items.isEmpty else { return }
        let reloadedItems = reloadChangedNewsPostCells(in: &snapshot)
        snapshot.reconfigureItems(items.filter { !reloadedItems.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    public override func scrollToTop(animated: Bool) {
        if let consentView {
            consentView.scrollToTop(animated: animated)
            return
        }
        scrollToLatest(animated: animated)
    }

    private func setupViews() {
        view.addLayoutGuide(contentLayoutGuide)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delaysContentTouches = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.delegate = self
        collectionView.preservePositionDuringLayout = { [weak self] layout in
            guard let self, self.pinnedUserMessageID != nil, !self.collectionView.isScrollingToLatest else {
                layout()
                return
            }
            self.preservingTopVisibleRow(anchor: self.lastVisibleRowAnchor, fittingReserveSpacer: true, layout)
        }
        if #available(iOS 26.0, *) {
            collectionView.topEdgeEffect.isHidden = true
            collectionView.bottomEdgeEffect.isHidden = true
        }
        bottomEdgeEffectView.update(content: .air.background, blur: true, alpha: 0.85, edge: .bottom, edgeSize: AgentVCLayout.bottomEdgeFadeHeight + 24)

        let dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCollectionViewTap))
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        dismissKeyboardTapGesture.delegate = self
        collectionView.addGestureRecognizer(dismissKeyboardTapGesture)

        composerView.translatesAutoresizingMaskIntoConstraints = false
        updateComposerPlaceholder()
        composerView.dictationController = dictationController
        dictationController.onTranscript = { [weak self] text in
            guard let self else { return }
            self.composerView.setDraftText(text, focus: false)
        }
        dictationController.onFinishedWithoutTranscript = { [weak self] in
            self?.clearEmptyUnfocusedEdit()
        }
        composerView.onDraftTextChanged = { [weak self] in
            guard let self else { return }
            self.updateSendButtonState()
        }
        composerView.onBeginEditing = { [weak self] in
            guard let self else { return }
            self.lastKnownNearBottom = self.isNearBottom()
        }
        composerView.onEndEditing = { [weak self] in
            guard let self else { return }
            if self.dictationController.state.phase == .idle {
                self.clearEmptyUnfocusedEdit()
            }
        }
        composerView.onSend = { [weak self] in
            self?.sendCurrentMessage()
        }
        composerView.onLayoutHeightChanged = { [weak self] in
            self?.view.setNeedsLayout()
        }
        // The scroll-to-bottom button keeps clear of the recording circle, as Telegram's navigation buttons do
        composerView.onRecordingCircleVisibilityChanged = { [weak self] in
            self?.updateScrollToBottomButtonVisibility(animated: true)
        }

        bottomEdgeEffectView.translatesAutoresizingMaskIntoConstraints = false

        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomButtonPressed), for: .touchUpInside)
        scrollToBottomButton.accessibilityIdentifier = "agent_scroll_to_bottom"

        hintsContainerView.translatesAutoresizingMaskIntoConstraints = false
        hintsContainerView.backgroundColor = .clear
        hintsContainerView.clipsToBounds = false
        hintsContainerView.layer.masksToBounds = false
        hintsContainerView.isUserInteractionEnabled = true

        hintsSectionView.translatesAutoresizingMaskIntoConstraints = false
        hintsSectionView.alpha = 0
        hintsSectionView.transform = hintsHiddenTransform
        hintsSectionView.isUserInteractionEnabled = false

        view.addSubview(collectionView)
        view.addSubview(bottomEdgeEffectView)
        thinkingGlowView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(thinkingGlowView)
        view.addSubview(hintsContainerView)
        view.addSubview(composerView)
        view.addSubview(scrollToBottomButton)
        hintsContainerView.addSubview(hintsSectionView)

        // The field sits 12 pt above the keyboard, or where the Agent list's field rests without it
        if #available(iOS 17.0, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        let keyboardConstraint = composerKeyboardConstraint
        updateComposerKeyboardConstraint()
        let edgeLimitConstraint = composerEdgeLimitConstraint
        let fallbackConstraint = composerRestingConstraint
        contentLayoutGuideWidthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            contentLayoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            contentLayoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentLayoutGuide.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            contentLayoutGuide.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor),
            contentLayoutGuide.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor),
            contentLayoutGuideWidthConstraint,
            contentLayoutGuideMaxWidthConstraint,

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            thinkingGlowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thinkingGlowView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thinkingGlowView.topAnchor.constraint(equalTo: view.topAnchor),
            thinkingGlowView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomEdgeEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomEdgeEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomEdgeEffectView.topAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -AgentVCLayout.bottomEdgeFadeHeight),
            bottomEdgeEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollToBottomButtonTrailingConstraint,
            scrollToBottomButtonBottomToComposerConstraint,
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: AgentVCLayout.scrollToBottomButtonSize),
            scrollToBottomButton.heightAnchor.constraint(equalTo: scrollToBottomButton.widthAnchor),

            hintsContainerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            hintsContainerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            hintsContainerView.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -AgentVCLayout.hintsSpacingToComposer),
            hintsContainerHeightConstraint,

            hintsSectionView.leadingAnchor.constraint(equalTo: hintsContainerView.leadingAnchor),
            hintsSectionView.trailingAnchor.constraint(equalTo: hintsContainerView.trailingAnchor),
            hintsSectionView.bottomAnchor.constraint(equalTo: hintsContainerView.bottomAnchor),
            hintsSectionHeightConstraint,

            composerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            composerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            keyboardConstraint,
            edgeLimitConstraint,
            fallbackConstraint
        ])

        view.backgroundColor = .air.background
        navigationBarBackground = AgentChatNavigation.installHeader(in: self, titleView: chatTitleView, scrollView: collectionView)
        // The edge light reaches over the header tint, while the real glass controls sample it from above.
        view.bringSubviewToFront(thinkingGlowView)
        view.bringSubviewToFront(hintsContainerView)
        view.bringSubviewToFront(composerView)
        view.bringSubviewToFront(scrollToBottomButton)
        loadingOlderIndicator.install(in: view, column: contentLayoutGuide)
        loadErrorView.onRetry = { [weak self] in (self?.model as? AgentV2Model)?.retryLoad() }
        loadErrorView.install(in: view, column: contentLayoutGuide, centerY: collectionView.centerYAnchor)
        updateLoadError()
        setupNavigationItem()

        updateTheme()
    }

    private func setupNavigationItem() {
        AgentChatNavigation.installThreadsButton(in: self)
        refreshNavigationTitle()
        updateNavigationMenuAvailability()
    }

    func refreshNavigationTitle(animated: Bool = false) {
        title = model.chatTitle
        let threadID = (model as? AgentV2Model)?.threadId
        chatTitleView.setTitle(
            model.chatTitleText,
            icon: model.chatIcon,
            animated: animated && isNavigationTitleVisible && displayedTitleThreadID == threadID
        )
        displayedTitleThreadID = threadID
    }

    /// Every chat asks the same, a news discussion too, so the field doesn't change on the way from the list
    func updateComposerPlaceholder() {
        composerView.placeholder = lang("Ask anything")
    }

    func updateOpeningConsentView() {
        guard let model = model as? AgentV2Model, model.needsOpeningConsent else {
            guard consentView != nil else { return }
            consentView?.removeFromSuperview()
            consentView = nil
            collectionView.accessibilityElementsHidden = false
            composerView.accessibilityElementsHidden = false
            hintsContainerView.accessibilityElementsHidden = false
            scrollToBottomButton.accessibilityElementsHidden = false
            updateNavigationMenuAvailability()
            return
        }
        if consentView == nil {
            view.endEditing(true)
            dictationController.cancel()
            let consentView = AgentConsentView()
            consentView.translatesAutoresizingMaskIntoConstraints = false
            consentView.onLearnMore = {
                guard let url = URL(string: APP_PRIVACY_POLICY_URL) else { return }
                AppActions.openInBrowser(url, title: lang("Privacy Policy"), injectDappConnect: false)
            }
            consentView.onContinue = { [weak model] in model?.acceptOpeningConsent() }
            view.addSubview(consentView)
            NSLayoutConstraint.activate([
                consentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                consentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                consentView.topAnchor.constraint(equalTo: view.topAnchor),
                consentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            self.consentView = consentView
            collectionView.accessibilityElementsHidden = true
            composerView.accessibilityElementsHidden = true
            hintsContainerView.accessibilityElementsHidden = true
            scrollToBottomButton.accessibilityElementsHidden = true
            updateNavigationMenuAvailability()
        }
        consentView?.isUserInteractionEnabled = !model.isAcceptingOpeningConsent
    }

    func updateLoadError() {
        loadErrorView.show((model as? AgentV2Model)?.initialLoadError)
    }

    func refreshNavigationItemMenu() {
        AgentChatNavigation.findButton(in: navigationItem.rightBarButtonItem)?.menu = chatActions.makeNavigationOverflowMenu()
        updateNavigationMenuAvailability()
    }

    /// The "…" button shows once the chat has something in it, or is about to: a question being answered or a news post
    /// opened for discussion shows it from the start. It stays in place while deletion closes the chat.
    func updateNavigationMenuAvailability() {
        guard !isThreadDeleted else { return }
        let canUseMenu = chatActions.canDeleteChat || model.canReportProblem
        let hasMenu = canUseMenu || chatActions.willHaveMenu
        var menuButton = AgentChatNavigation.findButton(in: navigationItem.rightBarButtonItem)
        if hasMenu != (menuButton?.accessibilityIdentifier == AgentChatNavigation.menuButtonIdentifier) {
            let animated = viewIfLoaded?.window != nil && navigationController?.transitionCoordinator == nil
            let item = hasMenu ? AgentChatNavigation.makeMenuItem(menu: chatActions.makeNavigationOverflowMenu()) : nil
            navigationItem.setRightBarButton(item, animated: animated)
            menuButton = AgentChatNavigation.findButton(in: item)
        }
        if let menuButton, menuButton.isEnabled != canUseMenu {
            menuButton.isEnabled = canUseMenu
        }
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSignificantTimeChange),
            name: UIApplication.significantTimeChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentLocaleDidChange),
            name: NSLocale.currentLocaleDidChangeNotification,
            object: nil
        )
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(handleKeyboardChange), name: name, object: nil)
        }
    }

    /// The field widens above a docked keyboard and narrows back as it goes, in the keyboard's animation
    @objc private func handleKeyboardChange(_ notification: Notification) {
        guard isViewLoaded, let window = view.window else { return }
        var isAboveKeyboard = false
        if notification.name != UIResponder.keyboardWillHideNotification,
           let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let frameInWindow = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
            let frame = view.convert(frameInWindow, from: window)
            let isDocked = frameInWindow.maxY >= window.bounds.maxY && frameInWindow.width >= window.bounds.width - 1
            isAboveKeyboard = isDocked && view.bounds.maxY - frame.minY > view.safeAreaInsets.bottom
        }
        guard isAboveKeyboard != composerView.isAboveKeyboard else { return }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        composerView.isAboveKeyboard = isAboveKeyboard
        updateComposerKeyboardConstraint()
        scrollToBottomButtonTrailingConstraint.constant = -composerView.horizontalInset
        UIView.animate(
            withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : duration,
            delay: 0,
            options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, ListItemID> {
        let messageRegistration = UICollectionView.CellRegistration<AgentMessageCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else { return }

            cell.onPreferredHeightChanged = { [weak self] _ in
                self?.handleStreamingCellHeightChanged(itemID: itemID)
            }
            cell.onStreamingRevealCompleted = { [weak self] in
                self?.handleStreamingRevealCompleted(itemID: itemID)
            }
            cell.contextMenuConfigurationProvider = { [weak self] in
                self?.makeContextMenuConfiguration(for: itemID)
            }
            cell.configure(
                with: message,
                onURLTap: { [weak self] url in
                    self?.openMessageURL(url, renderingPolicy: message.renderingPolicy)
                },
                onControlTap: { [weak self] controlID in
                    guard let self else { return }
                    self.dictationController.cancel()
                    self.model.performControl(messageID: message.id, controlID: controlID)
                }
            )
        }

        let systemRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else { return }
            cell.contextMenuConfigurationProvider = { [weak self] in
                self?.makeContextMenuConfiguration(for: itemID)
            }
            cell.configure(with: message) { [weak self] controlID in
                guard let self else { return }
                self.dictationController.cancel()
                self.model.performControl(messageID: message.id, controlID: controlID)
            }
        }

        let newsPostRegistration = UICollectionView.CellRegistration<AgentNewsPostCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  case .message(let message)? = self.model.item(for: itemID),
                  let news = (self.model as? AgentV2Model)?.newsPost(for: message) else { return }
            self.newsPostArrival?.hidePost(in: cell)
            cell.configure(with: news)
            cell.configureFollowups(message.controls, isLoading: model.itemIDs.last == message.id && !message.isStreaming)
            cell.onFollowupTap = { [weak self] controlID in
                guard let self else { return }
                self.dictationController.cancel()
                self.model.performControl(messageID: message.id, controlID: controlID)
            }
            cell.openSourceAction = {
                AgentTextLinks.openNewsSource(news.sources?.first?.url)
            }
            cell.onPictureTap = { [weak self] imageView in
                self?.openNewsPicture(news, date: message.timestamp, image: imageView.image)
            }
            cell.contextMenuConfigurationProvider = { [weak self] in
                self?.makeContextMenuConfiguration(for: itemID)
            }
            cell.onPreferredHeightChanged = { [weak self] in
                self?.handleNewsPostHeightChanged(itemID: itemID)
            }
        }

        let typingRegistration = UICollectionView.CellRegistration<AgentTypingIndicatorCell, AgentItemID> { [weak self] cell, _, _ in
            cell.configure(
                statusText: self?.typingStatusPacing.typingStatusText(self?.model.typingIndicatorStatusText),
                accessibilityLabel: self?.model.typingIndicatorAccessibilityLabel
            )
        }

        let spacerRegistration = UICollectionView.CellRegistration<AgentSpacerCell, ListItemID> { cell, _, _ in
            cell.heightProvider = { 0 }
        }

        let unreadDividerRegistration = UICollectionView.CellRegistration<AgentUnreadDividerCell, ListItemID> { cell, _, _ in
            cell.accessibilityIdentifier = "agent_unread_divider"
        }

        return UICollectionViewDiffableDataSource<Section, ListItemID>(collectionView: collectionView) { [weak self] collectionView, indexPath, listItemID in
            switch listItemID {
            case .bottomSpacer:
                return collectionView.dequeueConfiguredReusableCell(using: spacerRegistration, for: indexPath, item: listItemID)
            case .unreadDivider:
                return collectionView.dequeueConfiguredReusableCell(using: unreadDividerRegistration, for: indexPath, item: listItemID)
            case .message(let itemID):
                guard let self, let item = self.model.item(for: itemID) else {
                    return UICollectionViewCell()
                }
                switch item {
                case .message(let message):
                    if (self.model as? AgentV2Model)?.newsPostItemID == itemID {
                        return collectionView.dequeueConfiguredReusableCell(using: newsPostRegistration, for: indexPath, item: itemID)
                    }
                    if message.isFailureCaption {
                        return collectionView.dequeueConfiguredReusableCell(using: systemRegistration, for: indexPath, item: itemID)
                    }
                    switch message.role {
                    case .system:
                        return collectionView.dequeueConfiguredReusableCell(using: systemRegistration, for: indexPath, item: itemID)
                    case .assistant, .user:
                        return collectionView.dequeueConfiguredReusableCell(using: messageRegistration, for: indexPath, item: itemID)
                    }
                case .typingIndicator:
                    return collectionView.dequeueConfiguredReusableCell(using: typingRegistration, for: indexPath, item: itemID)
                }
            }
        }
    }

    /// Opens the post's picture in the media viewer, as the feed opens its pictures
    private func openNewsPicture(_ news: ApiAgentV2ThreadNewsCard, date: Date, image: UIImage?) {
        guard let window = view.window else { return }
        let post = AgentNewsPictureViewer.Post(content: AgentNewsPostView.Content(news: news), date: date, image: image)
        AgentNewsPictureViewer.present(posts: [post], index: 0, in: window, openSource: { _ in
            AgentTextLinks.openNewsSource(news.sources?.first?.url)
        }) { [weak self] _ in
            guard let self, let itemID = (self.model as? AgentV2Model)?.newsPostItemID,
                  let indexPath = self.messageIndexPath(for: itemID),
                  let cell = self.collectionView.cellForItem(at: indexPath) as? AgentNewsPostCell,
                  !cell.newsView.imageView.isHidden else { return nil }
            return cell.newsView.imageView
        }
    }

    func snapshotMessageIDs() -> [AgentItemID] {
        dataSource.snapshot().itemIdentifiers.compactMap { listItemID in
            if case .message(let id) = listItemID { return id }
            return nil
        }
    }

    func messageIndexPath(for id: AgentItemID) -> IndexPath? {
        dataSource.indexPath(for: .message(id))
    }

    func messageItemID(at indexPath: IndexPath) -> AgentItemID? {
        if case .message(let id)? = dataSource.itemIdentifier(for: indexPath) { return id }
        return nil
    }

    private static let replyCrossfadeDuration: TimeInterval = 0.2
    static let dissolvedGapAnimationKey = "agentDissolvedGap"

    var currentNewsPostItemIDs: Set<AgentItemID> {
        guard let id = (model as? AgentV2Model)?.newsPostItemID else { return [] }
        return [id]
    }

    func reloadChangedNewsPostCells(
        in snapshot: inout NSDiffableDataSourceSnapshot<Section, ListItemID>
    ) -> Set<ListItemID> {
        let currentItems = Set(dataSource.snapshot().itemIdentifiers)
        let nextItems = Set(snapshot.itemIdentifiers)
        let nextPostIDs = currentNewsPostItemIDs.filter { nextItems.contains(.message($0)) }
        let changedItems = Set(renderedNewsPostItemIDs.symmetricDifference(nextPostIDs).map { ListItemID.message($0) })
        let reloadedItems = changedItems.intersection(currentItems).intersection(nextItems)
        snapshot.reloadItems(Array(reloadedItems))
        renderedNewsPostItemIDs = nextPostIDs
        return reloadedItems
    }

    func applySnapshot(
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = [],
        crossfade: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let currentItemIDs = Set(snapshotMessageIDs())
        let nextItemIDs = Set(model.itemIDs)
        resolveUnreadDividerIfNeeded()
        var snapshot = NSDiffableDataSourceSnapshot<Section, ListItemID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(model.itemIDs.flatMap { id -> [ListItemID] in
            id == unreadDividerItemID ? [.unreadDivider, .message(id)] : [.message(id)]
        }, toSection: .main)
        snapshot.appendItems([.bottomSpacer], toSection: .main)
        let reloadedItems = reloadChangedNewsPostCells(in: &snapshot)
        let changedExistingItemIDs = reconfigureItemIDs.filter {
            currentItemIDs.contains($0) && nextItemIDs.contains($0) && !reloadedItems.contains(.message($0))
        }
        if !changedExistingItemIDs.isEmpty {
            snapshot.reconfigureItems(changedExistingItemIDs.map { .message($0) })
        }

        guard crossfade else {
            dataSource.apply(snapshot, animatingDifferences: animated) { completion?() }
            return
        }
        UIView.transition(
            with: collectionView,
            duration: Self.replyCrossfadeDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.dataSource.apply(snapshot, animatingDifferences: false)
        } completion: { _ in
            completion?()
        }
    }

    /// Finds the first unseen message once the chat's messages have loaded
    private func resolveUnreadDividerIfNeeded() {
        guard !hasResolvedUnreadDivider, let unreadSeenMessageCount,
              let model = model as? AgentV2Model, model.seenMessageCount != nil else { return }
        hasResolvedUnreadDivider = true
        unreadDividerItemID = model.getFirstUnseenItemID(seenMessageCount: unreadSeenMessageCount)
    }

    var hasActiveStreamingMessage: Bool {
        !streamingItemIDs.isEmpty
    }

    func updateStreamingState(for itemIDs: [AgentItemID]) {
        for itemID in itemIDs {
            if case .message(let message)? = model.item(for: itemID), message.isStreaming {
                streamingItemIDs.insert(itemID)
            } else {
                streamingItemIDs.remove(itemID)
            }
        }
    }

    var totalOcclusionBottomInset: CGFloat {
        let composerInputFrame = collectionView.convert(composerView.inputBackgroundFrame, from: composerView)
        let overlayTop = coveredBottomOverlayTop(using: composerInputFrame)
        return max(0, collectionView.bounds.maxY - overlayTop) + AgentVCLayout.bottomMessageSpacing
    }

    private func sendCurrentMessage() {
        sendMessage(
            text: composerView.draftText,
            clearsComposerDraft: true,
            editingMessageID: editingMessageID,
            source: .composer
        )
    }

    private func sendHint(_ hint: AgentHint) {
        editingMessageID = nil
        sendMessage(
            text: hint.prompt,
            clearsComposerDraft: false,
            editingMessageID: nil,
            source: .hint(id: hint.id, catalogVersion: hint.catalogVersion)
        )
    }

    func openMessageURL(_ url: URL, renderingPolicy: AgentMessageRenderingPolicy) {
        dictationController.cancel()
        view.endEditing(true)
        AgentMessageLinks.openMessageURL(url, renderingPolicy: renderingPolicy)
    }

    func updateSendButtonState() {
        composerView.setSendEnabled(model.canSendMessage(draftText: composerView.draftText))
        // As the design's "Limit Reached" frame shows it, the composer is at half its opacity while a limit blocks sending
        let contentAlpha: CGFloat = (model as? AgentV2Model)?.isInputBlockedByLimit == true ? 0.5 : 1
        if composerView.contentAlpha != contentAlpha {
            composerView.contentAlpha = contentAlpha
        }
    }

    private func clearEmptyUnfocusedEdit() {
        if !composerView.isTextInputActive, composerView.draftText?.isEmpty != false {
            editingMessageID = nil
        }
    }

    func updateHintsView(animated: Bool) {
        let visibleHints = model.visibleHints
        let shouldShow = !visibleHints.isEmpty
        let wasShowing = hintsSectionView.alpha > 0.01

        if shouldShow {
            hintsSectionView.configure(with: visibleHints) { [weak self] hint in
                self?.sendHint(hint)
            }
            updateHintsHeightConstraints(hintCount: visibleHints.count)
        } else {
            updateHintsHeightConstraints(hintCount: 0)
        }

        guard animated, wasShowing != shouldShow else {
            applyHintsPresentation(shouldShow)
            view.setNeedsLayout()
            return
        }

        animateHintsVisibilityChange(to: shouldShow)
    }

    private func updateHintsHeightConstraints(hintCount: Int) {
        let containerHeight = AgentVCLayout.calculateHintsContainerHeight(for: hintCount)
        hintsContainerHeightConstraint.constant = containerHeight
        hintsSectionHeightConstraint.constant = max(0, containerHeight - AgentVCLayout.hintsSpacingToMessages)
    }

    private func sendMessage(
        text: String?,
        clearsComposerDraft: Bool,
        editingMessageID: AgentItemID?,
        source: AgentBackendSendSource = .composer
    ) {
        guard model.canSendMessage(draftText: text) else { return }

        self.editingMessageID = nil
        model.send(text: text, editingMessageID: editingMessageID, source: source)
        if clearsComposerDraft {
            composerView.clearDraft()
            updateSendButtonState()
        }
    }

    private func editMessage(_ message: AgentMessage) {
        guard message.role == .user,
              (model as? AgentV2Model)?.newsPost(for: message) == nil else { return }
        dictationController.cancel()
        editingMessageID = message.id
        composerView.setDraftText(message.text, focus: true)
        updateSendButtonState()
    }

    /// Asks for the answer again: it and the messages after it dissolve, and the new answer is written in their place
    private func regenerateMessage(_ messageID: AgentItemID) {
        dictationController.cancel()
        dissolveItems(model.getItemIDsRemovedByRegenerating(messageID)) {
            model.regenerateMessage(messageID)
        }
        updateSendButtonState()
    }

    private func loadOlderMessagesIfNeeded() {
        guard hasPerformedInitialScroll,
              paginationTask == nil,
              isNearTopForLoadingOlder,
              paginationAnchor() != nil else { return }
        let operationID = UUID()
        let initialReloadGeneration = paginationReloadGeneration
        paginationOperationID = operationID
        requiredPaginationReloadGeneration = nil
        paginationTask = Task { [weak self] in
            guard let model = self?.model else { return }
            let didLoad = await model.loadOlderMessages()
            guard !Task.isCancelled,
                  let self,
                  self.paginationOperationID == operationID else { return }
            guard didLoad else {
                self.finishPagination(operationID: operationID)
                return
            }
            let requiredGeneration = self.paginationReloadGeneration
            guard requiredGeneration > initialReloadGeneration else {
                self.finishPagination(operationID: operationID)
                return
            }
            self.requiredPaginationReloadGeneration = requiredGeneration
            self.finishPaginationIfReady(operationID: operationID)
        }
    }

    func finishPaginationIfReady(operationID: UUID) {
        guard paginationOperationID == operationID,
              let requiredGeneration = requiredPaginationReloadGeneration,
              completedPaginationReloadGeneration >= requiredGeneration else { return }
        finishPagination(operationID: operationID)
    }

    private func finishPagination(operationID: UUID) {
        guard paginationOperationID == operationID else { return }
        paginationTask = nil
        paginationOperationID = nil
        requiredPaginationReloadGeneration = nil
    }

    func updateVisibleTypingIndicator() {
        guard let typingID = lastTypingIndicatorID,
              let indexPath = messageIndexPath(for: typingID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentTypingIndicatorCell else { return }
        let wasNearBottom = isNearBottom()
        let statusChanged = cell.configure(
            statusText: typingStatusPacing.typingStatusText(model.typingIndicatorStatusText),
            accessibilityLabel: model.typingIndicatorAccessibilityLabel
        )
        guard statusChanged else { return }
        let context = UICollectionViewLayoutInvalidationContext()
        context.invalidateItems(at: [indexPath])
        collectionView.collectionViewLayout.invalidateLayout(with: context)
        collectionView.layoutIfNeeded()
        if pinnedUserMessageID == nil, wasNearBottom {
            revealLastItemIfNeeded(animated: false)
        }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    func updateAccessibilityStatus() {
        guard model.isActive, viewIfLoaded?.window != nil else { return }
        guard dictationController.state.phase != .holding, dictationController.state.phase != .locked else { return }
        let status = model.accessibilityStatus
        guard status != lastAccessibilityStatus else { return }
        lastAccessibilityStatus = status
        guard let status else { return }
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func setModelActive(_ isActive: Bool) {
        if let model = model as? AgentV2Model {
            model.setPresentationActive(isActive, owner: ObjectIdentifier(self))
        } else {
            model.isActive = isActive
        }
    }

    func copyText(for itemID: AgentItemID) -> String? {
        if case .message(let message)? = model.item(for: itemID),
           let news = (model as? AgentV2Model)?.newsPost(for: message) {
            return AgentMessageMenuItems.copyText(for: news)
        }
        if let indexPath = messageIndexPath(for: itemID),
           let cell = collectionView.cellForItem(at: indexPath) as? AgentContextMenuPresentingCell,
           let text = cell.contextMenuCopyText {
            return text
        }

        guard let item = model.item(for: itemID),
              case .message(let message) = item else {
            return nil
        }

        return AgentMessageMenuItems.copyText(for: message)
    }

    /// The menu a long press opens on any message, with an answer's rating when it can be rated
    private func makeContextMenuConfiguration(for itemID: AgentItemID) -> ContextMenuConfiguration? {
        guard case .message(let message)? = model.item(for: itemID) else { return nil }
        if let news = (model as? AgentV2Model)?.newsPost(for: message) {
            let items = AgentMessageMenuItems.makeItems(for: news, openSource: {
                AgentTextLinks.openNewsSource(news.sources?.first?.url)
            }, share: { [weak self] text in
                guard let self else { return }
                let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                let sourceView = self.messageIndexPath(for: itemID).flatMap { self.collectionView.cellForItem(at: $0) }
                self.presentActivityViewController(controller, sourceView: sourceView)
            })
            dictationController.cancel()
            return AgentMessageMenu.makeConfiguration(
                items: items,
                date: message.timestamp,
                isOutgoing: false,
                contentAreaInWindow: getVisibleMessagesRectInWindow()
            )
        }
        let items = AgentMessageMenuItems.makeItems(
            for: message,
            copyText: copyText(for: itemID),
            canRegenerate: model.canRegenerateMessage(itemID),
            canReportProblem: model.canReportProblem,
            edit: { [weak self] in self?.editMessage(message) },
            regenerate: { [weak self] in self?.regenerateMessage(itemID) },
            reportProblem: { [weak self] in self?.chatActions.reportProblem(messageID: itemID) }
        )
        guard !items.isEmpty else { return nil }

        dictationController.cancel()

        let accessory = message.canRate
            ? AgentFeedbackPillView.makeMenuAccessory(feedback: message.feedback) { [weak self] feedback in
                self?.chatActions.rateMessage(itemID, feedback: feedback)
            }
            : nil
        return AgentMessageMenu.makeConfiguration(
            items: items,
            date: message.timestamp,
            isOutgoing: message.role == .user,
            // The rows a system cell shows centred: date lines and failure captions
            isCentered: message.role == .system || message.isFailureCaption,
            accessory: accessory,
            contentAreaInWindow: getVisibleMessagesRectInWindow()
        )
    }

    /// The chat between its header and the composer, or the suggestions or the scroll button over it, in the window's
    /// coordinates: the pressed message slides into view out of it under its menu, and scrolls with the menu when they
    /// are taller than the screen. The scroll button stays over the message as the bars do, rather than going under
    /// its replica for a moment.
    private func getVisibleMessagesRectInWindow() -> CGRect? {
        guard collectionView.window != nil else { return nil }
        let composerFrame = collectionView.convert(composerView.inputBackgroundFrame, from: composerView)
        var bottom = coveredBottomOverlayTop(using: composerFrame)
        if scrollToBottomButton.isButtonVisible, !scrollToBottomButton.isHidden {
            bottom = min(bottom, collectionView.convert(scrollToBottomButton.bounds, from: scrollToBottomButton).minY)
        }
        return AgentMessageMenu.getVisibleArea(of: collectionView, bottom: bottom)
    }

    var lastItemIndexPath: IndexPath? {
        guard collectionView.numberOfSections > 0 else { return nil }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        return itemCount > 1 ? IndexPath(item: itemCount - 2, section: 0) : nil
    }

    @objc private func handleCollectionViewTap() {
        view.endEditing(true)
    }

    private func isTouchInsideControl(_ view: UIView?) -> Bool {
        var currentView = view
        while let view = currentView {
            if view is UIControl {
                return true
            }
            currentView = view.superview
        }
        return false
    }

    @objc private func handleSignificantTimeChange() {
        model.refreshDerivedSystemMessages(animated: false)
    }

    @objc private func handleCurrentLocaleDidChange() {
        model.refreshDerivedSystemMessages(animated: false)
    }

    @objc func scrollToBottomButtonPressed() {
        scrollToLatest(animated: true)
    }

    private static let hintsAnimationDuration = AgentVCLayout.bottomAlignmentAnimationDuration

    private var hintsHiddenTransform: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: AgentVCLayout.hintsSpacingToComposer)
    }

    private func applyHintsPresentation(_ shouldShow: Bool) {
        hintsSectionView.isUserInteractionEnabled = shouldShow
        scrollToBottomButtonBottomToHintsConstraint.isActive = shouldShow
        scrollToBottomButtonBottomToComposerConstraint.isActive = !shouldShow
        hintsSectionView.alpha = shouldShow ? 1 : 0
        hintsSectionView.transform = shouldShow ? .identity : hintsHiddenTransform
    }

    private func animateHintsVisibilityChange(to shouldShow: Bool) {
        view.layoutIfNeeded()

        if shouldShow {
            hintsSectionView.alpha = 0
            hintsSectionView.transform = hintsHiddenTransform
        }

        hintsSectionView.isUserInteractionEnabled = false
        scrollToBottomButtonBottomToHintsConstraint.isActive = shouldShow
        scrollToBottomButtonBottomToComposerConstraint.isActive = !shouldShow

        UIView.animate(
            withDuration: Self.hintsAnimationDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
            self.hintsSectionView.alpha = shouldShow ? 1 : 0
            self.hintsSectionView.transform = shouldShow ? .identity : self.hintsHiddenTransform
        } completion: { _ in
            self.hintsSectionView.isUserInteractionEnabled = shouldShow
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    private func coveredBottomOverlayTop(using composerFrame: CGRect) -> CGFloat {
        guard model.areHintsVisible else {
            return composerFrame.minY
        }

        let hintsFrame = collectionView.convert(hintsContainerView.bounds, from: hintsContainerView)
        return min(composerFrame.minY, hintsFrame.minY)
    }

}

extension AgentVC: UICollectionViewDelegate, UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTouchInsideControl(touch.view)
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if collectionView === self.collectionView, let cell = cell as? AgentTypingIndicatorCell,
           let itemID = messageItemID(at: indexPath), revealedTypingIndicatorIDs.insert(itemID).inserted,
           view.window != nil {
            cell.revealFromTransparency()
        }
        guard collectionView === self.collectionView,
              let itemID = messageItemID(at: indexPath),
              deferredStreamingItemIDs.remove(itemID) != nil,
              let cell = cell as? AgentMessageCell else { return }
        updateVisibleCell(itemID: itemID, preparedCell: cell)
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard collectionView === self.collectionView else { return }
        // A cell that dissolved with its row, once taken for another, shows that one, where the layout puts it
        cell.contentView.isHidden = false
        for key in cell.layer.animationKeys() ?? [] where key.hasPrefix(Self.dissolvedGapAnimationKey) {
            cell.layer.removeAnimation(forKey: key)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        if !collectionView.isPreservingLayout, !isPreservingVisibleRow {
            // UIKit can adjust the offset together with self-sized row frames before layoutSubviews.
            // Updating just the offset would apply that same height change a second time next layout.
            lastVisibleRowAnchor = topVisibleRowAnchor()
        }
        lastKnownNearBottom = isNearBottom()
        rememberPinnedPosition()
        scrollToBottomButton.setButtonVisible(!lastKnownNearBottom && !composerView.isRecordingCircleVisible, animated: true)
        loadOlderMessagesIfNeeded()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === collectionView, !decelerate else { return }
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateScrollToBottomButtonVisibility(animated: true)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        collectionView.isScrollingToLatest = false
        listScrollAnimator.stop()
        stopFollowingCoveredArea()
    }
}

#if DEBUG
@available(iOS 18, *)
@MainActor
private func previewTabBarController() -> UITabBarController {
    let tabBarController = UITabBarController()

    let walletRootViewController = UIViewController()
    walletRootViewController.view.backgroundColor = UIColor.air.background
    walletRootViewController.title = "Wallet"
    let walletNavigationController = UINavigationController(rootViewController: walletRootViewController)
    walletNavigationController.tabBarItem = UITabBarItem(
        title: "Wallet",
        image: UIImage(named: "tab_home", in: AirBundle, compatibleWith: nil),
        selectedImage: UIImage(named: "tab_home", in: AirBundle, compatibleWith: nil)
    )

    let agentNavigationController = UINavigationController(rootViewController: AgentEntryPoint.makeNewChatViewController())
    agentNavigationController.tabBarItem = UITabBarItem(
        title: "Agent",
        image: UIImage(named: "tab_agent", in: AirBundle, compatibleWith: nil),
        selectedImage: UIImage(named: "tab_agent", in: AirBundle, compatibleWith: nil)
    )

    let exploreRootViewController = UIViewController()
    exploreRootViewController.view.backgroundColor = UIColor.air.background
    exploreRootViewController.title = "Explore"
    let exploreNavigationController = UINavigationController(rootViewController: exploreRootViewController)
    exploreNavigationController.tabBarItem = UITabBarItem(
        title: "Explore",
        image: UIImage(named: "tab_explore", in: AirBundle, compatibleWith: nil),
        selectedImage: UIImage(named: "tab_explore", in: AirBundle, compatibleWith: nil)
    )

    let settingsRootViewController = UIViewController()
    settingsRootViewController.view.backgroundColor = UIColor.air.background
    settingsRootViewController.title = "Settings"
    let settingsNavigationController = UINavigationController(rootViewController: settingsRootViewController)
    settingsNavigationController.tabBarItem = UITabBarItem(
        title: "Settings",
        image: UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil),
        selectedImage: UIImage(named: "tab_settings", in: AirBundle, compatibleWith: nil)
    )

    tabBarController.viewControllers = [
        walletNavigationController,
        agentNavigationController,
        exploreNavigationController,
        settingsNavigationController
    ]
    tabBarController.selectedViewController = agentNavigationController

    return tabBarController
}

@available(iOS 18, *)
#Preview {
    previewTabBarController()
}
#endif
