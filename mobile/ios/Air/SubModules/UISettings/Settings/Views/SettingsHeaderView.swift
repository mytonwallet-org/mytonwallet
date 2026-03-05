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

protocol SettingsHeaderViewDelegate: AnyObject {
    func settingsHeaderViewDidTapQRCodeButton()
}

class SettingsHeaderView: WTouchPassView {
    weak var delegate: SettingsHeaderViewDelegate?
    
    private var qrButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(named: "QRIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
        return btn
    }()

    private var moreButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(named: "More22", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
        return btn
    }()
    
    private lazy var blurView = WBlurView()
    
    private lazy var navBarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.clipsToBounds = false

        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
           
        } else {
            headerTouchTarget.translatesAutoresizingMaskIntoConstraints = false
            let buttonSize: CGFloat = 44
            let buttonMidY = buttonSize / 2

            view.addSubview(blurView)
            view.addSubview(qrButton)
            view.addSubview(moreButton)
            qrButton.addTarget(self, action: #selector(qrPressed), for: .touchUpInside)
            view.addSubview(headerTouchTarget)

            NSLayoutConstraint.activate([
                blurView.leftAnchor.constraint(equalTo: view.leftAnchor),
                blurView.rightAnchor.constraint(equalTo: view.rightAnchor),
                blurView.topAnchor.constraint(equalTo: view.topAnchor),
                blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                qrButton.heightAnchor.constraint(equalToConstant: buttonSize),
                qrButton.widthAnchor.constraint(equalToConstant: buttonSize),
                qrButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -buttonMidY),
                qrButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                
                moreButton.heightAnchor.constraint(equalToConstant: buttonSize),
                moreButton.widthAnchor.constraint(equalToConstant: buttonSize),
                moreButton.centerYAnchor.constraint(equalTo: view.bottomAnchor, constant: -buttonMidY),
                moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),

                headerTouchTarget.leftAnchor.constraint(equalTo: view.leftAnchor, constant: layoutGeometry.titleCollapsedHorMargin),
                headerTouchTarget.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -layoutGeometry.titleCollapsedHorMargin),
                headerTouchTarget.topAnchor.constraint(equalTo: qrButton.topAnchor),
                headerTouchTarget.bottomAnchor.constraint(equalTo: qrButton.bottomAnchor),
            ])
        }
        return view
    }()
        
    lazy var headerTouchTarget: UIView = {
        
        class HeaderTouchTarget: UILabel {
            var onWindowMoved: (() -> Void)?
            var onSizeChanged: (() -> Void)?
            var prevSize: CGSize?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                if window != nil {
                    onWindowMoved?()
                }
            }
            
            override func layoutSubviews() {
                super.layoutSubviews()
                if prevSize != bounds.size {
                    prevSize = bounds.size
                    onSizeChanged?()
                }
            }
        }
        
        let view = HeaderTouchTarget()
        view.text = String(repeating: "A", count: 100)
        view.textColor = .clear
        view.font = .systemFont(ofSize: 24)
        view.isUserInteractionEnabled = true
        view.accessibilityElementsHidden = true
        view.onWindowMoved = { [weak self] in
            guard let self else { return }
            self.updateWithLastScrollOffset()
        }
        view.onSizeChanged = { [weak self] in
            guard let self else { return }
            self.updateWithLastScrollOffset()
        }
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTouched)))
        return view
    }()
    
    private var avatarImageView: IconView = IconView(size: 88)
    
    private var avatarBlurView: WBlurredContentView = {
        let v = WBlurredContentView()
        return v
    }()
    
    private var addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        return label
    }()
    
    struct LayoutGeometry {
        private var isLegacyOS: Bool {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                return false
            }
            return true
        }
        
        let titleHorMargin: CGFloat = 16.0
        var titleHorMarginCollapsedInset: CGFloat { isLegacyOS ? 40 : 56 }
        var titleCollapsedHorMargin: CGFloat { titleHorMargin +  titleHorMarginCollapsedInset}

        let distanceBetweenTitleAndAvatarMidY: CGFloat = 73

        /// The key parameter. A distance between navigation buttons and the title vertical centers.
        /// In fact, this is the real movement range for the title.
        let distanceBetweenNavButtonAndTitleStackMiddles: CGFloat = 108.0

        /// The value is used to shift top section to be closer to the title in the collapsed mode
        private var topSectionCollapsedInset: CGFloat { isLegacyOS ? 18 : 26 }
        
        var topSectionInset: CGFloat { isLegacyOS ? 40 : 32 }

        let collapseThreshold = 0.5

        var addressLabelShift: CGFloat { isLegacyOS ? -12 : -17 }

        var scrollTopContentInset: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles }
        var scrollRange: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles }
        var fullScrollRange: CGFloat { distanceBetweenNavButtonAndTitleStackMiddles + topSectionCollapsedInset }
                
        /// Directly is not involved in the view but used for additionalSafeAreaInsets in the parent VC
        let legacyNavBarHeight: CGFloat = 44.0
    }
    
    let layoutGeometry: LayoutGeometry = .init()
        
    private let largeTitleStack = TitleStackView(fontSize: 24)
    private let smallTitleStack = TitleStackView(fontSize: 17)
    private let titleContainer = WTouchPassView()
    private var titleCenterYConstraint: NSLayoutConstraint!

    private var isCollapsed = false {
        didSet {
            if isCollapsed != oldValue {
                Haptics.play(.transition)
            }
        }
    }
    
    private var lastScrollOffset: CGFloat = 0
    private var hasPerformedInitialLayout = false
    
    private var separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = WTheme.separator
        view.alpha = 0
        return view
    }()

    private var avatarCenterYConstraint: NSLayoutConstraint!
    private var navBarViewHeightConstraint: NSLayoutConstraint!
    private let navigationLayoutGuide = UILayoutGuide()
    private var navigationLayoutGuideCenterYConstraint: NSLayoutConstraint!

    func setupViews(moreMenu: UIMenu) {
        shouldAcceptTouchesOutside = true

        moreButton.menu = moreMenu
        moreButton.showsMenuAsPrimaryAction = true
        
        largeTitleStack.translatesAutoresizingMaskIntoConstraints = false
        smallTitleStack.translatesAutoresizingMaskIntoConstraints = false
        titleContainer.addSubview(largeTitleStack)
        titleContainer.addSubview(smallTitleStack)

        translatesAutoresizingMaskIntoConstraints = false
        titleContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(avatarBlurView)
        avatarBlurView.addSubview(avatarImageView)
        addSubview(navBarView)
        addSubview(separatorView)
        addSubview(titleContainer)
        addSubview(addressLabel)
        addLayoutGuide(navigationLayoutGuide)
                
        avatarCenterYConstraint = avatarImageView.centerYAnchor.constraint(equalTo: largeTitleStack.centerYAnchor)
        navBarViewHeightConstraint = navBarView.heightAnchor.constraint(equalToConstant: 0)
        navigationLayoutGuideCenterYConstraint = navigationLayoutGuide.centerYAnchor.constraint(equalTo: topAnchor)
        titleCenterYConstraint = titleContainer.centerYAnchor.constraint(equalTo: navigationLayoutGuide.centerYAnchor)

        NSLayoutConstraint.activate([
            avatarCenterYConstraint,
            avatarImageView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            
            avatarBlurView.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -50),
            avatarBlurView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 50),
            avatarBlurView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -50),
            avatarBlurView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 50),
            
            navigationLayoutGuideCenterYConstraint,
            navigationLayoutGuide.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: layoutGeometry.titleCollapsedHorMargin),
            navigationLayoutGuide.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -layoutGeometry.titleCollapsedHorMargin),
            navigationLayoutGuide.heightAnchor.constraint(equalToConstant: 0),

            navBarView.topAnchor.constraint(equalTo: topAnchor),
            navBarView.leftAnchor.constraint(equalTo: leftAnchor),
            navBarView.rightAnchor.constraint(equalTo: rightAnchor),
            navBarViewHeightConstraint,

            smallTitleStack.centerYAnchor.constraint(equalTo: titleContainer.centerYAnchor),
            smallTitleStack.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor, constant: layoutGeometry.titleHorMarginCollapsedInset),
            smallTitleStack.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor, constant: -layoutGeometry.titleHorMarginCollapsedInset),
            
            largeTitleStack.topAnchor.constraint(equalTo: titleContainer.topAnchor),
            largeTitleStack.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            largeTitleStack.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
            largeTitleStack.bottomAnchor.constraint(equalTo: titleContainer.bottomAnchor),

            titleCenterYConstraint,
            titleContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: layoutGeometry.titleHorMargin),
            titleContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -layoutGeometry.titleHorMargin),
            
            addressLabel.topAnchor.constraint(equalTo: largeTitleStack.bottomAnchor, constant: 4),
            addressLabel.leadingAnchor.constraint(equalTo: titleContainer.leadingAnchor),
            addressLabel.trailingAnchor.constraint(equalTo: titleContainer.trailingAnchor),
                        
            separatorView.bottomAnchor.constraint(equalTo: navBarView.bottomAnchor),
            separatorView.leftAnchor.constraint(equalTo: navBarView.leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: navBarView.rightAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33),

            heightAnchor.constraint(equalToConstant: 200) // in fact it affects almost nothing 
        ])
        
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            separatorView.isHidden = true
        }
        
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
        
        Haptics.prepare(.transition)
    }
    
    var tapCount = 0
    @objc private func headerTapped() {
        tapCount += 1
        if tapCount == 5 {
            WalletContextManager.delegate?.switchToCapacitor()
        }
    }
         
    func config() {
        guard let account = AccountStore.account else {
            return
        }
        
        avatarImageView.config(with: account)
        updateTitle()
        updateAddresses()
    }
    
    private func updateTitle() {
        guard let account = AccountStore.account else {
            return
        }
        largeTitleStack.updateWithAccount(account)
        smallTitleStack.updateWithAccount(account)
    }
    
    private func updateAddresses() {
        guard let account = AccountStore.account else {
            return
        }
        let addressLine = account.addressLine
        addressLabel.attributedText = addressLine.attributedString(
            font: .systemFont(ofSize: 16, weight: .regular),
            color: WTheme.secondaryLabel
        )
    }
    
    func updateBalance() {
        updateTitle()
    }
    
    @objc private func headerTouched(recognizer: UIGestureRecognizer) {
        if isCollapsed && smallTitleStack.alpha > 0 {
            let location = recognizer.location(in: smallTitleStack)
            smallTitleStack.handleTouchAt(location: location)
        }
    }
    
    fileprivate func updateWithLastScrollOffset() {
        update(scrollOffset: lastScrollOffset)
    }

    func update(scrollOffset: CGFloat) {
        let horizontalSpace = bounds.width
        guard horizontalSpace > 0 else { return }
        guard headerTouchTarget.superview != nil else { return }
        
        lastScrollOffset = scrollOffset
        
        let scrollMultiplier: CGFloat = scrollOffset > 0 ? 0.85 : 1
        let scrollNonNegative = max(scrollOffset, 0)
        avatarCenterYConstraint.constant = -layoutGeometry.distanceBetweenTitleAndAvatarMidY - scrollNonNegative * 1.0 / (1.0 + log(1 + scrollNonNegative))
 
        let blurProgress: CGFloat = 1.0 - min(1.0, max(0.0, (155.0 - scrollOffset * scrollMultiplier) / 155.0))
        avatarBlurView.blurRadius = blurProgress * 30
        avatarImageView.alpha = min(1.0, max(0.0, (190.0 - scrollOffset * scrollMultiplier) / 40.0))
                         
        navBarViewHeightConstraint.constant = safeAreaInsets.top
        navigationLayoutGuideCenterYConstraint.constant = headerTouchTarget.convert(headerTouchTarget.bounds.center, to: self).y
        
        let scrollRange = layoutGeometry.scrollRange
        let collapseProgress = max(0, min(1, scrollOffset / layoutGeometry.fullScrollRange))
        
        UIView.animate(withDuration: 0.3) {
            self.addressLabel.alpha = 1 - collapseProgress
            let alpha = scrollOffset > self.layoutGeometry.fullScrollRange ? 1.0 : 0.0
            self.separatorView.alpha = alpha
            self.blurView.alpha = alpha
        }
        
        let titleArea = horizontalSpace - layoutGeometry.titleHorMargin * 2
        let titleCollapsedArea = horizontalSpace - 2 * layoutGeometry.titleCollapsedHorMargin
        let titleMinScale = titleCollapsedArea / titleArea
        let easeOutProgress = 1 - pow(1 - collapseProgress, 3)
        let titleScale = interpolate(from: 1.0, to: titleMinScale, progress: easeOutProgress)

        let collapseThreshold = layoutGeometry.collapseThreshold

        let titleTransform = CGAffineTransform.identity.scaledBy(x: titleScale, y: titleScale)
        let titlePosition = interpolate(from: scrollRange, to: 0, progress: collapseProgress >= collapseThreshold ? 1.0 : collapseProgress)
                
        let addressTransform = CGAffineTransform.identity
            .scaledBy(x: titleScale, y: titleScale)
            .translatedBy(x: 0, y: layoutGeometry.addressLabelShift * collapseProgress)
        
        isCollapsed = collapseProgress >= collapseThreshold
        
        if !hasPerformedInitialLayout {
            hasPerformedInitialLayout = true
            UIView.performWithoutAnimation {
                applyUpdate(titlePosition: titlePosition, titleTransform: titleTransform, addressTransform: addressTransform)
            }
        } else {
            applyUpdate(titlePosition: titlePosition, titleTransform: titleTransform, addressTransform: addressTransform)
        }
    }
        
    private func applyUpdate(titlePosition: CGFloat, titleTransform: CGAffineTransform, addressTransform: CGAffineTransform) {
        UIView.animate(withDuration: 0.12, delay: self.isCollapsed ? 0 : 0.12) {
            self.smallTitleStack.alpha = self.isCollapsed ? 1 : 0
            self.largeTitleStack.alpha = self.isCollapsed ? 0 : 1
        }
        self.titleCenterYConstraint.constant = titlePosition
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
            self.largeTitleStack.transform = titleTransform
            self.addressLabel.transform = addressTransform
            self.layoutIfNeeded()
        }
    }
                
    @objc private func qrPressed() {
        delegate?.settingsHeaderViewDidTapQRCodeButton()
    }
}

private class TitleStackView: UIView {
    private let font: UIFont
        
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
            label.textColor = WTheme.secondaryLabel
            
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
    
    private var separatorLeadingCostraint: NSLayoutConstraint!
    private var nameLeadingConstraint: NSLayoutConstraint!
    private var nameWidthConstraint: NSLayoutConstraint!
    private var hasPerformedInitialLayout = false

    private lazy var separatorDotLabel: UILabel = {
        let label = UILabel()
        label.textColor = WTheme.secondaryLabel
        label.text = "\u{202f}·\u{202f}"
        label.font = font
        return label
    }()
    
    lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        label.adjustsFontSizeToFitWidth = false
        label.allowsDefaultTighteningForTruncation = false
        label.font = font
        label.textColor = WTheme.primaryLabel
        return label
    }()
    
    init(fontSize: CGFloat) {
        font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        fullBalance = BalanceViewContext(font: font, cellSize: ceil(fontSize / 3))
        shortenedBalance = BalanceViewContext(font: font, cellSize: ceil(fontSize / 3))

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
        
        observationToken = NotificationCenter.default.addObserver(
            forName: .updateSensitiveData,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layoutIfNeededAnimated()
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
        balance = BalanceStore.accountBalanceData[account.id]?.totalBalance
        if oldBalance != balance {
            fullBalance.label.text = balance?.formatted(.baseCurrencyEquivalent)
            shortenedBalance.label.text = balance?.formatted(.baseCurrencyEquivalentShortened)
            separatorDotLabel.isHidden = balance == nil
            fullBalance.container.isDisabled = balance == nil
            shortenedBalance.container.isDisabled = balance == nil
            shouldUpdateLayout = true
        }
        
        if shouldUpdateLayout {
            layoutIfNeededAnimated()
        }
    }
    
    func handleTouchAt(location: CGPoint)  {
        if shortenedBalance.container.alpha > 0 {
            if shortenedBalance.container.frame.contains(location) {
                shortenedBalance.container.performTap()
            }
            return
        }
        if fullBalance.container.alpha > 0 {
            if fullBalance.container.frame.contains(location) {
                fullBalance.container.performTap()
            }
            return
        }
    }
    
    private func layoutIfNeededAnimated() {
        self.setNeedsLayout()
        if !hasPerformedInitialLayout {
            UIView.performWithoutAnimation {
                layoutIfNeeded()
            }
            hasPerformedInitialLayout = true
        } else {
            UIView.animate(withDuration: 0.15) {
                self.layoutIfNeeded()
            }
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
        var contentLength: CGFloat = 0
        
        var nameLabelWidth = ceil(nameLabel.sizeThatFits(.init(width: .greatestFiniteMagnitude, height: b.height)).width)
        let separatorDotLabelWidth = ceil(separatorDotLabel.sizeThatFits(.init(width: .greatestFiniteMagnitude, height: b.height)).width)

        // Update balances. Use alpha for visibility, not isHidden, to avoid layout loops
        var showFullBalance = false
        var showShortenedBalance = false
        if balance != nil {
            let fullBalanceWidth = ceil(fullBalance.widthThatFitsHeight(b.height))
            if nameLabelWidth + separatorDotLabelWidth + fullBalanceWidth > b.width {
                showShortenedBalance = true
                contentLength += ceil(shortenedBalance.widthThatFitsHeight(b.height))
            } else {
                showFullBalance = true
                contentLength += fullBalanceWidth
            }
            contentLength += separatorDotLabelWidth
        }
        fullBalance.container.alpha = showFullBalance ? 1.0 : 0.0
        shortenedBalance.container.alpha = showShortenedBalance ? 1.0 : 0.0

        // Final name length. Shorten if needed. Recalculate if shortened (it usually be less due truncation specifics)
        if nameLabelWidth + contentLength > b.width {
            nameLabelWidth = max(0, b.width - contentLength)
            if nameLabelWidth > 0 {
                 nameLabelWidth = getIntrinsicNameWidth(forWidth: nameLabelWidth)
            }
        }
        contentLength += nameLabelWidth
        
        var offsetX = max(0.0, ((b.width - contentLength) / 2).rounded())

        nameWidthConstraint.constant = nameLabelWidth
        nameLeadingConstraint.constant = offsetX
        offsetX += nameLabelWidth
        
        separatorLeadingCostraint.constant = offsetX
        offsetX += separatorDotLabelWidth
        
        fullBalance.leadingConstraint.constant = offsetX
        shortenedBalance.leadingConstraint.constant = offsetX
        
        super.layoutSubviews()
    }
}
