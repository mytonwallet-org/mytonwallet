import SwiftUI
import Perception
import WalletCore
import WalletContext

public struct AccountMenuCell: View {
    private let accountContext: AccountContext

    public init(accountContext: AccountContext) {
        self.accountContext = accountContext
    }

    public var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 8) {
                AccountIcon(account: accountContext.account, size: 38, initialsFontSize: 16)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountContext.account.displayName)
                        .textStyle(.body)
                        .foregroundStyle(Color.air.primaryLabel)
                        .lineLimit(1)
                        .frame(height: 20)

                    HStack(spacing: 4) {
                        let addressLine = accountContext.addressLine
                        if addressLine.isTestnet || addressLine.leadingIcon != nil {
                            accountTypeIcons
                                .fixedSize()
                                .layoutPriority(1)
                        }

                        if let balance = accountContext.balance {
                            Text(balance.formatted(.baseCurrencyEquivalent, roundHalfUp: true))
                                .textStyle(.footnote, content: .technical)
                                .lineLimit(1)
                                .sensitiveDataInPlace(cols: 8, rows: 2, cellSize: 6, theme: .adaptive, cornerRadius: 4)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accountTypeIcons: some View {
        HStack(spacing: 4) {
            let addressLine = accountContext.addressLine
            if addressLine.isTestnet {
                addressLine.testnetImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10, height: 11)
            }
            if let leadingIcon = addressLine.leadingIcon {
                Image.airBundle(leadingIcon == .ledger ? "AccountTypeLedger" : "AccountTypeView")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}
