
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

@MainActor
final class TokenExpandableContentView: WTouchPassView {

    private var token: ApiToken? = nil
    
    let metrics = Metrics()

    @AccountContext private var account: MAccount

    init(accountContext: AccountContext) {
        self._account = accountContext
        super.init(frame: .fromSize(width: 200, height: 100))
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private let balanceModel = TokenHeaderBalanceModel()
    private lazy var balanceHostingView: HostingView = HostingView { TokenHeaderBalanceView(model: balanceModel) }

    private var iconTopConstraint: NSLayoutConstraint!
    private var balanceCenterConstraint: NSLayoutConstraint!
    private var balanceHeightConstraint: NSLayoutConstraint!

    private lazy var iconView: IconView = {
        let v = IconView(size: 60)
        v.setChainSize(24, borderWidth: 1.5, horizontalOffset: 5, verticalOffset: 1.5)
        v.config(with: token, isStaking: false, isWalletView: false, shouldShowChain: true)
        v.isUserInteractionEnabled = false
        return v
    }()

    private lazy var iconBlurView: WBlurredContentView = {
        let v = WBlurredContentView()
        v.isUserInteractionEnabled = false
        return v
    }()

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBlurView)
        iconBlurView.addSubview(iconView)
        iconTopConstraint = iconView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: metrics.iconTopExpanded)

        addSubview(balanceHostingView)
        balanceCenterConstraint = balanceHostingView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor)
        balanceHeightConstraint = balanceHostingView.heightAnchor.constraint(equalToConstant: metrics.balanceHostingExpandedHeight)

        NSLayoutConstraint.activate([
            iconTopConstraint,
            iconView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),

            iconBlurView.leadingAnchor.constraint(equalTo: iconView.leadingAnchor, constant: -50),
            iconBlurView.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 50),
            iconBlurView.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -50),
            iconBlurView.bottomAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 50),

            balanceCenterConstraint,
            balanceHeightConstraint,
            balanceHostingView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            balanceHostingView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            
            bottomAnchor.constraint(greaterThanOrEqualTo: balanceHostingView.bottomAnchor),
        ])
    }
    
    func configure(token: ApiToken) {
        self.token = token
        iconView.config(with: token, isStaking: false, shouldShowChain: true)
        let balance = $account.balances[token.slug] ?? 0
        let balanceAsDouble = balance.doubleAbsRepresentation(decimals: token.decimals)
        let baseCurrencyValue = balanceAsDouble * (token.price ?? 0)
        balanceModel.token = token
        balanceModel.balance = balance
        balanceModel.baseCurrencyAmount = BaseCurrencyAmount.fromDouble(baseCurrencyValue, TokenStore.baseCurrency)
    }

    func update(scrollOffset: CGFloat, navBarShift: CGFloat) {
        guard bounds.width > 0 else { return }
        
        let m = metrics
        let expansionProgress = m.getExpansionProgress(from: scrollOffset, clamped: true)
        let positionalOffset = max(0, scrollOffset)
        
        iconTopConstraint.constant = max(m.iconTopCollapsed, m.iconTopExpanded - positionalOffset * m.iconScrollModifier)
        let blurProgress = 1 - min(1, max(0, (150 - scrollOffset) / 150))
        iconBlurView.blurRadius = blurProgress * 30
        iconView.alpha = min(1, max(0, (180 - scrollOffset) / 40))
        
        balanceCenterConstraint.constant = interpolate(from: 0, to: m.balanceExpandedCenterY, progress: expansionProgress) - navBarShift
        balanceHeightConstraint.constant = interpolate(
            from: m.balanceHostingExpandedHeight,
            to: m.balanceHostingCollapsedHeight,
            progress: 1 - expansionProgress
        )
        balanceModel.expansionProgress = expansionProgress
    }
}

extension TokenExpandableContentView {
    struct Metrics {
        let iconTopExpanded: CGFloat = 12
        let iconTopCollapsed: CGFloat = -117
        let iconScrollModifier: CGFloat = 0.85
        
        let balanceExpandedCenterY = 162.0
        var balanceHostingExpandedHeight: CGFloat { 74 }
        var balanceHostingCollapsedHeight: CGFloat { 44 }
        
        let collapseThreshold: CGFloat = 0.5
                
        var fullScrollRange: CGFloat { 188 }

        /// adjust top cells top gap at collapsed state
        var adjustedFullScrollRange: CGFloat { fullScrollRange - 4 }

        var headerPlaceholderHeight: CGFloat { 164 }
        
        func getExpansionProgress(from scrollOffset: CGFloat, clamped: Bool) -> CGFloat {
            let positionalOffset = max(0, scrollOffset)
            let expansionProgress = interpolate(from: 1, to: 0, progress: positionalOffset / adjustedFullScrollRange)
            return clamped ? clamp(expansionProgress, min: 0, max: 1) : expansionProgress
        }
    }
}

@Perceptible
private final class TokenHeaderBalanceModel {
    var token: ApiToken?
    var balance: BigInt?
    var baseCurrencyAmount: BaseCurrencyAmount?
    var expansionProgress: CGFloat = 1
}

private struct TokenHeaderBalanceView: View {
    let model: TokenHeaderBalanceModel

    @State private var showsFullBalance = false

    private let primaryFontSize: CGFloat = 40
    private var collapseProgress: CGFloat { 1 - model.expansionProgress }
    private var balanceScale: CGFloat { interpolate(from: 1, to: 17.0 / primaryFontSize, progress: collapseProgress) }
    private var equivalentScale: CGFloat { interpolate(from: 1, to: 13.0 / 17.0, progress: collapseProgress) }
    private var spacing: CGFloat { interpolate(from: 5, to: -1, progress: collapseProgress) }
    private var bottomPadding: CGFloat { interpolate(from: 0, to: 24, progress: collapseProgress) }

    var body: some View {
        return WithPerceptionTracking {
            VStack(spacing: spacing) {
                balanceView
                    .minimumScaleFactor(0.1)
                    .scaleEffect(balanceScale, anchor: .bottom)
                equivalentView
                    .minimumScaleFactor(0.1)
                    .scaleEffect(equivalentScale, anchor: .top)
            }
            .frame(minWidth: 300, maxWidth: 300)
            .padding(.horizontal, 24)
            .padding(.bottom, bottomPadding)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var balanceView: some View {
        if let token = model.token, let balance = model.balance {
            let amount = TokenAmount(balance, token)
            let decimalsCount = showsFullBalance
                ? token.decimals
                : tokenDecimals(for: balance, tokenDecimals: token.decimals)
            let fadeDecimals = integerPart(balance, tokenDecimals: token.decimals) >= 10
            AmountText(
                amount: amount,
                format: .init(maxDecimals: decimalsCount, showMinus: false, roundHalfUp: false, precision: .exact),
                integerFont: .compactRounded(ofSize: primaryFontSize, weight: .bold),
                fractionFont: .compactRounded(ofSize: 33, weight: .bold),
                symbolFont: .compactRounded(ofSize: 35, weight: .bold),
                integerColor: UIColor.label,
                fractionColor: fadeDecimals ? .air.secondaryLabel : UIColor.label,
                symbolColor: .air.secondaryLabel
            )
            .contentTransition(.numericText())
            .lineLimit(1)
            .animation(.default, value: amount.amount)
            .animation(.default, value: showsFullBalance)
            .contentShape(Rectangle())
            .onTapGesture {
                showsFullBalance.toggle()
            }
            .onChange(of: token.slug) { _ in
                showsFullBalance = false
            }
            .onChange(of: balance) { _ in
                showsFullBalance = false
            }
            .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 12, theme: .adaptive, cornerRadius: 10)
        } else {
            Color.clear
                .frame(height: 40)
        }
    }

    @ViewBuilder
    private var equivalentView: some View {
        if let baseCurrencyAmount = model.baseCurrencyAmount {
            Text(baseCurrencyAmount.formatted(.baseCurrencyEquivalent, roundHalfUp: true))
                .font(.system(size: 17))
                .foregroundStyle(Color.air.secondaryLabel)
                .lineLimit(1)
                .sensitiveData(alignment: .center, cols: 14, rows: 2, cellSize: 13, theme: .adaptive, cornerRadius: 13)
        } else {
            Color.clear
                .frame(height: 17)
        }
    }
}
