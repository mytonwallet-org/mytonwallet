import Foundation

/// Matches backend `pricePrecisionFromUsdPrice` / web `src/util/assetPrecision.ts`.
public enum AssetPrecision {
    public static let twoMinUsd = 0.98
    public static let defaultAmountPrecision = 2

    public static func pricePrecision(fromUsdPrice priceUsd: Double) -> Int {
        guard priceUsd.isFinite, priceUsd >= twoMinUsd else { return 0 }
        if priceUsd < 1000 { return 2 }
        return 4
    }

    /// Prefers the backend field; otherwise derives from `priceUsd`, else the historic default of 2.
    public static func amountPrecision(precision: Int?, priceUsd: Double?) -> Int {
        if let precision {
            return precision
        }
        guard let priceUsd, priceUsd.isFinite, priceUsd > 0 else {
            return defaultAmountPrecision
        }
        return pricePrecision(fromUsdPrice: priceUsd)
    }
}
