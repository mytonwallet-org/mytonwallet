
import UIKit
import UIComponents
import WalletCore
import WalletContext

let actionsRowHeight: CGFloat = IOS_26_MODE_ENABLED ? 70 : 60

@MainActor
class TokenExpandableContentView: NSObject, ExpandableNavigationView.ExpandableContent, WThemedView {

    public static let requiredScrollOffset: CGFloat = 139 + 40 + 16 + actionsRowHeight // after actions section

    private let navHeight = CGFloat(1048)
    private var token: ApiToken? = nil

    // layout constants
    let iconOffset: CGFloat = 15
    let iconSize: CGFloat = 60
    let balanceExpandedOffset: CGFloat = 139
    var balanceCollapsedOffset: CGFloat { -12 + (isInModal ? 6 : 0) }
    let equivalentExpandedSpacing: CGFloat = 8.667
    let equivalentCollapsedSpacing: CGFloat = -13
    var belowNavbarPadding: CGFloat { (IOS_26_MODE_ENABLED ? (isInModal ? 16 : 10) : 0) }
    var actionsOffset: CGFloat { 139 + 40 + 16 }
    var expandedHeight: CGFloat { actionsOffset + actionsRowHeight + 16 }

    let iconScrollModifier = 0.85
    let balanceScrollModifier = 0.8

    private let onHeightChange: () -> Void
    private let parentProcessorQueue: DispatchQueue
    private let isInModal: Bool

    init(isInModal: Bool,
         parentProcessorQueue: DispatchQueue,
         onHeightChange: @escaping () -> Void) {
        self.onHeightChange = onHeightChange
        self.parentProcessorQueue = parentProcessorQueue
        self.isInModal = isInModal
        super.init()
        setupViews()
    }

    // MARK: Sticky Views

    var balanceContainer: WSensitiveData<UIView> = .init(cols: 12, rows: 3, cellSize: 12, cornerRadius: 10, theme: .adaptive, alignment: .center)

    private let balanceView: BalanceView = {
        let lbl = BalanceView(config: .token)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    lazy var balanceStackView: UIView = {
        let v = UIView(frame: .zero)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(balanceView)
        NSLayoutConstraint.activate([
            balanceView.leftAnchor.constraint(equalTo: v.leftAnchor),
            balanceView.topAnchor.constraint(equalTo: v.topAnchor),
            balanceView.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            balanceView.rightAnchor.constraint(equalTo: v.rightAnchor),
        ])
        return v
    }()

    private var equivalentContainer: WSensitiveData<UIView> = .init(cols: 14, rows: 2, cellSize: 13, cornerRadius: 13, theme: .adaptive, alignment: .center)

    private let equivalentLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17)
        return lbl
    }()

    private var balanceStackTopConstraint: NSLayoutConstraint!
    private var equivalentLabelTopConstraint: NSLayoutConstraint!

    private var iconTopConstraint: NSLayoutConstraint? = nil
    private var actionsTopConstraint: NSLayoutConstraint? = nil
    private var chartContainerTopConstraint: NSLayoutConstraint? = nil
    private var chartContainerBottomConstraint: NSLayoutConstraint? = nil

    lazy var stickyStackView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false
        balanceContainer.addContent(balanceStackView)
        v.addSubview(balanceContainer)
        equivalentContainer.addContent(equivalentLabel)
        v.addSubview(equivalentContainer)
        equivalentLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        balanceStackTopConstraint = balanceStackView.topAnchor.constraint(equalTo: v.topAnchor, constant: balanceExpandedOffset)
        equivalentLabelTopConstraint = equivalentLabel.topAnchor.constraint(equalTo: balanceStackView.bottomAnchor, constant: equivalentExpandedSpacing)
        NSLayoutConstraint.activate([
            balanceStackView.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            balanceStackTopConstraint,
            equivalentLabelTopConstraint,
            equivalentLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
        ])
        return v
    }()

    lazy var stickyView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stickyStackView)
        NSLayoutConstraint.activate([
            stickyStackView.leftAnchor.constraint(equalTo: v.leftAnchor),
            stickyStackView.rightAnchor.constraint(equalTo: v.rightAnchor),
            stickyStackView.topAnchor.constraint(equalTo: v.topAnchor),
            stickyStackView.bottomAnchor.constraint(equalTo: v.bottomAnchor)
        ])
        return v
    }()

    // MARK: Content Views

    private lazy var iconView: IconView = {
        let v = IconView(size: 60)
        v.setChainSize(24, borderWidth: 1.5, borderColor: isInModal ? WTheme.sheetBackground : WTheme.groupedBackground, horizontalOffset: 5, verticalOffset: 1.5)
        v.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: true)
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var iconBlurView: WBlurredContentView = {
        let v = WBlurredContentView()
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var actionsStackView: TokenActionsView = {
        let actionsStackView = TokenActionsView(delegate: self)
        return actionsStackView
    }()

    lazy var contentView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(iconBlurView)
        iconBlurView.addSubview(iconView)

        v.addSubview(actionsStackView)
        iconTopConstraint = iconView.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: navHeight + iconOffset)
        actionsTopConstraint = actionsStackView.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: navHeight + actionsOffset)
        NSLayoutConstraint.activate([

            iconTopConstraint!,
            iconView.centerXAnchor.constraint(equalTo: v.centerXAnchor),

            iconBlurView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -50),
            iconBlurView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 50),
            iconBlurView.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -50),
            iconBlurView.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 50),

            actionsTopConstraint!,
            actionsStackView.heightAnchor.constraint(equalToConstant: actionsRowHeight),
            actionsStackView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -16),
        ])
        if IOS_26_MODE_ENABLED {
            NSLayoutConstraint.activate([
                actionsStackView.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                actionsStackView.leftAnchor.constraint(equalTo: v.leftAnchor, constant: S.insetSectionHorizontalMargin),
                actionsStackView.rightAnchor.constraint(equalTo: v.rightAnchor, constant: -S.insetSectionHorizontalMargin),
            ])
        }
        return v
    }()

    func setupViews() {
        updateTheme()
        setupTapGestures()
    }

    func setupTapGestures() {
        let g = UITapGestureRecognizer(target: self, action: #selector(onBalanceTap))
        balanceContainer.addGestureRecognizer(g)
        let g2 = UITapGestureRecognizer(target: self, action: #selector(onBalanceTap))
        equivalentContainer.addGestureRecognizer(g2)
    }

    @objc func onBalanceTap() {
        let isHidden = AppStorageHelper.isSensitiveDataHidden
        AppActions.setSensitiveDataIsHidden(!isHidden)
    }

    func updateTheme() {
        contentView.backgroundColor = isInModal ? WTheme.sheetBackground : WTheme.groupedBackground
        equivalentLabel.textColor = WTheme.secondaryLabel
    }

    func configure(token: ApiToken) {
        self.token = token
        iconView.config(with: token, isStaking: false, shouldShowChain: true)
        actionsStackView.swapAvailable = AccountStore.account?.supportsSwap == true
        actionsStackView.earnAvailable = AccountStore.account?.supportsEarn == true && token.earnAvailable
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }
            let walletToken = BalanceStore.currentAccountBalanceData?.walletTokens.first(where: { it in
                it.tokenSlug == token.slug
            })
            DispatchQueue.main.async { [weak self] in
                guard let self else {return}
                balanceView.set(balance: walletToken?.balance ?? 0,
                                currency: token.symbol,
                                tokenDecimals: token.decimals,
                                decimalsCount: tokenDecimals(for: walletToken?.balance ?? 0, tokenDecimals: token.decimals),
                                animated: nil)
                equivalentLabel.text = formatAmountText(amount: walletToken?.toBaseCurrency ?? 0,
                                                        currency: TokenStore.baseCurrency.sign,
                                                        decimalsCount: tokenDecimals(for: walletToken?.toBaseCurrency ?? 0, tokenDecimals: 9))
            }
        }
    }

    func update(scrollOffset: CGFloat) {

        let iconScrollModifier = scrollOffset > 0 ? iconScrollModifier : 1
        let balanceScrollModifier = scrollOffset > 0 ? balanceScrollModifier : 1

        // icon
        iconTopConstraint?.constant = max(navHeight - 165, navHeight + iconOffset - scrollOffset * iconScrollModifier)
        let blurProgress = 1 - min(1, max(0, (150 - scrollOffset) / 150))
        iconBlurView.blurRadius = blurProgress * 30
        iconView.alpha = min(1, max(0, (180 - scrollOffset) / 40))

        // balance stack + equvialent
        let expansionProgress = min(1, max(0, (balanceExpandedOffset - balanceCollapsedOffset - scrollOffset * balanceScrollModifier ) / (balanceExpandedOffset - balanceCollapsedOffset)))
        let scale = interpolate(from: 17.0 / WAnimatedAmountLabelConfig.token.primaryFont.pointSize, to: 1, progress: expansionProgress)
        let equivalentLabelScale = interpolate(from: 13.0/17.0, to: 1, progress: expansionProgress)

        balanceStackTopConstraint.constant = max(balanceCollapsedOffset, balanceExpandedOffset - scrollOffset * balanceScrollModifier) // multiplier visually compensates for the  gap below collapsing views
        balanceContainer.transform = .identity.scaledBy(x: scale, y: scale)

        equivalentLabelTopConstraint.constant = expansionProgress * equivalentExpandedSpacing + (1 - expansionProgress) * equivalentCollapsedSpacing
        equivalentContainer.transform = .identity.scaledBy(x: equivalentLabelScale, y: equivalentLabelScale)

        // actions
        let actionsTopMargin = actionsOffset - scrollOffset
        actionsTopConstraint?.constant = navHeight + max(belowNavbarPadding, actionsTopMargin)
        let actionsVisibleHeight = min(actionsRowHeight, max(0, actionsRowHeight + actionsTopMargin - belowNavbarPadding))
        actionsStackView.set(
            actionsVisibleHeight: actionsVisibleHeight
        )

        contentView.isHidden = actionsVisibleHeight == 0
    }
}


extension TokenExpandableContentView: TokenActionsView.Delegate {
    func addPressed() {
        AppActions.showReceive(chain: token?.chainValue, showBuyOptions: nil, title: nil)
    }

    func sendPressed() {
        AppActions.showSend(prefilledValues: .init(
            token: token?.slug
        ))
    }

    func swapPressed() {
        AppActions.showSwap(defaultSellingToken: token?.slug, defaultBuyingToken: token?.slug == "toncoin" ? nil : "toncoin", defaultSellingAmount: nil, push: nil)
    }

    func earnPressed() {
        AppActions.showEarn(token: token)
    }
}
