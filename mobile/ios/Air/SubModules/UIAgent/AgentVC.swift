import UIKit
import UIComponents
import WalletContext
import WalletCore

private let log = Log("AgentVC")

private enum AgentVCLayout {
    static let maxContentWidth = AgentContentLayout.maxContentWidth
    static let bottomMessageSpacing: CGFloat = 16
    static let hintsSpacingToMessages: CGFloat = 17
    static let hintsSpacingToComposer: CGFloat = 26
    static let hintsRowHeight: CGFloat = 66
    static let hintsContainerHeight = hintsSpacingToMessages + hintsRowHeight
    static let nearBottomThreshold: CGFloat = 60
    static let composerResizeAnimationDuration: TimeInterval = 0.2
    static let bottomAlignmentAnimationDuration: TimeInterval = 0.25
    static let arrivalUserMessageTailInset: CGFloat = 100
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

@MainActor
extension AgentBackendKind {
    var isAvailable: Bool {
        switch self {
        case .testing:
            #if DEBUG
            true
            #else
            false
            #endif
        case .real:
            true
        case .local, .hybrid:
            AgentStore.shared.isLocalBackendAvailable
        }
    }
    
    static var preferredKind: AgentBackendKind {
        switch ConfigStore.shared.preferredAgent {
        case .local:
            return AgentStore.shared.isLocalBackendAvailable ? .local : .real
        case .hybrid:
            return AgentStore.shared.isLocalBackendAvailable ? .hybrid : .real
        case .online:
            return .real
        }
    }
}

public final class AgentVC: WViewController {
    private enum Section: Hashable {
        case main
    }

    private enum ListItemID: Hashable {
        case message(AgentItemID)
        case bottomSpacer
    }

    private let model: AgentModel
    private let collectionView: UICollectionView = {
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

        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    
    private lazy var dataSource = makeDataSource()

    private let contentLayoutGuide = UILayoutGuide()
    private let hintsContainerView = AgentPassthroughContainerView()
    private let hintsSectionView = AgentHintsSectionView()
    private let composerView = AgentComposerView()
    private let scrollToBottomButton = AgentScrollToBottomButton()
    private lazy var contentLayoutGuideWidthConstraint: NSLayoutConstraint = {
        let constraint = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }()
    private lazy var contentLayoutGuideMaxWidthConstraint = contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentVCLayout.maxContentWidth)
    private lazy var hintsContainerHeightConstraint = hintsContainerView.heightAnchor.constraint(equalToConstant: AgentVCLayout.hintsContainerHeight)
    private lazy var scrollToBottomButtonBottomToComposerConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -16)
    private lazy var scrollToBottomButtonBottomToHintsConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: hintsContainerView.topAnchor, constant: -16)

    private var hasPerformedInitialScroll = false
    private var lastKnownNearBottom = true
    private var editingMessageID: AgentItemID?
    private var isArrivalScrollInFlight = false
    private var isRevealingSentUserMessage = false
    private var isResizingStreamingRow = false
    private var reserveSpacerHeight: CGFloat = 0
    private var arrivalAnchorUserMessageID: AgentItemID?
    private var pendingArrivalSpacerTrim = false

    private init(backend: AgentBackend) {
        self.model = AgentModel(backend: backend)
        super.init(nibName: nil, bundle: nil)
        title = lang("Agent")
    }

    public convenience init() {
        let backend = AgentModel.makeBackend(kind: AgentBackendKind.preferredKind)
        self.init(backend: backend)
    }

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
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        model.delegate = self
        setupViews()
        setupObservers()
        updateHintsView(animated: false)
        applySnapshot(animated: false)
        updateSendButtonState()
        updateHintsToggleState()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        model.isActive = true
        model.checkAccountChanged(animated: false)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.isActive = false
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateTheme()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard canResolveBottomLayoutState else { return }
        let keepBottomVisible = lastKnownNearBottom && !isArrivalScrollInFlight && !hasActiveStreamingMessage && !isRevealingSentUserMessage
        updateOcclusionInsets()
        if keepBottomVisible {
            revealLastItemIfNeeded(animated: false)
        }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func updateTheme() {
        view.backgroundColor = .air.background
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
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
    }

    public func switchBackend(to backendKind: AgentBackendKind, animated: Bool = true) {
        let backend = AgentModel.makeBackend(kind: backendKind)
        model.switchBackend(to: backend, animated: animated)
        refreshNavigationItemMenu()
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
        composerView.onHintsToggle = { [weak self] in
            self?.toggleHintsVisibility()
        }
        composerView.onLayoutHeightChanged = { [weak self] in
            self?.view.setNeedsLayout()
        }

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

            scrollToBottomButton.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
            scrollToBottomButtonBottomToComposerConstraint,
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 44),
            scrollToBottomButton.heightAnchor.constraint(equalTo: scrollToBottomButton.widthAnchor),

            hintsContainerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            hintsContainerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            hintsContainerView.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -AgentVCLayout.hintsSpacingToComposer),
            hintsContainerHeightConstraint,

            hintsSectionView.leadingAnchor.constraint(equalTo: hintsContainerView.leadingAnchor),
            hintsSectionView.trailingAnchor.constraint(equalTo: hintsContainerView.trailingAnchor),
            hintsSectionView.bottomAnchor.constraint(equalTo: hintsContainerView.bottomAnchor),
            hintsSectionView.heightAnchor.constraint(equalToConstant: AgentVCLayout.hintsRowHeight),

            composerView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            composerView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            keyboardConstraint,
            fallbackConstraint
        ])

        view.backgroundColor = .air.background
        addCustomNavigationBarBackground(color: .air.background)
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
        var children: [UIMenuElement] = []

        if IS_DEBUG_OR_TESTFLIGHT {
            children.append(makeBackendMenu())
        }
        
        children.append(
            UIAction(title: lang("Clear Chat"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.clearChat()
            }
        )

        return UIMenu(children: children)
    }

    private func makeBackendMenu() -> UIMenu {
        UIMenu(
            title: lang("Backend"),
            image: UIImage(systemName: "server.rack"),
            children: AgentBackendKind.menuOrder.filter(\.isAvailable).map { backendKind in
                let action = UIAction(
                    title: backendKind.menuTitle,
                    state: model.activeBackendKind == backendKind ? .on : .off
                ) { [weak self] _ in
                    self?.switchBackendFromMenu(to: backendKind)
                }
                return action
            }
        )
    }

    private func switchBackendFromMenu(to backendKind: AgentBackendKind) {
        switchBackend(to: backendKind, animated: false)
    }

    private func setupObservers() {
        WalletCoreData.add(eventObserver: self)
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
                onActionTap: { [weak self] in
                    self?.openAction(for: message)
                },
                onURLTap: { [weak self] url in
                    self?.openURL(url)
                }
            )
        }

        let systemRegistration = UICollectionView.CellRegistration<AgentSystemMessageCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else { return }
            cell.configure(with: message)
        }

        let typingRegistration = UICollectionView.CellRegistration<AgentTypingIndicatorCell, AgentItemID> { cell, _, _ in
            cell.configure()
        }

        let spacerRegistration = UICollectionView.CellRegistration<AgentSpacerCell, ListItemID> { [weak self] cell, _, _ in
            cell.heightProvider = { [weak self] in self?.reserveSpacerHeight ?? 0 }
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
        model.itemIDs.contains { itemID in
            guard let item = model.item(for: itemID), case .message(let message) = item else { return false }
            return message.isStreaming
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
        if abs(collectionView.contentInset.bottom - additional) > 0.5 {
            collectionView.contentInset.bottom = additional
        }
        if abs(collectionView.verticalScrollIndicatorInsets.bottom - total) > 0.5 {
            collectionView.verticalScrollIndicatorInsets.bottom = total
        }
    }

    private func applyMinimalArrivalReserveSpacerHeight(for userMessageID: AgentItemID) {
        guard let indexPath = messageIndexPath(for: userMessageID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let top = collectionView.adjustedContentInset.top
        let bottom = collectionView.adjustedContentInset.bottom
        let targetOffsetY = attributes.frame.maxY - top - AgentVCLayout.arrivalUserMessageTailInset
        let contentHeightWithoutSpacer = max(
            0,
            collectionView.collectionViewLayout.collectionViewContentSize.height - reserveSpacerHeight
        )
        let minSpacer = max(
            reserveSpacerHeight,
            max(0, targetOffsetY + collectionView.bounds.height - bottom - contentHeightWithoutSpacer)
        )
        applyReserveSpacerHeight(minSpacer, preservingOffset: true)
    }

    private func applyReserveSpacerHeight(_ height: CGFloat, preservingOffset: Bool = false) {
        let clamped = max(0, height)
        guard abs(reserveSpacerHeight - clamped) > 0.5 else { return }

        let invalidate = {
            self.reserveSpacerHeight = clamped
            let context = UICollectionViewLayoutInvalidationContext()
            if let spacerIndexPath = self.dataSource.indexPath(for: .bottomSpacer) {
                context.invalidateItems(at: [spacerIndexPath])
            }
            self.collectionView.collectionViewLayout.invalidateLayout(with: context)
            if preservingOffset {
                self.collectionView.layoutIfNeeded()
            }
        }

        if preservingOffset {
            preservingTopVisibleRow(invalidate)
        } else {
            invalidate()
        }
    }

    private func preservingTopVisibleRow(_ body: () -> Void) {
        let anchor = topVisibleRowAnchor()
        body()
        guard let anchor,
              let frameAfter = collectionView.layoutAttributesForItem(at: anchor.indexPath)?.frame else {
            return
        }
        let corrected = clampedContentOffsetY(anchor.offsetY + (frameAfter.minY - anchor.minY))
        if abs(collectionView.contentOffset.y - corrected) > 0.5 {
            collectionView.contentOffset.y = corrected
        }
    }

    private func topVisibleRowAnchor() -> (indexPath: IndexPath, minY: CGFloat, offsetY: CGFloat)? {
        guard let indexPath = collectionView.indexPathsForVisibleItems
            .filter({ dataSource.itemIdentifier(for: $0) != .bottomSpacer })
            .min(),
              let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame else {
            return nil
        }
        return (indexPath, frame.minY, collectionView.contentOffset.y)
    }

    private func clampedContentOffsetY(_ rawY: CGFloat) -> CGFloat {
        let top = collectionView.adjustedContentInset.top
        let bottom = collectionView.adjustedContentInset.bottom
        let minY = -top
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let maxY = max(minY, contentHeight - collectionView.bounds.height + bottom)
        return min(max(rawY, minY), maxY)
    }

    private func trimReserveSpacerPreservingOffset() {
        collectionView.layoutIfNeeded()
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let heightWithoutSpacer = max(0, contentHeight - reserveSpacerHeight)
        let top = collectionView.adjustedContentInset.top
        let bottom = collectionView.adjustedContentInset.bottom
        let minY = -top
        let offsetY = collectionView.contentOffset.y
        let maxYWithZero = max(minY, heightWithoutSpacer - collectionView.bounds.height + bottom)
        if offsetY <= maxYWithZero + 0.5 {
            applyReserveSpacerHeight(0, preservingOffset: true)
            return
        }
        let spacerNeeded = offsetY - heightWithoutSpacer + collectionView.bounds.height - bottom
        applyReserveSpacerHeight(max(0, spacerNeeded), preservingOffset: true)
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

    private var lastAssistantReplyID: AgentItemID? {
        for itemID in model.itemIDs.reversed() {
            guard let item = model.item(for: itemID),
                  case .message(let message) = item,
                  message.role == .assistant else {
                continue
            }
            return itemID
        }
        return nil
    }

    private var arrivalUserMessageID: AgentItemID? {
        guard let assistantID = lastStreamingAssistantID,
              let assistantIndex = model.itemIDs.firstIndex(of: assistantID) else {
            return nil
        }
        for itemID in model.itemIDs[..<assistantIndex].reversed() {
            guard let item = model.item(for: itemID),
                  case .message(let message) = item,
                  message.role == .user else {
                continue
            }
            return itemID
        }
        return nil
    }

    private func visibleContentRect() -> CGRect {
        let insets = collectionView.adjustedContentInset
        return CGRect(
            x: collectionView.contentOffset.x + insets.left,
            y: collectionView.contentOffset.y + insets.top,
            width: collectionView.bounds.width - insets.left - insets.right,
            height: collectionView.bounds.height - insets.top - insets.bottom
        )
    }

    private func revealTypingIndicatorIfNeeded() {
        guard let typingID = lastTypingIndicatorID,
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
    private func performArrivalScroll(for userMessageID: AgentItemID) -> Bool {
        guard let indexPath = messageIndexPath(for: userMessageID) else { return false }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return false }

        let top = collectionView.adjustedContentInset.top
        let distanceBelowTop = attributes.frame.maxY - (collectionView.contentOffset.y + top)
        guard distanceBelowTop > AgentVCLayout.arrivalUserMessageTailInset + 0.5 else { return false }

        let targetOffsetY = attributes.frame.maxY - top - AgentVCLayout.arrivalUserMessageTailInset
        let clampedOffsetY = clampedContentOffsetY(targetOffsetY)
        guard abs(clampedOffsetY - collectionView.contentOffset.y) > 0.5 else { return false }

        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: clampedOffsetY),
            animated: true
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.endArrivalScroll()
        }
        return true
    }

    private func endArrivalScroll() {
        guard isArrivalScrollInFlight else { return }
        isArrivalScrollInFlight = false
        renderDeferredReply()
        if pendingArrivalSpacerTrim {
            pendingArrivalSpacerTrim = false
            trimArrivalSpacerIfNeeded()
        }
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func renderDeferredReply() {
        let anchorUserMessageID = arrivalAnchorUserMessageID
        arrivalAnchorUserMessageID = nil

        if let assistantID = lastAssistantReplyID, !updateVisibleCell(itemID: assistantID) {
            let listID = ListItemID.message(assistantID)
            var snapshot = dataSource.snapshot()
            if snapshot.itemIdentifiers.contains(listID) {
                snapshot.reconfigureItems([listID])
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
        resizeStreamingRow()
        repinArrivalOffset(to: anchorUserMessageID)
    }

    private func repinArrivalOffset(to userMessageID: AgentItemID?) {
        guard let userMessageID,
              let indexPath = messageIndexPath(for: userMessageID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let top = collectionView.adjustedContentInset.top
        let desiredOffsetY = clampedContentOffsetY(
            attributes.frame.maxY - top - AgentVCLayout.arrivalUserMessageTailInset
        )
        guard abs(desiredOffsetY - collectionView.contentOffset.y) > 0.5 else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: desiredOffsetY),
            animated: false
        )
    }

    @discardableResult
    private func updateVisibleCell(itemID: AgentItemID) -> Bool {
        guard let item = model.item(for: itemID),
              case .message(let message) = item,
              message.role == .assistant,
              let indexPath = messageIndexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentMessageCell else {
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
                onActionTap: { [weak self] in self?.openAction(for: message) },
                onURLTap: { [weak self] url in self?.openURL(url) }
            )
        }
        return true
    }

    private func resizeStreamingRow() {
        guard !isResizingStreamingRow else { return }
        isResizingStreamingRow = true
        defer { isResizingStreamingRow = false }

        let batchUpdate = {
            UIView.performWithoutAnimation {
                self.collectionView.performBatchUpdates(nil)
            }
        }
        if reserveSpacerHeight > 0 {
            preservingTopVisibleRow(batchUpdate)
        } else {
            batchUpdate()
        }
    }

    private func handleStreamingCellHeightChanged(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard snapshotMessageIDs().contains(itemID) else { return }
        resizeStreamingRow()
    }

    private func handleStreamingRevealCompleted(itemID: AgentItemID) {
        guard model.item(for: itemID) != nil else { return }
        guard reserveSpacerHeight > 0 else { return }
        if isArrivalScrollInFlight {
            pendingArrivalSpacerTrim = true
            return
        }
        trimArrivalSpacerIfNeeded()
    }

    private func trimArrivalSpacerIfNeeded() {
        guard reserveSpacerHeight > 0 else { return }
        resizeStreamingRow()
        trimReserveSpacerPreservingOffset()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func revealLastItemIfNeeded(animated: Bool) {
        guard let indexPath = lastItemIndexPath else { return }
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: indexPath) else { return }
        let visibleBottom = collectionView.contentOffset.y
            + collectionView.bounds.height
            - collectionView.adjustedContentInset.bottom
        guard attributes.frame.maxY > visibleBottom + 0.5 else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: animated)
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
            - collectionView.adjustedContentInset.bottom
        return attributes.frame.maxY <= visibleBottom + AgentVCLayout.nearBottomThreshold
    }

    private func updateScrollToBottomButtonVisibility(animated: Bool) {
        scrollToBottomButton.setVisible(!isNearBottom(), animated: animated)
    }

    private func sendCurrentMessage() {
        sendMessage(
            text: composerView.draftText,
            clearsComposerDraft: true,
            editingMessageID: editingMessageID
        )
    }

    private func sendHint(_ hint: AgentHint) {
        editingMessageID = nil
        sendMessage(text: hint.prompt, clearsComposerDraft: false, editingMessageID: nil)
    }

    private func openAction(for message: AgentMessage) {
        guard let action = message.action else { return }
        openURL(action.url)
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

    private func updateHintsToggleState() {
        composerView.setHintsToggleVisible(
            model.canToggleHintsVisibility,
            isSelected: model.areHintsVisible
        )
    }

    private func updateHintsView(animated: Bool) {
        let visibleHints = model.visibleHints
        let shouldShow = !visibleHints.isEmpty
        let wasShowing = hintsSectionView.alpha > 0.01

        if shouldShow {
            hintsSectionView.configure(with: visibleHints) { [weak self] hint in
                self?.sendHint(hint)
            }
        }

        guard animated, wasShowing != shouldShow else {
            applyHintsPresentation(shouldShow)
            view.setNeedsLayout()
            return
        }

        animateHintsVisibilityChange(to: shouldShow)
    }

    private func sendMessage(text: String?, clearsComposerDraft: Bool, editingMessageID: AgentItemID?) {
        guard model.canSendMessage(draftText: text) else { return }
        
        self.editingMessageID = nil
        model.send(text: text, editingMessageID: editingMessageID)
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
        view.endEditing(true)
        editingMessageID = nil
        isArrivalScrollInFlight = false
        arrivalAnchorUserMessageID = nil
        pendingArrivalSpacerTrim = false
        applyReserveSpacerHeight(0)
        model.clearChat()
    }

    private func toggleHintsVisibility() {
        model.toggleHintsVisibility()
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

        return message.text.isEmpty ? nil : message.text
    }

    private func contextMenuPreview(for itemID: AgentItemID) -> UITargetedPreview? {
        guard let indexPath = messageIndexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentContextMenuPresentingCell else {
            return nil
        }
        return cell.contextMenuPreview()
    }

    private var lastItemIndexPath: IndexPath? {
        guard let lastMessageID = snapshotMessageIDs().last else { return nil }
        return messageIndexPath(for: lastMessageID)
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

    @objc private func scrollToBottomButtonPressed() {
        guard let indexPath = lastItemIndexPath else { return }
        collectionView.scrollToItem(at: indexPath, at: .bottom, animated: true)
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

extension AgentVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(_, _):
            model.handleAccountChangedEvent()
        default:
            break
        }
    }
}

extension AgentVC: AgentModelDelegate {
    func agentModelDidReloadTimeline(animated: Bool, reconfigureItemIDs: [AgentItemID]) {
        updateHintsView(animated: false)
        updateHintsToggleState()

        let hasStreaming = lastStreamingAssistantID != nil
        let crossfade = hasStreaming
        let arrivalUserMessageID = hasStreaming ? self.arrivalUserMessageID : nil
        if arrivalUserMessageID != nil {
            isArrivalScrollInFlight = true
            arrivalAnchorUserMessageID = arrivalUserMessageID
        }

        applySnapshot(animated: false, reconfigureItemIDs: reconfigureItemIDs, crossfade: crossfade) { [weak self] in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()

            if let arrivalUserMessageID {
                self.applyMinimalArrivalReserveSpacerHeight(for: arrivalUserMessageID)
                if !self.performArrivalScroll(for: arrivalUserMessageID) {
                    self.arrivalAnchorUserMessageID = nil
                    self.endArrivalScroll()
                }
                return
            }

            if hasStreaming {
                self.resizeStreamingRow()
                return
            }
            
            if self.lastTypingIndicatorID != nil {
                self.revealTypingIndicatorIfNeeded()
            } else {
                if !self.hasPerformedInitialScroll {
                    self.revealLastItemIfNeeded(animated: false)
                }
                self.trimReserveSpacerPreservingOffset()
            }
            self.hasPerformedInitialScroll = true
            self.lastKnownNearBottom = self.isNearBottom()
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {
        updateHintsToggleState()

        let isStreamingUpdate = ids.contains { itemID in
            guard let item = model.item(for: itemID),
                  case .message(let message) = item else {
                return false
            }
            return message.isStreaming
        }
        let isStreamingFinalize = ids.contains { itemID in
            guard let item = model.item(for: itemID),
                  case .message(let message) = item else {
                return false
            }
            return message.role == .assistant && !message.isStreaming
        }

        if isArrivalScrollInFlight {
            if ids.count == 1, let itemID = ids.first {
                _ = updateVisibleCell(itemID: itemID)
                resizeStreamingRow()
            }
            return
        }

        if (isStreamingUpdate || isStreamingFinalize),
           ids.count == 1,
           let itemID = ids.first,
           updateVisibleCell(itemID: itemID) {
            resizeStreamingRow()
            updateScrollToBottomButtonVisibility(animated: false)
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
            if !isStreamingUpdate && !isStreamingFinalize && !self.hasActiveStreamingMessage {
                self.trimReserveSpacerPreservingOffset()
            }
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    func agentModelDidUpdateHints(animated: Bool) {
        updateHintsView(animated: animated)
        updateHintsToggleState()
    }

    func agentModelWillRevealSentUserMessage(_ userMessageID: AgentItemID, then completion: @escaping () -> Void) {
        isRevealingSentUserMessage = true
        let finish: () -> Void = { [weak self] in
            self?.isRevealingSentUserMessage = false
            completion()
        }

        collectionView.layoutIfNeeded()
        guard let indexPath = messageIndexPath(for: userMessageID),
              let attributes = collectionView.layoutAttributesForItem(at: indexPath) else {
            staggerTypingIndicatorReveal(then: finish)
            return
        }

        let top = collectionView.adjustedContentInset.top
        let targetOffsetY = attributes.frame.maxY - top - AgentVCLayout.arrivalUserMessageTailInset
        applyMinimalArrivalReserveSpacerHeight(for: userMessageID)
        collectionView.layoutIfNeeded()
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

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: true)
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
        endArrivalScroll()
        updateScrollToBottomButtonVisibility(animated: true)
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

    let agentNavigationController = UINavigationController(rootViewController: AgentVC())
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
