import SwiftUI
import WalletCore
import WalletContext

public struct FeeDetailsView: View {
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The native token used to display the fee amounts.
    private var nativeToken: ApiToken
    private var fee: ExplainedTransferFee
    private var extraContent: AnyView?
    
    private var realAmount: TokenAmount {
        TokenAmount(fee.realFee?.nativeSumOrTerms ?? 0, nativeToken)
    }
    
    private var fullAmount: TokenAmount {
        TokenAmount(fee.fullFee?.nativeSumOrTerms ?? 0, nativeToken)
    }
    
    private var excessAmount: TokenAmount {
        TokenAmount(fee.excessFee ?? 0, nativeToken)
    }
    
    private var showExcess: Bool {
        excessAmount.amount > 0
    }
    private var realLargerThanExcess: Bool {
        realAmount.amount > excessAmount.amount
    }
    
    public init(nativeToken: ApiToken, fee: ExplainedTransferFee, extraContent: AnyView? = nil) {
        self.nativeToken = nativeToken
        self.fee = fee
        self.extraContent = extraContent
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            chart
            explanation
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var chart: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedChart
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 4) {
                    finalFeeSegment(singleLine: true)
                    if showExcess { excessSegment(singleLine: true) }
                }
                stackedChart
            }
        }
    }

    private var stackedChart: some View {
        VStack(spacing: 12) {
            finalFeeSegment(singleLine: false)
            if showExcess { excessSegment(singleLine: false) }
        }
    }

    private func finalFeeSegment(singleLine: Bool) -> some View {
        feeSegment(
            title: lang("Final Fee"), amount: realAmount, precision: fee.realFee?.precision,
            color: .accentColor, alignment: .leading, singleLine: singleLine,
            expands: !singleLine || !showExcess || realLargerThanExcess
        )
    }

    private func excessSegment(singleLine: Bool) -> some View {
        feeSegment(
            title: lang("Excess"), amount: excessAmount, precision: .approximate,
            color: .green, alignment: singleLine ? .trailing : .leading,
            singleLine: singleLine, expands: !singleLine || !realLargerThanExcess
        )
    }

    private func feeSegment(
        title: String, amount: TokenAmount, precision: MFee.FeePrecision?, color: Color,
        alignment: HorizontalAlignment, singleLine: Bool, expands: Bool
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .textStyle(.footnoteStrong, scaling: .dynamic)
                .foregroundStyle(color)
                .fixedSize(horizontal: singleLine, vertical: true)
                .padding(.horizontal, 12)
            Text(amount: amount, format: .init(preset: .fee, precision: precision))
                .textStyle(.bodyStrong, content: .technical, scaling: .dynamic)
                .foregroundStyle(.white)
                .lineLimit(singleLine ? 1 : nil)
                .fixedSize(horizontal: singleLine, vertical: true)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .frame(maxWidth: expands ? .infinity : nil, alignment: alignment == .leading ? .leading : .trailing)
                .background(color, in: .rect(cornerRadius: 12))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            fullFeeExplanation
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let extraContent = extraContent {
                extraContent
            }
        }
        .textStyle(.body, scaling: .dynamic)
    }

    private var fullFeeExplanation: Text {
        let precision = fee.fullFee?.precision
        let fullAmountText = fullAmount.formatted(
            .fee,
            roundHalfUp: true,
            precision: precision
        )
        let explanation: String
        if showExcess {
            explanation = L10n.feeDetails(fullFee: fullAmountText, excessSymbol: nativeToken.symbol, chainName: nativeToken.chain.title)
        } else {
            let paragraphs = L10n.dappReturnDetails(feeAmount: fullAmountText, receivedAmount: "")
            explanation = paragraphs.components(separatedBy: "\n\n").first ?? paragraphs
        }
        var attributed = (try? AttributedString(markdown: explanation, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(explanation)
        // Style the amount after parsing so RTL direction marks cannot break Markdown delimiters.
        if let range = attributed.range(of: fullAmountText) {
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(attributed)
    }
}

public extension WViewController {
    func showFeeDetails(nativeToken: ApiToken, fee: ExplainedTransferFee, extraContent: AnyView? = nil) {
        guard fee.supportsLegacyDetailsView else { return }
        showTip(title: lang("Blockchain Fee Details"), wide: true) {
            FeeDetailsView(nativeToken: nativeToken, fee: fee, extraContent: extraContent)
        }
    }
}
