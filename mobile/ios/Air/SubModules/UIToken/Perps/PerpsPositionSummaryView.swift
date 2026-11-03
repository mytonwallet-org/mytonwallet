import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct PerpsPositionSummaryView: View {
    let token: ApiToken
    let direction: PerpsTradeDirection
    let leverage: Int
    let margin: BaseCurrencyAmount
    var previousMargin: BaseCurrencyAmount? = nil
    var showsPlus = false
    var isLoss = false
    var isEstimated = false
    var spacing: CGFloat = 24
    var backgroundColor: Color = .air.headerBackground
    let accessibilityPrefix: String

    var body: some View {
        VStack(spacing: spacing) {
            TokenHeroView(token: token, size: 80, shouldShowChain: false)
                .accessibilityHidden(true)
                .overlay(alignment: .bottom) {
                    Text(leverage > 0 ? L10n.perpsLeverageDirection(
                        leverage: leverage.formatted(.number.locale(.forNumberFormatters)),
                        direction: lang(direction == .long ? "Long" : "Short")) : lang(direction == .long ? "Long" : "Short"))
                        .textStyle(.subheadlineEmphasized)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(direction == .long ? Color.air.positiveAmount : Color.air.negativeAmount, in: .capsule)
                        .overlay(Capsule().stroke(backgroundColor, lineWidth: 2))
                        .offset(y: 12)
                        .accessibilityIdentifier(accessibilityPrefix + ".direction")
                }
            HStack(spacing: 8) {
                if margin.optionalAmount != nil, let previousMargin, previousMargin.optionalAmount != nil {
                    amount(previousMargin, previous: true)
                    Text("→")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                if isEstimated, margin.optionalAmount != nil {
                    Text("≈")
                        .textStyle(.screenTitle, content: .technical)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
                amount(margin, previous: false)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier(accessibilityPrefix + ".margin")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func amount(_ value: BaseCurrencyAmount, previous: Bool) -> some View {
        if value.optionalAmount != nil {
            knownAmount(value, previous: previous)
        } else {
            Text("—")
                .font(Font(UIFont.compactRounded(ofSize: 34, weight: .bold)))
                .foregroundStyle(Color.air.secondaryLabel)
                .accessibilityLabel(lang("Unavailable"))
        }
    }

    private func knownAmount(_ value: BaseCurrencyAmount, previous: Bool) -> some View {
        HStack(spacing: 4) {
            if value.amount < 0 || (!previous && showsPlus && value.amount > 0) {
                Text(value.amount < 0 ? "−" : "+")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(isLoss ? Color.air.error : Color.air.secondaryLabel)
            }
            // Keep the sign outside AmountText so the currency symbol remains at the start of its numeric run.
            AmountText(amount: value, format: .init(preset: .defaultAdaptive, showMinus: false, roundHalfUp: false),
                       integerFont: .compactRounded(ofSize: 34, weight: .bold),
                       fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                       symbolFont: .compactRounded(ofSize: 31, weight: .bold),
                       integerColor: isLoss ? .air.error : .label,
                       fractionColor: isLoss ? .air.error : .air.secondaryLabel, symbolColor: isLoss ? .air.error : .air.secondaryLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.formatted(.defaultAdaptive, showPlus: !previous && showsPlus))
    }
}
