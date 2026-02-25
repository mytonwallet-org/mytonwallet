
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Kingfisher


struct TransactionActivityHeader: View {
    
    var account: AccountContext
    var transaction: ApiTransactionActivity
    var token: ApiToken
    var amountDisplayMode: ApiActivity.AmountDisplayMode
    var onTokenTapped: ((ApiToken) -> Void)?
    var isTransactionConfirmation: Bool
    
    private var amount: TokenAmount {
        TokenAmount(transaction.amount, token)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            iconView
            if amountDisplayMode != .hide {
                amountView
            }
            toView
        }
    }
    
    @ViewBuilder
    var iconView: some View {
        ActivityIconView(activity: .transaction(transaction), size: 80, accessorySize: 30, isTransactionConfirmation: isTransactionConfirmation)
            .frame(width: 80, height: 80)
    }
    
    @ViewBuilder
    var amountView: some View {
        let shouldShowSign = amountDisplayMode != .noSign
        let isStake = transaction.type == .stake
        let amountColor: UIColor = isStake ? .air.textPurple : WTheme.primaryLabel
        let fractionColor: UIColor = isStake ? .air.textPurple : abs(amount.doubleValue) >= 10 ? WTheme.secondaryLabel : WTheme.primaryLabel
        let symbolColor: UIColor = isStake ? .air.textPurple : WTheme.secondaryLabel
        Button {
            onTokenTapped?(token)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let amount = self.amount
                AmountText(
                    amount: amount,
                    format: .init(
                        preset: .defaultAdaptive,
                        showPlus: shouldShowSign ? transaction.isIncoming : false,
                        showMinus: shouldShowSign ? !transaction.isIncoming : false
                    ),
                    integerFont: .compactRounded(ofSize: 34, weight: .bold),
                    fractionFont: .compactRounded(ofSize: 28, weight: .bold),
                    symbolFont: .compactRounded(ofSize: 28, weight: .bold),
                    integerColor: amountColor,
                    fractionColor: fractionColor,
                    symbolColor: symbolColor
                )
                .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 11, theme: .adaptive, cornerRadius: 10)
                
                TokenIconView(token: token, accessorySize: 12)
                    .frame(height: 28)
                    .offset(y: 3.5)
            }
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    var toView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (Text(transaction.isIncoming ? lang("Received from") :  lang("Sent to")) + Text(" "))
                .font17h22()
            TappableAddress(account: account, model: .fromTransaction(transaction, chain: token.chain, addressKind: .peer))
        }
    }
}


struct SIconView<Content: View, Attachment: View>: View {
    
    var accessorySize: CGFloat?
    var content: Content
    var attachment: Attachment
    
    init(accessorySize: CGFloat?, @ViewBuilder content: () -> Content, @ViewBuilder attachment: () -> Attachment) {
        self.accessorySize = accessorySize
        self.content = content()
        self.attachment = attachment()
    }
    
    var body: some View {
        content
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.circle)
            .overlay(alignment: .bottomTrailing) {
                if let accessorySize {
                    
                    let borderWidth = borderWidthForAccessorySize(accessorySize)
                    let horizontalOffset = horizontalOffsetForAccessorySize(accessorySize)
                    let verticalOffset = verticalOffsetForAccessorySize(accessorySize)
                    
                    attachment
                        .clipShape(.circle)
                        .background {
                            Circle()
                                .fill(Color(WTheme.sheetBackground))
                                .padding(-borderWidth)
                        }
                        .frame(width: accessorySize, height: accessorySize)
                        .offset(x: horizontalOffset, y: verticalOffset)
                }
            }
    }
    
    func borderWidthForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        accessorySize <= 16 ? 1.0 : accessorySize < 50 ? 1.667 : 2.667
    }
    
    func horizontalOffsetForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        2.0
    }

    func verticalOffsetForAccessorySize(_ accessorySize: CGFloat) -> CGFloat {
        accessorySize <= 16 ? 0 : 2
    }
}


struct TokenIconView: View {
    
    var token: ApiToken
    var accessorySize: CGFloat?
    
    var body: some View {
        SIconView(accessorySize: accessorySize) {
            if let image = token.image?.nilIfEmpty, let url = URL(string: image) {
                KFImage(url)
                    .cacheOriginalImage()
                    .resizable()
                    .loadDiskFileSynchronously(false)
            }
        } attachment: {
            if !token.isNative {
                Image.airBundle("chain_\(token.chain.rawValue)")
                    .resizable()
            }
        }
    }
}
