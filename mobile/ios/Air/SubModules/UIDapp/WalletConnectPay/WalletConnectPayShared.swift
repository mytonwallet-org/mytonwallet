import Foundation
import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import WalletCoreTypes

let walletConnectPaySignUrl = "https://walletconnect.com/pay"
let walletConnectPayUserCancelReason = "Canceled by the user"

extension WcPayMerchant {
    var asDapp: ApiDapp {
        ApiDapp(
            url: walletConnectPaySignUrl,
            name: name,
            iconUrl: iconUrl ?? "",
            connectedAt: nil,
            urlTrustStatus: .verified,
            sse: nil
        )
    }
}

extension ApiUpdate.WalletConnectPaySignTransaction {
    var dappRequest: ApiUpdate.DappSendTransactions {
        ApiUpdate.DappSendTransactions(
            promiseId: promiseId,
            accountId: accountId,
            dapp: merchant.asDapp,
            operationChain: operationChain,
            transactions: transactions,
            validUntil: validUntil,
            emulation: emulation,
            shouldHideTransfers: shouldHideTransfers,
            isLegacyOutput: isLegacyOutput ?? isSignOnly
        )
    }
}

struct WalletConnectPayMerchantHeaderView: View {
    var merchant: WcPayMerchant?
    var accountContext: AccountContext
    var chain: ApiChain?
    var customTokenBalance: BigInt?
    var customToken: ApiToken?

    var body: some View {
        HStack {
            leadingSide
            trailingSide
        }
        .truncationMode(.middle)
        .allowsTightening(true)
        .foregroundStyle(.white)
        .background {
            WalletConnectPayHeaderBackground()
        }
        .clipShape(.containerRelative)
        .containerShape(.rect(cornerRadius: 26))
        .padding(.horizontal, 16)
    }

    private var leadingSide: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(accountContext.account.displayName)
                .font(.system(size: 16, weight: .medium))
                .frame(minHeight: 22)
            if let customToken, let customTokenBalance {
                Text(TokenAmount(customTokenBalance, customToken).formatted(.defaultAdaptive))
                    .font(.system(size: 14, weight: .regular))
                    .opacity(0.75)
            } else if let balance = accountContext.balance {
                Text(balance.formatted(.baseCurrencyEquivalent))
                    .font(.system(size: 14, weight: .regular))
                    .opacity(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .padding(.leading, 16)
    }

    private var trailingSide: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(merchant?.name ?? lang("Payment"))
                    .font(.system(size: 16, weight: .medium))
                    .frame(minHeight: 22)
                    .lineLimit(3)
                Text(chain?.title ?? "WalletConnect Pay")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(2)
            }
            DappIcon(iconUrl: merchant?.iconUrl)
                .frame(width: 40, height: 40)
                .background(Color.air.secondaryFill)
                .clipShape(.rect(cornerRadius: 12))
        }
        .padding(.trailing, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .multilineTextAlignment(.trailing)
        .background {
            ZStack {
                BackgroundBlur(radius: 16)
                Rectangle()
                    .fill(.black)
                    .opacity(0.1)
                    .blendMode(.plusDarker)
            }
            .frame(maxWidth: .infinity)
            .clipShape(WalletConnectPayHeaderLine())
            .padding(.leading, -24)
        }
    }
}

private struct WalletConnectPayHeaderBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.32, blue: 0.44),
                Color(red: 0.17, green: 0.48, blue: 0.34),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct WalletConnectPayHeaderLine: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        Path {
            let h = rect.height
            let w = rect.width
            let dx = 0.3 * h
            let dw = 7.0
            let ds = 5.0
            let x1 = dw + ds
            let r = 10.0
            $0.move(to: CGPoint(x: 0, y: 0))
            $0.addArc(tangent1End: CGPoint(x: dx, y: h / 2), tangent2End: CGPoint(x: 0, y: h), radius: r)
            $0.addLine(to: CGPoint(x: 0, y: h))
            $0.addLine(to: CGPoint(x: dw, y: h))
            $0.addArc(tangent1End: CGPoint(x: dw + dx, y: h / 2), tangent2End: CGPoint(x: dw, y: 0), radius: r + dw * 0.5)
            $0.addLine(to: CGPoint(x: dw, y: 0))
            $0.closeSubpath()

            $0.move(to: CGPoint(x: x1, y: 0))
            $0.addArc(tangent1End: CGPoint(x: x1 + dx, y: h / 2), tangent2End: CGPoint(x: x1, y: h), radius: r + x1 * 0.5)
            $0.addLine(to: CGPoint(x: x1, y: h))
            $0.addLine(to: CGPoint(x: w, y: h))
            $0.addLine(to: CGPoint(x: w, y: 0))
            $0.closeSubpath()
        }
    }
}

struct WalletConnectPayPaymentHeaderView: View {
    var merchant: WcPayMerchant
    var paymentInfo: WcPayPaymentInfo?

    var body: some View {
        VStack(spacing: 16) {
            WalletConnectPayMerchantIcon(iconUrl: merchant.iconUrl)

            if let amount {
                VStack(spacing: 8) {
                    WalletConnectPayLargeAmountText(amount: amount)

                    if let baseCurrencyText {
                        Text(baseCurrencyText)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Color.air.secondaryLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var amount: WalletConnectPayHeaderAmount? {
        if let amount = paymentInfo?.amount {
            let value = amount.fiatAmount?.value ?? amount.value
            return WalletConnectPayHeaderAmount(
                value: value,
                decimals: amount.fiatAmount?.decimals ?? amount.display.decimals,
                symbol: amount.fiatAmount?.currency?.sign ?? amount.display.assetSymbol,
                forceCurrencyToRight: amount.fiatAmount?.currency?.forceCurrencyToRight ?? true
            )
        }
        return nil
    }

    private var baseCurrencyText: String? {
        formattedPayBaseCurrencyEquivalent(paymentInfo?.amount?.fiatAmount)
    }
}

struct WalletConnectPayPaymentContext {
    var paymentInfo: WcPayPaymentInfo?
    var paymentOption: WcPayPaymentOption?
}

struct WalletConnectPayAuthHeaderView: View {
    var merchant: WcPayMerchant
    var paymentContext: WalletConnectPayPaymentContext
    var accountContext: AccountContext

    var body: some View {
        VStack(spacing: 16) {
            WalletConnectPayMerchantIcon(iconUrl: merchant.iconUrl)

            VStack(spacing: 12) {
                if let amount = walletConnectPaySelectedPaymentAmount(
                    paymentContext: paymentContext,
                    accountContext: accountContext
                ) {
                    WalletConnectPayAmountLine(amount: amount)
                }

                WalletConnectPayMerchantLine(prefix: lang("Send to"), merchant: merchant)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 33)
    }
}

private struct WalletConnectPayMerchantIcon: View {
    var iconUrl: String?

    var body: some View {
        DappIcon(iconUrl: iconUrl)
            .frame(width: 80, height: 80)
            .background(Color.air.secondaryFill)
            .clipShape(Circle())
        .frame(width: 80, height: 80)
    }
}

struct WalletConnectPaySelectedPaymentAmount {
    var amount: WalletConnectPayHeaderAmount
    var token: ApiToken?
    var iconUrl: String?
    var networkIconUrl: String?
}

@MainActor
func walletConnectPaySelectedPaymentAmount(
    paymentContext: WalletConnectPayPaymentContext,
    accountContext: AccountContext
) -> WalletConnectPaySelectedPaymentAmount? {
    if let option = paymentContext.paymentOption {
        let displayData = walletConnectPayOptionDisplayData(
            for: option,
            accountContext: accountContext
        )
        return WalletConnectPaySelectedPaymentAmount(
            amount: WalletConnectPayHeaderAmount(
                value: -option.amountValue,
                decimals: option.display.decimals,
                symbol: option.display.assetSymbol,
                forceCurrencyToRight: true
            ),
            token: displayData.token,
            iconUrl: displayData.iconUrl,
            networkIconUrl: displayData.networkIconUrl
        )
    }

    guard let amount = paymentContext.paymentInfo?.amount else {
        return nil
    }

    return WalletConnectPaySelectedPaymentAmount(
        amount: WalletConnectPayHeaderAmount(
            value: -amount.value,
            decimals: amount.display.decimals,
            symbol: amount.display.assetSymbol,
            forceCurrencyToRight: true
        ),
        token: nil,
        iconUrl: amount.display.iconUrl,
        networkIconUrl: nil
    )
}

@MainActor
func walletConnectPayCompletedPaymentAmount(
    complete: ApiUpdate.WalletConnectPayPaymentComplete,
    paymentContext: WalletConnectPayPaymentContext?,
    accountContext: AccountContext
) -> WalletConnectPaySelectedPaymentAmount? {
    if let paymentAmount = complete.paymentAmount {
        var token: ApiToken?
        var iconUrl = paymentAmount.display.iconUrl
        var networkIconUrl: String?

        if let option = paymentContext?.paymentOption {
            let displayData = walletConnectPayOptionDisplayData(
                for: option,
                accountContext: accountContext
            )
            token = displayData.token
            iconUrl = displayData.iconUrl ?? iconUrl
            networkIconUrl = displayData.networkIconUrl
        }

        return WalletConnectPaySelectedPaymentAmount(
            amount: WalletConnectPayHeaderAmount(
                value: -paymentAmount.value,
                decimals: paymentAmount.display.decimals,
                symbol: paymentAmount.display.assetSymbol,
                forceCurrencyToRight: true
            ),
            token: token,
            iconUrl: iconUrl,
            networkIconUrl: networkIconUrl
        )
    }

    guard let paymentContext else {
        return nil
    }

    return walletConnectPaySelectedPaymentAmount(
        paymentContext: paymentContext,
        accountContext: accountContext
    )
}

struct WalletConnectPayAmountLine: View {
    var amount: WalletConnectPaySelectedPaymentAmount
    var showsIcon = true

    var body: some View {
        let hasIcon = amount.token != nil || amount.iconUrl?.nilIfEmpty != nil
        AmountIconRow(showsIcon: showsIcon && hasIcon) {
            WalletConnectPayLargeAmountText(amount: amount.amount)
        } icon: {
            WalletConnectPayTokenIcon(
                token: amount.token,
                iconUrl: amount.iconUrl,
                networkIconUrl: amount.networkIconUrl,
                size: 28,
                chainSize: 12,
                chainBorderWidth: 1,
                chainHorizontalOffset: 1.5,
                chainVerticalOffset: 1
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct WalletConnectPayMerchantLine: View {
    var prefix: String
    var merchant: WcPayMerchant

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(prefix)
                .font17h22()
                .foregroundStyle(Color.air.primaryLabel)

            HStack(alignment: .center, spacing: 4) {
                DappIcon(iconUrl: merchant.iconUrl)
                    .frame(width: 18, height: 18)
                    .background(Color.air.secondaryFill)
                    .clipShape(.rect(cornerRadius: 4))

                Text(merchant.name)
                    .font17h22()
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct WalletConnectPayTokenIcon: View {
    var token: ApiToken?
    var iconUrl: String?
    var networkIconUrl: String?
    var size: CGFloat
    var chainSize: CGFloat
    var chainBorderWidth: CGFloat
    var chainHorizontalOffset: CGFloat
    var chainVerticalOffset: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let token {
                WUIIconViewToken(
                    token: token,
                    isWalletView: false,
                    showldShowChain: true,
                    size: size,
                    chainSize: chainSize,
                    chainBorderWidth: chainBorderWidth,
                    chainHorizontalOffset: chainHorizontalOffset,
                    chainVerticalOffset: chainVerticalOffset
                )
                .frame(width: size, height: size)
            } else {
                DappIcon(iconUrl: iconUrl)
                    .frame(width: size, height: size)
                    .background(Color.air.secondaryFill)
                    .clipShape(Circle())

                if let iconUrl = iconUrl?.nilIfEmpty,
                   let networkIconUrl = networkIconUrl?.nilIfEmpty,
                   iconUrl != networkIconUrl {
                    DappIcon(iconUrl: networkIconUrl)
                        .frame(width: chainSize, height: chainSize)
                        .background(Color.air.groupedItem)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.air.groupedItem, lineWidth: chainBorderWidth))
                        .offset(x: chainHorizontalOffset, y: chainVerticalOffset)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

struct WalletConnectPayConfirmationSummarySections: View {
    var accountContext: AccountContext
    var paymentOption: WcPayPaymentOption?

    var body: some View {
        tokenSection
    }

    @ViewBuilder
    private var tokenSection: some View {
        if let paymentOption {
            InsetSection(addDividers: false) {
                WalletConnectPayOptionRow(
                    option: paymentOption,
                    displayData: walletConnectPayOptionDisplayData(
                        for: paymentOption,
                        accountContext: accountContext
                    ),
                    showsSeparator: false
                )
            } header: {
                Text("Token")
            }
        }
    }
}

struct WalletConnectPayTransferInfoRow: View {
    var action: () -> Void

    var body: some View {
        InsetSection(addDividers: false) {
            InsetButtonCell(action: action) {
                HStack(spacing: 12) {
                    Text(lang("Transfer Info"))
                        .font17h22()
                        .foregroundStyle(Color.air.primaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    InsetListChevron()
                }
            }
        }
    }
}

struct WalletConnectPayHeaderAmount {
    var value: BigInt
    var decimals: Int
    var symbol: String
    var forceCurrencyToRight: Bool
}

struct WalletConnectPayLargeAmountText: View {
    var amount: WalletConnectPayHeaderAmount

    var body: some View {
        let decimalAmount = AnyDecimalAmount(
            amount.value,
            decimals: amount.decimals,
            symbol: amount.symbol,
            forceCurrencyToRight: amount.forceCurrencyToRight
        )
        AmountText(
            amount: decimalAmount,
            format: .init(preset: .baseCurrencyEquivalent),
            integerFont: .compactRounded(ofSize: 34, weight: .bold),
            fractionFont: .compactRounded(ofSize: 28, weight: .bold),
            symbolFont: .compactRounded(ofSize: 28, weight: .bold),
            integerColor: UIColor.label,
            fractionColor: abs(decimalAmount.doubleValue) >= 10 ? .air.secondaryLabel : UIColor.label,
            symbolColor: .air.secondaryLabel
        )
            .lineLimit(1)
    }
}

func formattedPayAmount(_ amount: WcPayPaymentInfo.Amount) -> String {
    formattedPayAmount(value: amount.value, display: amount.display, fiatAmount: amount.fiatAmount)
}

func formattedPayAmount(_ amount: WcPayPaymentAmount) -> String {
    formattedPayAmount(value: amount.value, display: amount.display, fiatAmount: amount.fiatAmount)
}

func formattedPayAmount(value: BigInt, display: WcPayAmountDisplay, fiatAmount: WcPayFiatAmount? = nil) -> String {
    if let fiatAmount, let formatted = formattedPayOriginalFiatAmount(fiatAmount) {
        return formatted
    }

    return AnyDecimalAmount(value, decimals: display.decimals, symbol: display.assetSymbol, forceCurrencyToRight: true)
        .formatted(.defaultAdaptive)
}

func formattedPayOptionAmount(_ option: WcPayPaymentOption) -> String {
    AnyDecimalAmount(option.amountValue, decimals: option.display.decimals, symbol: option.display.assetSymbol, forceCurrencyToRight: true)
        .formatted(.defaultAdaptive)
}

func formattedPayBaseCurrencyEquivalent(
    _ fiatAmount: WcPayFiatAmount?,
    includesMatchingBaseCurrency: Bool = false
) -> String? {
    guard let fiatAmount, let sourceCurrency = fiatAmount.currency else {
        return nil
    }

    let baseCurrency = TokenStore.baseCurrency
    guard includesMatchingBaseCurrency || sourceCurrency != baseCurrency else {
        return nil
    }

    let original = AnyDecimalAmount(
        fiatAmount.value,
        decimals: fiatAmount.decimals,
        symbol: sourceCurrency.sign,
        forceCurrencyToRight: sourceCurrency.forceCurrencyToRight
    )
    let amountInUsd = sourceCurrency == .USD
        ? original.doubleValue
        : original.doubleValue / TokenStore.getCurrencyRate(sourceCurrency)
    let amountInBaseCurrency = amountInUsd * TokenStore.getCurrencyRate(baseCurrency)
    let formatted = BaseCurrencyAmount
        .fromDouble(amountInBaseCurrency, baseCurrency)
        .formatted(.baseCurrencyEquivalent)

    return "\u{2248}\u{2009}\(formatted)"
}

private func formattedPayOriginalFiatAmount(_ fiatAmount: WcPayFiatAmount) -> String? {
    guard let currency = fiatAmount.currency else {
        return nil
    }

    return AnyDecimalAmount(
        fiatAmount.value,
        decimals: fiatAmount.decimals,
        symbol: currency.sign,
        forceCurrencyToRight: currency.forceCurrencyToRight
    )
    .formatted(.baseCurrencyEquivalent)
}

#if DEBUG
@MainActor
enum WalletConnectPayPreviewData {
    static let accountContext = AccountContext(source: .constant(DUMMY_ACCOUNT))

    static let merchant = WcPayMerchant(
        name: "Merchant Name",
        iconUrl: "https://walletconnect.com/walletconnect-logo.png"
    )

    static let paymentContext = WalletConnectPayPaymentContext(
        paymentInfo: paymentInfo,
        paymentOption: paymentOption
    )

    static let paymentInfo = try! JSONDecoder().decode(WcPayPaymentInfo.self, fromString: """
    {
      "expiresAt": 1893456000,
      "amount": {
        "value": "748210000000",
        "display": {
          "assetSymbol": "GRAM",
          "assetName": "Gram",
          "decimals": 9
        },
        "fiatAmount": {
          "value": "12345678",
          "decimals": 2,
          "slug": "USD"
        }
      }
    }
    """)

    static let paymentOption = try! JSONDecoder().decode(WcPayPaymentOption.self, fromString: """
    {
      "id": "gram-ton",
      "account": "ton:mainnet:preview",
      "amountValue": "748210000000",
      "display": {
        "assetSymbol": "GRAM",
        "assetName": "Gram",
        "decimals": 9,
        "iconUrl": "https://walletconnect.com/walletconnect-logo.png",
        "networkName": "TON",
        "networkIconUrl": "https://walletconnect.com/walletconnect-logo.png"
      }
    }
    """)

    static let processing = try! JSONDecoder().decode(ApiUpdate.WalletConnectPayProcessing.self, fromString: """
    {
      "accountId": "\(DUMMY_ACCOUNT.id)",
      "merchant": {
        "name": "Merchant Name",
        "iconUrl": "https://walletconnect.com/walletconnect-logo.png"
      },
      "operationChain": "ton"
    }
    """)

    static let complete = try! JSONDecoder().decode(ApiUpdate.WalletConnectPayPaymentComplete.self, fromString: """
    {
      "accountId": "\(DUMMY_ACCOUNT.id)",
      "merchant": {
        "name": "Merchant Name",
        "iconUrl": "https://walletconnect.com/walletconnect-logo.png"
      },
      "operationChain": "ton",
      "txId": "preview",
      "paymentAmount": {
        "value": "748210000000",
        "display": {
          "assetSymbol": "GRAM",
          "assetName": "Gram",
          "decimals": 9,
          "iconUrl": "https://walletconnect.com/walletconnect-logo.png"
        }
      }
    }
    """)
}

@available(iOS 18, *)
#Preview("WC Pay Auth Header") {
    WalletConnectPayAuthHeaderView(
        merchant: WalletConnectPayPreviewData.merchant,
        paymentContext: WalletConnectPayPreviewData.paymentContext,
        accountContext: WalletConnectPayPreviewData.accountContext
    )
    .background(Color.air.sheetBackground)
}
#endif
