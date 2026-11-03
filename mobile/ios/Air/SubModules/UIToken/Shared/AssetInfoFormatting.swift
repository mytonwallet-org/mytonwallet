import Foundation
import WalletContext
import WalletCore

@MainActor
enum AssetInfoFormatting {
    static func compactCurrency(_ value: Double, currency: MBaseCurrency) -> String {
        let number = compactNumber(value)
        return currency.sign.count == 1 && currency.sign != "₽"
            ? "\(currency.sign)\(number)"
            : "\(number) \(currency.sign)"
    }

    static func compactNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String) = if magnitude >= 1_000_000_000 {
            (value / 1_000_000_000, "B")
        } else if magnitude >= 1_000_000 {
            (value / 1_000_000, "M")
        } else if magnitude >= 1_000 {
            (value / 1_000, "K")
        } else {
            (value, "")
        }

        return scaled.formatted(
            .number
                .locale(LocalizationSupport.shared.locale)
                .precision(.fractionLength(0...2))
        ) + suffix
    }
}
