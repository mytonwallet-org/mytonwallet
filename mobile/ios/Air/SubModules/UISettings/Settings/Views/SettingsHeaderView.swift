//
//  SettingsHeaderView.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import UIKit
import Dispatch
import UIComponents
import WalletContext
import WalletCore

class SettingsHeaderView: WTouchPassView {
    private let accountContext = AccountContext(source: .current)

    var onLargeAvatarLongPress: (() -> Void)? {
        didSet {
            updateHeaderInteractions()
        }
    }

    private let statusIndicator = WActivityIndicator()
    private let statusLabel = NavigationHeader2.makeTitleLabel("", fixedColor: true)
    private var updateStatus: WalletUpdateStatus = .updated
    private var statusAnimationId = 0

    lazy var headerTouchTarget: NavigationHeader2 = {
        
        let view = NavigationHeader2()
        view.accessibilityElementsHidden = false
        let indicatorContainer = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        indicatorContainer.addSubview(statusIndicator)
        NSLayoutConstraint.activate([
            statusIndicator.centerXAnchor.constraint(equalTo: indicatorContainer.centerXAnchor),
            statusIndicator.centerYAnchor.constraint(equalTo: indicatorContainer.centerYAnchor),
        ])
        statusLabel.textColor = .air.secondaryLabel
        statusIndicator.isAccessibilityElement = false
        view.setStack(of: [indicatorContainer, statusLabel], spacing: 4, truncatingAt: [1])
        view.contentView?.alpha = 0
        
        view.onMovedToWindow = { [weak self] window in
            guard let self, window != nil else { return }
            if updateStatus != .updated {
                statusIndicator.stopAnimating(animated: false)
                statusIndicator.startAnimating(animated: false)
            }
            self.updateWithLastScrollOffset()
        }
        
        view.onSizeChanged = { [weak self] in
            guard let self else { return }
            self.updateWithLastScrollOffset()
        }
        
        view.onTap = { [weak self] recognizer in
            guard let self else { return }
            if isCollapsed {
                let location = recognizer.location(in: titleStack)
                titleStack.handleTouchAt(location: location)
            }
        }
        
        return view
    }()
    
    private let avatarImageView = IconView(size: 88)
    private let avatarBlurView = WBlurredContentView()
    private lazy var avatarLongPressGestureRecognizer: UILongPressGestureRecognizer = {
        let gestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(avatarLongPressed(_:))
        )
        gestureRecognizer.cancelsTouchesInView = false
        gestureRecognizer.isEnabled = false
        return gestureRecognizer
    }()
    private var addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        return label
    }()
    
    struct LayoutGeometry {
        var isShowingStatus = false

        private var isLegacyOS: Bool {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                return false
            }
            return true
        }
        
        let titleHorMargin: CGFloat = 16.0

        let distanceBetweenTitleAndAvatarMidY: CGFloat = 73

        /// The key parameter. A distance between navigation buttons and the title vertical centers.
        /// In fact, this is the real movement range for the title.
        var distanceBetweenNavButtonAndTitleStackMiddles: CGFloat { isShowingStatus ? 148 : 108 }

        /// The value is used to shift top section to be closer to the title in the collapsed mode
        private var topSectionCollapsedInset: CGFloat { isLegacyOS ? 18 : 26 }
        
        var topSectionInset: CGFloat { isLegacyOS ? 40 : 32 }

        let collapseThreshold = 0.5

        var addressLabelShift: CGFloat { isLegacyOS ? -12 : -17 }

        var scrollTopContentInset: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles }
        var scrollRange: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles }
        var fullScrollRange: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles + topSectionCollapsedInset }
    }
    
    var layoutGeometry: LayoutGeometry { .init(isShowingStatus: updateStatus != .updated) }
        
    private let titleStack = TitleStackView()
    private let titleContainer = WTouchPassView()
    private var titleCenterYConstraint: NSLayoutConstraint!
    private var isCollapsed = false
    private var lastScrollOffset: CGFloat = 0
    private var hasPerformedInitialLayout = false
    private var avatarCenterYConstraint: NSLayoutConstraint!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        shouldAcceptTouchesOutside = true
        
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(titleStack)

        translatesAutoresizingMaskIntoConstraints = false
        titleContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(avatarBlurView)
        avatarBlurView.addSubview(avatarImageView)
        addSubview(titleContainer)
        addSubview(addressLabel)
                
        avatarCenterYConstraint = avatarImageView.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor)
        titleCenterYConstraint = titleContainer.centerYAnchor.constraint(equalTo: topAnchor)

        NSLayoutConstraint.activate([
            avatarCenterYConstraint,
            avatarImageView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            
            avatarBlurView.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -50),
            avatarBlurView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 50),
            avatarBlurView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -50),
            avatarBlurView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 50),
            
            titleStack.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            titleStack.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            titleStack.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            titleStack.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),

            titleCenterYConstraint,
            titleContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: layoutGeometry.titleHorMargin),
            titleContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -layoutGeometry.titleHorMargin),
            
            addressLabel.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
                        
            heightAnchor.constraint(equalToConstant: 200) // in fact it affects almost nothing
        ])
    }

    private func updateHeaderInteractions() {
        let isDebugMenuEnabled = onLargeAvatarLongPress != nil

        avatarLongPressGestureRecognizer.isEnabled = isDebugMenuEnabled

        if isDebugMenuEnabled, avatarLongPressGestureRecognizer.view == nil {
            avatarImageView.addGestureRecognizer(avatarLongPressGestureRecognizer)
        } else if !isDebugMenuEnabled, avatarLongPressGestureRecognizer.view != nil {
            avatarImageView.removeGestureRecognizer(avatarLongPressGestureRecognizer)
        }

        avatarImageView.isUserInteractionEnabled = isDebugMenuEnabled
        titleStack.nameLabel.isUserInteractionEnabled = false
        avatarImageView.isAccessibilityElement = isDebugMenuEnabled
        avatarImageView.accessibilityLabel = isDebugMenuEnabled ? "Debug menu" : nil
        avatarImageView.accessibilityTraits = isDebugMenuEnabled ? .button : []
        titleStack.isAccessibilityElement = false
        titleStack.nameLabel.isAccessibilityElement = false
        titleStack.nameLabel.accessibilityLabel = nil
        titleStack.nameLabel.accessibilityHint = nil
        titleStack.nameLabel.accessibilityTraits = []

        var accessibilityActions: [UIAccessibilityCustomAction] = []
        if isDebugMenuEnabled {
            accessibilityActions.append(
                UIAccessibilityCustomAction(
                    name: "Open Debug Menu",
                    target: self,
                    selector: #selector(openDebugMenuFromAccessibility)
                )
            )
        }
        avatarImageView.accessibilityCustomActions = accessibilityActions.nilIfEmpty
    }

    @objc private func avatarLongPressed(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began, !isCollapsed else { return }
        onLargeAvatarLongPress?()
    }

    @objc private func openDebugMenuFromAccessibility() -> Bool {
        guard !isCollapsed, let onLargeAvatarLongPress else { return false }
        onLargeAvatarLongPress()
        return true
    }

    func updateAll() {
        avatarImageView.config(with: accountContext.account)
        updateTitle()
        updateAddresses()
    }

    func updateBalance() {
        updateTitle()
        updateAddresses()
    }

    func setUpdateStatus(_ state: WalletUpdateStatus, animated: Bool) {
        guard updateStatus != state else { return }
        updateStatus = state
        statusAnimationId += 1
        let animationId = statusAnimationId
        switch state {
        case .waitingForNetwork:
            statusLabel.text = lang("Waiting for network…")
        case .updating:
            statusLabel.text = lang("Updating…")
        case .updated:
            break
        }
        if state != .updated {
            statusIndicator.startAnimating(animated: false)
        }
        headerTouchTarget.contentView?.invalidateIntrinsicContentSize()
        headerTouchTarget.setNeedsLayout()
        UIView.animate(
            withDuration: animated && !UIAccessibility.isReduceMotionEnabled ? 0.3 : 0,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.updateStatusVisibility()
        } completion: { [weak self] _ in
            guard let self, statusAnimationId == animationId, updateStatus == .updated else { return }
            statusIndicator.stopAnimating(animated: false)
        }
    }

    private func updateStatusVisibility() {
        let alpha = updateStatus == .updated ? 0 : 1 - clamp(lastScrollOffset / 32, to: 0...1)
        headerTouchTarget.contentView?.alpha = alpha
        headerTouchTarget.isAccessibilityElement = false
        headerTouchTarget.contentView?.accessibilityElementsHidden = alpha == 0
    }
    
    private func updateTitle() {
        titleStack.updateWithAccount(accountContext.account)
    }
    
    private func updateAddresses() {
        let addressLine = accountContext.addressLine
        addressLabel.attributedText = addressLine.attributedString(
            font: WTypography.uiFont(.callout, content: .technical),
            color: .air.secondaryLabel,
            maxChainCount: 3,
            multichainAddressCount: 2
        )
    }
    
    fileprivate func updateWithLastScrollOffset() {
        update(scrollOffset: lastScrollOffset)
    }

    func update(scrollOffset: CGFloat) {
        let horizontalSpace = bounds.width
        guard horizontalSpace > 0 else { return }
        guard headerTouchTarget.superview != nil else { return }
        
        lastScrollOffset = scrollOffset
        updateStatusVisibility()
        
        let scrollMultiplier: CGFloat = scrollOffset > 0 ? 0.85 : 1
        let scrollNonNegative = max(scrollOffset, 0)
        avatarCenterYConstraint.constant = -layoutGeometry.distanceBetweenTitleAndAvatarMidY - scrollNonNegative * 1.0 / (1.0 + log(1 + scrollNonNegative))
 
        let blurProgress: CGFloat = 1.0 - min(1.0, max(0.0, (155.0 - scrollOffset * scrollMultiplier) / 155.0))
        avatarBlurView.blurRadius = blurProgress * 30
        avatarImageView.alpha = min(1.0, max(0.0, (190.0 - scrollOffset * scrollMultiplier) / 40.0))
                         
        let navigationCenterY = headerTouchTarget.convert(headerTouchTarget.bounds.center, to: self).y
        let scrollRange = layoutGeometry.scrollRange
        let collapseProgress = max(0, min(1, scrollOffset / layoutGeometry.fullScrollRange))
        
        self.addressLabel.alpha = 1 - collapseProgress
        
        let titleMinScale = 17.0 / 24.0
        let titleScale = interpolate(from: 1.0, to: titleMinScale, progress: collapseProgress)
        let titleTransform = CGAffineTransform.identity.scaledBy(x: titleScale, y: titleScale)
        let topOverscroll = -min(0, scrollOffset)
        let titlePosition = interpolate(from: scrollRange, to: 0, progress: collapseProgress) + navigationCenterY + topOverscroll
                
        let addressTransform = CGAffineTransform.identity
            .scaledBy(x: titleScale, y: titleScale)
            .translatedBy(x: 0, y: layoutGeometry.addressLabelShift * collapseProgress)
        
        isCollapsed = collapseProgress >= layoutGeometry.collapseThreshold
        hasPerformedInitialLayout = true
        
        applyUpdate(titlePosition: titlePosition, titleTransform: titleTransform, addressTransform: addressTransform)
        updateTitleMaximumContentWidth(collapseProgress: collapseProgress)
    }

    private func updateTitleMaximumContentWidth(collapseProgress: CGFloat) {
        let titleBounds = titleStack.bounds
        guard titleBounds.width > 0 else { return }

        let navigationBounds = headerTouchTarget.convert(headerTouchTarget.bounds, to: titleStack)
        let distanceToLeadingEdge = titleBounds.midX - navigationBounds.minX
        let distanceToTrailingEdge = navigationBounds.maxX - titleBounds.midX
        let collapsedMaximumWidth = 2 * max(0, min(distanceToLeadingEdge, distanceToTrailingEdge))
        titleStack.maximumContentWidth = floor(
            interpolate(from: titleBounds.width, to: collapsedMaximumWidth, progress: collapseProgress)
        )
        titleStack.layoutIfNeeded()
    }
    
    private func applyUpdate(titlePosition: CGFloat, titleTransform: CGAffineTransform, addressTransform: CGAffineTransform) {
        self.titleCenterYConstraint.constant = titlePosition
        self.titleStack.transform = titleTransform
        self.addressLabel.transform = addressTransform
        self.layoutIfNeeded()
    }
}

private class TitleStackView: UIView {
    private let font: UIFont
    private let technicalFont: UIFont
        
    // to avoid layout looping let's have both full and shortened views alive. It's cheap enough
    @MainActor
    private class BalanceViewContext {
        let container: WSensitiveData<UILabel>
        var leadingConstraint: NSLayoutConstraint!
        let label: UILabel

        init(font: UIFont, cellSize: CGFloat) {
            label = UILabel()
            label.font = font
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.textColor = .air.secondaryLabel
            
            container = .init(cols: 8, rows: 2, cellSize: cellSize, cornerRadius: 4, theme: .adaptive, alignment: .leading)
            container.addContent(label)
        }
        
        func addToParent(parent: TitleStackView) {
            container.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(container)
            leadingConstraint = container.leadingAnchor.constraint(equalTo: parent.leadingAnchor)
            NSLayoutConstraint.activate([
                leadingConstraint,
                container.centerYAnchor.constraint(equalTo: parent.centerYAnchor)
            ])
        }
        
        func widthThatFitsHeight(_ height: CGFloat) -> CGFloat {
            return container.contentSizeThatFits(.init(width: .greatestFiniteMagnitude, height: height)).width
        }
    }
    
    nonisolated(unsafe)private var observationToken: NSObjectProtocol?
    private let fullBalance: BalanceViewContext
    private let shortenedBalance: BalanceViewContext
    private var balance: BaseCurrencyAmount?
    private let separatorHorizontalSpacing: CGFloat = 5
    
    private var separatorLeadingCostraint: NSLayoutConstraint!
    private var nameLeadingConstraint: NSLayoutConstraint!
    private var nameWidthConstraint: NSLayoutConstraint!
    private var hasPerformedInitialLayout = false
    var maximumContentWidth: CGFloat? {
        didSet {
            guard maximumContentWidth != oldValue else { return }
            setNeedsLayout()
        }
    }

    private lazy var separatorDotLabel: UILabel = {
        let label = UILabel()
        label.textColor = .air.secondaryLabel
        label.text = "·"
        label.font = technicalFont
        label.isHidden = true
        return label
    }()
    
    lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        label.adjustsFontSizeToFitWidth = false
        label.allowsDefaultTighteningForTruncation = false
        label.font = font
        label.textColor = UIColor.label
        return label
    }()
    
    init() {
        font = WTypography.uiFont(.prominentTitle)
        technicalFont = WTypography.uiFont(.amount, content: .technical)
        fullBalance = BalanceViewContext(font: technicalFont, cellSize: ceil(technicalFont.pointSize / 3))
        shortenedBalance = BalanceViewContext(font: technicalFont, cellSize: ceil(technicalFont.pointSize / 3))

        super.init(frame: .zero)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        separatorDotLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        addSubview(separatorDotLabel)
        separatorLeadingCostraint = separatorDotLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        nameLeadingConstraint = nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        nameWidthConstraint = nameLabel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            separatorDotLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            separatorLeadingCostraint,
            nameWidthConstraint,
            nameLeadingConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        fullBalance.addToParent(parent: self)
        shortenedBalance.addToParent(parent: self)
        
        shortenedBalance.container.onMaskStateChanged = { [weak self] _ in self?.updateLayout() }
        fullBalance.container.onMaskStateChanged = { [weak self] _ in self?.updateLayout() }

        observationToken = NotificationCenter.default.addObserver(
            forName: .updateSensitiveData,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateLayout()
                }
            }
        )
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        observationToken.map { NotificationCenter.default.removeObserver($0) }
    }
    
    func updateWithAccount(_ account: MAccount) {
        var shouldUpdateLayout = false
        
        let name = account.displayName
        if name != nameLabel.text {
            nameLabel.text = name
            shouldUpdateLayout = true
        }
        
        let oldBalance = self.balance
        balance = BalanceDataStore.for(accountId: account.id).balanceTotals?.totalBalance
        if oldBalance != balance {
            fullBalance.label.text = balance?.formatted(.baseCurrencyEquivalent)
            shortenedBalance.label.text = balance?.formatted(.baseCurrencyEquivalentShortened)
            separatorDotLabel.isHidden = balance == nil
            fullBalance.container.isDisabled = balance == nil
            shortenedBalance.container.isDisabled = balance == nil
            shouldUpdateLayout = true
        }
        
        if shouldUpdateLayout {
            updateLayout()
        }
    }
    
    func handleTouchAt(location: CGPoint)  {
        
        func check(_ balance: BalanceViewContext) -> Bool {
            if balance.container.alpha > 0, let shyMask = balance.container.shyMask {
                if shyMask.bounds.contains(convert(location, to: shyMask)) {
                    balance.container.performTap()
                    return true
                }
            }
            return false
        }
        
        _ = check(shortenedBalance) || check(fullBalance)
    }
    
    private func updateLayout() {
        // The loading status can lay out the empty title before the account name arrives.
        invalidateIntrinsicContentSize()
        self.setNeedsLayout()
        
        guard hasPerformedInitialLayout else {
            let hasData = fullBalance.label.text?.nilIfEmpty != nil || nameLabel.text?.nilIfEmpty != nil
            if hasData {
                UIView.performWithoutAnimation {
                    layoutIfNeeded()
                }
                hasPerformedInitialLayout = true
            }
            return
        }
        
        UIView.animate(withDuration: 0.15) {
            self.layoutIfNeeded()
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: nameLabel.intrinsicContentSize.height)
    }
    
    private func getIntrinsicNameWidth(forWidth maxWidth: CGFloat) -> CGFloat {
        let attrString = NSAttributedString(string: nameLabel.text ?? "", attributes: [.font: font] )
        let line = CTLineCreateWithAttributedString(attrString)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: [.font: font] ))
        guard let truncatedLine = CTLineCreateTruncatedLine(line, Double(maxWidth), .middle, ellipsis) else { return maxWidth }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let result = ceil(CGFloat(CTLineGetTypographicBounds(truncatedLine, &ascent, &descent, &leading)))
        return result
    }
    
    override public func layoutSubviews() {
        // Note: to avoid any possible truncation issues (glitches, misaligning) we ceil() all calculated widths
        
        let b = bounds
        let availableWidth = min(b.width, maximumContentWidth ?? b.width)
        var contentLength: CGFloat = 0
        
        var nameLabelWidth = ceil(nameLabel.sizeThatFits(.init(width: .greatestFiniteMagnitude, height: b.height)).width)
        let separatorDotLabelWidth = ceil(separatorDotLabel.sizeThatFits(.init(width: .greatestFiniteMagnitude, height: b.height)).width)
        let separatorWidth = separatorDotLabelWidth + 2 * separatorHorizontalSpacing

        // Update balances. Use alpha for visibility, not isHidden, to avoid layout loops
        var showFullBalance = false
        var showShortenedBalance = false
        if balance != nil {
            let fullBalanceWidth = ceil(fullBalance.widthThatFitsHeight(b.height))
            if nameLabelWidth + separatorWidth + fullBalanceWidth > availableWidth {
                showShortenedBalance = true
                contentLength += ceil(shortenedBalance.widthThatFitsHeight(b.height))
            } else {
                showFullBalance = true
                contentLength += fullBalanceWidth
            }
            contentLength += separatorWidth
        }
        fullBalance.container.alpha = showFullBalance ? 1.0 : 0.0
        shortenedBalance.container.alpha = showShortenedBalance ? 1.0 : 0.0
        separatorDotLabel.alpha = balance != nil ? 1.0 : 0.0

        // Final name length. Shorten if needed. Recalculate if shortened (it usually be less due truncation specifics)
        if nameLabelWidth + contentLength > availableWidth {
            nameLabelWidth = max(0, availableWidth - contentLength)
            if nameLabelWidth > 0 {
                 nameLabelWidth = getIntrinsicNameWidth(forWidth: nameLabelWidth)
            }
        }
        contentLength += nameLabelWidth
        
        var offsetX = max(0.0, ((b.width - contentLength) / 2).rounded())

        nameWidthConstraint.constant = nameLabelWidth
        nameLeadingConstraint.constant = offsetX
        offsetX += nameLabelWidth
        
        separatorLeadingCostraint.constant = offsetX + separatorHorizontalSpacing
        offsetX += separatorWidth
        
        fullBalance.leadingConstraint.constant = offsetX
        shortenedBalance.leadingConstraint.constant = offsetX
        
        super.layoutSubviews()
    }
}
