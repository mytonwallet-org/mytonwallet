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

    struct TokenDecimalsCase: Sendable {
        let amount: BigInt
        let tokenDecimals: Int
        let minimumSignificantDigits: Int
        let expected: Int
    }

    static let tokenDecimalsCases: [TokenDecimalsCase] = [
        .init(
            amount: BigInt(0),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 0
        ),
        .init(
            amount: BigInt(1),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 6
        ),
        .init(
            amount: BigInt(2_222),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 4
        ),
        .init(
            amount: BigInt(22_222),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 3
        ),
        .init(
            amount: BigInt(222_222),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 2
        ),
        .init(
            amount: BigInt(1_234_567),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 2
        ),
        .init(
            amount: BigInt(12_345_678_901),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 2
        ),
        .init(
            amount: BigInt(-22_222),
            tokenDecimals: 6,
            minimumSignificantDigits: 2,
            expected: 3
        ),
        .init(
            amount: BigInt(22_222),
            tokenDecimals: 6,
            minimumSignificantDigits: 4,
            expected: 5
        ),
        .init(
            amount: BigInt(1_234_567),
            tokenDecimals: 6,
            minimumSignificantDigits: 4,
            expected: 4
        ),
        .init(
            amount: BigInt(22_222),
            tokenDecimals: 2,
            minimumSignificantDigits: 4,
            expected: 2
        ),
        .init(
            amount: BigInt(22_222),
            tokenDecimals: 0,
            minimumSignificantDigits: 2,
            expected: 0
        ),
    ]

    @Test(arguments: Self.tokenDecimalsCases)
    func `tokenDecimals returns adaptive fractional digits`(testCase: TokenDecimalsCase) {
        #expect(
            tokenDecimals(
                for: testCase.amount,
                tokenDecimals: testCase.tokenDecimals,
                minimumSignificantDigits: testCase.minimumSignificantDigits
            ) == testCase.expected
        )
    }

    struct AmountValueCase: Sendable {
        let input: String
        let decimals: Int
        let expected: BigInt
    }

    static let amountValueCases: [AmountValueCase] = [
        .init(input: "0.5", decimals: 9, expected: BigInt(500_000_000)),
        .init(input: "0,5", decimals: 9, expected: BigInt(500_000_000)),
        .init(input: "12 345.67", decimals: 2, expected: BigInt(1_234_567)),
        .init(input: "12 345,67", decimals: 2, expected: BigInt(1_234_567)),
        .init(input: "1,234.56", decimals: 2, expected: BigInt(123_456)),
        .init(input: "1.234,56", decimals: 2, expected: BigInt(123_456)),
    ]

    @Test(arguments: Self.amountValueCases)
    func `amountValue accepts mixed decimal separators and grouping formats`(testCase: AmountValueCase) {
        #expect(amountValue(testCase.input, digits: testCase.decimals) == testCase.expected)
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
    func `formatBigIntText can compact leading fractional zero count`() {
        let formatted = formatBigIntText(
            BigInt(560),
            tokenDecimals: 9,
            zeroCountSubscriptMinCount: 6
        )

        #expect(formatted == "0.0₆56")
    }

    @Test
    func `formatBigIntText keeps leading fractional zeroes below threshold`() {
        let formatted = formatBigIntText(
            BigInt(5_600),
            tokenDecimals: 9,
            zeroCountSubscriptMinCount: 6
        )

        #expect(formatted == "0.0000056")
    }

    @Test
    func `formatBigIntText supports multi-digit zero count subscripts`() {
        let formatted = formatBigIntText(
            BigInt(1),
            tokenDecimals: 18,
            zeroCountSubscriptMinCount: 6
        )

        #expect(formatted == "0.0₁₇1")
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
