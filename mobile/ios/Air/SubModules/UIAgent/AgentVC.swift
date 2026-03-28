import UIKit
import UIComponents
import WalletContext
import WalletCore

private let log = Log("AgentVC")

private enum AgentVCLayout {
    static let screenBackgroundColor = UIColor.air.background
    static let maxContentWidth: CGFloat = 580
    static let sectionInsets = NSDirectionalEdgeInsets(top: 16, leading: 0, bottom: 16, trailing: 0)
    static let interGroupSpacing: CGFloat = 6
    static let hintsSpacingToMessages: CGFloat = 17
    static let hintsSpacingToComposer: CGFloat = 26
    static let hintsRowHeight: CGFloat = 66
    static let hintsContainerHeight = hintsSpacingToMessages + hintsRowHeight
    static let nearBottomThreshold: CGFloat = 60
    static let composerResizeAnimationDuration: TimeInterval = 0.2
    static let bottomAlignmentAnimationDuration: TimeInterval = 0.25
}

private struct AgentBottomAlignmentAnimation {
    let duration: TimeInterval
    let options: UIView.AnimationOptions
}

private struct AgentBottomLayoutState {
    let contentInset: UIEdgeInsets
    let verticalScrollIndicatorInsets: UIEdgeInsets
    let contentOffset: CGPoint
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

public final class AgentVC: WViewController, UICollectionViewDelegate, UIGestureRecognizerDelegate {
    private enum Section: Hashable {
        case main
    }

    private let model: AgentModel
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: AgentVC.makeLayout())
    private lazy var dataSource = makeDataSource()

    private let contentLayoutGuide = UILayoutGuide()
    private let hintsContainerView = AgentPassthroughContainerView()
    private let hintsSectionView = AgentHintsSectionView()
    private let composerView = AgentComposerView()
    private let scrollToBottomButton = AgentScrollToBottomButton()
    private lazy var contentLayoutGuideWidthConstraint = contentLayoutGuide.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor)
    private lazy var contentLayoutGuideMaxWidthConstraint = contentLayoutGuide.widthAnchor.constraint(lessThanOrEqualToConstant: AgentVCLayout.maxContentWidth)
    private lazy var hintsContainerHeightConstraint = hintsContainerView.heightAnchor.constraint(equalToConstant: AgentVCLayout.hintsContainerHeight)
    private lazy var scrollToBottomButtonBottomToComposerConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: composerView.inputTopAnchor, constant: -16)
    private lazy var scrollToBottomButtonBottomToHintsConstraint = scrollToBottomButton.bottomAnchor.constraint(equalTo: hintsContainerView.topAnchor, constant: -16)

    private var hasPerformedInitialScroll = false
    private var lastKnownNearBottom = true
    private var keepsBottomPinnedWhileKeyboardIsActive = false
    private var shouldScrollToBottomAfterNextLayout = false
    private var pendingBottomAlignmentAnimation: AgentBottomAlignmentAnimation?
    private var editingMessageID: AgentItemID?

    public init(backendKind: AgentBackendKind) {
        self.model = AgentModel(backendKind: backendKind)
        super.init(nibName: nil, bundle: nil)
        title = lang("Agent")
    }

    public convenience init() {
        self.init(backendKind: AgentModel.preferredBackendKind())
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

    public override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        setupNavigationItem()
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
        guard !hasPerformedInitialScroll else { return }
        hasPerformedInitialScroll = true
        UIView.performWithoutAnimation {
            view.layoutIfNeeded()
            updateBottomPinnedInsets()
            scrollToBottom(animated: false)
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateContentWidthConstraints()
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateTheme()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if shouldScrollToBottomAfterNextLayout {
            let animation = pendingBottomAlignmentAnimation
            shouldScrollToBottomAfterNextLayout = false
            pendingBottomAlignmentAnimation = nil
            performPendingBottomAlignment(animation: animation)
        } else {
            updateBottomPinnedInsets()
        }
        lastKnownNearBottom = isNearBottom()
        updateScrollToBottomButtonVisibility(animated: false)
    }

    private func updateTheme() {
        view.backgroundColor = AgentVCLayout.screenBackgroundColor
        collectionView.backgroundColor = .clear
        composerView.applyTheme()
        scrollToBottomButton.applyTheme()
        updateSendButtonState()
    }

    public override func scrollToTop(animated: Bool) {
        scrollToBottom(animated: animated)
    }

    public func switchBackend(to backendKind: AgentBackendKind, animated: Bool = true) {
        model.switchBackend(to: backendKind, animated: animated)
        refreshNavigationItemMenu()
    }

    private func setupViews() {
        view.backgroundColor = AgentVCLayout.screenBackgroundColor
        view.addLayoutGuide(contentLayoutGuide)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.delaysContentTouches = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.delegate = self

        let dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleCollectionViewTap))
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        dismissKeyboardTapGesture.delegate = self
        collectionView.addGestureRecognizer(dismissKeyboardTapGesture)

        composerView.translatesAutoresizingMaskIntoConstraints = false
        composerView.onDraftTextChanged = { [weak self] in
            guard let self else { return }
            if self.composerView.draftText?.isEmpty != false {
                self.editingMessageID = nil
            }
            self.updateSendButtonState()
        }
        composerView.onBeginEditing = { [weak self] in
            guard let self else { return }
            let isNearBottom = self.isNearBottom()
            self.lastKnownNearBottom = isNearBottom
            self.keepsBottomPinnedWhileKeyboardIsActive = isNearBottom
        }
        composerView.onEndEditing = { [weak self] in
            self?.keepsBottomPinnedWhileKeyboardIsActive = false
        }
        composerView.onSend = { [weak self] in
            self?.sendCurrentMessage()
        }
        composerView.onHintsToggle = { [weak self] in
            self?.toggleHintsVisibility()
        }
        composerView.onLayoutHeightChanged = { [weak self] in
            guard let self, self.composerView.isTextInputActive else { return }
            self.requestBottomAlignmentAfterNextLayout(
                animation: Self.composerResizeBottomAlignmentAnimation,
                onlyIfNearBottom: true
            )
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

            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
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

        updateContentWidthConstraints()
        updateTheme()
    }

    private func updateContentWidthConstraints() {
        contentLayoutGuideMaxWidthConstraint.isActive = traitCollection.userInterfaceIdiom == .pad
    }

    private func setupNavigationItem() {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<Section, AgentItemID> {
        let messageRegistration = UICollectionView.CellRegistration<AgentMessageCell, AgentItemID> { [weak self] cell, _, itemID in
            guard let self,
                  let item = self.model.item(for: itemID),
                  case .message(let message) = item else { return }
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

        return UICollectionViewDiffableDataSource<Section, AgentItemID>(collectionView: collectionView) { [weak self] collectionView, indexPath, itemID in
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

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, AgentItemID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(model.itemIDs, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
            self?.scrollToBottom(animated: animated)
        }
    }

    private func updateBottomPinnedInsets() {
        collectionView.layoutIfNeeded()
        applyInsets(from: makeBottomLayoutState())
    }

    private func scrollToBottom(animated: Bool) {
        performBottomAlignment(animation: animated ? Self.timelineBottomAlignmentAnimation : nil)
    }

    private func isNearBottom() -> Bool {
        guard collectionView.bounds.height > 0 else { return true }

        let adjustedInsets = collectionView.adjustedContentInset
        let visibleHeight = collectionView.bounds.height - adjustedInsets.top - adjustedInsets.bottom
        guard visibleHeight > 0 else { return true }

        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        guard contentHeight > visibleHeight + 1 else { return true }

        let offsetFromTop = collectionView.contentOffset.y + adjustedInsets.top
        let distanceFromBottom = contentHeight - visibleHeight - offsetFromTop
        return distanceFromBottom <= AgentVCLayout.nearBottomThreshold
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
            AppActions.showError(error: BridgeCallError.customMessage(lang("Unsupported link"), nil))
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
        if composerView.isTextInputActive {
            requestBottomAlignmentAfterNextLayout()
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
        model.clearChat()
    }

    private func toggleHintsVisibility() {
        model.toggleHintsVisibility()
    }

    private func copyText(for itemID: AgentItemID) -> String? {
        if let indexPath = dataSource.indexPath(for: itemID),
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
        guard let indexPath = dataSource.indexPath(for: itemID),
              let cell = collectionView.cellForItem(at: indexPath) as? AgentContextMenuPresentingCell else {
            return nil
        }
        return cell.contextMenuPreview()
    }

    private func itemID(from configuration: UIContextMenuConfiguration) -> AgentItemID? {
        guard let identifier = configuration.identifier as? NSUUID else { return nil }
        return UUID(uuidString: identifier.uuidString)
    }

    private func requestBottomAlignmentAfterNextLayout(
        animation: AgentBottomAlignmentAnimation? = nil,
        onlyIfNearBottom: Bool = false
    ) {
        guard !onlyIfNearBottom || lastKnownNearBottom else { return }
        shouldScrollToBottomAfterNextLayout = true
        pendingBottomAlignmentAnimation = animation
        view.setNeedsLayout()
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

    @objc private func handleKeyboardWillChangeFrame(_ notification: Notification) {
        guard composerView.isTextInputActive,
              keepsBottomPinnedWhileKeyboardIsActive,
              let animation = keyboardBottomAlignmentAnimation(for: notification) else {
            return
        }
        requestBottomAlignmentAfterNextLayout(animation: animation)
    }

    @objc private func scrollToBottomButtonPressed() {
        scrollToBottom(animated: true)
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(76)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = AgentVCLayout.interGroupSpacing
        section.contentInsets = AgentVCLayout.sectionInsets
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func performPendingBottomAlignment(animation: AgentBottomAlignmentAnimation?) {
        performBottomAlignment(animation: animation ?? Self.timelineBottomAlignmentAnimation)
    }

    private func keyboardBottomAlignmentAnimation(for notification: Notification) -> AgentBottomAlignmentAnimation? {
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveRawValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int else {
            return nil
        }

        let curve = UIView.AnimationOptions(rawValue: UInt(curveRawValue << 16))
        return AgentBottomAlignmentAnimation(
            duration: duration,
            options: [curve, .beginFromCurrentState, .allowUserInteraction]
        )
    }

    private static let composerResizeBottomAlignmentAnimation = AgentBottomAlignmentAnimation(
        duration: AgentVCLayout.composerResizeAnimationDuration,
        options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
    )

    private static let timelineBottomAlignmentAnimation = AgentBottomAlignmentAnimation(
        duration: AgentVCLayout.bottomAlignmentAnimationDuration,
        options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
    )

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
        let shouldKeepBottomPinned = isNearBottom()
        let animation = Self.timelineBottomAlignmentAnimation

        view.layoutIfNeeded()

        if shouldShow {
            hintsSectionView.alpha = 0
            hintsSectionView.transform = hintsHiddenTransform
        }

        hintsSectionView.isUserInteractionEnabled = false
        scrollToBottomButtonBottomToHintsConstraint.isActive = shouldShow
        scrollToBottomButtonBottomToComposerConstraint.isActive = !shouldShow

        UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options) {
            self.view.layoutIfNeeded()
            if shouldKeepBottomPinned {
                let state = self.makeBottomLayoutState()
                self.applyBottomLayoutState(state)
                self.lastKnownNearBottom = true
                if self.composerView.isTextInputActive {
                    self.keepsBottomPinnedWhileKeyboardIsActive = true
                }
            }
            self.hintsSectionView.alpha = shouldShow ? 1 : 0
            self.hintsSectionView.transform = shouldShow ? .identity : self.hintsHiddenTransform
        } completion: { _ in
            self.hintsSectionView.isUserInteractionEnabled = shouldShow
            self.updateScrollToBottomButtonVisibility(animated: false)
        }
    }

    private func makeBottomLayoutState() -> AgentBottomLayoutState {
        let currentContentInset = collectionView.contentInset
        let currentIndicatorInsets = collectionView.verticalScrollIndicatorInsets
        let baselineTopInset = collectionView.adjustedContentInset.top - currentContentInset.top
        let baselineBottomInset = collectionView.adjustedContentInset.bottom - currentContentInset.bottom
        let composerInputFrame = collectionView.convert(composerView.inputBackgroundFrame, from: composerView)
        let overlayTop = coveredBottomOverlayTop(using: composerInputFrame)
        let totalCoveredBottomInset = max(0, collectionView.bounds.maxY - overlayTop)
        let additionalBottomInset = max(0, totalCoveredBottomInset - baselineBottomInset)
        let availableHeight = collectionView.bounds.height - baselineTopInset - baselineBottomInset - additionalBottomInset
        let contentHeight = collectionView.collectionViewLayout.collectionViewContentSize.height
        let topInset = max(0, availableHeight - contentHeight)
        let adjustedTopInset = baselineTopInset + topInset
        let adjustedBottomInset = baselineBottomInset + additionalBottomInset
        let visibleHeight = max(0, collectionView.bounds.height - adjustedTopInset - adjustedBottomInset)
        let maxOffsetFromTop = max(0, contentHeight - visibleHeight)

        return AgentBottomLayoutState(
            contentInset: UIEdgeInsets(
                top: topInset,
                left: currentContentInset.left,
                bottom: additionalBottomInset,
                right: currentContentInset.right
            ),
            verticalScrollIndicatorInsets: UIEdgeInsets(
                top: topInset,
                left: currentIndicatorInsets.left,
                bottom: totalCoveredBottomInset,
                right: currentIndicatorInsets.right
            ),
            contentOffset: CGPoint(
                x: collectionView.contentOffset.x,
                y: maxOffsetFromTop - adjustedTopInset
            )
        )
    }

    private func applyInsets(from state: AgentBottomLayoutState) {
        let needsTopUpdate = abs(collectionView.contentInset.top - state.contentInset.top) > 0.5
        let needsBottomUpdate = abs(collectionView.contentInset.bottom - state.contentInset.bottom) > 0.5
        let needsIndicatorTopUpdate = abs(collectionView.verticalScrollIndicatorInsets.top - state.verticalScrollIndicatorInsets.top) > 0.5
        let needsIndicatorBottomUpdate = abs(collectionView.verticalScrollIndicatorInsets.bottom - state.verticalScrollIndicatorInsets.bottom) > 0.5
        guard needsTopUpdate || needsBottomUpdate || needsIndicatorTopUpdate || needsIndicatorBottomUpdate else { return }

        collectionView.contentInset.top = state.contentInset.top
        collectionView.contentInset.bottom = state.contentInset.bottom
        collectionView.verticalScrollIndicatorInsets.top = state.verticalScrollIndicatorInsets.top
        collectionView.verticalScrollIndicatorInsets.bottom = state.verticalScrollIndicatorInsets.bottom
    }

    private func applyBottomLayoutState(_ state: AgentBottomLayoutState) {
        applyInsets(from: state)
        collectionView.contentOffset = state.contentOffset
    }

    private func performBottomAlignment(animation: AgentBottomAlignmentAnimation?) {
        collectionView.layoutIfNeeded()
        let state = makeBottomLayoutState()
        lastKnownNearBottom = true
        if composerView.isTextInputActive {
            keepsBottomPinnedWhileKeyboardIsActive = true
        }

        guard let animation else {
            applyBottomLayoutState(state)
            updateScrollToBottomButtonVisibility(animated: false)
            return
        }

        UIView.animate(withDuration: animation.duration, delay: 0, options: animation.options) {
            self.applyBottomLayoutState(state)
        }
        updateScrollToBottomButtonVisibility(animated: true)
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
    func agentModelDidReloadTimeline(animated: Bool) {
        updateHintsView(animated: false)
        updateHintsToggleState()
        applySnapshot(animated: animated)
    }

    func agentModelDidUpdateItems(_ ids: [AgentItemID], animated: Bool, scrollToBottom: Bool) {
        updateHintsToggleState()
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        let idsToReload = ids.filter { existingIDs.contains($0) }
        guard !idsToReload.isEmpty else { return }

        var snapshot = dataSource.snapshot()
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(idsToReload)
        } else {
            snapshot.reloadItems(idsToReload)
        }
        dataSource.apply(snapshot, animatingDifferences: animated) { [weak self] in
            self?.collectionView.collectionViewLayout.invalidateLayout()
            if scrollToBottom {
                self?.scrollToBottom(animated: true)
            } else {
                self?.updateBottomPinnedInsets()
            }
        }
    }

    func agentModelDidUpdateHints(animated: Bool) {
        updateHintsView(animated: animated)
        updateHintsToggleState()
    }
}

extension AgentVC {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTouchInsideControl(touch.view)
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard collectionView === self.collectionView,
              let itemID = dataSource.itemIdentifier(for: indexPath),
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
        let isNearBottom = isNearBottom()
        lastKnownNearBottom = isNearBottom
        if composerView.isTextInputActive,
           scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating {
            keepsBottomPinnedWhileKeyboardIsActive = isNearBottom
        }
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
