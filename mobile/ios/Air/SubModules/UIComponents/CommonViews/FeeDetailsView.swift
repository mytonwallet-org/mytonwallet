import SwiftUI
import WalletCore
import WalletContext

public struct FeeDetailsView: View {
    
    ///The token denoting the `token` fields of the `FeeTerms` objects.
    private var nativeToken: ApiToken
    private var fee: ExplainedTransferFee
    private var extraContent: AnyView?
    
    private var realAmount: TokenAmount {
        TokenAmount(fee.realFee?.nativeSum ?? 0, nativeToken)
    }
    
    private var fullAmount: TokenAmount {
        TokenAmount(fee.fullFee?.nativeSum ?? 0, nativeToken)
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
            explaination
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    var chart: some View {
        VStack(spacing: 3) {
            HStack {
                Text(lang("Final Fee"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(WTheme.tint))
                
                Spacer()
                
                if showExcess {
                    Text(lang("Excess"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            
            HStack(spacing: 3) {
                Text(amount: realAmount, format: .init(maxDecimals: 4, precision: fee.realFee?.precision))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 12)
                    
                    .padding(.trailing, 3) // visually balance ~
                    .frame(maxWidth: realLargerThanExcess ? .infinity : nil, alignment: .leading)
                    .background(Color(WTheme.tint))
                    .clipShape(.rect(cornerRadius: 4))
                
                if showExcess {
                    Text(amount: excessAmount, format: .init(maxDecimals: 4, precision: .approximate))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 12)
                        
                        .frame(maxWidth: realLargerThanExcess ? nil : .infinity, alignment: .trailing)
                        .background(Color.green)
                        .clipShape(.rect(cornerRadius: 4))
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
        }
    }

    @ViewBuilder
    var explaination: some View {
        VStack(alignment: .leading, spacing: 12) {
            let precision = fee.fullFee?.precision
            Text(showExcess ? "**\(Text(amount: fullAmount, format: .init(maxDecimals: precision == .exact ? nil : 4, roundUp: true, precision: precision)))** need to be immediately debited from your wallet to pay the fee. Part of this will be returned in TON to you as excess within a few minutes." : "**\(Text(amount: fullAmount, format: .init()))** will be immediately debited from your wallet to pay the fee.")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if showExcess {
                Text(lang("This is how the TON Blockchain works."))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
            }
            
            if let extraContent = extraContent {
                extraContent
            }
        }
        .padding(.horizontal, 12)
    }
}
