import Foundation
import Testing
import WalletContext

@Suite("WalletContext Number Formatting")
struct WalletContextNumberFormattingTests {
    @Test(arguments: [
        (0.0, "0"),
        (12.346, "12.35"),
        (999.0, "999"),
        (1_000.0, "1K"),
        (1_540.0, "1.54K"),
        (999_990.0, "999.99K"),
        (1_000_000.0, "1M"),
        (1_540_000.0, "1.54M"),
        (999_990_000.0, "999.99M"),
        (1_000_000_000.0, "1B"),
        (1_540_000_000.0, "1.54B"),
        (999_990_000_000.0, "999.99B"),
        (1_000_000_000_000.0, "1T"),
        (1_540_000_000_000.0, "1.54T"),
        (12_345_678_900_000.0, "12.35T"),
        (-1_540_000_000_000.0, "-1.54T"),
    ])
    func `compact numbers use K M B T with a dot separator`(value: Double, expected: String) {
        #expect(formatCompactNumber(value) == expected)
    }

    @Test(arguments: [
        ("$", "$1.54T"),
        ("€", "€1.54T"),
        ("¥", "¥1.54T"),
        ("₽", "1.54T ₽"),
        ("BTC", "1.54T BTC"),
        ("GRAM", "1.54T GRAM"),
        ("", "1.54T"),
    ])
    func `compact currencies preserve symbol placement`(currency: String, expected: String) {
        #expect(formatCompactNumber(1_540_000_000_000, currency: currency) == expected)
    }

    @Test(arguments: [
        ("en", "+\(signSpace)15.59%", "-\(signSpace)0.66%", "13.3%", "0.0%", "13%"),
        ("fa", "+\(signSpace)۱۵.۵۹%", "-\(signSpace)۰.۶۶%", "۱۳.۳%", "۰.۰%", "۱۳%"),
        ("ar@numbers=arab", "+\(signSpace)١٥.٥٩%", "-\(signSpace)٠.٦٦%", "١٣.٣%", "٠.٠%", "١٣%"),
    ])
    func `percentages localize digits and preserve signs and precision`(
        identifier: String, positive: String, negative: String, unsigned: String, zero: String, whole: String
    ) {
        let locale = Locale(identifier: identifier)
        #expect(formatPercent(0.1559, locale: locale) == positive)
        #expect(formatPercent(-0.0066, locale: locale) == negative)
        #expect(formatPercent(0.133, showPlus: false, locale: locale) == unsigned)
        #expect(formatPercent(-0.133, showMinus: false, locale: locale) == unsigned)
        #expect(formatPercent(-0.000001, locale: locale) == zero)
        #expect(formatPercent(0.133, decimals: 0, showPlus: false, locale: locale) == whole)
    }

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
    func `formatBigIntText preserves requested minimum fraction digits`() {
        let trailingZero = formatBigIntText(
            BigInt(12_345_100_000),
            currency: "$",
            tokenDecimals: 6,
            decimalsCount: 2,
            minimumFractionDigits: 2
        )
        let whole = formatBigIntText(
            BigInt(12_345_000_000),
            currency: "$",
            tokenDecimals: 6,
            decimalsCount: 2,
            minimumFractionDigits: 2
        )

        #expect(trailingZero == "$12 345.10")
        #expect(whole == "$12 345.00")
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
