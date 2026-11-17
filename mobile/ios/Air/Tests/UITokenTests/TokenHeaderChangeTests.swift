import SwiftUI
import Testing
import WalletContext
import WalletCore
import WalletResources
@testable import UIToken

@MainActor
@Suite("Token Header Change")
struct TokenHeaderChangeTests {
    @Test(arguments: [MBaseCurrency.USD, .BTC, .TON], [-1.0, 1.0])
    func `change below currency precision shows only the signed percentage`(currency: MBaseCurrency, direction: Double) {
        let change = BaseCurrencyAmount.fromDouble(direction * 0.3 / pow(10, Double(currency.decimals)), currency)
        let percent = direction * 0.0124
        let expectedPercent = "\(direction < 0 ? "-" : "+")\(signSpace)1.24%"

        #expect(change.amount == 0)
        let formatted = formatTokenHeaderChange(change, percent: percent)
        #expect(formatted.text == expectedPercent)
        #expect(formatted.accessibilityLabel == lang("Daily P&L") + ": " + expectedPercent)
    }

    @Test
    func `exact zero has no sign or monetary change`() {
        let formatted = formatTokenHeaderChange(BaseCurrencyAmount(0, .USD), percent: 0)

        #expect(formatted.text == "0.0%")
        #expect(formatted.accessibilityLabel == lang("Daily P&L") + ": 0.0%")
    }

    @Test(arguments: [
        (MBaseCurrency.USD, 1, "$0.000001"),
        (.BTC, 1, "0.00000001 BTC"),
        (.TON, 1, "0.000000001 GRAM"),
        (.USD, 12_340_000, "$12.34"),
    ], [-1, 1])
    func `representable change keeps amount and percentage`(currencyAndAmount: (MBaseCurrency, Int, String), direction: Int) {
        let (currency, magnitude, expectedAmount) = currencyAndAmount
        let change = BaseCurrencyAmount(BigInt(direction * magnitude), currency)
        let formatted = formatTokenHeaderChange(change, percent: Double(direction) * 0.0124)
        let sign = direction < 0 ? "-" : "+"
        let signedAmount = "\(sign)\(signSpace)\(expectedAmount)"
        let signedPercent = "\(sign)\(signSpace)1.24%"
        let visiblePercent = direction < 0 ? signedPercent : "1.24%"

        #expect(formatted.text == "\(signedAmount) (\(visiblePercent))")
        #expect(formatted.accessibilityLabel == lang("Daily P&L") + ": \(signedAmount), \(signedPercent)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `render zero and nonzero daily changes`(colorScheme: ColorScheme) throws {
        _ = WalletResourcesBundle.bundle.load()
        let renderer = ImageRenderer(content: VStack(alignment: .leading, spacing: 24) {
            renderRow(title: "Tiny loss", change: .fromDouble(-0.0000003, .USD), percent: -0.0124)
            renderRow(title: "Tiny gain", change: .fromDouble(0.0000003, .USD), percent: 0.0124)
            renderRow(title: "No change", change: BaseCurrencyAmount(0, .USD), percent: 0)
            renderRow(title: "Representable loss", change: BaseCurrencyAmount(-1, .USD), percent: -0.0124)
            renderRow(title: "Ordinary gain", change: BaseCurrencyAmount(12_340_000, .USD), percent: 0.0124)
        }
        .padding(24)
        .frame(width: 390, alignment: .leading)
        .background(Color.air.background)
        .environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        let image = try #require(renderer.uiImage?.pngData())
        Attachment.record(image, named: "token-header-change-\(colorScheme).png")
    }

    private func renderRow(title: String, change: BaseCurrencyAmount, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.air.secondaryLabel)
            TokenHeaderEquivalentView(
                amount: BaseCurrencyAmount(24, .USD),
                change: change,
                percent: percent,
                expansionProgress: 1
            )
        }
    }
}
