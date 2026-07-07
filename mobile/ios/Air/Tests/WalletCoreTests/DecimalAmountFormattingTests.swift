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

    struct WebActivityAmountCase: Sendable {
        let amount: BigInt
        let decimals: Int
        let expected: String
    }

    static let webActivityAmountCases: [WebActivityAmountCase] = [
        .init(amount: BigInt(440_074), decimals: 4, expected: "44 TEST"),
        .init(amount: BigInt(440_740), decimals: 4, expected: "44.07 TEST"),
        .init(amount: BigInt(2_857), decimals: 4, expected: "0.28 TEST"),
        .init(amount: BigInt(2_857), decimals: 5, expected: "0.028 TEST"),
        .init(amount: BigInt(-1_234_560), decimals: 4, expected: "-\(signSpace)123.45 TEST"),
    ]

    @Test(arguments: Self.webActivityAmountCases)
    func `defaultAdaptive can truncate like web activity amounts`(testCase: WebActivityAmountCase) {
        let amount = AnyDecimalAmount(
            testCase.amount,
            decimals: testCase.decimals,
            symbol: "TEST",
            forceCurrencyToRight: true
        )

        #expect(amount.formatted(.defaultAdaptive, roundHalfUp: false) == testCase.expected)
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

    @Test
    func `fee preset uses zero count subscript for tiny values`() {
        let amount = AnyDecimalAmount(
            BigInt(5_600),
            decimals: 9,
            symbol: "TON",
            forceCurrencyToRight: true
        )

        #expect(amount.formatted(.fee) == "0.0₅56 TON")
        #expect(amount.formatted(.defaultAdaptive) == "0.0000056 TON")
    }

    @Test
    func `fee string uses fee formatting preset`() {
        let fee = MFee(
            precision: .approximate,
            terms: .init(token: nil, native: BigInt(5_600), stars: nil),
            nativeSum: nil
        )

        #expect(fee.toString(token: .TONCOIN, nativeToken: .TONCOIN) == "~0.0₅56 GRAM")
    }

    @Test
    func `base currency price uses significant digits for small values`() {
        let amount = BaseCurrencyAmount(BigInt(22_222), .USD)

        #expect(amount.formatted(.baseCurrencyPrice) == "$0.022")
    }

    @Test
    func `base currency price still hides decimals for large values`() {
        let amount = BaseCurrencyAmount(BigInt(12_345_678_901), .USD)

        #expect(amount.formatted(.baseCurrencyPrice) == "$12 346")
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
