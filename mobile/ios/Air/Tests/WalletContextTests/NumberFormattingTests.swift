import Testing
import WalletContext

@Suite("WalletContext Number Formatting")
struct WalletContextNumberFormattingTests {
    struct RoundDecimalsCase: Sendable {
        let amount: BigInt
        let decimals: Int
        let maxDecimals: Int
        let expected: BigInt
    }

    static let roundDecimalsCases: [RoundDecimalsCase] = [
        .init(
            amount: BigInt(123_456_789),
            decimals: 6,
            maxDecimals: 2,
            expected: BigInt(123_450_000)
        ),
        .init(
            amount: BigInt(12_345_678),
            decimals: 6,
            maxDecimals: 4,
            expected: BigInt(12_345_600)
        ),
        .init(
            amount: BigInt(-123_456_789),
            decimals: 6,
            maxDecimals: 2,
            expected: BigInt(-123_450_000)
        ),
        .init(
            amount: BigInt(0),
            decimals: 6,
            maxDecimals: 2,
            expected: BigInt(0)
        ),
    ]

    @Test(arguments: Self.roundDecimalsCases)
    func `roundDecimals truncates fractional digits`(testCase: RoundDecimalsCase) {
        #expect(
            roundDecimals(
                testCase.amount,
                decimals: testCase.decimals,
                roundTo: testCase.maxDecimals
            ) == testCase.expected
        )
    }

    @Test
    func `formatBigIntText uses grouping and trims trailing zeroes`() {
        let formatted = formatBigIntText(
            BigInt(1_234_567_890),
            tokenDecimals: 4
        )

        #expect(formatted == "123 456.789")
    }

    @Test
    func `formatBigIntText rounds half up when requested`() {
        let formatted = formatBigIntText(
            BigInt(123_450),
            currency: "$",
            tokenDecimals: 4,
            decimalsCount: 2,
            roundHalfUp: true
        )

        #expect(formatted == "$12.35")
    }

    @Test
    func `formatBigIntText truncates when roundHalfUp is disabled`() {
        let formatted = formatBigIntText(
            BigInt(123_450),
            currency: "$",
            tokenDecimals: 4,
            decimalsCount: 2,
            roundHalfUp: false
        )

        #expect(formatted == "$12.34")
    }

    struct CurrencyPlacementCase: Sendable {
        let currency: String
        let forceCurrencyToRight: Bool
        let expected: String
    }

    static let currencyPlacementCases: [CurrencyPlacementCase] = [
        .init(currency: "$", forceCurrencyToRight: false, expected: "$12.34"),
        .init(currency: "TON", forceCurrencyToRight: false, expected: "12.34 TON"),
        .init(currency: "$", forceCurrencyToRight: true, expected: "12.34 $"),
        .init(currency: "₽", forceCurrencyToRight: false, expected: "12.34 ₽"),
    ]

    @Test(arguments: Self.currencyPlacementCases)
    func `formatBigIntText places currency on expected side`(testCase: CurrencyPlacementCase) {
        let formatted = formatBigIntText(
            BigInt(1_234),
            currency: testCase.currency,
            tokenDecimals: 2,
            forceCurrencyToRight: testCase.forceCurrencyToRight
        )

        #expect(formatted == testCase.expected)
    }

    @Test
    func `formatBigIntText applies positive and negative signs`() {
        let positive = formatBigIntText(
            BigInt(1_234),
            currency: "TON",
            positiveSign: true,
            tokenDecimals: 2
        )
        let negative = formatBigIntText(
            BigInt(-1_234),
            currency: "$",
            negativeSign: true,
            tokenDecimals: 2
        )

        #expect(positive == "+\(signSpace)12.34 TON")
        #expect(negative == "-\(signSpace)$12.34")
    }
}
