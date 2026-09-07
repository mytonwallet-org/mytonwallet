//
//  SettingsHeaderView.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import UIKit
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
    private let balanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = WTypography.uiFont(.callout, content: .technical)
        label.textColor = .air.secondaryLabel
        label.textAlignment = .center
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()
    private let balanceContainer = WSensitiveData<UILabel>(cols: 8, rows: 2, cellSize: 6, cornerRadius: 4, theme: .adaptive, alignment: .leading)
    private let balanceStack = UIStackView()
    private let accountTypeIcons = UIStackView()
    private var balanceWidthConstraint: NSLayoutConstraint!
    
    struct LayoutGeometry {
        var isShowingStatus = false

        private var isLegacyOS: Bool {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                return false
            }
            return true
        }
        
        let titleHorMargin: CGFloat = 16.0

        let distanceBetweenTitleAndAvatarMidY: CGFloat = 72

        /// The key parameter. A distance between navigation buttons and the title vertical centers.
        /// In fact, this is the real movement range for the title.
        var distanceBetweenNavButtonAndTitleStackMiddles: CGFloat { isShowingStatus ? 146 : 106 }

        /// The value is used to shift top section to be closer to the title in the collapsed mode
        private var topSectionCollapsedInset: CGFloat { isLegacyOS ? 18 : 26 }
        
        var topSectionInset: CGFloat { isLegacyOS ? 40 : 32 }

        let collapseThreshold = 0.5

        var balanceRowShift: CGFloat { isLegacyOS ? -12 : -17 }

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
        balanceContainer.addContent(balanceLabel)
        balanceWidthConstraint = balanceContainer.widthAnchor.constraint(equalToConstant: 0)
        balanceWidthConstraint.priority = .defaultHigh
        balanceWidthConstraint.isActive = true
        balanceContainer.onMaskStateChanged = { [weak self] _ in
            self?.updateBalanceWidth()
        }
        balanceStack.translatesAutoresizingMaskIntoConstraints = false
        balanceStack.axis = .horizontal
        balanceStack.alignment = .center
        balanceStack.spacing = 5
        accountTypeIcons.axis = .horizontal
        accountTypeIcons.alignment = .center
        accountTypeIcons.spacing = 4
        accountTypeIcons.isAccessibilityElement = false
        accountTypeIcons.accessibilityElementsHidden = true
        balanceStack.addArrangedSubview(accountTypeIcons)
        balanceStack.addArrangedSubview(balanceContainer)
        addSubview(balanceStack)
                
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
            
            balanceStack.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor, constant: 30),
            balanceStack.centerXAnchor.constraint(equalTo: titleContainer.centerXAnchor),
            balanceStack.leadingAnchor.constraint(greaterThanOrEqualTo: titleContainer.leadingAnchor),
            balanceStack.trailingAnchor.constraint(lessThanOrEqualTo: titleContainer.trailingAnchor),
                        
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
        updateBalanceRow()
    }

    func updateBalance() {
        updateBalanceRow()
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
    
    private func updateBalanceRow() {
        let balance = accountContext.balance
        balanceLabel.text = balance?.formatted(.baseCurrencyEquivalent)
        balanceContainer.isDisabled = balance == nil
        balanceContainer.isHidden = balance == nil
        updateBalanceWidth()

        for view in accountTypeIcons.arrangedSubviews {
            view.removeFromSuperview()
        }
        let addressLine = accountContext.addressLine
        var names: [String] = []
        if addressLine.isTestnet { names.append("inline_testnet") }
        if let leadingIcon = addressLine.leadingIcon {
            names.append(leadingIcon == .ledger ? "AccountTypeLedger" : "AccountTypeView")
        }
        for name in names {
            let imageView = UIImageView(image: .airBundle(name).withRenderingMode(.alwaysTemplate))
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .air.secondaryLabel
            accountTypeIcons.addArrangedSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 14),
                imageView.heightAnchor.constraint(equalToConstant: name == "inline_testnet" ? 14 : 14 * 2 / 3),
            ])
        }
        accountTypeIcons.isHidden = names.isEmpty
    }

    private func updateBalanceWidth() {
        // Keep the icon and balance centered together when the mask replaces the amount.
        balanceWidthConstraint.constant = balanceContainer.contentSizeThatFits(
            CGSize(width: .greatestFiniteMagnitude, height: balanceLabel.font.lineHeight)
        ).width
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
        
        balanceStack.alpha = 1 - collapseProgress
        balanceStack.accessibilityElementsHidden = collapseProgress == 1
        
        let titleMinScale = 17.0 / 24.0
        let titleScale = interpolate(from: 1.0, to: titleMinScale, progress: collapseProgress)
        let titleTransform = CGAffineTransform.identity.scaledBy(x: titleScale, y: titleScale)
        let topOverscroll = -min(0, scrollOffset)
        let titlePosition = interpolate(from: scrollRange, to: 0, progress: collapseProgress) + navigationCenterY + topOverscroll
                
        let balanceTransform = CGAffineTransform.identity
            .scaledBy(x: titleScale, y: titleScale)
            .translatedBy(x: 0, y: layoutGeometry.balanceRowShift * collapseProgress)
        
        isCollapsed = collapseProgress >= layoutGeometry.collapseThreshold
        
        applyUpdate(titlePosition: titlePosition, titleTransform: titleTransform, balanceTransform: balanceTransform)
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
    
    private func applyUpdate(titlePosition: CGFloat, titleTransform: CGAffineTransform, balanceTransform: CGAffineTransform) {
        self.titleCenterYConstraint.constant = titlePosition
        self.titleStack.transform = titleTransform
        self.balanceStack.transform = balanceTransform
        self.layoutIfNeeded()
    }
}

private class TitleStackView: UIView {
    let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        label.textAlignment = .center
        label.font = WTypography.uiFont(.prominentTitle)
        label.textColor = UIColor(light: "#333333", dark: "#FFFFFF")
        return label
    }()

    private var nameWidthConstraint: NSLayoutConstraint!
    var maximumContentWidth: CGFloat? {
        didSet {
            guard maximumContentWidth != oldValue else { return }
            setNeedsLayout()
        }
    }

    init() {
        super.init(frame: .zero)
        addSubview(nameLabel)
        nameWidthConstraint = nameLabel.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            nameWidthConstraint,
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateWithAccount(_ account: MAccount) {
        guard nameLabel.text != account.displayName else { return }
        nameLabel.text = account.displayName
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: nameLabel.intrinsicContentSize.height)
    }

    override func layoutSubviews() {
        nameWidthConstraint.constant = min(bounds.width, maximumContentWidth ?? bounds.width)
        super.layoutSubviews()
    }
}
