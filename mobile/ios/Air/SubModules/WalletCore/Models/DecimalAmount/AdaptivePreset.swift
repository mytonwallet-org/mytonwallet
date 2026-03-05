
import WalletContext

public enum AdaptivePreset<Backing: DecimalBackingType>: Codable {
    /// Default token display.
    case defaultAdaptive
    /// Compact token display. Used for swaps.
    case compact
    /// Displays 2 fiat decimals for fiat currencies, even for large values. Used on card.
    case baseCurrencyEquivalent
    /// Similar to `baseCurrencyEquivalent` but shortened for large values with K/M format (as is for less than 1000, then 1.5K, 9.2K, 123K, 999.1K, 1M, 2.5M etc)
    case baseCurrencyEquivalentShortened
    /// Hide decimals for large amounts. Used for widgets.
    case baseCurrencyPrice
    /// Used on chart hover.
    case baseCurrencyHighPrecision
    
    func resolve(_ decimalAmount: DecimalAmount<Backing>) -> Int? {
        let v = abs(decimalAmount.doubleValue)
        let decimals = decimalAmount.decimals
        switch self {
        case .defaultAdaptive:
            return tokenDecimals(for: abs(decimalAmount.amount), tokenDecimals: decimals)

        case .compact:
            let resolved = if v < 0.00_00_05 {
                min(decimals, 8)
            } else if v < 0.00_05 {
                min(decimals, 6)
            } else if v < 0.05 {
                min(decimals, 4)
            } else if v < 50 {
                min(decimals, 2)
            } else {
                0
            }
            return resolved

        case .baseCurrencyEquivalent, .baseCurrencyEquivalentShortened:
            return tokenDecimals(for: abs(decimalAmount.amount), tokenDecimals: decimals)
            
        case .baseCurrencyPrice:
            let resolved = if v < 0.00_00_05 {
                min(decimals, 8)
            } else if v < 0.00_05 {
                min(decimals, 6)
            } else if v < 0.05 {
                min(decimals, 4)
            } else if v < 10_000 {
                min(decimals, 2)
            } else {
                0
            }
            return resolved

        case .baseCurrencyHighPrecision:
            return tokenDecimals(for: abs(decimalAmount.amount), tokenDecimals: decimals, minimumSignificantDigits: 4)
        }
    }
}
