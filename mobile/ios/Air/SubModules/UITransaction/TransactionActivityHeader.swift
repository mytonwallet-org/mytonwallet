
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Kingfisher


struct TransactionActivityHeader: View {
    
    var transaction: ApiTransactionActivity
    var token: ApiToken
    
    private var amount: TokenAmount {
        TokenAmount(transaction.amount, token)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            iconView
            amountView
            toView
        }
    }
    
    @ViewBuilder
    var iconView: some View {
        ActivtyIconView(activity: .transaction(transaction))
            .accessorySize(30)
            .frame(height: 80)
    }
    
    @ViewBuilder
    var amountView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            let amount = self.amount
            AmountText(
                amount: amount,
                format: .init(maxDecimals: amount.defaultDisplayDecimals, showPlus: transaction.isIncoming, showMinus: !transaction.isIncoming),
                integerFont: .rounded(ofSize: 34, weight: .bold),
                fractionFont: .rounded(ofSize: 28, weight: .bold),
                symbolFont: .rounded(ofSize: 28, weight: .bold),
                integerColor: WTheme.primaryLabel,
                fractionColor: abs(amount.doubleValue) >= 10 ? WTheme.secondaryLabel : WTheme.primaryLabel,
                symbolColor: WTheme.secondaryLabel
            )
            .sensitiveData(alignment: .center, cols: 12, rows: 3, cellSize: 11, theme: .adaptive, cornerRadius: 10)
            
            TokenIconView(token: token)
                .accessorySize(12)
                .frame(height: 28)
                .offset(y: 3.5)
        }
    }
    
    @ViewBuilder
    var toView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (Text(transaction.isIncoming ? lang("Received from") :  lang("Sent to")) + Text(" "))
                .font17h22()
            let addressToShow = transaction.addressToShow
            TappableAddress(name: addressToShow, chain: token.chain, resolvedAddress: transaction.normalizedAddress, addressOrName: addressToShow)
        }
    }
}


struct SIconView<Content: View, Attachment: View>: View {
    
    var content: Content
    var attachment: Attachment
    
    @Environment(\.accessorySize) private var accessorySize
    
    init(@ViewBuilder content: () -> Content, @ViewBuilder attachment: () -> Attachment) {
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


struct ActivtyIconView: View {
    
    var activity: ApiActivity
    
    var body: some View {
        
        let colors = activity.iconColors.map { Color($0) }
        let content = activity.avatarContent
        
        if case .image(let image) = content {
            
            SIconView {
                Image.airBundle(image)
                    .resizable()
                    .background {
                        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    }
            } attachment: {
                if activity.isLocal {
                    Image.airBundle("ActivityWaiting")
                        .resizable()
                }
            }
        }
    }
}


struct TokenIconView: View {
    
    var token: ApiToken
    
    var body: some View {
        SIconView {
            if let image = token.image?.nilIfEmpty, let url = URL(string: image) {
                KFImage(url)
                    .cacheOriginalImage()
                    .resizable()
                    .loadDiskFileSynchronously(false)
            }
        } attachment: {
            Image.airBundle("chain_\(token.chain)")
                    .resizable()
            
        }
    }
}


public extension EnvironmentValues {
    @Entry var accessorySize: CGFloat? = nil
}

public extension View {
    func accessorySize(_ size: CGFloat) -> some View {
        self.environment(\.accessorySize, size)
    }
}
