
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

let actionsRowHeight: CGFloat = TokenActionsView.rowHeight

@MainActor
class TokenExpandableContentView: NSObject, ExpandableNavigationView.ExpandableContent, WThemedView {

    public static let requiredScrollOffset: CGFloat = 139 + 40 + 16 + actionsRowHeight // after actions section

    private let navHeight = CGFloat(1048)
    private var token: ApiToken? = nil {
        didSet {
            actionsView.token = token
        }
    }

    // layout constants
    let iconOffset: CGFloat = 15
    let iconSize: CGFloat = 60
    let balanceExpandedOffset: CGFloat = 139
    var balanceCollapsedOffset: CGFloat { -12 + (isInModal ? 6 : 0) }
    var belowNavbarPadding: CGFloat { (IOS_26_MODE_ENABLED ? (isInModal ? 16 : 10) : 0) }
    var actionsOffset: CGFloat { 139 + 40 + 16 }
    var expandedHeight: CGFloat { actionsOffset + actionsRowHeight + 16 }

    let iconScrollModifier = 0.85
    let balanceScrollModifier = 0.8

    private let onHeightChange: () -> Void
    private let parentProcessorQueue: DispatchQueue
    private let isInModal: Bool
    @AccountContext private var account: MAccount

    init(accountContext: AccountContext,
         isInModal: Bool,
         parentProcessorQueue: DispatchQueue,
         onHeightChange: @escaping () -> Void) {
        self._account = accountContext
        self.onHeightChange = onHeightChange
        self.parentProcessorQueue = parentProcessorQueue
        self.isInModal = isInModal
        super.init()
        setupViews()
    }

    // MARK: Sticky Views

    private let balanceModel = TokenHeaderBalanceModel()

    private lazy var balanceHostingView: HostingView = HostingView {
        TokenHeaderBalanceView(model: balanceModel)
    }

    private var balanceStackTopConstraint: NSLayoutConstraint!
    private var iconTopConstraint: NSLayoutConstraint? = nil
    private var actionsTopConstraint: NSLayoutConstraint? = nil
    private var chartContainerTopConstraint: NSLayoutConstraint? = nil
    private var chartContainerBottomConstraint: NSLayoutConstraint? = nil

    lazy var stickyStackView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(balanceHostingView)
        balanceStackTopConstraint = balanceHostingView.topAnchor.constraint(equalTo: v.topAnchor, constant: balanceExpandedOffset)
        NSLayoutConstraint.activate([
            balanceHostingView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            balanceHostingView.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            balanceStackTopConstraint,
        ])
        return v
    }()

    lazy var stickyView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stickyStackView)
        NSLayoutConstraint.activate([
            stickyStackView.leftAnchor.constraint(equalTo: v.layoutMarginsGuide.leftAnchor),
            stickyStackView.rightAnchor.constraint(equalTo: v.layoutMarginsGuide.rightAnchor),
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

    private lazy var actionsView: TokenActionsView = TokenActionsView(token: token)

    lazy var contentView: WTouchPassView = {
        let v = WTouchPassView()
        v.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(iconBlurView)
        iconBlurView.addSubview(iconView)

        v.addSubview(actionsView)
        iconTopConstraint = iconView.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: navHeight + iconOffset)
        actionsTopConstraint = actionsView.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.topAnchor, constant: navHeight + actionsOffset)
        NSLayoutConstraint.activate([

            iconTopConstraint!,
            iconView.centerXAnchor.constraint(equalTo: v.layoutMarginsGuide.centerXAnchor),

            iconBlurView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -50),
            iconBlurView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 50),
            iconBlurView.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -50),
            iconBlurView.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 50),

            actionsTopConstraint!,
            actionsView.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -16),
        ])
        if TokenActionsView.usesSplitHomeActionStyle {
            NSLayoutConstraint.activate([
                actionsView.centerXAnchor.constraint(equalTo: v.layoutMarginsGuide.centerXAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                actionsView.leftAnchor.constraint(equalTo: v.leftAnchor, constant: S.insetSectionHorizontalMargin),
                actionsView.rightAnchor.constraint(equalTo: v.rightAnchor, constant: -S.insetSectionHorizontalMargin),
            ])
        }
        return v
    }()

    func setupViews() {
        updateTheme()
    }

    func updateTheme() {
        contentView.backgroundColor = isInModal ? WTheme.sheetBackground : WTheme.groupedBackground
    }

    func configure(token: ApiToken) {
        self.token = token
        iconView.config(with: token, isStaking: false, shouldShowChain: true)
        actionsView.sendAvailable = account.supportsSend
        actionsView.swapAvailable = account.supportsSwap
        actionsView.earnAvailable = account.supportsEarn && token.earnAvailable
        let walletTokens = $account.balanceData?.walletTokens
        let walletToken = walletTokens?.first { $0.tokenSlug == token.slug }
        balanceModel.token = token
        balanceModel.balance = walletToken?.balance ?? 0
        let baseCurrencyValue = walletToken?.toBaseCurrency ?? 0
        balanceModel.baseCurrencyAmount = BaseCurrencyAmount.fromDouble(baseCurrencyValue, TokenStore.baseCurrency)
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
        balanceStackTopConstraint.constant = max(balanceCollapsedOffset, balanceExpandedOffset - scrollOffset * balanceScrollModifier) // multiplier visually compensates for the  gap below collapsing views
        balanceModel.expansionProgress = expansionProgress

        // actions
        let actionsTopMargin = actionsOffset - scrollOffset
        actionsTopConstraint?.constant = navHeight + max(belowNavbarPadding, actionsTopMargin)
        let actionsVisibleHeight = min(actionsRowHeight, max(0, actionsRowHeight + actionsTopMargin - belowNavbarPadding))
        actionsView.set(actionsVisibleHeight: actionsVisibleHeight)

        contentView.isHidden = actionsVisibleHeight == 0
    }

    func updateSensitiveData() {
        balanceHostingView.setNeedsLayout()
    }
}

@Perceptible
private final class TokenHeaderBalanceModel {
    var token: ApiToken?
    var balance: BigInt?
    var baseCurrencyAmount: BaseCurrencyAmount?
    var expansionProgress: CGFloat = 1
}

private let primaryFontSize: CGFloat = 40

private struct TokenHeaderBalanceView: View {
    let model: TokenHeaderBalanceModel

    private var collapseProgress: CGFloat { 1 - model.expansionProgress }
    private var balanceScale: CGFloat { interpolate(from: 1, to: 17.0 / primaryFontSize, progress: collapseProgress) }
    private var equivalentScale: CGFloat { interpolate(from: 1, to: 13.0 / 17.0, progress: collapseProgress) }
    private var spacing: CGFloat { interpolate(from: expandedSpacing, to: collapsedSpacing, progress: collapseProgress) }
    private var bottomPadding: CGFloat { interpolate(from: 12, to: targetBottomPadding, progress: collapseProgress) }

    private let targetBottomPadding: CGFloat = IOS_26_MODE_ENABLED ? 48 : 44
    private let expandedSpacing: CGFloat = 5
    private let collapsedSpacing: CGFloat = -2

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: spacing) {
                balanceView
                    .minimumScaleFactor(0.1)
                    .scaleEffect(balanceScale, anchor: .bottom)
                equivalentView
                    .minimumScaleFactor(0.1)
                    .scaleEffect(equivalentScale, anchor: .top)
            }
            .frame(height: 74)
            .frame(minWidth: 300, maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .padding(.bottom, bottomPadding)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .contentShape(.rect)
            .onTapGesture {
                if AppStorageHelper.isSensitiveDataHidden {
                    AppActions.setSensitiveDataIsHidden(false)
                }
            }
        }
    }

    @ViewBuilder
    private var balanceView: some View {
        if let token = model.token, let balance = model.balance {
            let amount = TokenAmount(balance, token)
            let decimalsCount = tokenDecimals(for: balance, tokenDecimals: token.decimals)
            let fadeDecimals = integerPart(balance, tokenDecimals: token.decimals) >= 10
            AmountText(
                amount: amount,
                format: .init(maxDecimals: decimalsCount, showMinus: false, roundUp: false, precision: .exact),
                integerFont: .compactRounded(ofSize: 40, weight: .bold),
                fractionFont: .compactRounded(ofSize: 33, weight: .bold),
                symbolFont: .compactRounded(ofSize: 35, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: fadeDecimals ? WTheme.secondaryLabel : WTheme.primaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            .contentTransition(.numericText())
            .lineLimit(1)
            .animation(.default, value: amount.amount)
            .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 12, theme: .adaptive, cornerRadius: 10)
        } else {
            Color.clear
                .frame(height: 40)
        }
    }

    @ViewBuilder
    private var equivalentView: some View {
        if let baseCurrencyAmount = model.baseCurrencyAmount {
            Text(baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundUp: true))
                .font(.system(size: 17))
                .foregroundStyle(Color(WTheme.secondaryLabel))
                .lineLimit(1)
                .sensitiveData(alignment: .center, cols: 14, rows: 2, cellSize: 13, theme: .adaptive, cornerRadius: 13)
        } else {
            Color.clear
                .frame(height: 17)
        }
    }
}
