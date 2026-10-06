import Foundation
import Perception
import UIComponents
import WalletCore
import WalletContext

public enum TokenTradeDirection: Sendable {
    case buy
    case sell
}

/// Keeps native text edits decimal and lossless until they enter the shared quote pipeline.
struct TokenTradeAmountInput: Equatable {
    private(set) var text = ""

    struct Edit {
        let input: TokenTradeAmountInput
        let caret: Int
    }

    func replacing(_ range: NSRange, with replacement: String, decimals: Int) -> Edit? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        let replacement = replacement.normalizeArabicPersianNumeralStringToWestern()
        let allowed = CharacterSet(charactersIn: "0123456789., '\u{00A0}\u{202F}\u{2009}’")
        guard replacement.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        if replacement == "." || replacement == "," {
            guard !text.replacingCharacters(in: swiftRange, with: "").contains(".") else { return nil }
        }
        let raw = text.replacingCharacters(in: swiftRange, with: replacement)
        let normalized = normalizeAmountInput(raw, preserveTrailingSeparator: true)
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (parts.first?.count ?? 0) <= 12,
              parts.count < 2 || (decimals > 0 && parts[1].count <= decimals) else { return nil }

        // Map the insertion point through removed grouping characters and leading zeroes.
        let rawCaret = range.location + replacement.utf16.count
        let separator = raw.lastIndex { $0 == "." || $0 == "," }
        let prefix = String(decoding: raw.utf16.prefix(rawCaret), as: UTF16.self)
        var caret = prefix.filter(\.isWholeNumber).count
        if let separator, raw.distance(from: raw.startIndex, to: separator) < prefix.count { caret += 1 }
        if raw.first == "." || raw.first == "," { caret += 1 }
        let integral = String(parts.first ?? "")
        let trimmed = integral.drop { $0 == "0" }
        let removedZeros = integral.count - max(1, trimmed.count)
        let result = String(normalized.dropFirst(max(0, removedZeros)))
        caret = min(result.utf16.count, max(0, caret - max(0, removedZeros)))
        return Edit(input: TokenTradeAmountInput(text: result), caret: caret)
    }

    mutating func set(_ amount: BigInt, decimals: Int) {
        text = amount > 0 ? bigIntToDoubleString(amount, decimals: decimals) : ""
    }

    func amount(decimals: Int) -> BigInt {
        normalizedAmountValue(text, digits: decimals)
    }
}

@Perceptible @MainActor
final class TokenTradeModel {
    let swap: SwapModel
    let direction: TokenTradeDirection
    private(set) var token: ApiToken
    var input = TokenTradeAmountInput()
    var isTokenAmount = false
    var cardCurrency: MBaseCurrency?
    private var cardMaximum: TokenAmount?
    private var cardMaximumError: String?
    private var retainedTokenAmount: TokenAmount?
    @PerceptionIgnored @AccountContext var account: MAccount

    init(swap: SwapModel, direction: TokenTradeDirection, token: ApiToken, accountContext: AccountContext) {
        self.swap = swap
        self.direction = direction
        self._account = accountContext
        self.token = token
        // Start with the resolved swap pair. Card is another payment/receipt method in the picker.
        if (token.price ?? 0) <= 0 { isTokenAmount = true }
    }

    var currentToken: ApiToken { TokenStore.getToken(slug: token.slug) ?? token }
    var isBuying: Bool { direction == .buy }
    var paymentToken: ApiToken? { isBuying ? swap.input.sellingToken : swap.input.buyingToken }
    var hint: SwapHint? { cardCurrency == nil ? swap.hint : nil }
    var displayImpactWarning: Double? { cardCurrency == nil ? swap.displayImpactWarning : nil }
    var currency: MBaseCurrency { cardCurrency ?? TokenStore.baseCurrency }
    var price: Double { (currentToken.priceUsd ?? 0) * TokenStore.getCurrencyRate(currency) }
    var inputDecimals: Int { isTokenAmount ? token.decimals : (currency.preferredDecimals ?? currency.decimalsCount) }
    var hasAmount: Bool { input.amount(decimals: inputDecimals) > 0 }
    var typedTokenAmount: TokenAmount {
        if let retainedTokenAmount { return retainedTokenAmount }
        if isTokenAmount { return TokenAmount(input.amount(decimals: token.decimals), currentToken) }
        guard price > 0 else { return TokenAmount(0, currentToken) }
        let amount = convertDecimalsKeepingDoubleValue(input.amount(decimals: inputDecimals), fromDecimals: inputDecimals, toDecimals: currency.decimalsCount)
        return BaseCurrencyAmount(amount, currency).convertTo(currentToken, exchangeRate: 1 / price)
    }

    var displayedTokenAmount: TokenAmount {
        if isBuying, cardCurrency == nil,
           let amount = swap.input.buyingTokenAmount, amount.amount > 0 {
            return amount
        }
        return typedTokenAmount
    }

    var availableCardCurrencies: [MBaseCurrency] {
        guard account.network == .mainnet, !account.isView, !account.isHardware,
              !ConfigStore.shared.shouldRestrictSwapsAndOnRamp,
              account.supports(chain: token.chain), token.isNative else { return [] }
        if isBuying {
            guard token.chain.isOnrampSupported else { return [] }
            return OnRampCurrencyPolicy.supportedCurrencies(for: token.chain)
        }
        guard token.chain.isOfframpSupported else { return [] }
        let allowed = ConfigStore.shared.config?.allowedOnOffRampCurrencies
        return Moonpay.Offramp.supportedCurrencies.filter { currency in
            allowed?.contains { $0.uppercased() == currency.rawValue } ?? true
        }
    }

    var maximumTokenAmount: TokenAmount? {
        if cardCurrency != nil {
            return isBuying ? nil : cardMaximum
        }
        guard let selling = swap.input.sellingToken, let maximum = swap.input.maxAmount ?? swap.input.tokenBalance else { return nil }
        let amount = TokenAmount(maximum, selling)
        if !isBuying { return amount }
        guard let sellingPrice = selling.priceUsd, let buyingPrice = currentToken.priceUsd, buyingPrice > 0 else { return nil }
        return amount.convertTo(currentToken, exchangeRate: sellingPrice / buyingPrice)
    }

    var feeText: String? {
        guard cardCurrency == nil, hasAmount,
              let selling = swap.input.sellingToken,
              let native = TokenStore.getToken(slug: selling.nativeTokenSlug) else { return nil }
        let details: ExplainedTransferFee?
        if let estimate = swap.estimateState.cexEstimate {
            details = explainSwapFee(.init(swapType: swap.swapType, tokenIn: selling,
                                           networkFee: estimate.networkFee, realNetworkFee: estimate.realNetworkFee,
                                           dieselStatus: nil, dieselFee: nil,
                                           nativeTokenInBalance: $account.balances[native.slug])).networkFeeDetails
        } else { details = swap.detailsVM.feeDetails }
        guard let fee = details?.realFee ?? details?.fullFee else { return nil }
        var displayedFee = fee
        if displayedFee.precision == .approximate { displayedFee.precision = .exact }
        let prefix = fee.precision == .lessThan ? " " : " ~ "
        return lang("Fee") + prefix + displayedFee.toString(token: selling, nativeToken: native)
    }

    var methodAmountText: String? {
        guard hasAmount else { return nil }
        if let cardCurrency {
            return DecimalAmountFormatStyle<MBaseCurrency>(preset: .baseCurrencyEquivalent, showSymbol: false)
                .format(typedTokenAmount.convertTo(cardCurrency, exchangeRate: price))
        }
        let amount = isBuying ? swap.input.sellingTokenAmount : swap.input.buyingTokenAmount
        guard let amount, amount.amount > 0 else { return nil }
        return DecimalAmountFormatStyle<ApiToken>(preset: .defaultAdaptive, showSymbol: false).format(amount)
    }

    var methodSymbol: String { cardCurrency?.rawValue ?? paymentToken?.symbol ?? lang("Select Token") }

    var isMethodAmountStale: Bool {
        cardCurrency == nil && swap.input.staleAmountSide == (isBuying ? .selling : .buying)
    }

    var isConversionAmountStale: Bool {
        isBuying && !isTokenAmount && cardCurrency == nil && swap.input.staleAmountSide == .buying
    }

    var actionTitle: String {
        if cardCurrency == nil {
            switch swap.currentButtonState {
            case .blocked(let issue): return issue.buttonTitle
            case .invalidPair: return SwapIssue.invalidPair.buttonTitle
            case .authorizeDiesel: return L10n.authorizeTokenFeeCapitalized(token: swap.input.sellingToken?.symbol ?? token.symbol)
            default: break
            }
        }
        if let cardCurrency {
            if !isBuying {
                if let cardMaximumError { return cardMaximumError }
                if cardMaximum == nil { return lang("Loading...") }
                if typedTokenAmount.amount > (cardMaximum?.amount ?? 0) { return lang("Insufficient Balance") }
            }
            let provider = cardCurrency == .RUB ? "Dreamwalkers" : "MoonPay"
            return isBuying ? L10n.buyTokenViaProvider(token: token.symbol, provider: provider)
                : L10n.sellTokenViaProvider(token: token.symbol, provider: provider)
        }
        return isBuying ? L10n.buyToken(token: token.symbol) : L10n.sellSymbol(symbol: token.symbol)
    }

    var canContinue: Bool {
        guard hasAmount, typedTokenAmount.amount > 0, !ConfigStore.shared.shouldRestrictSwapsAndOnRamp else { return false }
        if let cardCurrency {
            return availableCardCurrencies.contains(cardCurrency)
                && (isBuying || typedTokenAmount.amount <= (maximumTokenAmount?.amount ?? 0))
        }
        return swap.currentButtonConfiguration.isEnabled
    }

    var buttonConfiguration: DraftButtonConfiguration {
        .init(title: .text(actionTitle), isEnabled: canContinue,
              showLoading: cardCurrency == nil && swap.currentButtonConfiguration.showLoading,
              resetsLoadingAppearance: !hasAmount)
    }

    func performHintAction(_ hint: SwapHint) {
        guard hint == self.hint else { return }
        if case .intermediate(let token, _) = hint {
            if isBuying {
                swap.performHintAction(hint)
                self.token = token
                // The previous quantity belongs to the original asset.
                resetAmount()
                if price <= 0 { isTokenAmount = true }
            } else {
                selectToken(token)
            }
        } else {
            swap.performHintAction(hint)
        }
    }

    var rateText: String {
        if cardCurrency != nil {
            return "\(token.symbol) ≈ \(BaseCurrencyAmount.fromDouble(price, currency).formatted(.baseCurrencyHighPrecision))"
        }
        guard let other = paymentToken else { return "" }
        let estimate = swap.estimateState
        let selling = estimate.dexEstimate?.fromAmount.value ?? estimate.cexEstimate?.fromAmount.value
        let buying = estimate.dexEstimate?.toAmount.value ?? estimate.cexEstimate?.toAmount.value
        let hasQuote = (selling ?? 0) > 0 && (buying ?? 0) > 0
        guard let rate = ExchangeRateHelpers.getSwapRate(
            fromAmount: hasQuote ? selling : other.priceUsd,
            toAmount: hasQuote ? buying : currentToken.priceUsd,
            fromToken: hasQuote ? swap.input.sellingToken : currentToken,
            toToken: hasQuote ? swap.input.buyingToken : other
        ) else { return "" }
        return "\(rate.toToken.symbol) ≈ \(TokenAmount.fromDouble(rate.price, rate.fromToken).formatted(.defaultAdaptive))"
    }

    func userEditedInput(_ input: TokenTradeAmountInput) {
        guard self.input != input else { return }
        self.input = input
        retainedTokenAmount = nil
        updateSwapAmount()
    }

    func toggleUnit() {
        guard price > 0 else { return }
        let amount = typedTokenAmount
        isTokenAmount.toggle()
        setInput(amount)
    }

    func useFraction(_ percentage: Int) {
        guard let maximum = maximumTokenAmount else { return }
        if cardCurrency == nil {
            guard let selling = swap.input.sellingToken else { return }
            let maximumSelling = swap.input.maxAmount ?? swap.input.tokenBalance ?? 0
            let amount = maximumSelling * BigInt(percentage) / 100
            if percentage == 100 { swap.input.userTappedUseAll() }
            else { swap.input.userEditedAmount(amount, side: .selling) }
            let tokenAmount = isBuying
                ? TokenAmount(amount, selling).convertTo(currentToken, exchangeRate: (selling.priceUsd ?? 0) / max(currentToken.priceUsd ?? 0, .leastNonzeroMagnitude))
                : TokenAmount(amount, currentToken)
            setInput(tokenAmount)
        } else {
            setInput(TokenAmount(maximum.amount * BigInt(percentage) / 100, currentToken))
        }
    }

    func selectCard(_ currency: MBaseCurrency) {
        guard availableCardCurrencies.contains(currency) else { return }
        let amount = typedTokenAmount
        let changesCurrency = self.currency != currency
        cardCurrency = currency
        swap.setStage(.externalAddress)
        if changesCurrency { setInput(amount) }
        else { retainedTokenAmount = amount }
    }

    func selectToken(_ token: ApiToken) {
        guard token.slug != self.token.slug else { return }
        let amount = typedTokenAmount
        let changesCurrency = currency != TokenStore.baseCurrency
        cardCurrency = nil
        swap.setStage(.editing)
        swap.input.userSelectedToken(token, side: isBuying ? .selling : .buying)
        swap.updateSwapType()
        if changesCurrency { setInput(amount) }
        else { retainedTokenAmount = amount }
        updateSwapAmount()
    }

    func resetAmount() {
        input = TokenTradeAmountInput()
        retainedTokenAmount = nil
        cardMaximum = nil
        cardMaximumError = nil
        if let cardCurrency, !availableCardCurrencies.contains(cardCurrency) { self.cardCurrency = nil }
        swap.input.userEditedAmount(nil, side: .selling)
    }

    private func setInput(_ tokenAmount: TokenAmount) {
        retainedTokenAmount = tokenAmount
        if isTokenAmount { input.set(tokenAmount.amount, decimals: token.decimals) }
        else {
            let amount = tokenAmount.convertTo(currency, exchangeRate: price)
            let divisor = powI64(10, currency.decimalsCount - inputDecimals)
            input.set((amount.amount + divisor / 2) / divisor, decimals: inputDecimals)
        }
    }

    private func updateSwapAmount() {
        guard cardCurrency == nil else { return }
        if isBuying && swap.input.buyingAmountInputDisabled {
            guard let payingToken = paymentToken, let payingPrice = payingToken.priceUsd, payingPrice > 0 else {
                swap.input.userEditedAmount(nil, side: .selling)
                return
            }
            let amount = typedTokenAmount.convertTo(payingToken, exchangeRate: (currentToken.priceUsd ?? 0) / payingPrice)
            swap.input.userEditedAmount(amount.amount, side: .selling)
        } else {
            swap.input.userEditedAmount(typedTokenAmount.amount, side: isBuying ? .buying : .selling)
        }
    }

    struct CardMaximumRequest: Hashable {
        let accountId: String
        let balance: BigInt
    }

    var cardMaximumRequest: CardMaximumRequest? {
        guard !isBuying, let cardCurrency, availableCardCurrencies.contains(cardCurrency) else { return nil }
        return CardMaximumRequest(accountId: account.id, balance: $account.balances[token.slug] ?? 0)
    }

    func refreshCardMaximum() async {
        cardMaximum = nil
        cardMaximumError = nil
        guard let request = cardMaximumRequest else { return }
        do {
            var amount = try await SellFeeEstimate.maximumAmount(accountId: request.accountId, tokenSlug: token.slug,
                                                                chain: token.chain, balance: request.balance) ?? 0
            if let limit = Moonpay.Offramp.limitsBySlug[token.slug] {
                amount = min(amount, TokenAmount.fromDouble(limit, token).amount)
            }
            guard !Task.isCancelled, cardMaximumRequest == request else { return }
            cardMaximum = TokenAmount(max(0, amount), currentToken)
        } catch {
            guard !Task.isCancelled, cardMaximumRequest == request else { return }
            cardMaximumError = lang("Unexpected Error")
        }
    }
}
