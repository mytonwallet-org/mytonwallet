import Testing
import WalletContext

@Suite("AssetPrecision")
struct AssetPrecisionTests {
    @Test(arguments: [
        (0.0, 0),
        (0.0001, 0),
        (0.97, 0),
        (0.98, 2),
        (1.0, 2),
        (999.99, 2),
        (1000.0, 4),
        (95_000.0, 4),
    ] as [(Double, Int)])
    func pricePrecision(priceUsd: Double, expected: Int) {
        #expect(AssetPrecision.pricePrecision(fromUsdPrice: priceUsd) == expected)
    }

    @Test
    func prefersBackendField() {
        #expect(AssetPrecision.amountPrecision(precision: 4, priceUsd: 0.0001) == 4)
    }

    @Test
    func derivesFromPriceWhenPrecisionAbsent() {
        #expect(AssetPrecision.amountPrecision(precision: nil, priceUsd: 95_000) == 4)
        #expect(AssetPrecision.amountPrecision(precision: nil, priceUsd: 2) == 2)
        #expect(AssetPrecision.amountPrecision(precision: nil, priceUsd: 0.0001) == 0)
    }

    @Test
    func fallsBackToTwoWhenPriceMissing() {
        #expect(AssetPrecision.amountPrecision(precision: nil, priceUsd: nil) == 2)
        #expect(AssetPrecision.amountPrecision(precision: nil, priceUsd: 0) == 2)
    }
}
