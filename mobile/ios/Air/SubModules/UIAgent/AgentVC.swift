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
    /// Toasts stand above the composer as Telegram's chat keeps its overlays: 12 pt above its messages' bottom inset,
    /// which ends 11 pt above the input field
    static let toastSpacingToComposer: CGFloat = 23

    static func calculateHintsContainerHeight(for hintCount: Int) -> CGFloat {
        let sectionHeight = AgentHintsSectionView.calculateContentHeight(for: hintCount)
        guard sectionHeight > 0 else { return 0 }
        return hintsSpacingToMessages + sectionHeight
    }
    static let nearBottomThreshold: CGFloat = 60
    /// The space at the top within which a chat loads its older messages; the News feed counts rows instead
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
    /// As on Android, a question that appears where it lands stays there this long before the chat brings it up
    static let sentUserMessagePinDelay: TimeInterval = 0.25
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
    /// The consent sheet that an opening without consent asks with, while it is up
    private var isOpeningConsentAsked = false
    /// How many times the chat has gone from the screen, so a recording asked for before it went doesn't start after
    private var disappearanceCount = 0
    private var isOpeningConsentRetryScheduled = false
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
    /// Support had the chat at the last change the chat saw
    var wasSupportActive = false
    /// The last row as support took the chat over a pinned question. The question keeps its place until a row comes
    /// after this one.
    var supportFollowResumeItemID: AgentItemID?
    /// What the question being sent came from, for its bubble to grow out of
    var pendingSentSource: AgentSentMessageSource?
    /// The field's text of the question being sent, drawn from its layers, for its bubble to grow out of as the chat
    /// brings the question up from below
    var pendingSentTextPicture: AgentSentMessageSource?
    /// A question with nothing to come out of, as one of more than ten lines, that the chat brings up from below: its
    /// bubble fades in and grows as it comes on screen, as Android's row opens
    var pendingSentAppearanceID: AgentItemID?
    /// Where the question this chat opens with was asked on the screen before, the chat list's field or suggestion, in
    /// the window: its bubble grows out of it as the chat comes in
    var openingSentSource: AgentSentMessageSource?
    private var isOpeningMorphRetryScheduled = false
    /// The typing row turning into the answer that took its place
    var typingAnswerMorph: AgentTypingAnswerMorph?
    /// The suggestion tapped turning into its question's bubble
    var suggestionMorph: AgentSuggestionMorph?
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
    /// A digest headline's news item is loading to open over the chat
    private var isOpeningDigestHeadline = false
    /// The placeholder bubbles of a discussion whose post is loading
    private var postSkeletonView: AgentMessagesSkeletonView?
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
    private let reactionToasts: AgentReactionToasts
    /// The latest reaction the user chose on each answer whose rating is still saving
    private var savingReactionIDs: [AgentItemID: UUID] = [:]

    init(
        model: AgentModel,
        dictationController: AgentDictationController = AgentDictationController(),
        reactionToasts: AgentReactionToasts = .shared
    ) {
        self.model = model
        self.reactionToasts = reactionToasts
        let openingModel = model as? AgentV2Model
        let initialOpeningInputItemID = openingModel?.isOpening == true ? openingModel?.openingInputItemID : nil
        self.initialOpeningInputItemID = initialOpeningInputItemID
        pinnedUserMessageID = initialOpeningInputItemID
        wasSupportActive = model.isSupportActive
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
        AgentReactionAnimations.prewarm()
        model.delegate = self
        updateStreamingState(for: model.itemIDs)
        setupViews()
        setupObservers()
        updateHintsView(animated: false)
        applySnapshot(animated: false)
        updateSendButtonState()
        updatePostSkeleton()
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            DispatchQueue.main.async { [weak self, weak model] in
                guard self?.parent == nil else { return }
                (model as? AgentV2Model)?.cancelOpeningIfNeeded()
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
        updateThinkingVisuals()
    }

    @objc private func handleDidBecomeActive() {
        guard isViewLoaded else { return }
        updateThinkingVisuals()
    }

    /// Every visual of the Agent thinking, from the run as it stands now: still thinking, the glow and the typing row go
    /// on; an answer that ended while the app was away, or the chat off screen, takes them with it at once, rather than
    /// leaving them where their last frames had them
    func updateThinkingVisuals() {
        guard lastTypingIndicatorID == nil else {
            updateThinkingGlow()
            updateVisibleTypingIndicator()
            return
        }
        thinkingGlowView.setGlowing(false, animated: false)
        typingAnswerMorph?.cancel()
        typingAnswerMorph = nil
        let itemIDs = Set(model.itemIDs)
        let hasStrayTypingRow = collectionView.visibleCells.contains { cell in
            guard cell is AgentTypingIndicatorCell, let indexPath = collectionView.indexPath(for: cell),
                  let itemID = messageItemID(at: indexPath) else { return false }
            return !itemIDs.contains(itemID)
        }
        if hasStrayTypingRow {
            applySnapshot(animated: false)
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateOpeningConsentView()
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
        disappearanceCount += 1
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
        startOpeningMorphIfReady()
    }

    /// The chat's layout may settle without a pass of its own, as its rows lay out, so the opening's morph looks again
    /// a frame later while its source lasts
    private func scheduleOpeningMorphRetry() {
        guard openingSentSource != nil, !isOpeningMorphRetryScheduled else { return }
        isOpeningMorphRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard let self else { return }
            isOpeningMorphRetryScheduled = false
            startOpeningMorphIfReady()
        }
    }

    /// The question the chat opens with: its opening's, or else its first question
    private func getOpeningQuestionID() -> AgentItemID? {
        if let initialOpeningInputItemID, model.itemIDs.contains(initialOpeningInputItemID) {
            return initialOpeningInputItemID
        }
        return model.itemIDs.first { itemID in
            guard case .message(let message)? = model.item(for: itemID) else { return false }
            return message.role == .user
        }
    }

    /// Once the chat has laid out the bubble of the question it opens with, the question grows into it out of where it
    /// was asked, in the window over both screens, following the bubble as the chat slides or fades in and keeping it
    /// out of sight until it lands. It takes the push's time, if longer than its own.
    private func startOpeningMorphIfReady() {
        guard let source = openingSentSource else { return }
        // The bubble may wait for the chat to be created; one that comes much later just shows
        guard CACurrentMediaTime() - source.time < AgentSentMessageSource.openingLifetime else {
            openingSentSource = nil
            return
        }
        guard let window = view.window, let itemID = getOpeningQuestionID() else {
            scheduleOpeningMorphRetry()
            return
        }
        // The morph waits where the question was asked until the chat shows its bubble, then goes to it
        let getCell: () -> AgentMessageCell? = { [weak self] in
            guard let self, let indexPath = self.messageIndexPath(for: itemID),
                  let cell = self.collectionView.cellForItem(at: indexPath) as? AgentMessageCell,
                  cell.messageID == itemID else { return nil }
            return cell
        }
        collectionView.layoutIfNeeded()
        openingSentSource = nil
        suggestionMorph?.cancel()
        suggestionMorph = AgentSuggestionMorph.start(
            from: source,
            in: window,
            duration: max(AgentSuggestionMorph.duration, transitionCoordinator?.transitionDuration ?? 0),
            getCell: getCell
        )
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

    /// How long the typing row's top stays grown after a Stop while the Agent thinks, as its knock settles mostly; how
    /// long it then takes to ease back to its resting size; and how long the row and its top then take to fade away
    static let stoppedTypingRowHoldDuration: TimeInterval = 1
    static let stoppedTypingTopShrinkDuration: TimeInterval = 0.75
    static let stoppedTypingRowExitDuration: CFTimeInterval = 0.3

    /// The next timeline the model brings animates its changes, as a row leaving closes up its place
    var animatesNextTimelineReload = false

    /// The typing row of the Agent thinking now, not one kept on screen after its run ended
    var thinkingTypingIndicatorID: AgentItemID? {
        guard let id = lastTypingIndicatorID, id != model.heldTypingIndicatorID else { return nil }
        return id
    }

    /// Knocks the chat's large top, and has the typing row show the Stop: its status goes and its top grows and is
    /// knocked
    private func knockTops() {
        hintsSectionView.knockTop()
        typingIndicatorCell(for: lastTypingIndicatorID)?.showStop()
    }

    func typingIndicatorCell(for id: AgentItemID?) -> AgentTypingIndicatorCell? {
        guard let id, let indexPath = messageIndexPath(for: id) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? AgentTypingIndicatorCell
    }

    /// The chat's large top shows its run: thinking while the Agent thinks or writes, a knock when the run fails
    func updateLargeTopState() {
        let isThinking = thinkingTypingIndicatorID != nil || hasActiveStreamingMessage
        let isFailed = (model as? AgentV2Model)?.isRunFailed == true
        hintsSectionView.agentState = isThinking ? .thinking : isFailed ? .failed : .idle
    }

    public override func scrollToTop(animated: Bool) {
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
            self.composerView.revealDictatedText(text)
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
        composerView.shouldStartDictation = { [weak self] in
            self?.checkDictationConsent() ?? true
        }
        composerView.onDictationPhaseChanged = { [weak self] in
            self?.updateScrollToBottomButtonPlacement(animated: true)
        }
        composerView.onStop = { [weak self] in
            guard let self else { return }
            // Stopped while it thinks, before any of the answer has come, the Agent's tops are knocked as by a
            // failure, the typing row's status going at once and its top growing, staying grown a moment for its knock
            // to show before it shrinks back and the row goes; with Reduce Motion the row only fades. Stopped while it
            // writes, the tops only ease back.
            if thinkingTypingIndicatorID != nil, !hasActiveStreamingMessage {
                knockTops()
                model.holdTypingIndicator(
                    for: UIAccessibility.isReduceMotionEnabled ? 0 : Self.stoppedTypingRowHoldDuration
                )
            }
            model.stopAnswer()
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
        toastController.keepAbove(composerView.inputTopGuide, spacing: AgentVCLayout.toastSpacingToComposer)
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
        chatTitleView.setSubtitle(AgentSupportPresentation.getSubtitle(for: model.supportState))
        displayedTitleThreadID = threadID
    }

    /// Every chat asks the same, a news discussion too, so the field doesn't change on the way from the list. A chat
    /// that support has writes to support.
    func updateComposerPlaceholder() {
        let placeholder = AgentSupportPresentation.getComposerPlaceholder(for: model.supportState)
        if composerView.placeholder != placeholder {
            composerView.placeholder = placeholder
        }
    }

    /// A chat opened with a question asks for consent in the consent sheet, once the chat is on screen. Allow carries on
    /// with the opening; closing the sheet leaves the chat without sending anything. A news discussion asks at its
    /// first message, suggestion or recording instead.
    func updateOpeningConsentView() {
        // Allowed, the chat waits for the consent to be recorded without asking again
        guard let model = model as? AgentV2Model, model.needsOpeningConsent, !model.isAcceptingOpeningConsent,
              !isOpeningConsentAsked, viewIfLoaded?.window != nil else { return }
        // A push, or a sheet coming or going, as when search closes for the chat it opens, holds the ask back until
        // it has ended
        guard AgentConsentSheetPresentation.current.presentedViewController(of: self) == nil,
              navigationController?.transitionCoordinator == nil else {
            scheduleOpeningConsentRetry()
            return
        }
        isOpeningConsentAsked = true
        // Consent is read again before the sheet asks, so a consented user whose consent was read as missing as the
        // chat opened, as search opens it, goes on without the sheet. A failed read asks again later.
        Task { [weak self, weak model] in
            let isGiven = try? await model?.loadConsent()
            guard let self, let model else { return }
            guard model.needsOpeningConsent, !model.isAcceptingOpeningConsent else {
                isOpeningConsentAsked = false
                return
            }
            switch isGiven {
            case true?:
                isOpeningConsentAsked = false
                model.confirmOpeningConsent()
            case false?:
                presentOpeningConsent(for: model)
            case nil:
                isOpeningConsentAsked = false
                scheduleOpeningConsentRetry(after: Self.openingConsentReadRetryDelay)
            }
        }
    }

    /// Asks for the opening's consent in the sheet, unless something has come over the chat since
    private func presentOpeningConsent(for model: AgentV2Model) {
        guard viewIfLoaded?.window != nil, AgentConsentSheetPresentation.current.presentedViewController(of: self) == nil,
              navigationController?.transitionCoordinator == nil else {
            isOpeningConsentAsked = false
            scheduleOpeningConsentRetry()
            return
        }
        view.endEditing(true)
        dictationController.cancel()
        let isAsked = AgentConsentPrompt.present(
            from: self,
            accept: nil,
            onCancel: { [weak self] in
                guard let self else { return }
                isOpeningConsentAsked = false
                AgentEntryPoint.removeDeletedChat(self, animated: true)
            },
            onAllow: { [weak self, weak model] in
                self?.isOpeningConsentAsked = false
                model?.acceptOpeningConsent()
            }
        )
        // UIKit turned the sheet down: the chat asks again
        if !isAsked {
            isOpeningConsentAsked = false
            scheduleOpeningConsentRetry()
        }
    }

    /// Looks again a moment later whether the opening's consent can be asked for
    private func scheduleOpeningConsentRetry(after delay: TimeInterval = AgentVC.openingConsentRetryDelay) {
        guard !isOpeningConsentRetryScheduled else { return }
        isOpeningConsentRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            isOpeningConsentRetryScheduled = false
            updateOpeningConsentView()
        }
    }

    private static let openingConsentRetryDelay: TimeInterval = 0.15
    private static let openingConsentReadRetryDelay: TimeInterval = 1

    func updateLoadError() {
        loadErrorView.show((model as? AgentV2Model)?.initialLoadError)
    }

    /// A discussion opened without the feed's copy of its post, as from a digest's headline, holds the post's place with
    /// Telegram's placeholder bubbles until the post comes, as on Android and the web, and the post grows out of them
    /// once it is in the list, which `isPostInList` tells
    func updatePostSkeleton(isPostInList: Bool = false) {
        guard isViewLoaded else { return }
        let model = model as? AgentV2Model
        let hasPost = model?.hasMessages == true
        if model?.isAwaitingDiscussionPost == true {
            guard postSkeletonView == nil else { return }
            let skeleton = AgentMessagesSkeletonView()
            skeleton.translatesAutoresizingMaskIntoConstraints = false
            skeleton.isUserInteractionEnabled = false
            insertUnderMessages(skeleton)
            NSLayoutConstraint.activate([
                skeleton.topAnchor.constraint(equalTo: view.topAnchor),
                skeleton.leadingAnchor.constraint(equalTo: composerView.leadingAnchor),
                skeleton.trailingAnchor.constraint(equalTo: composerView.trailingAnchor),
                skeleton.bottomAnchor.constraint(equalTo: composerView.topAnchor, constant: -4),
            ])
            postSkeletonView = skeleton
            return
        }
        guard let skeleton = postSkeletonView, !hasPost || isPostInList else { return }
        postSkeletonView = nil
        let placeholders = skeleton.placeholdersInWindow()
        skeleton.removeFromSuperview()
        guard hasPost, view.window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        revealMessagesFromSkeleton(placeholders: placeholders)
    }

    func refreshNavigationItemMenu() {
        AgentChatNavigation.findButton(in: navigationItem.rightBarButtonItem)?.menu = chatActions.makeNavigationOverflowMenu()
        updateNavigationMenuAvailability()
    }

    /// The "…" button shows once the chat has something in it, or is about to: a question being answered shows it from
    /// the start. A news discussion the user hasn't written in shows it only while its menu has an item, such as Report
    /// a Problem once the user has allowed the Agent. It stays in place while deletion closes the chat. The headset
    /// before it shows while the chat offers Contact Support.
    func updateNavigationMenuAvailability() {
        guard !isThreadDeleted else { return }
        let isSupportVisible = model.isSupportRequestVisible
        let canUseMenu = chatActions.canDeleteChat || model.canReportProblem
        let hasMenu = canUseMenu || chatActions.willHaveMenu
        let items = navigationItem.rightBarButtonItems ?? []
        var menuItem = items.first { AgentChatNavigation.findButton(in: $0)?.accessibilityIdentifier == AgentChatNavigation.menuButtonIdentifier }
        var supportItem = items.first {
            AgentChatNavigation.findButton(in: $0)?.accessibilityIdentifier == AgentChatNavigation.supportButtonIdentifier
        }
        if hasMenu != (menuItem != nil) || isSupportVisible != (supportItem != nil) {
            let animated = viewIfLoaded?.window != nil && navigationController?.transitionCoordinator == nil
            if !hasMenu {
                menuItem = nil
            } else if menuItem == nil {
                menuItem = AgentChatNavigation.makeMenuItem(menu: chatActions.makeNavigationOverflowMenu())
            }
            if !isSupportVisible {
                supportItem = nil
            } else if supportItem == nil {
                supportItem = AgentChatNavigation.makeSupportItem(primaryAction: UIAction { [weak self] _ in
                    self?.chatActions.confirmHeaderSupportRequest()
                })
            }
            // The first item stands at the trailing edge, where the root's header morphs into the "…" button
            navigationItem.setRightBarButtonItems([menuItem, supportItem].compactMap { $0 }, animated: animated)
        }
        if let menuButton = AgentChatNavigation.findButton(in: menuItem), menuButton.isEnabled != canUseMenu {
            menuButton.isEnabled = canUseMenu
        }
        if let supportButton = AgentChatNavigation.findButton(in: supportItem) {
            AgentChatNavigation.setGlyphButtonEnabled(supportButton, isEnabled: model.canRequestSupport)
        }
        chatActions.updateSupportConfirmation()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
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
                onControlTap: self.makeControlTapHandler(for: message) { [weak cell] in
                    cell?.getFollowupButton(controlID: $0)
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
                  let post = (self.model as? AgentV2Model)?.newsPostContent(for: message) else { return }
            self.newsPostArrival?.hidePost(in: cell)
            cell.configure(with: post)
            cell.configureFollowups(message.controls, isLoading: model.itemIDs.last == message.id && !message.isStreaming)
            cell.onFollowupTap = self.makeControlTapHandler(for: message) { [weak cell] in
                cell?.getFollowupButton(controlID: $0)
            }
            cell.openSourceAction = {
                AgentTextLinks.openNewsSource(post.sourceURL)
            }
            cell.onPictureTap = { [weak self] imageView in
                self?.openNewsPicture(post, date: message.timestamp, image: imageView.image)
            }
            cell.onDigestHeadlineTap = { [weak self] eventId in self?.openDigestHeadline(eventId: eventId) }
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

    /// Opens a digest headline's news item over the chat, as the digest's card opens it over the feed. The chat slides
    /// in with its post once the post comes, which a news item opened before has in a moment; one that takes longer
    /// slides in holding the post's place with placeholder bubbles.
    private func openDigestHeadline(eventId: Int) {
        guard !isOpeningDigestHeadline, navigationController != nil else { return }
        isOpeningDigestHeadline = true
        Task { [weak self] in
            defer { self?.isOpeningDigestHeadline = false }
            do {
                let controller = try await AgentEntryPoint.makeNewsChatViewController(eventId: eventId)
                if let model = (controller as? AgentVC)?.model as? AgentV2Model {
                    let deadline = ContinuousClock.now + Self.headlinePostWait
                    while model.isAwaitingDiscussionPost, ContinuousClock.now < deadline {
                        try await Task.sleep(for: Self.headlinePostCheckInterval)
                    }
                }
                guard let self, self.view.window != nil else { return }
                self.navigationController?.pushViewController(controller, animated: true)
            } catch {
                if !(error is CancellationError) { AppActions.showError(error: error) }
            }
        }
    }

    /// How long a headline's chat may wait for its post before it slides in with placeholders, and how often it looks
    private static let headlinePostWait: Duration = .seconds(1)
    private static let headlinePostCheckInterval: Duration = .milliseconds(30)

    /// Opens the post's picture in the media viewer, as the feed opens its pictures
    private func openNewsPicture(_ content: AgentNewsPostView.Content, date: Date, image: UIImage?) {
        guard let window = view.window else { return }
        let post = AgentNewsPictureViewer.Post(
            content: content, date: date, image: image, locale: (model as? AgentV2Model)?.newsLocale
        )
        AgentNewsPictureViewer.present(posts: [post], index: 0, in: window, openSource: { url in
            AgentTextLinks.openNewsSource(url)
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
    static let rowMoveAnimationKey = "agentRowMove"

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
        if (model as? AgentV2Model)?.needsConsentToSend == true, model.canSendMessage(draftText: composerView.draftText) {
            performAfterConsent(refocusesField: true) { [weak self] in self?.sendCurrentMessage() }
            return
        }
        // A question of more than ten lines shows without the flight, as on Android and the web
        let canFly = editingMessageID == nil
            && AgentSentMessageMorph.canFly(composerView.draftText, chatWidth: collectionView.bounds.width)
        pendingSentSource = canFly ? composerView.makeSentTextSource(in: view) : nil
        pendingSentTextPicture = canFly ? composerView.makeSentTextPictureSource(in: view) : nil
        sendMessage(
            text: composerView.draftText,
            clearsComposerDraft: true,
            editingMessageID: editingMessageID,
            source: .composer
        )
    }

    private func sendHint(_ hint: AgentHint) {
        if hint.isSupportRequest {
            // The request waits for the server's chats, and a chat the user has left by then drops it
            let disappearanceCount = disappearanceCount
            chatActions.confirmStarterHintSupportRequest(
                hasStayedOnScreen: { [weak self] in self?.disappearanceCount == disappearanceCount }
            ) { [weak self] thread in
                self?.openSupportThread(thread)
            }
            return
        }
        guard (model as? AgentV2Model)?.needsConsentToSend != true else {
            performAfterConsent { [weak self] in self?.sendHint(hint) }
            return
        }
        guard model.canSendMessage(draftText: hint.prompt) else { return }
        editingMessageID = nil
        pendingSentTextPicture = nil
        // The question grows out of the tapped suggestion while the others ripple away, as under an answer
        if let button = hintsSectionView.getButton(for: hint),
           let source = AgentSentMessageSource.makeSuggestion(of: button, in: view) {
            pendingSentSource = source
            AgentSuggestionMorph.rippleAway(
                AgentSuggestionMorph.findSuggestionButtons(in: hintsSectionView),
                from: button,
                in: view
            )
            button.alpha = 0
        }
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
        composerView.setSendEnabled(model.canSendMessage(draftText: composerView.draftText, isEditing: editingMessageID != nil))
        composerView.setStopAvailable(model.canStopAnswer)
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

    /// Support takes no edits, so the question being edited stays in the composer to go as a new message
    func leaveEditingOnceSupportHasChat() {
        if model.isSupportActive {
            editingMessageID = nil
        }
    }

    /// Contact Support among the starter hints can be tapped while the chat can ask and the server's chats have loaded
    func updateSupportHint() {
        hintsSectionView.isSupportRequestEnabled = (model as? AgentV2Model)?.canRequestSupportFromHint == true
    }

    /// The chat support has takes the starter hint's request in this empty chat's place
    private func openSupportThread(_ thread: ApiAgentV2ThreadSummary) {
        guard let navigationController,
              let index = navigationController.viewControllers.firstIndex(of: self) else { return }
        var viewControllers = navigationController.viewControllers
        viewControllers[index] = AgentEntryPoint.makeRootViewController(thread: thread)
        navigationController.setViewControllers(viewControllers, animated: true)
    }

    func updateHintsView(animated: Bool) {
        let visibleHints = model.visibleHints
        let shouldShow = !visibleHints.isEmpty
        let wasShowing = hintsSectionView.alpha > 0.01

        if shouldShow {
            hintsSectionView.configure(with: visibleHints) { [weak self] hint in
                self?.sendHint(hint)
            }
            updateSupportHint()
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
        guard model.canSendMessage(draftText: text, isEditing: editingMessageID != nil) else { return }

        self.editingMessageID = nil
        closeKeyboardIfQuestionSent {
            model.send(text: text, editingMessageID: editingMessageID, source: source)
            if clearsComposerDraft {
                composerView.clearDraft()
                updateSendButtonState()
            }
        }
    }

    /// Runs `send`, then closes the keyboard if the chat took a question from it, as Android does; a question turned
    /// down keeps the keyboard. It closes only after the question's bubble has set out, whose flight takes the field's
    /// text where it shows above the keyboard.
    private func closeKeyboardIfQuestionSent(by send: () -> Void) {
        let sentQuestionCount = model.sentQuestionCount
        send()
        guard model.sentQuestionCount != sentQuestionCount else { return }
        view.endEditing(true)
    }

    /// What a tap on a control of `message` does, wherever its cell was configured: in a news discussion opened before
    /// consent it asks first, and a suggestion's question grows out of the suggestion, which `getSuggestion` finds by
    /// the control's ID
    func makeControlTapHandler(
        for message: AgentMessage,
        getSuggestion: @escaping (String) -> AgentSuggestionButton?
    ) -> (String) -> Void {
        { [weak self] controlID in
            // A suggestion of the cached history answers no tap
            guard let self, (self.model as? AgentV2Model)?.isShowingCachedMessages != true else { return }
            self.performAfterConsent { [weak self] in
                guard let self else { return }
                self.dictationController.cancel()
                let suggestion = getSuggestion(controlID)
                self.pendingSentTextPicture = nil
                self.pendingSentSource = suggestion.flatMap {
                    AgentSentMessageSource.makeSuggestion(of: $0, in: self.view)
                }
                // The suggestions beside it leave as the tapped one turns into its question
                if let suggestion, self.pendingSentSource != nil,
                   let followups = sequence(first: suggestion as UIView, next: \.superview).first(where: { $0 is AgentFollowupView }) {
                    AgentSuggestionMorph.rippleAway(
                        AgentSuggestionMorph.findSuggestionButtons(in: followups),
                        from: suggestion,
                        in: self.view
                    )
                }
                self.closeKeyboardIfQuestionSent {
                    self.model.performControl(messageID: message.id, controlID: controlID)
                }
            }
        }
    }

    /// A news discussion opened before the user allowed the Agent asks for consent in the sheet at its first message,
    /// suggestion or recording. Allow carries `action` out; closing the sheet does nothing, and a message typed in the
    /// field stays there, with the keyboard back if it was up.
    private func performAfterConsent(refocusesField: Bool = false, _ action: @escaping @MainActor () -> Void) {
        guard let model = model as? AgentV2Model, model.needsConsentToSend else {
            action()
            return
        }
        pendingSentSource = nil
        pendingSentTextPicture = nil
        dictationController.cancel()
        let wasEditing = refocusesField && composerView.isTextInputActive
        performWithConsent(of: model, onCancel: { [weak self] in
            guard wasEditing, let self else { return }
            self.composerView.setDraftText(self.composerView.draftText ?? "", focus: true)
        }, action: { [weak model] in
            model?.markConsentGiven()
            action()
        })
    }

    /// A recording goes to the Agent's transcription, so in a news discussion opened before consent, or whose consent
    /// read hasn't answered, it starts once the Agent turns out allowed: hands-free, as the finger that held the
    /// microphone has let go. A chat that went from the screen while the consent was read doesn't record, back or not.
    private func checkDictationConsent() -> Bool {
        guard let model = model as? AgentV2Model else { return true }
        if model.needsConsentToSend {
            performAfterConsent(makeDictationStart())
            return false
        }
        guard model.isConsentToSendUnknown else { return true }
        // The prompt reads the consent itself, and asks in the sheet only without it
        dictationController.cancel()
        let startDictation = makeDictationStart()
        performWithConsent(of: model) { [weak model] in
            model?.markConsentGiven()
            startDictation()
        }
        return false
    }

    /// Makes the start of a hands-free recording, which does nothing once the chat has gone from the screen since
    private func makeDictationStart() -> @MainActor () -> Void {
        let disappearanceCount = disappearanceCount
        return { [weak self] in
            guard let self, self.disappearanceCount == disappearanceCount else { return }
            self.composerView.startDictationHandsFree()
        }
    }

    private func performWithConsent(
        of model: AgentV2Model,
        onCancel: @escaping @MainActor () -> Void = {},
        action: @escaping @MainActor () -> Void
    ) {
        AgentConsentPrompt.run(
            from: self,
            isGiven: false,
            load: { [weak model] in try await model?.loadConsent() ?? false },
            accept: { [weak model] in _ = try await model?.acceptConsent() },
            onCancel: onCancel,
            action: action
        )
    }

    private func editMessage(_ message: AgentMessage) {
        guard message.role == .user, !message.isEditingDisabled,
              (model as? AgentV2Model)?.newsPostContent(for: message) == nil else { return }
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
        // A row kept on screen after its run ended keeps its status
        guard let typingID = thinkingTypingIndicatorID,
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
        guard dictationController.state.phase != .holding, dictationController.state.phase != .handsFree else { return }
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
           let post = (model as? AgentV2Model)?.newsPostContent(for: message) {
            return post.copyText
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

    /// The menu a long press opens on any message but an answer still being written, with an answer's rating when it
    /// can be rated
    private func makeContextMenuConfiguration(for itemID: AgentItemID) -> ContextMenuConfiguration? {
        guard case .message(let message)? = model.item(for: itemID),
              !(message.role == .assistant && message.isStreaming) else { return nil }
        if let v2Model = model as? AgentV2Model, let post = v2Model.newsPostContent(for: message) {
            let items = AgentMessageMenuItems.makeItems(for: post, locale: v2Model.newsLocale, openSource: { url in
                AgentTextLinks.openNewsSource(url)
            }, share: { [weak self] activityItems in
                guard let self else { return }
                let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
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
            canEdit: model.canEditMessage(itemID),
            canRegenerate: model.canRegenerateMessage(itemID),
            canReportProblem: model.canReportProblem,
            edit: { [weak self] in self?.editMessage(message) },
            regenerate: { [weak self] in self?.regenerateMessage(itemID) },
            reportProblem: { [weak self] in self?.chatActions.reportProblem(messageID: itemID) }
        )
        guard !items.isEmpty else { return nil }

        dictationController.cancel()

        let accessory = message.canRate
            ? AgentFeedbackPillView.makeMenuAccessory(
                feedback: message.feedback,
                onSelect: { [weak self] selection in
                    self?.selectReaction(selection, for: itemID)
                },
                onMenuDidClose: { [weak self] _ in
                    self?.settleReaction(for: itemID)
                }
            )
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

    /// Rates the answer with the cloud's choice, as Telegram's message takes a reaction: the chosen icon flies from the
    /// cloud to the bubble's corner, and a withdrawn reaction's emoji scales down and fades out, while the cloud closes
    /// into its tail. Nothing in the chat moves. The first like and the first dislike, of answers and of operator replies
    /// apart, explain themselves in a toast once they have landed and their rating is saved, unless the answer has
    /// another reaction by then.
    private func selectReaction(_ selection: AgentFeedbackPillView.Selection, for itemID: AgentItemID) {
        let reactionID = UUID()
        savingReactionIDs[itemID] = reactionID
        var isSaved = false
        var hasLanded = false
        let explain = { [weak self] in
            guard isSaved, hasLanded, let self, let feedback = selection.feedback,
                  let message = self.model.message(for: itemID), message.feedback == feedback else { return }
            let isOperatorReply = if case .operator = message.author { true } else { false }
            self.reactionToasts.explain(feedback, isOperatorReply: isOperatorReply)
        }
        chatActions.rateMessage(itemID, feedback: selection.feedback) { [weak self] didSave in
            guard let self, self.savingReactionIDs[itemID] == reactionID else { return }
            self.savingReactionIDs.removeValue(forKey: itemID)
            isSaved = didSave
            explain()
        }
        let visibleCell = visibleMessageCell(for: itemID)
        visibleCell?.holdFeedback()
        guard let feedback = selection.feedback else {
            visibleCell?.animateFeedback(nil)
            return
        }
        let land = {
            hasLanded = true
            explain()
        }
        guard let cell = visibleCell else {
            land()
            return
        }
        cell.flyReaction(
            feedback,
            from: selection.icon,
            getFrameOnReplica: selection.getSourceFrameOnScreen,
            onLanding: land
        )
    }

    /// Once the menu is gone, the corner takes the message's rating should the rating have failed meanwhile
    private func settleReaction(for itemID: AgentItemID) {
        visibleMessageCell(for: itemID)?.releaseFeedback()
    }

    private func visibleMessageCell(for itemID: AgentItemID) -> AgentMessageCell? {
        guard let indexPath = messageIndexPath(for: itemID) else { return nil }
        return collectionView.cellForItem(at: indexPath) as? AgentMessageCell
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

    /// The floating microphone takes the place nearest the field, where the scroll-to-bottom button rests; while it
    /// shows, the button stands above it as far apart, as Telegram stacks its floating buttons
    func updateScrollToBottomButtonPlacement(animated: Bool) {
        guard animated, view.window != nil, !UIAccessibility.isReduceMotionEnabled else {
            applyScrollToBottomButtonPlacement(animated: false)
            return
        }
        // On the next turn, once the change that brought or took the floating microphone has laid out the composer in
        // its own way, such as text growing the field, so only the button moves on this spring
        DispatchQueue.main.async { [weak self] in
            self?.applyScrollToBottomButtonPlacement(animated: true)
        }
    }

    private func applyScrollToBottomButtonPlacement(animated: Bool) {
        let spacing = AgentVCLayout.scrollToBottomButtonSpacing
        let constant = composerView.isShowingFloatingMicrophone
            ? -(spacing + AgentVoiceResumeButton.diameter + spacing)
            : -spacing
        guard scrollToBottomButtonBottomToComposerConstraint.constant != constant else { return }
        scrollToBottomButtonBottomToComposerConstraint.constant = constant
        guard animated, view.window != nil else { return }
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
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
        if collectionView === self.collectionView, let itemID = messageItemID(at: indexPath),
           itemID == pendingSentAppearanceID, let cell = cell as? AgentMessageCell, cell.messageID == itemID {
            pendingSentAppearanceID = nil
            AgentSentMessageAppearance.animate(cell.sentAppearanceView)
        }
        guard collectionView === self.collectionView,
              let itemID = messageItemID(at: indexPath),
              deferredStreamingItemIDs.remove(itemID) != nil,
              let cell = cell as? AgentMessageCell else { return }
        updateVisibleCell(itemID: itemID, preparedCell: cell)
    }

    public func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard collectionView === self.collectionView else { return }
        // A cell that dissolved with its row, or moved with it, once taken for another, shows that one, where the layout
        // puts it
        cell.contentView.isHidden = false
        for key in cell.layer.animationKeys() ?? []
        where key.hasPrefix(Self.dissolvedGapAnimationKey) || key.hasPrefix(Self.rowMoveAnimationKey) {
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
