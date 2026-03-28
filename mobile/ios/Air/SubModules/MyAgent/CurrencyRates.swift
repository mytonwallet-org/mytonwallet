import Foundation

/// Stores currency exchange rates (relative to USD) injected by the caller.
///
/// Rates come from `https://api.mytonwallet.org/currency-rates` where USD = 1.
/// The library does NOT fetch rates — the caller provides them via `updateRates(_:)`.
///
/// ```swift
/// let rates = CurrencyRates()
/// await rates.updateRates(["USD": 1, "EUR": 0.867, "TON": ...])
/// let eurPrice = await rates.convert(usdAmount: 3.5, to: "EUR") // 3.0345
/// ```
public actor CurrencyRates {

    private var rates: [String: Double] = [:]

    public init() {}

    /// Update rates. Keys should be uppercase currency codes (e.g. "EUR", "CNY").
    /// Values are multipliers relative to USD (USD = 1).
    public func updateRates(_ newRates: [String: Double]) {
        self.rates = newRates
    }

    /// Convert a USD amount to the target currency.
    /// Returns nil if the target currency has no known rate.
    public func convert(usdAmount: Double, to currency: String) -> Double? {
        guard let rate = rates[currency.uppercased()] else { return nil }
        return usdAmount * rate
    }

    /// Returns the symbol/code to display for a currency (e.g. "$", "€", "¥", or the code itself).
    public func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "CNY", "JPY": return "¥"
        case "RUB": return "₽"
        default: return code.uppercased()
        }
    }
}
