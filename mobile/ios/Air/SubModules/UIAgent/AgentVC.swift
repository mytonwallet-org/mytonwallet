import UIKit
import UIComponents
import WalletContext
import WalletCore

private let log = Log("AgentVC")

private let problemReportCommentMaxLength = 1000

private enum AgentVCLayout {
    static let maxContentWidth = AgentContentLayout.maxContentWidth
    static let bottomMessageSpacing: CGFloat = 16
    static let hintsSpacingToMessages: CGFloat = 17
    static let hintsSpacingToComposer: CGFloat = 26

    static func calculateHintsContainerHeight(for hintCount: Int) -> CGFloat {
        let sectionHeight = AgentHintsSectionView.calculateContentHeight(for: hintCount)
        guard sectionHeight > 0 else { return 0 }
        return hintsSpacingToMessages + sectionHeight
    }
    static let nearBottomThreshold: CGFloat = 60
    static let composerResizeAnimationDuration: TimeInterval = 0.2
    static let bottomAlignmentAnimationDuration: TimeInterval = 0.25
    static let arrivalUserMessageTailInset: CGFloat = 100
    static let scrollToBottomButtonSize: CGFloat = 44
    static let scrollToBottomButtonSpacing: CGFloat = 16
    static let bottomEdgeFadeHeight: CGFloat = 40
    static let navigationBarFadeHeight: CGFloat = 28
    static let minimumTypingStatusDuration: TimeInterval = 1.2
    static let sentUserMessageRevealDuration: TimeInterval = 0.25
    static let sentUserMessageFlyUpDuration: TimeInterval = 0.3
    static let typingIndicatorRevealGap: TimeInterval = 0.18
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
private final class AgentCollectionView: UICollectionView {
    var preservePositionDuringLayout: ((() -> Void) -> Void)?
    private(set) var isPreservingLayout = false
    var isScrollingToLatest = false

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        // Self-sizing can start UIKit's automatic offset animation. Settle it before restoring
        // the visible row, or that animation will continue moving the question after layout.
        super.setContentOffset(contentOffset, animated: animated && !isPreservingLayout)
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

public final class AgentVC: WViewController {
    static let streamingReserveSpaceSlack: CGFloat = 80

    private struct PaginationAnchor {
        let itemID: AgentItemID
        let minY: CGFloat
        let offsetY: CGFloat
    }

    private enum Section: Hashable {
        case main
    }

    private enum ListItemID: Hashable {
        case message(AgentItemID)
        case bottomSpacer
    }

    private let model: AgentModel
    private let collectionView: AgentCollectionView = {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(76)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 6
        section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 0, trailing: 0)
        let layout = UICollectionViewCompositionalLayout(section: section)

        return AgentCollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    private lazy var dataSource = makeDataSource()

    private let contentLayoutGuide = UILayoutGuide()
    private let hintsContainerView = AgentPassthroughContainerView()
    private let hintsSectionView = AgentHintsSectionView()
    private let composerView = AgentComposerView()
    private let scrollToBottomButton = AgentScrollToBottomButton()
    private let bottomEdgeEffectView = EdgeEffectView()
    private lazy var contentLayoutGuideWidthConstraint: NSLayoutConstraint = {
        let constraint = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }()
    private lazy var contentLayoutGuideMaxWidthConstraint = contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentVCLayout.maxContentWidth)
    private lazy var hintsContainerHeightConstraint = hintsContainerView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var hintsSectionHeightConstraint = hintsSectionView.heightAnchor.constraint(equalToConstant: 0)
    private lazy var scrollToBottomButtonBottomToComposerConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -AgentVCLayout.scrollToBottomButtonSpacing)
    private lazy var scrollToBottomButtonBottomToHintsConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: hintsContainerView.topAnchor, constant: -AgentVCLayout.scrollToBottomButtonSpacing)

    private var hasPerformedInitialScroll = false
    private var lastKnownNearBottom = true
    private var wasNearBottomBeforeRowResize = false
    private var shownTypingStatusText: String?
    private var typingStatusShownAt: CFTimeInterval = 0
    private var pendingTypingStatusUpdate: DispatchWorkItem?
    private var editingMessageID: AgentItemID?
    private var isRevealingSentUserMessage = false
    private var revealsSentMessageFromBottom = false
    private var isResizingStreamingRow = false
    private var isStreamingRowResizeScheduled = false
    private var streamingItemIDs: Set<AgentItemID> = []
    private var deferredStreamingItemIDs: Set<AgentItemID> = []
    private(set) var reserveSpacerHeight: CGFloat = 0
    // A sent question owns the scroll position until it is replaced or removed, including after the reply finishes.
    private var pinnedUserMessageID: AgentItemID?
    private var pinnedOffsetBeforeResize: (offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?
    private var lastPinnedPosition: (messageID: AgentItemID, offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?
    private var lastLayoutViewSize: CGSize = .zero
    private var lastLayoutAdjustedContentInset: UIEdgeInsets = .zero
    // Invalidated layout attributes may already contain estimates; retain the last settled geometry.
    private var lastVisibleRowAnchor: (itemID: AgentItemID, minY: CGFloat, offsetY: CGFloat)?
    private var isPreservingVisibleRow = false
    private var pendingEntryPointRequest: AgentEntryPoint.Request?
    private var paginationTask: Task<Void, Never>?
    private var paginationOperationID: UUID?
    private var paginationReloadGeneration = 0
    private var completedPaginationReloadGeneration = 0
    private var requiredPaginationReloadGeneration: Int?
    private var didStopModel = false
    private var lastAccessibilityStatus: String?

    init(model: AgentModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = lang("Agent")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        paginationTask?.cancel()
        Task { @MainActor [model] in model.stop() }
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
        capturePendingEntryPointRequestIfNeeded()
        submitPendingEntryPointQueryIfPossible()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        model.isActive = true
        capturePendingEntryPointRequestIfNeeded()
        submitPendingEntryPointQueryIfPossible()
        updateAccessibilityStatus()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateAccessibilityStatus()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.isActive = false
        lastAccessibilityStatus = nil
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || parent?.isMovingFromParent == true
            || isBeingDismissed || navigationController?.isBeingDismissed == true {
            stopModelIfNeeded()
        }
    }

    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if parent == nil {
            stopModelIfNeeded()
        }
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

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let offsetBeforeResize = pinnedOffsetBeforeResize
        pinnedOffsetBeforeResize = nil
        lastLayoutViewSize = view.bounds.size
        composerView.layoutIfNeeded()

        guard canResolveBottomLayoutState else { return }
        let keepBottomVisible = pinnedUserMessageID == nil && lastKnownNearBottom
            && !hasActiveStreamingMessage && !isRevealingSentUserMessage
        updateOcclusionInsets()
        restorePinnedOffsetAfterResize(offsetBeforeResize)
        performInitialScrollIfNeeded()
        if keepBottomVisible {
            revealLastItemIfNeeded(animated: false)
        }
        lastKnownNearBottom = isNearBottom()
        lastLayoutAdjustedContentInset = collectionView.adjustedContentInset
        rememberPinnedPosition()
        updateScrollToBottomButtonVisibility(animated: false)
        guard model.isActive else { return }
        capturePendingEntryPointRequestIfNeeded()
        if pendingEntryPointRequest?.query != nil {
            DispatchQueue.main.async { [weak self] in
                self?.submitPendingEntryPointQueryIfPossible()
            }
        }
    }

    private func updateTheme() {
        view.backgroundColor = .air.background
        bottomEdgeEffectView.update(
            content: .air.background,
            alpha: 1,
            edge: .bottom,
            edgeSize: AgentVCLayout.bottomEdgeFadeHeight
        )
        composerView.applyTheme()
        scrollToBottomButton.applyTheme()
        updateSendButtonState()
        reconfigureItemsForTheme()
    }

    private func reconfigureItemsForTheme() {
        var snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    public override func scrollToTop(animated: Bool) {
        guard let indexPath = lastItemIndexPath else { return }
        scrollToBottom(of: indexPath, animated: animated)
        if !animated {
            revealLastItemSettlingRowHeights()
        }
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
        }

        let dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCollectionViewTap))
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        dismissKeyboardTapGesture.delegate = self
        collectionView.addGestureRecognizer(dismissKeyboardTapGesture)

        composerView.translatesAutoresizingMaskIntoConstraints = false
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
            if self.composerView.draftText?.isEmpty != false {
                self.editingMessageID = nil
            }
        }
        composerView.onSend = { [weak self] in
            self?.sendCurrentMessage()
        }
        composerView.onLayoutHeightChanged = { [weak self] in
            self?.view.setNeedsLayout()
        }

        bottomEdgeEffectView.translatesAutoresizingMaskIntoConstraints = false

        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.addTarget(self, action: #selector(scrollToBottomButtonPressed), for: .touchUpInside)

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
        view.addSubview(hintsContainerView)
        view.addSubview(composerView)
        view.addSubview(scrollToBottomButton)
        hintsContainerView.addSubview(hintsSectionView)

        let keyboardConstraint = composerView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        let fallbackConstraint = composerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        fallbackConstraint.priority = .defaultHigh
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

            bottomEdgeEffectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomEdgeEffectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomEdgeEffectView.topAnchor.constraint(
                equalTo: composerView.inputTopAnchor,
                constant: -AgentVCLayout.bottomMessageSpacing
            ),
            bottomEdgeEffectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollToBottomButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
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
            fallbackConstraint
        ])

        view.backgroundColor = .air.background
        addCustomNavigationBarBackground(color: .air.background, maxEdgeSize: AgentVCLayout.navigationBarFadeHeight)
        setupNavigationItem()

        updateTheme()
    }

    private func setupNavigationItem() {
        let header = NavigationHeader2()
        header.setTitle(lang("Agent"))
        navigationItem.titleView = header
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeOverflowMenu())
    }

    private func refreshNavigationItemMenu() {
        navigationItem.rightBarButtonItem?.menu = makeOverflowMenu()
    }

    private func makeOverflowMenu() -> UIMenu {
        let clearChat = UIAction(
            title: lang("Clear Chat"),
            image: UIImage(systemName: "trash"),
            attributes: model.canClearChat ? .destructive : [.destructive, .disabled]
        ) { [weak self] _ in
            self?.clearChat()
        }
        guard model.canReportProblem else { return UIMenu(children: [clearChat]) }
        let reportProblem = UIAction(title: lang("Report a Problem"), image: UIImage(systemName: "flag")) { [weak self] _ in
            self?.reportProblem(messageID: nil)
        }
        return UIMenu(children: [reportProblem, clearChat])
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
            selector: #selector(handlePendingEntryPointRequest),
            name: AgentEntryPoint.requestDidChangeNotification,
            object: nil
        )
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
            cell.configure(
                with: message,
                onURLTap: { [weak self] url in
                    self?.openMessageURL(url, renderingPolicy: message.renderingPolicy)
                },
                onControlTap: { [weak self] controlID in
                    self?.model.performControl(messageID: message.id, controlID: controlID)
                }
            )
        }

        let systemRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else { return }
            cell.configure(with: message)
        }

        let typingRegistration = UICollectionView.CellRegistration<AgentTypingIndicatorCell, AgentItemID> { [weak self] cell, _, _ in
            cell.configure(
                statusText: self?.typingStatusText(),
                accessibilityLabel: self?.model.typingIndicatorAccessibilityLabel
            )
        }

        let spacerRegistration = UICollectionView.CellRegistration<AgentSpacerCell, ListItemID> { cell, _, _ in
            cell.heightProvider = { 0 }
        }

        return UICollectionViewDiffableDataSource<Section, ListItemID>(collectionView: collectionView) { [weak self] collectionView, indexPath, listItemID in
            switch listItemID {
            case .bottomSpacer:
                return collectionView.dequeueConfiguredReusableCell(using: spacerRegistration, for: indexPath, item: listItemID)
            case .message(let itemID):
                guard let self, let item = self.model.item(for: itemID) else {
                    return UICollectionViewCell()
                }
                switch item {
                case .message(let message):
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

    private func snapshotMessageIDs() -> [AgentItemID] {
        dataSource.snapshot().itemIdentifiers.compactMap { listItemID in
            if case .message(let id) = listItemID { return id }
            return nil
        }
    }

    private func messageIndexPath(for id: AgentItemID) -> IndexPath? {
        dataSource.indexPath(for: .message(id))
    }

    private func messageItemID(at indexPath: IndexPath) -> AgentItemID? {
        if case .message(let id)? = dataSource.itemIdentifier(for: indexPath) { return id }
        return nil
    }

    private static let replyCrossfadeDuration: TimeInterval = 0.2

    private func applySnapshot(
        animated: Bool,
        reconfigureItemIDs: [AgentItemID] = [],
        crossfade: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let currentItemIDs = Set(snapshotMessageIDs())
        let nextItemIDs = Set(model.itemIDs)
        var snapshot = NSDiffableDataSourceSnapshot<Section, ListItemID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(model.itemIDs.map { .message($0) }, toSection: .main)
        snapshot.appendItems([.bottomSpacer], toSection: .main)
        let changedExistingItemIDs = reconfigureItemIDs.filter {
            currentItemIDs.contains($0) && nextItemIDs.contains($0)
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

    private var hasActiveStreamingMessage: Bool {
        !streamingItemIDs.isEmpty
    }

    private func updateStreamingState(for itemIDs: [AgentItemID]) {
        for itemID in itemIDs {
            if case .message(let message)? = model.item(for: itemID), message.isStreaming {
                streamingItemIDs.insert(itemID)
            } else {
                streamingItemIDs.remove(itemID)
            }
        }
    }

    private var totalOcclusionBottomInset: CGFloat {
        let composerInputFrame = collectionView.convert(composerView.inputBackgroundFrame, from: composerView)
        let overlayTop = coveredBottomOverlayTop(using: composerInputFrame)
        return max(0, collectionView.bounds.maxY - overlayTop) + AgentVCLayout.bottomMessageSpacing
    }

    private func updateOcclusionInsets() {
        guard canResolveBottomLayoutState else { return }
        let total = totalOcclusionBottomInset
        let baselineBottom = collectionView.adjustedContentInset.bottom - collectionView.contentInset.bottom
        let additional = max(0, total - baselineBottom)
        let previousOcclusion = collectionView.contentInset.bottom - reserveSpacerHeight
        if abs(previousOcclusion - additional) > 0.5 {
            preservingTopVisibleRow {
                if additional < previousOcclusion {
                    fitReserveSpacer(
                        keepingOffsetY: min(collectionView.contentOffset.y, maxContentOffsetY),
                        bottomInset: baselineBottom + additional
                    )
                }
                collectionView.contentInset.bottom = additional + reserveSpacerHeight
                collectionView.layoutIfNeeded()
            }
        }
        if abs(collectionView.verticalScrollIndicatorInsets.bottom - total) > 0.5 {
            collectionView.verticalScrollIndicatorInsets.bottom = total
        }
    }

    private func applyMinimalArrivalReserveSpacerHeight(for userMessageID: AgentItemID) {
        guard let targetOffsetY = pinnedOffsetY(for: userMessageID) else { return }
        let minSpacer = max(reserveSpacerHeight, reserveSpacerHeightNeeded(toReachOffsetY: targetOffsetY))
        applyReserveSpacerHeight(minSpacer, preservingOffset: true)
    }

    private func pinnedOffsetY(for userMessageID: AgentItemID) -> CGFloat? {
        guard let indexPath = messageIndexPath(for: userMessageID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
        return attributes.frame.maxY
            - collectionView.adjustedContentInset.top
            - AgentVCLayout.arrivalUserMessageTailInset
    }

    private func reserveSpacerHeightNeeded(toReachOffsetY offsetY: CGFloat, bottomInset: CGFloat? = nil) -> CGFloat {
        let bottom = bottomInset ?? occlusionBottomInset
        let contentHeightWithoutSpacer = collectionView.collectionViewLayout.collectionViewContentSize.height
        return max(0, offsetY + collectionView.bounds.height - bottom - contentHeightWithoutSpacer)
    }

    private func fitReserveSpacer(keepingOffsetY offsetY: CGFloat?, bottomInset: CGFloat? = nil) {
        guard reserveSpacerHeight > 0 || pinnedUserMessageID != nil else { return }
        let pinnedY = pinnedUserMessageID.flatMap(pinnedOffsetY(for:))
        let reachableOffsetY: CGFloat?
        if let offsetY, let pinnedY {
            reachableOffsetY = max(offsetY, pinnedY)
        } else {
            reachableOffsetY = offsetY ?? pinnedY
        }
        let requestedHeight = reachableOffsetY.map { reserveSpacerHeightNeeded(toReachOffsetY: $0, bottomInset: bottomInset) } ?? 0
        let height = requestedHeight < 0.5 ? 0 : requestedHeight
        guard abs(reserveSpacerHeight - height) > 0.5 else {
            // Model updates can still have pending self-sizing. A scroll-driven layout pass is already settling it.
            if !collectionView.isPreservingLayout {
                collectionView.layoutIfNeeded()
            }
            return
        }
        if (isResizingStreamingRow || collectionView.isPreservingLayout), isRevealingStreamedAnswer,
           height <= reserveSpacerHeight, reserveSpacerHeight - height <= Self.streamingReserveSpaceSlack {
            return
        }
        applyReserveSpacerHeight(height)
        collectionView.layoutIfNeeded()
    }

    private var isRevealingStreamedAnswer: Bool {
        hasActiveStreamingMessage || collectionView.visibleCells.contains {
            ($0 as? AgentMessageCell)?.isRevealingStreamedText == true
        }
    }

    private func restorePinnedOffsetAfterResize(_ pinnedOffsetBeforeResize: (offsetFromPin: CGFloat, maxOffsetFromPin: CGFloat)?) {
        guard let pinnedOffsetBeforeResize else { return }
        collectionView.layoutIfNeeded()
        guard let pinnedUserMessageID, let pinnedOffsetY = pinnedOffsetY(for: pinnedUserMessageID) else { return }
        fitReserveSpacer(keepingOffsetY: pinnedOffsetY + min(
            pinnedOffsetBeforeResize.offsetFromPin,
            pinnedOffsetBeforeResize.maxOffsetFromPin
        ))
        guard let fittedPinnedOffsetY = self.pinnedOffsetY(for: pinnedUserMessageID) else { return }
        let correctedOffsetY = clampedContentOffsetY(fittedPinnedOffsetY + pinnedOffsetBeforeResize.offsetFromPin)
        if abs(collectionView.contentOffset.y - correctedOffsetY) > 0.5 {
            collectionView.contentOffset.y = correctedOffsetY
        }
    }

    private func rememberPinnedPosition() {
        guard view.bounds.size == lastLayoutViewSize,
              collectionView.adjustedContentInset == lastLayoutAdjustedContentInset,
              !isResizingStreamingRow,
              let pinnedUserMessageID,
              let pinnedY = pinnedOffsetY(for: pinnedUserMessageID) else { return }
        lastPinnedPosition = (
            messageID: pinnedUserMessageID,
            offsetFromPin: collectionView.contentOffset.y - pinnedY,
            maxOffsetFromPin: maxContentOffsetY - pinnedY
        )
    }

    private func applyReserveSpacerHeight(_ height: CGFloat, preservingOffset: Bool = false) {
        let clamped = height < 0.5 ? 0 : height
        guard abs(reserveSpacerHeight - clamped) > 0.5 else { return }

        let update = {
            let adjustment = clamped - self.reserveSpacerHeight
            self.reserveSpacerHeight = clamped
            // Scrollable padding is independent of row sizing. Resizing a spacer item repeatedly
            // invalidates historical table measurements and can create a self-sizing feedback loop.
            self.collectionView.contentInset.bottom += adjustment
            if preservingOffset {
                self.collectionView.layoutIfNeeded()
            }
        }

        if preservingOffset {
            preservingTopVisibleRow(update)
        } else {
            update()
        }
    }

    private func preservingTopVisibleRow(
        anchor cachedAnchor: (itemID: AgentItemID, minY: CGFloat, offsetY: CGFloat)? = nil,
        fittingReserveSpacer: Bool = false,
        _ body: () -> Void
    ) {
        guard !isPreservingVisibleRow else {
            body()
            return
        }
        isPreservingVisibleRow = true
        defer {
            isPreservingVisibleRow = false
            lastVisibleRowAnchor = topVisibleRowAnchor()
        }
        let anchor = cachedAnchor ?? topVisibleRowAnchor()
        let maxOffsetYBefore = maxContentOffsetY
        body()
        guard let anchor,
              let indexPath = messageIndexPath(for: anchor.itemID),
              let frameAfter = collectionView.layoutAttributesForItem(at: indexPath)?.frame else {
            return
        }
        var shift = frameAfter.minY - anchor.minY
        if fittingReserveSpacer {
            fitReserveSpacer(keepingOffsetY: min(anchor.offsetY, maxOffsetYBefore) + shift)
            shift = (collectionView.layoutAttributesForItem(at: indexPath)?.frame.minY ?? frameAfter.minY) - anchor.minY
        }
        // Keep UIKit's overscroll and deceleration when no row has moved.
        guard abs(shift) > 0.5 || abs(collectionView.contentOffset.y - anchor.offsetY) > 0.5 else { return }
        let corrected = clampedContentOffsetY(anchor.offsetY + shift)
        if abs(collectionView.contentOffset.y - corrected) > 0.5 {
            collectionView.contentOffset.y = corrected
        }
    }

    private func topVisibleRowAnchor() -> (itemID: AgentItemID, minY: CGFloat, offsetY: CGFloat)? {
        let offsetY = collectionView.contentOffset.y
        // Older visible answers can change height during hydration; keep the sent question in place when it is visible.
        if let pinnedUserMessageID,
           let indexPath = messageIndexPath(for: pinnedUserMessageID),
           let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame,
           frame.intersects(visibleContentRect()) {
            return (pinnedUserMessageID, frame.minY, offsetY)
        }
        guard let anchor = collectionView.indexPathsForVisibleItems
            .compactMap({ indexPath -> (itemID: AgentItemID, frame: CGRect)? in
                guard let itemID = messageItemID(at: indexPath),
                      case .message(let message)? = model.item(for: itemID),
                      message.role != .system,
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return nil }
                return (itemID: itemID, frame: attributes.frame)
            })
            .filter({ $0.frame.maxY > offsetY })
            .min(by: { $0.frame.minY < $1.frame.minY }) else {
            return nil
        }
        return (anchor.itemID, anchor.frame.minY, offsetY)
    }

    private func paginationAnchor() -> PaginationAnchor? {
        guard let indexPath = collectionView.indexPathsForVisibleItems
            .filter({ indexPath in
                guard let itemID = messageItemID(at: indexPath),
                      let item = model.item(for: itemID),
                      case .message(let message) = item else { return false }
                return message.role != .system
            })
            .min(),
              let itemID = messageItemID(at: indexPath),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else {
            return nil
        }
        return PaginationAnchor(
            itemID: itemID,
            minY: frame.minY,
            offsetY: collectionView.contentOffset.y
        )
    }

    private func restorePaginationAnchor(_ anchor: PaginationAnchor) {
        collectionView.layoutIfNeeded()
        guard let indexPath = messageIndexPath(for: anchor.itemID),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
        collectionView.contentOffset.y = clampedContentOffsetY(
            anchor.offsetY + frame.minY - anchor.minY
        )
    }

    private var maxContentOffsetY: CGFloat {
        let minY = -collectionView.adjustedContentInset.top
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        return max(minY, contentHeight - collectionView.bounds.height + collectionView.adjustedContentInset.bottom)
    }

    private func clampedContentOffsetY(_ rawY: CGFloat) -> CGFloat {
        min(max(rawY, -collectionView.adjustedContentInset.top), maxContentOffsetY)
    }

    private func trimReserveSpacerPreservingOffset() {
        collectionView.layoutIfNeeded()
        let offsetY = collectionView.contentOffset.y
        let isScrolledToTop = offsetY <= -collectionView.adjustedContentInset.top + 0.5
        preservingTopVisibleRow {
            fitReserveSpacer(keepingOffsetY: isScrolledToTop ? nil : offsetY)
        }
    }

    private var lastTypingIndicatorID: AgentItemID? {
        for itemID in model.itemIDs.reversed() {
            guard let item = model.item(for: itemID), case .typingIndicator = item else { continue }
            return itemID
        }
        return nil
    }

    private var lastStreamingAssistantID: AgentItemID? {
        for itemID in model.itemIDs.reversed() {
            guard let item = model.item(for: itemID),
                  case .message(let message) = item,
                  message.role == .assistant,
                  message.isStreaming else {
                continue
            }
            return itemID
        }
        return nil
    }

    private func visibleContentRect() -> CGRect {
        var insets = collectionView.adjustedContentInset
        insets.bottom = occlusionBottomInset
        return CGRect(
            x: collectionView.contentOffset.x + insets.left,
            y: collectionView.contentOffset.y + insets.top,
            width: collectionView.bounds.width - insets.left - insets.right,
            height: collectionView.bounds.height - insets.top - insets.bottom
        )
    }

    private func revealTypingIndicatorIfNeeded() {
        guard pinnedUserMessageID == nil,
              let typingID = lastTypingIndicatorID,
              let indexPath = messageIndexPath(for: typingID) else {
            return
        }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }

        let visible = visibleContentRect()
        let frame = attributes.frame
        if frame.minY >= visible.minY - 0.5, frame.maxY <= visible.maxY + 0.5 {
            return
        }
        if visible.intersects(frame.insetBy(dx: 0, dy: 1)) {
            return
        }

        var targetOffsetY = collectionView.contentOffset.y
        if frame.maxY > visible.maxY {
            targetOffsetY += frame.maxY - visible.maxY
        } else if frame.minY < visible.minY {
            targetOffsetY += frame.minY - visible.minY
        }
        targetOffsetY = clampedContentOffsetY(targetOffsetY)
        guard abs(targetOffsetY - collectionView.contentOffset.y) > 0.5 else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: targetOffsetY),
            animated: true
        )
    }

    @discardableResult
    private func updateVisibleCell(itemID: AgentItemID, preparedCell: AgentMessageCell? = nil) -> Bool {
        guard let item = model.item(for: itemID),
              case .message(let message) = item,
              message.role == .assistant,
              let indexPath = messageIndexPath(for: itemID),
              let cell = preparedCell ?? collectionView.cellForItem(at: indexPath) as? AgentMessageCell else {
            return false
        }
        cell.onPreferredHeightChanged = { [weak self] _ in
            self?.handleStreamingCellHeightChanged(itemID: itemID)
        }
        cell.onStreamingRevealCompleted = { [weak self] in
            self?.handleStreamingRevealCompleted(itemID: itemID)
        }
        if message.isStreaming {
            cell.updateStreamingMessage(message)
        } else {
            cell.configure(
                with: message,
                onURLTap: { [weak self] url in self?.openMessageURL(url, renderingPolicy: message.renderingPolicy) },
                onControlTap: { [weak self] controlID in
                    self?.model.performControl(messageID: message.id, controlID: controlID)
                }
            )
        }
        return true
    }

    private func resizeStreamingRow() {
        guard !isResizingStreamingRow else { return }
        if collectionView.isPreservingLayout {
            // Refreshing a prefetched streaming cell in willDisplay must not begin a batch
            // update while UICollectionView is still updating its visible cells.
            guard !isStreamingRowResizeScheduled else { return }
            isStreamingRowResizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isStreamingRowResizeScheduled = false
                self.resizeStreamingRow()
            }
            return
        }
        isResizingStreamingRow = true
        defer { isResizingStreamingRow = false }

        let batchUpdate = {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates(nil)
            }
        }
        if reserveSpacerHeight > 0 || pinnedUserMessageID != nil {
            preservingTopVisibleRow(fittingReserveSpacer: true, batchUpdate)
        } else {
            batchUpdate()
        }
        lastKnownNearBottom = isNearBottom()
    }

    private func isRevealingStreamedText(itemID: AgentItemID) -> Bool {
        guard let indexPath = messageIndexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell else { return false }
        return cell.isRevealingStreamedText
    }

    private func handleStreamingCellHeightChanged(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard messageIndexPath(for: itemID) != nil else { return }
        wasNearBottomBeforeRowResize = isNearBottom()
        resizeStreamingRow()
    }

    private func handleStreamingRevealCompleted(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard reserveSpacerHeight > 0 || pinnedUserMessageID != nil else { return }
        trimArrivalSpacerIfNeeded()
        if pinnedUserMessageID == nil, wasNearBottomBeforeRowResize {
            revealLastItemIfNeeded(animated: false)
            updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    private func trimArrivalSpacerIfNeeded() {
        guard reserveSpacerHeight > 0 else { return }
        resizeStreamingRow()
        trimReserveSpacerPreservingOffset()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func revealLastItemSettlingRowHeights() {
        for _ in 0..<3 {
            let offsetY = collectionView.contentOffset.y
            revealLastItemIfNeeded(animated: false)
            collectionView.layoutIfNeeded()
            guard abs(collectionView.contentOffset.y - offsetY) > 0.5 else { return }
        }
    }

    private func performInitialScrollIfNeeded() {
        guard !hasPerformedInitialScroll, canResolveBottomLayoutState, lastItemIndexPath != nil else { return }
        hasPerformedInitialScroll = true
        if pinnedUserMessageID == nil {
            revealLastItemSettlingRowHeights()
        }
    }

    private func revealLastItemIfNeeded(animated: Bool) {
        guard let indexPath = lastItemIndexPath else { return }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let visibleBottom = collectionView.contentOffset.y
            + collectionView.bounds.height
            - occlusionBottomInset
        guard attributes.frame.maxY > visibleBottom + 0.5 else { return }
        scrollToBottom(of: indexPath, animated: animated)
    }

    // Reserve space extends the scroll range; it does not cover any part of the viewport.
    var occlusionBottomInset: CGFloat {
        collectionView.adjustedContentInset.bottom - reserveSpacerHeight
    }

    private func scrollToBottom(of indexPath: IndexPath, animated: Bool) {
        guard let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else { return }
        let offsetY = clampedContentOffsetY(frame.maxY - collectionView.bounds.height + occlusionBottomInset)
        if animated {
            collectionView.isScrollingToLatest = true
            UIView.animate(
                withDuration: AgentVCLayout.sentUserMessageRevealDuration,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.collectionView.contentOffset.y = offsetY
                self.revealLastItemSettlingRowHeights()
            } completion: { [weak self] finished in
                guard let self, finished, self.collectionView.isScrollingToLatest else { return }
                self.collectionView.isScrollingToLatest = false
                self.lastVisibleRowAnchor = self.topVisibleRowAnchor()
                self.revealLastItemSettlingRowHeights()
                self.updateScrollToBottomButtonVisibility(animated: false)
            }
        } else {
            collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: offsetY), animated: false)
        }
    }

    private var canResolveBottomLayoutState: Bool {
        view.window != nil
            && collectionView.bounds.width > 0
            && collectionView.bounds.height > 0
            && composerView.inputBackgroundFrame.width > 0
            && composerView.inputBackgroundFrame.height > 0
    }

    private func isNearBottom() -> Bool {
        guard collectionView.bounds.height > 0,
              let indexPath = lastItemIndexPath,
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            return true
        }
        let visibleBottom = collectionView.contentOffset.y
            + collectionView.bounds.height
            - occlusionBottomInset
        return attributes.frame.maxY <= visibleBottom + AgentVCLayout.nearBottomThreshold
    }

    private func updateScrollToBottomButtonVisibility(animated: Bool) {
        scrollToBottomButton.setButtonVisible(!isNearBottom(), animated: animated)
    }

    private func sendCurrentMessage() {
        let source = pendingEntryPointRequest?.entryPoint.map(AgentBackendSendSource.entryPoint) ?? .composer
        let wasEditingMessage = editingMessageID != nil
        let canSend = model.canSendMessage(draftText: composerView.draftText)
        sendMessage(
            text: composerView.draftText,
            clearsComposerDraft: true,
            editingMessageID: editingMessageID,
            source: source
        )
        if canSend, !wasEditingMessage {
            pendingEntryPointRequest = nil
        }
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

    private func openMessageURL(_ url: URL, renderingPolicy: AgentMessageRenderingPolicy) {
        guard renderingPolicy == .agentV2Safe else {
            openURL(url)
            return
        }
        openAnswerLink(url)
    }

    /// Opens a link of an Agent V2 answer. A link to a screen of the app runs as its deeplink; any other link never
    /// does, so a universal link of the app opens its page in the browser instead of starting an in-app flow.
    private func openAnswerLink(_ url: URL) {
        view.endEditing(true)
        guard AgentTextLinks.isOpenable(url) else {
            log.error("unsupported agent answer url=\(url.absoluteString, .public)")
            AppActions.showError(error: DisplayError(text: lang("Unsupported link")))
            return
        }
        if AgentTextLinks.isAppScreenLink(url) {
            if WalletContextManager.delegate?.handleDeeplink(url: url) != true {
                log.error("unhandled agent answer deeplink url=\(url.absoluteString, .public)")
                AppActions.showError(error: DisplayError(text: lang("Unsupported link")))
            }
        } else if url.isTelegramURL {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else {
            AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
        }
    }

    private func openURL(_ url: URL) {
        view.endEditing(true)
        let deeplinkHandled = WalletContextManager.delegate?.handleDeeplink(url: url) ?? false
        guard !deeplinkHandled else { return }

        if url.isTelegramURL {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
        } else {
            log.error("unsupported agent url=\(url.absoluteString, .public)")
            AppActions.showError(error: DisplayError(text: lang("Unsupported link")))
        }
    }

    private func updateSendButtonState() {
        composerView.setSendEnabled(model.canSendMessage(draftText: composerView.draftText))
    }

    private func updateHintsView(animated: Bool) {
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
        guard message.role == .user else { return }
        editingMessageID = message.id
        composerView.setDraftText(message.text, focus: true)
        updateSendButtonState()
    }

    private func clearChat() {
        guard model.canClearChat else { return }
        guard model.shouldConfirmChatClear else {
            performClearChat()
            return
        }
        let alert = UIAlertController(
            title: lang("Clear Chat"),
            message: lang("This action cannot be undone."),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: lang("Clear"), style: .destructive) { [weak self] _ in
            self?.performClearChat()
        })
        present(alert, animated: true)
    }

    private func performClearChat() {
        guard model.canClearChat else { return }
        view.endEditing(true)
        editingMessageID = nil
        pinnedUserMessageID = nil
        applyReserveSpacerHeight(0)
        model.clearChat()
    }

    /// Opens the report form; after a failed send it opens again with the `failedComment` the user wrote
    private func reportProblem(messageID: AgentItemID?, failedComment: String? = nil) {
        guard model.canReportProblem else { return }
        let alert = UIAlertController(
            title: lang("Report a Problem"),
            message: lang(failedComment == nil ? "$agent_report_problem_description" : "$agent_report_problem_failed"),
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] textField in
            textField.placeholder = lang("Optional")
            textField.text = failedComment
            textField.delegate = self
        }
        alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel))
        let sendAction = UIAlertAction(title: lang("Send"), style: .default) { [weak self, unowned alert] _ in
            self?.sendProblemReport(messageID: messageID, comment: alert.textFields![0].text)
        }
        alert.addAction(sendAction)
        alert.preferredAction = sendAction
        present(alert, animated: true)
    }

    private func sendProblemReport(messageID: AgentItemID?, comment: String?) {
        Task { [weak self, model] in
            if await model.reportProblem(messageID: messageID, comment: comment) {
                AppActions.showToast(message: lang("$agent_report_problem_sent"))
            } else if let self, self.model.canReportProblem,
                      self.viewIfLoaded?.window != nil, self.presentedViewController == nil {
                // A failed report opens again with its comment while the user is still on this screen and can report
                self.reportProblem(messageID: messageID, failedComment: comment ?? "")
            } else {
                AppActions.showError(error: DisplayError(text: lang("$agent_report_problem_failed")))
            }
        }
    }

    private func submitPendingEntryPointQueryIfPossible() {
        guard model.isActive, canResolveBottomLayoutState else { return }
        capturePendingEntryPointRequestIfNeeded()
        guard let request = pendingEntryPointRequest,
              let query = request.query,
              model.canSendMessage(draftText: query) else { return }
        pendingEntryPointRequest = nil
        let source = request.entryPoint.map(AgentBackendSendSource.entryPoint) ?? .composer
        sendMessage(text: query, clearsComposerDraft: false, editingMessageID: nil, source: source)
        capturePendingEntryPointRequestIfNeeded()
    }

    private func capturePendingEntryPointRequestIfNeeded() {
        guard pendingEntryPointRequest == nil else { return }
        pendingEntryPointRequest = AgentEntryPoint.consumePendingRequest()
    }

    private func loadOlderMessagesIfNeeded() {
        guard hasPerformedInitialScroll,
              paginationTask == nil,
              collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 120,
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
                  !self.didStopModel,
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

    private func finishPaginationIfReady(operationID: UUID) {
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

    private func typingStatusText() -> String? {
        let statusText = model.typingIndicatorStatusText
        guard statusText != shownTypingStatusText else { return statusText }
        let remainingDuration = AgentVCLayout.minimumTypingStatusDuration - (CACurrentMediaTime() - typingStatusShownAt)
        if shownTypingStatusText != nil, remainingDuration > 0 {
            scheduleTypingStatusUpdate(after: remainingDuration)
            return shownTypingStatusText
        }
        shownTypingStatusText = statusText
        typingStatusShownAt = CACurrentMediaTime()
        return statusText
    }

    private func scheduleTypingStatusUpdate(after delay: TimeInterval) {
        guard pendingTypingStatusUpdate == nil else { return }
        let update = DispatchWorkItem { [weak self] in
            self?.pendingTypingStatusUpdate = nil
            self?.updateVisibleTypingIndicator()
        }
        pendingTypingStatusUpdate = update
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: update)
    }

    private func updateVisibleTypingIndicator() {
        guard let typingID = lastTypingIndicatorID,
              let indexPath = messageIndexPath(for: typingID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentTypingIndicatorCell else { return }
        let wasNearBottom = isNearBottom()
        let statusChanged = cell.configure(
            statusText: typingStatusText(),
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

    private func updateAccessibilityStatus() {
        guard model.isActive, viewIfLoaded?.window != nil else { return }
        let status = model.accessibilityStatus
        guard status != lastAccessibilityStatus else { return }
        lastAccessibilityStatus = status
        guard let status else { return }
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func stopModelIfNeeded() {
        guard !didStopModel else { return }
        didStopModel = true
        paginationTask?.cancel()
        paginationTask = nil
        paginationOperationID = nil
        requiredPaginationReloadGeneration = nil
        model.stop()
    }

    private func copyText(for itemID: AgentItemID) -> String? {
        if let indexPath = messageIndexPath(for: itemID),
           let cell = collectionView.cellForItem(at: indexPath) as? AgentContextMenuPresentingCell,
           let text = cell.contextMenuCopyText {
            return text
        }

        guard let item = model.item(for: itemID),
              case .message(let message) = item else {
            return nil
        }

        var parts: [String] = []
        if !message.text.isEmpty {
            parts.append(message.text)
        }
        if let supplementaryErrorText = message.supplementaryErrorText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !supplementaryErrorText.isEmpty {
            parts.append(supplementaryErrorText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private func contextMenuPreview(for itemID: AgentItemID) -> UITargetedPreview? {
        guard let indexPath = messageIndexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentContextMenuPresentingCell else {
            return nil
        }
        return cell.contextMenuPreview()
    }

    private var lastItemIndexPath: IndexPath? {
        guard collectionView.numberOfSections > 0 else { return nil }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        return itemCount > 1 ? IndexPath(item: itemCount - 2, section: 0) : nil
    }

    private func itemID(from configuration: UIContextMenuConfiguration) -> AgentItemID? {
        guard let identifier = configuration.identifier as? NSUUID else { return nil }
        return UUID(uuidString: identifier.uuidString)
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

    @objc private func handlePendingEntryPointRequest() {
        guard model.isActive, viewIfLoaded?.window != nil else { return }
        capturePendingEntryPointRequestIfNeeded()
        submitPendingEntryPointQueryIfPossible()
    }

    @objc private func scrollToBottomButtonPressed() {
        guard let indexPath = lastItemIndexPath else { return }
        scrollToBottom(of: indexPath, animated: true)
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

extension AgentVC: AgentModelDelegate {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID]) {
        streamingItemIDs.removeAll(keepingCapacity: true)
        updateStreamingState(for: model.itemIDs)
        deferredStreamingItemIDs.formIntersection(model.itemIDs)
        updateHintsView(animated: false)

        if paginationTask != nil {
            let paginationAnchor = paginationAnchor()
            paginationReloadGeneration += 1
            let reloadGeneration = paginationReloadGeneration
            let operationID = paginationOperationID
            applySnapshot(animated: false, reconfigureItemIDs: reconfigureItemIDs) { [weak self] in
                guard let self else { return }
                if let paginationAnchor {
                    self.restorePaginationAnchor(paginationAnchor)
                }
                self.lastKnownNearBottom = self.isNearBottom()
                self.updateScrollToBottomButtonVisibility(animated: false)
                guard let operationID, self.paginationOperationID == operationID else { return }
                self.completedPaginationReloadGeneration = max(
                    self.completedPaginationReloadGeneration,
                    reloadGeneration
                )
                self.finishPaginationIfReady(operationID: operationID)
            }
            return
        }

        let hasStreaming = lastStreamingAssistantID != nil
        let crossfade = hasStreaming
        if let pinnedUserMessageID, !model.itemIDs.contains(pinnedUserMessageID) {
            self.pinnedUserMessageID = nil
        }
        let sentUserMessageID = hasStreaming ? nil : appendedUserMessageID()
        revealsSentMessageFromBottom = sentUserMessageID != nil && lastKnownNearBottom
        if let sentUserMessageID {
            pinnedUserMessageID = sentUserMessageID
        }

        let didApplyTimeline: () -> Void = { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()

            self.performInitialScrollIfNeeded()

            if hasStreaming {
                self.resizeStreamingRow()
                return
            }

            if self.lastTypingIndicatorID != nil {
                self.revealTypingIndicatorIfNeeded()
            } else {
                self.trimReserveSpacerPreservingOffset()
            }
            self.lastKnownNearBottom = self.isNearBottom()
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
        let applyTimeline = {
            self.applySnapshot(
                animated: false,
                reconfigureItemIDs: reconfigureItemIDs,
                crossfade: crossfade,
                completion: didApplyTimeline
            )
        }
        if pinnedUserMessageID != nil {
            preservingTopVisibleRow(fittingReserveSpacer: true, applyTimeline)
        } else {
            applyTimeline()
        }
    }

    private func appendedUserMessageID() -> AgentItemID? {
        let itemIDs = model.itemIDs
        guard let lastSnapshotIndexPath = lastItemIndexPath,
              itemIDs.count > lastSnapshotIndexPath.item + 1,
              messageItemID(at: lastSnapshotIndexPath) == itemIDs[lastSnapshotIndexPath.item],
              let lastItemID = itemIDs.last,
              case .message(let message)? = model.item(for: lastItemID),
              message.role == .user else { return nil }
        return lastItemID
    }

    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {
        updateStreamingState(for: ids)
        let isStreamingUpdate = ids.contains { streamingItemIDs.contains($0) }
        if isStreamingUpdate, ids.count == 1, let itemID = ids.first,
           let indexPath = messageIndexPath(for: itemID) {
            if collectionView.indexPathsForVisibleItems.contains(indexPath), updateVisibleCell(itemID: itemID) {
                deferredStreamingItemIDs.remove(itemID)
            } else {
                // A prefetched cell can survive offscreen; refresh it when it is actually displayed.
                deferredStreamingItemIDs.insert(itemID)
            }
            // The reveal callback resizes the row when its displayed size changes, independently of network chunks.
            return
        }
        deferredStreamingItemIDs.subtract(ids)
        let isStreamingFinalize = ids.contains { itemID in
            guard let item = model.item(for: itemID),
                  case .message(let message) = item else {
                return false
            }
            return message.role == .assistant && !message.isStreaming
        }
        let preservesBottomAfterFinalResize = isStreamingFinalize
            && pinnedUserMessageID == nil
            && !hasActiveStreamingMessage
            && isNearBottom()

        if (isStreamingUpdate || isStreamingFinalize),
           ids.count == 1,
           let itemID = ids.first,
           updateVisibleCell(itemID: itemID) {
            resizeStreamingRow()
            if preservesBottomAfterFinalResize {
                revealLastItemIfNeeded(animated: !isRevealingStreamedText(itemID: itemID))
            }
            updateScrollToBottomButtonVisibility(animated: true)
            return
        }

        let existingIDs = Set(snapshotMessageIDs())
        let idsToReload = ids.filter { existingIDs.contains($0) }
        guard !idsToReload.isEmpty else { return }

        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(idsToReload.map { .message($0) })
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self else { return }
            if isStreamingUpdate || self.hasActiveStreamingMessage || isStreamingFinalize {
                self.resizeStreamingRow()
            }
            if preservesBottomAfterFinalResize {
                self.revealLastItemIfNeeded(animated: !idsToReload.contains { self.isRevealingStreamedText(itemID: $0) })
            }
            if !isStreamingUpdate && !isStreamingFinalize && !self.hasActiveStreamingMessage {
                self.trimReserveSpacerPreservingOffset()
            }
            self.updateScrollToBottomButtonVisibility(animated: true)
        }
    }

    func agentModelDidUpdateHints(animated: Bool) {
        updateHintsView(animated: animated)
    }

    func agentModelDidUpdateState() {
        updateSendButtonState()
        refreshNavigationItemMenu()
        updateVisibleTypingIndicator()
        updateAccessibilityStatus()
        submitPendingEntryPointQueryIfPossible()
    }

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
        collectionView.isScrollingToLatest = false
        isRevealingSentUserMessage = true
        pinnedUserMessageID = userMessageID
        let finish: () -> Void = { [weak self] in
            self?.isRevealingSentUserMessage = false
            completion()
        }

        if revealsSentMessageFromBottom {
            revealLastItemSettlingRowHeights()
        } else {
            collectionView.layoutIfNeeded()
        }
        revealsSentMessageFromBottom = false
        applyMinimalArrivalReserveSpacerHeight(for: userMessageID)
        collectionView.layoutIfNeeded()
        guard let indexPath = messageIndexPath(for: userMessageID),
              let targetOffsetY = pinnedOffsetY(for: userMessageID) else {
            staggerTypingIndicatorReveal(then: finish)
            return
        }
        let clampedOffsetY = clampedContentOffsetY(targetOffsetY)

        guard abs(clampedOffsetY - collectionView.contentOffset.y) > 0.5 else {
            animateSentUserMessageFlyUp(at: indexPath, then: finish)
            return
        }

        UIView.animate(
            withDuration: AgentVCLayout.sentUserMessageRevealDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.collectionView.contentOffset.y = clampedOffsetY
        } completion: { _ in
            finish()
        }
    }

    private func animateSentUserMessageFlyUp(at indexPath: IndexPath, then completion: @escaping () -> Void) {
        guard let cell = collectionView.cellForItem(at: indexPath),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            staggerTypingIndicatorReveal(then: completion)
            return
        }
        let visible = visibleContentRect()
        let startTranslation = max(0, visible.maxY - attributes.frame.minY)
        guard startTranslation > 1 else {
            staggerTypingIndicatorReveal(then: completion)
            return
        }
        cell.transform = CGAffineTransform(translationX: 0, y: startTranslation)
        cell.alpha = 0
        UIView.animate(
            withDuration: AgentVCLayout.sentUserMessageFlyUpDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            cell.transform = .identity
            cell.alpha = 1
        } completion: { _ in
            cell.transform = .identity
            cell.alpha = 1
            completion()
        }
    }

    private func staggerTypingIndicatorReveal(then completion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + AgentVCLayout.typingIndicatorRevealGap) {
            completion()
        }
    }
}

extension AgentVC: UICollectionViewDelegate, UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTouchInsideControl(touch.view)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard collectionView === self.collectionView,
              let itemID = messageItemID(at: indexPath),
              let item = model.item(for: itemID),
              case .message = item else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: itemID as NSUUID, previewProvider: nil) { [weak self] _ in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else {
                return nil
            }

            var children: [UIMenuElement] = []

            if let copyText = self.copyText(for: itemID) {
                children.append(
                    UIAction(title: lang("Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
                        UIPasteboard.general.string = copyText
                    }
                )
            }

            if message.role == .user {
                children.append(
                    UIAction(title: lang("Edit"), image: UIImage(systemName: "pencil")) { [weak self] _ in
                        self?.editMessage(message)
                    }
                )
            }

            // An answer still being written has no stored message to report yet
            if message.role == .assistant, !message.isStreaming, self.model.canReportProblem {
                children.append(
                    UIAction(title: lang("Report a Problem"), image: UIImage(systemName: "flag")) { [weak self] _ in
                        self?.reportProblem(messageID: itemID)
                    }
                )
            }

            return children.isEmpty ? nil : UIMenu(children: children)
        }
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard collectionView === self.collectionView,
              let itemID = itemID(from: configuration) else {
            return nil
        }
        return contextMenuPreview(for: itemID)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        guard collectionView === self.collectionView,
              let itemID = itemID(from: configuration) else {
            return nil
        }
        return contextMenuPreview(for: itemID)
    }

    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard collectionView === self.collectionView,
              let itemID = messageItemID(at: indexPath),
              deferredStreamingItemIDs.remove(itemID) != nil,
              let cell = cell as? AgentMessageCell else { return }
        updateVisibleCell(itemID: itemID, preparedCell: cell)
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
        scrollToBottomButton.setButtonVisible(!lastKnownNearBottom, animated: true)
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
    }
}

extension AgentVC: UITextFieldDelegate {
    public func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        let length = (textField.text ?? "").utf16.count - range.length + string.utf16.count
        return length <= problemReportCommentMaxLength
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

    let agentNavigationController = UINavigationController(rootViewController: AgentEntryPoint.makeRootViewController())
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
