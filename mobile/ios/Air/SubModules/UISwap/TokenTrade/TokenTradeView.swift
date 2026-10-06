import SwiftUI
import Perception
import UIComponents
import WalletCore
import WalletContext

struct TokenTradeView: View {
    let model: TokenTradeModel
    let selectMethod: () -> Void
    let continueAction: () -> Void
    @State private var editor = TokenTradeEditor()
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { geometry in
                let bottomInset = max(32, geometry.safeAreaInsets.bottom)
                let preferredContentHeight: CGFloat = 320 + 84
                let keypadHeight = min(256, max(176, geometry.size.height - preferredContentHeight - 88 - bottomInset))
                let controlsHeight = 88 + keypadHeight + bottomInset
                let contentHeight = max(0, geometry.size.height - controlsHeight)
                VStack(spacing: 0) {
                    ScrollView(.vertical) {
                        VStack(spacing: 16) {
                            amountCard(height: max(200, contentHeight - 84))
                            methodRow
                                .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 16)
                        .frame(minHeight: contentHeight, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .backportScrollBounceBehaviorBasedOnSize()
                    VStack(spacing: 0) {
                        TokenTradeInputControls(model: model, continueAction: continueAction)
                        TokenTradeKeypadView(editor: editor, hasText: !model.input.text.isEmpty)
                            .frame(height: keypadHeight)
                    }
                    .padding(.bottom, bottomInset)
                    .background(Color.air.background, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32))
                }
                .background(Color.air.sheetBackground)
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard)
            .task(id: model.cardMaximumRequest) { await model.refreshCardMaximum() }
        }
    }

    private func amountCard(height: CGFloat) -> some View {
        let isCompact = height - footerHeight < 240
        let amountHeight: CGFloat = 26 + (isCompact ? 64 : 86)
        let topInset = max(64, min(118, height - amountHeight - 18 - footerHeight))
        return VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: topInset)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Button { model.toggleUnit() } label: {
                    HStack(spacing: 4) {
                        Text(model.isTokenAmount
                             ? model.typedTokenAmount.convertTo(model.currency, exchangeRate: model.price).formatted(.baseCurrencyEquivalent)
                             : model.displayedTokenAmount.formatted(.defaultAdaptive))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(model.isConversionAmountStale ? 0.55 : 1)
                            .mask { LoadingShineMask(isActive: model.isConversionAmountStale) }
                        Image("TokenTradeConverter", bundle: AirBundle)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 12, height: 16)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(Color.air.secondaryLabel.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(model.price <= 0)
                .accessibilityLabel(lang("Switch Amount Currency"))
                .accessibilityValue(model.displayedTokenAmount.formatted(.defaultAdaptive))
                .padding(.horizontal, 24)
                TokenTradeAmountField(model: model, editor: editor, maximumHeight: isCompact ? 64 : 86)
                    .padding(.leading, 24)
                    .padding(.trailing, 4)
            }
            .frame(height: amountHeight)
            Spacer(minLength: 18)
            VStack(spacing: 8) {
                if let fee = model.feeText {
                    Text(fee)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.air.secondaryLabel)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 24)
                }
                if let impact = model.displayImpactWarning {
                    TokenTradeNoticeView(title: SwapWarning.title(impact: impact), message: SwapWarning.message, isWarning: true)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("tokenTrade.impactWarning")
                }
                if let hint = model.hint {
                    let content = SwapHintContent(hint: hint, tradeDirection: model.direction)
                    TokenTradeNoticeView(title: content.title, message: content.message, actionTitle: content.actionTitle) {
                        model.performHintAction(hint)
                    }
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("tokenTrade.hint")
                }
            }
            .padding(.bottom, model.hint != nil || model.displayImpactWarning != nil ? 16 : (isCompact ? 12 : 22))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
        }
        .frame(minHeight: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.air.background, in: .rect(cornerRadius: 32))
    }

    private var methodRow: some View {
        Button(action: selectMethod) {
            HStack(spacing: 10) {
                if let currency = model.cardCurrency {
                    FiatCurrencyIcon(currency: currency)
                } else {
                    WUIIconViewToken(token: model.paymentToken, isWalletView: false, showldShowChain: true,
                                    size: 28, chainSize: 12, chainBorderWidth: 1, chainHorizontalOffset: 0, chainVerticalOffset: 0)
                        .frame(width: 28, height: 28)
                }
                Text(lang(model.isBuying ? "You Pay" : "You Receive"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    if let amount = model.methodAmountText {
                        Text(amount)
                            .foregroundStyle(Color.air.primaryLabel)
                            .opacity(model.isMethodAmountStale ? 0.55 : 1)
                            .mask { LoadingShineMask(isActive: model.isMethodAmountStale) }
                    }
                    Text(model.methodSymbol)
                        .foregroundStyle(Color.air.secondaryLabel)
                    if model.cardCurrency == nil, let token = model.paymentToken,
                       token.chain.usdtSlug.values.contains(token.slug) {
                        Text(token.chain.usdtBadgeText)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.air.secondaryLabel)
                            .padding(.horizontal, 3)
                            .frame(height: 14)
                            .background(Color.air.secondaryFill, in: .rect(cornerRadius: 4))
                    }
                    Image("TokenTradeDropdown", bundle: AirBundle)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 10, height: 22)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                .font(.system(size: 17))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 52)
            .background(Color.air.background, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tokenTrade.method")
    }
}

struct TokenTradeInputControls: View {
    let model: TokenTradeModel
    let continueAction: () -> Void

    var body: some View {
        WithPerceptionTracking {
            Group {
                if model.hasAmount || (model.cardCurrency != nil && model.isBuying) {
                    TokenTradeContinueButton(configuration: model.buttonConfiguration,
                                             tintColor: UIColor(hex: model.isBuying ? "#34C759" : "#FF383C"),
                                             action: continueAction)
                } else {
                    HStack(spacing: 10) {
                        ForEach([25, 50, 100], id: \.self) { percentage in
                            Button { model.useFraction(percentage) } label: {
                                Text(percentage.formatted(.percent.scale(1).locale(.forNumberFormatters)))
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(Color.air.sheetBackground, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.air.primaryLabel)
                            .disabled((model.maximumTokenAmount?.amount ?? 0) <= 0)
                        }
                    }
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
    }
}

struct TokenTradeContinueButton: UIViewRepresentable {
    let configuration: DraftButtonConfiguration
    let tintColor: UIColor
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WButton {
        let button = WButton(style: .primary)
        button.customTitleFont = WButton.capsuleFont
        button.accessibilityIdentifier = "tokenTrade.continue"
        context.coordinator.presenter = DraftButtonPresenter(button: button)
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WButton, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 52)
    }

    func updateUIView(_ button: WButton, context: Context) {
        let effectiveConfiguration = DraftButtonConfiguration(
            title: configuration.title,
            isEnabled: isEnabled && configuration.isEnabled,
            showLoading: isEnabled && configuration.showLoading,
            resetsLoadingAppearance: configuration.resetsLoadingAppearance
        )
        context.coordinator.action = action
        context.coordinator.isEnabled = effectiveConfiguration.isEnabled
        context.coordinator.presenter?.apply(effectiveConfiguration)
        let appearsEnabled = button.isEnabled
        button.customTintColor = appearsEnabled ? tintColor : nil
        if IOS_26_MODE_ENABLED, #available(iOS 26, *) {
            var configuration: UIButton.Configuration = appearsEnabled ? .prominentGlass() : .glass()
            configuration.title = button.title(for: .normal)
            configuration.baseBackgroundColor = appearsEnabled ? tintColor : nil
            configuration.baseForegroundColor = appearsEnabled ? .white : .air.secondaryLabel
            let foreground: UIColor = appearsEnabled ? .white : .air.secondaryLabel
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = WButton.capsuleFont
                attributes.foregroundColor = foreground
                return attributes
            }
            button.configuration = configuration
        }
    }

    @MainActor final class Coordinator: NSObject {
        var presenter: DraftButtonPresenter?
        var action: (() -> Void)?
        var isEnabled = false

        @objc func pressed() {
            guard isEnabled else { return }
            action?()
        }
    }
}
