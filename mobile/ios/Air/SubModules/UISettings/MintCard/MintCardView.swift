import Kingfisher
import UIKit
import UIComponents
import WalletContext
import WalletCore

final class MintCardView: UIView {
    var onUpgrade: (ApiMtwCardType) -> Void = { _ in }
    var isSubmitting = false {
        didSet { updateControls(); updatePlayback() }
    }
    private(set) var selectedPage = 0
    let scrollView = UIScrollView()
    let hero = MintCardHeroView(frame: .zero)
    let benefits = MintCardBenefitsView(frame: .zero)
    let upgradeButton = UIButton(type: .system)
    let discountNotice = UIView()
    let discountLabel = UILabel()
    let footerBackground = EdgeGradientView()
    private let content = UIView()
    private let pagingGesture = MintCardPagingGesture()
    private var cardsInfo: ApiCardsInfo?
    private var token: ApiToken?
    private var playbackActive = false
    private var posterPrefetcher: ImagePrefetcher?
    private var purchase = MintCardPurchaseState(cardInfo: nil, token: nil)
    private var countdownTimer: Timer?
    private var contentTransitionSnapshot: UIView?

    private var info: MintCardTypeInfo { .at(page: selectedPage) }
    private var canSelect: Bool { !isSubmitting && !hero.isTransitioning }

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        if #available(iOS 26, *) { scrollView.topEdgeEffect.isHidden = true; scrollView.bottomEdgeEffect.isHidden = true }
        addSubview(scrollView)
        scrollView.addSubview(content)
        content.addSubview(hero)
        content.addSubview(benefits)
        footerBackground.direction = .bottom
        addSubview(footerBackground)
        addSubview(discountNotice)
        discountNotice.addSubview(discountLabel)
        discountNotice.backgroundColor = .air.background
        discountNotice.layer.cornerCurve = .continuous
        discountLabel.applyTextStyle(.supporting, scaling: .dynamic)
        discountLabel.numberOfLines = 0
        discountLabel.textAlignment = .center
        discountLabel.lineBreakStrategy = .pushOut
        discountLabel.textColor = .air.secondaryLabel
        discountLabel.isAccessibilityElement = true
        discountLabel.accessibilityIdentifier = "MintCardDiscount"
        addSubview(upgradeButton)
        upgradeButton.accessibilityIdentifier = "MintCardUpgrade"
        upgradeButton.addAction(UIAction { [weak self] _ in
            guard let self, canSelect, purchase.isEnabled else { return }
            onUpgrade(info.type)
        }, for: .touchUpInside)
        hero.onSelect = { [weak self] in self?.select(offset: $0) }
        hero.onTransitionEnd = { [weak self] in self?.upgradeButton.isUserInteractionEnabled = true }
        pagingGesture.canSelect = { [weak self] in self?.canSelect == true }
        pagingGesture.onSelect = { [weak self] in self?.select(offset: $0) }
        addGestureRecognizer(pagingGesture)
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        MainActor.assumeIsolated {
            countdownTimer?.invalidate()
        }
    }

    func configure(cardsInfo: ApiCardsInfo?, token: ApiToken?) {
        guard self.cardsInfo != cardsInfo || self.token != token else { return }
        self.cardsInfo = cardsInfo
        self.token = token
        updateSelection()
    }

    func select(offset: Int, animated: Bool = true) {
        guard canSelect, offset != 0 else { return }
        selectedPage = (selectedPage + offset % MintCardTypeInfo.ordered.count + MintCardTypeInfo.ordered.count) % MintCardTypeInfo.ordered.count
        updateSelection(direction: offset, animated: animated)
        upgradeButton.isUserInteractionEnabled = !hero.isTransitioning
        UIAccessibility.post(notification: .pageScrolled, argument: lang(info.displayNameKey))
    }

    private func updateSelection(direction: Int = 1, animated: Bool = false) {
        contentTransitionSnapshot?.removeFromSuperview()
        contentTransitionSnapshot = nil
        layoutIfNeeded()
        let lowerTop = min(bounds.height, max(0, hero.convert(hero.bounds, to: self).maxY))
        let lowerFrame = CGRect(x: 0, y: lowerTop, width: bounds.width, height: bounds.height - lowerTop)
        // Fade the lower surface together without including the hero's separate wipe.
        let snapshot = animated && MintCardTransition.isEnabled(in: self) && lowerFrame.height > 0
            ? resizableSnapshotView(from: lowerFrame, afterScreenUpdates: false, withCapInsets: .zero) : nil
        purchase = MintCardPurchaseState(cardInfo: cardsInfo?[info.type], token: token)
        UIView.performWithoutAnimation {
            backgroundColor = info.surfaceColor
            footerBackground.color = info.surfaceColor
            benefits.configure(info)
        }
        hero.configure(info: info, cardInfo: cardsInfo?[info.type], direction: direction, animated: animated)
        updateDiscountNotice()
        updateControls(animated: snapshot == nil && animated && hero.isTransitioning)
        updateCountdownTimer()
        preloadNeighbors()
        layoutIfNeeded()
        if let snapshot {
            snapshot.frame = lowerFrame
            snapshot.isUserInteractionEnabled = false
            snapshot.accessibilityElementsHidden = true
            addSubview(snapshot)
            contentTransitionSnapshot = snapshot
            UIView.animate(withDuration: MintCardTransition.duration, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                snapshot.alpha = 0
            } completion: { [weak self] _ in
                snapshot.removeFromSuperview()
                if self?.contentTransitionSnapshot === snapshot { self?.contentTransitionSnapshot = nil }
            }
        }
    }

    private func updateDiscountNotice() {
        let discount = cardsInfo?[info.type]?.discount
        discountNotice.isHidden = discount == nil
        guard let discount else { return }
        let card = lang(info.displayNameKey)
        let percent = "\(localizedIntegerString(discount.percent))%"
        let text = discount.isApplied
            ? L10n.congratsYourFirstCardComesAtPercentOff(card: card, percent: percent)
            : L10n.mostActiveUsersGetPercentOffTheirFirstCardTradeOrStakeToQualifyForNextTime(percent: percent, card: card)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakStrategy = .pushOut
        paragraph.minimumLineHeight = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 20)
        // Center the line box, then lift the text slightly for optical alignment.
        let baselineOffset = (paragraph.minimumLineHeight - discountLabel.font.lineHeight) / 2 + 0.3
        discountLabel.attributedText = NSAttributedString(string: text, attributes: [
            .paragraphStyle: paragraph,
            .baselineOffset: baselineOffset,
        ])
    }

    private func updateControls(animated: Bool = false) {
        let showsCountdown = cardsInfo?[info.type]?.mintCountdownDate != nil
        let isEnabled = purchase.isEnabled && !isSubmitting
        var configuration: UIButton.Configuration
        if showsCountdown {
            configuration = .filled()
            configuration.background.backgroundColor = .systemGray2
            configuration.background.backgroundColorTransformer = UIConfigurationColorTransformer { _ in .systemGray2 }
        } else if #available(iOS 26, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .filled()
        }
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        configuration.baseBackgroundColor = info.accentColor(for: traitCollection)
        let titleColor = showsCountdown ? UIColor.white : info.titleColor(for: traitCollection, isEnabled: isEnabled)
        configuration.baseForegroundColor = titleColor
        // Glass styling otherwise replaces the disabled title color on iOS 26.
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.foregroundColor = titleColor
            return outgoing
        }
        let font = WTypography.uiFont(.bodyEmphasized, scaling: .dynamic)
        var titleAttributes: [NSAttributedString.Key: Any] = [.font: font]
        if showsCountdown {
            titleAttributes[.foregroundColor] = UIColor.white
            titleAttributes[.font] = UIFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .semibold)
        }
        configuration.attributedTitle = AttributedString(purchase.title, attributes: AttributeContainer(titleAttributes))
        configuration.titleAlignment = .center
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.showsActivityIndicator = isSubmitting
        MintCardTransition.crossfade(upgradeButton, animated: animated) {
            self.upgradeButton.configuration = configuration
            self.upgradeButton.isEnabled = isEnabled
        }
        upgradeButton.accessibilityLabel = purchase.title
        upgradeButton.accessibilityValue = isSubmitting ? lang("Loading") : nil
        setNeedsLayout()
    }

    func setPlaybackActive(_ active: Bool) {
        playbackActive = active
        updatePlayback()
        refreshCountdown()
    }

    func refreshCountdown(now: Date = .now) {
        purchase = MintCardPurchaseState(cardInfo: cardsInfo?[info.type], token: token, now: now)
        updateControls()
        updateCountdownTimer(now: now)
    }

    private func updateCountdownTimer(now: Date = .now) {
        guard playbackActive, window != nil,
              let startsAt = cardsInfo?[info.type]?.mintCountdownDate, startsAt > now else {
            countdownTimer?.invalidate()
            countdownTimer = nil
            return
        }
        guard countdownTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshCountdown() }
        }
        countdownTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updatePlayback() {
        hero.setPlaybackActive(playbackActive && !isSubmitting)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            posterPrefetcher?.stop()
            posterPrefetcher = nil
            hero.setPlaybackActive(false)
        } else {
            preloadNeighbors()
            updatePlayback()
        }
        refreshCountdown()
    }

    private func preloadNeighbors() {
        guard window != nil else { return }
        posterPrefetcher?.stop()
        let urls = [-1, 0, 1].compactMap { MintCardTypeInfo.at(page: selectedPage + $0).posterURL }
        posterPrefetcher = ImagePrefetcher(urls: urls, options: MintCardMediaView.imageOptions)
        posterPrefetcher?.start()
        guard AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled else { return }
        let page = selectedPage
        Task(priority: .utility) { await MintCardVideoCache.shared.preloadNeighbors(of: page) }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateSelection()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let textWidth = max(1, width - 104)
        let titleHeight = (purchase.title as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: WTypography.uiFont(.bodyEmphasized, scaling: .dynamic)], context: nil
        ).height.rounded(.up)
        let buttonHeight = max(52, titleHeight + 24)
        upgradeButton.frame = CGRect(x: 36, y: bounds.height - safeAreaInsets.bottom - 2 - buttonHeight, width: max(0, width - 72), height: buttonHeight)
        let hasNotice = !discountNotice.isHidden && discountLabel.text?.isEmpty == false
        let naturalNoticeSize = hasNotice
            ? discountLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)) : .zero
        let noticeWidth = min(max(0, width - 32), ceil(naturalNoticeSize.width) + 24)
        let noticeSize = hasNotice
            ? discountLabel.sizeThatFits(CGSize(width: max(1, noticeWidth - 24), height: .greatestFiniteMagnitude)) : .zero
        let noticeHeight = noticeSize.height > 0 ? ceil(noticeSize.height) + 16 : 0
        discountNotice.frame = CGRect(x: (width - noticeWidth) / 2, y: upgradeButton.frame.minY - 16 - noticeHeight, width: noticeWidth, height: noticeHeight)
        discountNotice.layer.cornerRadius = min(26, noticeHeight / 2)
        discountLabel.frame = discountNotice.bounds.insetBy(dx: 12, dy: 8)
        let footerTop = hasNotice ? discountNotice.frame.minY - 16 : upgradeButton.frame.minY - 16
        let fadeTop = max(0, footerTop - 32)
        footerBackground.frame = CGRect(x: 0, y: fadeTop, width: width, height: bounds.height - fadeTop)
        footerBackground.solidEdgeLength = max(0, bounds.height - footerTop)
        // Scroll beneath the fade, with enough clearance to reveal the last row above it.
        let previousOffset = scrollView.contentOffset
        scrollView.frame = bounds
        scrollView.contentInset.bottom = bounds.height - fadeTop + 16
        let heroHeight = hero.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        hero.frame = CGRect(x: 0, y: 0, width: width, height: heroHeight)
        let benefitsWidth = max(0, width - 32)
        let benefitsHeight = benefits.sizeThatFits(CGSize(width: benefitsWidth, height: .greatestFiniteMagnitude)).height
        benefits.frame = CGRect(x: 16, y: heroHeight + 16, width: benefitsWidth, height: benefitsHeight)
        content.frame = CGRect(x: 0, y: 0, width: width, height: benefits.frame.maxY)
        scrollView.contentSize = content.bounds.size
        let maximumOffset = max(0, scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height)
        scrollView.contentOffset = CGPoint(x: previousOffset.x, y: min(previousOffset.y, maximumOffset))
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard canSelect else { return false }
        let forward = effectiveUserInterfaceLayoutDirection == .rightToLeft ? -1 : 1
        switch direction {
        case .left: select(offset: forward)
        case .right: select(offset: -forward)
        case .next: select(offset: 1)
        case .previous: select(offset: -1)
        default: return false
        }
        return true
    }
}

@MainActor
struct MintCardPurchaseState {
    let title: String
    let isEnabled: Bool

    init(cardInfo: ApiCardInfo?, token: ApiToken?, now: Date = .now) {
        if let startsAt = cardInfo?.mintCountdownDate {
            let remaining = Int(max(0, ceil(startsAt.timeIntervalSince(now))))
            let countdown = String(format: "%02lld:%02lld:%02lld", Int64(remaining / 3600), Int64(remaining / 60 % 60), Int64(remaining % 60))
            title = L10n.mintStartsInTime(time: countdown)
            isEnabled = false
        } else if let cardInfo, cardInfo.all <= 0 || cardInfo.notMinted <= 0 {
            title = lang("This card has been sold out")
            isEnabled = false
        } else if let cardInfo, let token, cardInfo.price.isFinite, cardInfo.price > 0,
                  token.tokenAddress?.nilIfEmpty != nil,
                  TokenAmount.fromDouble(cardInfo.price, token).amount > 0 {
            title = L10n.upgradeForAmountCurrency(
                amount: DecimalAmountFormatStyle(showSymbol: false).format(TokenAmount.fromDouble(cardInfo.price, token)),
                currency: token.symbol
            )
            isEnabled = true
        } else {
            title = lang("Unavailable")
            isEnabled = false
        }
    }
}
