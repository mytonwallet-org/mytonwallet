import Foundation
import WalletContext

enum TokenSendAmountInputMode: Equatable, Sendable {
    case token
    case baseCurrency
}

enum TokenSendAmountIntent: Equatable, Sendable {
    case exact(BigInt)
    case all
}

struct TokenSendAmountInput: Equatable, Sendable {
    private(set) var amount: BigInt?
    private(set) var amountInBaseCurrency: BigInt?
    private(set) var mode: TokenSendAmountInputMode
    private(set) var intent: TokenSendAmountIntent?

    init(
        amount: BigInt? = nil,
        amountInBaseCurrency: BigInt? = nil,
        mode: TokenSendAmountInputMode = .token,
        intent: TokenSendAmountIntent? = nil
    ) {
        self.amount = amount
        self.amountInBaseCurrency = amountInBaseCurrency
        self.mode = mode
        self.intent = intent
    }

    init(
        tokenAmount: BigInt?,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        self.init()
        setTokenAmount(
            tokenAmount,
            price: price,
            tokenDecimals: tokenDecimals,
            baseCurrencyDecimals: baseCurrencyDecimals
        )
    }

    mutating func setMode(_ mode: TokenSendAmountInputMode) {
        self.mode = mode
    }

    mutating func setTokenAmount(
        _ amount: BigInt?,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        self.amount = amount
        intent = amount.map(TokenSendAmountIntent.exact)
        amountInBaseCurrency = amount.flatMap {
            Self.convertToBaseCurrency(
                $0,
                price: price,
                tokenDecimals: tokenDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        }
    }

    mutating func setBaseCurrencyAmount(
        _ amountInBaseCurrency: BigInt?,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        self.amountInBaseCurrency = amountInBaseCurrency
        amount = amountInBaseCurrency.flatMap {
            Self.convertToToken(
                $0,
                price: price,
                tokenDecimals: tokenDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        }
        intent = amount.map(TokenSendAmountIntent.exact)
    }

    mutating func selectAll(
        _ maximumAmount: BigInt?,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        mode = .token
        intent = .all
        amount = maximumAmount
        amountInBaseCurrency = maximumAmount.flatMap {
            Self.convertToBaseCurrency(
                $0,
                price: price,
                tokenDecimals: tokenDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        }
    }

    mutating func updateMaximumAmount(
        _ maximumAmount: BigInt?,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        guard intent == .all else { return }
        selectAll(
            maximumAmount,
            price: price,
            tokenDecimals: tokenDecimals,
            baseCurrencyDecimals: baseCurrencyDecimals
        )
    }

    mutating func adjustExactAmount(
        to amount: BigInt,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        guard case .exact = intent else { return }
        self.amount = amount
        intent = .exact(amount)
        amountInBaseCurrency = Self.convertToBaseCurrency(
            amount,
            price: price,
            tokenDecimals: tokenDecimals,
            baseCurrencyDecimals: baseCurrencyDecimals
        )
    }

    mutating func refreshConversion(
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) {
        switch mode {
        case .token:
            amountInBaseCurrency = amount.flatMap {
                Self.convertToBaseCurrency(
                    $0,
                    price: price,
                    tokenDecimals: tokenDecimals,
                    baseCurrencyDecimals: baseCurrencyDecimals
                )
            }
            if intent != .all {
                intent = amount.map(TokenSendAmountIntent.exact)
            }
        case .baseCurrency:
            amount = amountInBaseCurrency.flatMap {
                Self.convertToToken(
                    $0,
                    price: price,
                    tokenDecimals: tokenDecimals,
                    baseCurrencyDecimals: baseCurrencyDecimals
                )
            }
            intent = amount.map(TokenSendAmountIntent.exact)
        }
    }

    mutating func changeToken(
        fromDecimals: Int,
        toDecimals: Int,
        price: Double?,
        baseCurrencyDecimals: Int,
        maximumAmount: BigInt?
    ) {
        if intent == .all {
            selectAll(
                maximumAmount,
                price: price,
                tokenDecimals: toDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        } else if mode == .baseCurrency {
            refreshConversion(
                price: price,
                tokenDecimals: toDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        } else {
            amount = amount.map {
                convertDecimalsKeepingDoubleValue(
                    $0,
                    fromDecimals: fromDecimals,
                    toDecimals: toDecimals
                )
            }
            intent = amount.map(TokenSendAmountIntent.exact)
            refreshConversion(
                price: price,
                tokenDecimals: toDecimals,
                baseCurrencyDecimals: baseCurrencyDecimals
            )
        }
    }

    private static func convertToBaseCurrency(
        _ amount: BigInt,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) -> BigInt? {
        guard let price, price > 0 else { return nil }
        return convertAmount(
            amount,
            price: price,
            tokenDecimals: tokenDecimals,
            baseCurrencyDecimals: baseCurrencyDecimals
        )
    }

    private static func convertToToken(
        _ amountInBaseCurrency: BigInt,
        price: Double?,
        tokenDecimals: Int,
        baseCurrencyDecimals: Int
    ) -> BigInt? {
        guard let price, price > 0 else { return nil }
        return convertAmountReverse(
            amountInBaseCurrency,
            price: price,
            tokenDecimals: tokenDecimals,
            baseCurrencyDecimals: baseCurrencyDecimals
        )
    }
}
