import Testing
@testable import UISend
import WalletContext

@Suite("Token Send Amount Input")
struct TokenSendAmountInputTests {
    @Test
    func `prefilled token amount initializes its fiat projection`() {
        let input = TokenSendAmountInput(
            tokenAmount: 2_000_000_000,
            price: 3,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        #expect(input.amount == 2_000_000_000)
        #expect(input.amountInBaseCurrency == 600)
        #expect(input.intent == .exact(2_000_000_000))
    }

    @Test
    func `token input remains authoritative when price changes`() {
        var input = TokenSendAmountInput()
        input.setTokenAmount(
            2_000_000_000,
            price: 2,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        input.refreshConversion(
            price: 3,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        #expect(input.amount == 2_000_000_000)
        #expect(input.amountInBaseCurrency == 600)
        #expect(input.intent == .exact(2_000_000_000))
    }

    @Test
    func `base currency input remains authoritative when price changes`() {
        var input = TokenSendAmountInput(mode: .baseCurrency)
        input.setBaseCurrencyAmount(
            600,
            price: 3,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        input.refreshConversion(
            price: 2,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        #expect(input.amountInBaseCurrency == 600)
        #expect(input.amount == 3_000_000_000)
        #expect(input.intent == .exact(3_000_000_000))
    }

    @Test
    func `changing token preserves the visible token amount`() {
        var input = TokenSendAmountInput()
        input.setTokenAmount(
            1_500_000_000,
            price: 2,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        input.changeToken(
            fromDecimals: 9,
            toDecimals: 6,
            price: 4,
            baseCurrencyDecimals: 2,
            maximumAmount: nil
        )

        #expect(input.amount == 1_500_000)
        #expect(input.amountInBaseCurrency == 600)
        #expect(input.intent == .exact(1_500_000))
    }

    @Test
    func `changing token preserves the visible base currency amount`() {
        var input = TokenSendAmountInput(mode: .baseCurrency)
        input.setBaseCurrencyAmount(
            600,
            price: 3,
            tokenDecimals: 9,
            baseCurrencyDecimals: 2
        )

        input.changeToken(
            fromDecimals: 9,
            toDecimals: 6,
            price: 4,
            baseCurrencyDecimals: 2,
            maximumAmount: nil
        )

        #expect(input.amountInBaseCurrency == 600)
        #expect(input.amount == 1_500_000)
        #expect(input.intent == .exact(1_500_000))
    }

    @Test
    func `all intent follows a changing maximum`() {
        var input = TokenSendAmountInput()
        input.selectAll(
            1_000,
            price: 2,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        input.updateMaximumAmount(
            900,
            price: 2,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        #expect(input.amount == 900)
        #expect(input.intent == .all)
    }

    @Test
    func `exact intent ignores Max tracking updates`() {
        var input = TokenSendAmountInput()
        input.setTokenAmount(
            1_000,
            price: 2,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        input.updateMaximumAmount(
            900,
            price: 2,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        #expect(input.amount == 1_000)
        #expect(input.intent == .exact(1_000))
    }

    @Test
    func `missing price never replaces token input with zero`() {
        var tokenInput = TokenSendAmountInput()
        tokenInput.setTokenAmount(
            1_000,
            price: nil,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        var baseCurrencyInput = TokenSendAmountInput(mode: .baseCurrency)
        baseCurrencyInput.setBaseCurrencyAmount(
            500,
            price: 0,
            tokenDecimals: 2,
            baseCurrencyDecimals: 2
        )

        #expect(tokenInput.amount == 1_000)
        #expect(tokenInput.amountInBaseCurrency == nil)
        #expect(tokenInput.intent == .exact(1_000))
        #expect(baseCurrencyInput.amountInBaseCurrency == 500)
        #expect(baseCurrencyInput.amount == nil)
        #expect(baseCurrencyInput.intent == nil)
    }
}
