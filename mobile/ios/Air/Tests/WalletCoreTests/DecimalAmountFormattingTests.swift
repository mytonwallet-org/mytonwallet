import Testing
import WalletCore
import WalletContext

@Suite("DecimalAmount Formatting")
struct DecimalAmountFormattingTests {
    struct AmountRoundingCase: Sendable {
        let amount: BigInt
        let expected: BigInt
    }

    static let roundedForDisplayCases: [AmountRoundingCase] = [
        .init(
            amount: BigInt(99_123_456_789),
            expected: BigInt(99_123_456_789)
        ),
        .init(
            amount: BigInt(100_123_456_789),
            expected: BigInt(100_123_456_000)
        ),
        .init(
            amount: BigInt(10_000_123_456_789),
            expected: BigInt(10_000_123_400_000)
        ),
        .init(
            amount: BigInt(100_000_123_456_789),
            expected: BigInt(100_000_120_000_000)
        ),
    ]

    @Test(arguments: Self.roundedForDisplayCases)
    func `roundedForDisplay uses expected thresholds`(testCase: AmountRoundingCase) {
        let amount = makeAmount(testCase.amount)

        #expect(amount.roundedForDisplay.amount == testCase.expected)
    }

    static let roundedForSwapCases: [AmountRoundingCase] = [
        .init(
            amount: BigInt(9_999_999_999),
            expected: BigInt(9_999_999_999)
        ),
        .init(
            amount: BigInt(10_123_456_789),
            expected: BigInt(10_123_456_000)
        ),
        .init(
            amount: BigInt(1_000_123_456_789),
            expected: BigInt(1_000_123_400_000)
        ),
        .init(
            amount: BigInt(100_000_123_456_789),
            expected: BigInt(100_000_120_000_000)
        ),
        .init(
            amount: BigInt(1_000_000_123_456_789),
            expected: BigInt(1_000_000_000_000_000)
        ),
    ]

    @Test(arguments: Self.roundedForSwapCases)
    func `roundedForSwap uses expected thresholds`(testCase: AmountRoundingCase) {
        let amount = makeAmount(testCase.amount)

        #expect(amount.roundedForSwap.amount == testCase.expected)
    }

    @Test
    func `format renders plus sign and respects roundHalfUp`() {
        let amount = AnyDecimalAmount(
            BigInt(123_450),
            decimals: 4,
            symbol: "$"
        )
        let roundedUp: DecimalAmountFormatStyle<AnyDecimalBackingType> = .init(
            maxDecimals: 2,
            showPlus: true
        )
        let truncated: DecimalAmountFormatStyle<AnyDecimalBackingType> = .init(
            maxDecimals: 2,
            roundHalfUp: false
        )

        #expect(roundedUp.format(amount) == "+\(signSpace)$12.35")
        #expect(truncated.format(amount) == "$12.34")
    }

    @Test
    func `format renders precision prefix and right side symbol`() {
        let amount = AnyDecimalAmount(
            BigInt(123_450),
            decimals: 4,
            symbol: "$",
            forceCurrencyToRight: true
        )
        let style: DecimalAmountFormatStyle<AnyDecimalBackingType> = .init(
            maxDecimals: 2,
            precision: .approximate
        )

        #expect(style.format(amount) == "~12.35 $")
    }

    @Test
    func `format can hide symbol and minus`() {
        let negativeAmount = AnyDecimalAmount(
            BigInt(-123_450),
            decimals: 4,
            symbol: "$"
        )
        let positiveAmount = AnyDecimalAmount(
            BigInt(123_450),
            decimals: 4,
            symbol: "$"
        )
        let noMinus: DecimalAmountFormatStyle<AnyDecimalBackingType> = .init(
            maxDecimals: 2,
            showMinus: false
        )
        let noSymbol: DecimalAmountFormatStyle<AnyDecimalBackingType> = .init(
            maxDecimals: 2,
            showSymbol: false
        )

        #expect(noMinus.format(negativeAmount) == "$12.35")
        #expect(noSymbol.format(positiveAmount) == "12.35")
    }

    @Test
    func `formatted with compact preset adjusts visible decimals`() {
        let belowThreshold = AnyDecimalAmount(
            BigInt(49_123_456_789),
            decimals: 9,
            symbol: "TON",
            forceCurrencyToRight: true
        )
        let aboveThreshold = AnyDecimalAmount(
            BigInt(50_123_456_789),
            decimals: 9,
            symbol: "TON",
            forceCurrencyToRight: true
        )

        #expect(belowThreshold.formatted(.compact) == "49.12 TON")
        #expect(aboveThreshold.formatted(.compact) == "50 TON")
    }

    func makeAmount(_ rawAmount: BigInt) -> AnyDecimalAmount {
        AnyDecimalAmount(
            rawAmount,
            decimals: 9,
            symbol: "TON",
            forceCurrencyToRight: true
        )
    }
}
