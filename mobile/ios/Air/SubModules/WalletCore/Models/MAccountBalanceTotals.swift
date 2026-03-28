import Foundation

public struct MAccountBalanceTotals: Equatable, Sendable {
    public let totalBalance: BaseCurrencyAmount
    public let totalBalanceYesterday: BaseCurrencyAmount
    public let totalBalanceUsd: Double
    public let totalBalanceChange: Double?
    public let totalBalanceUsdByChain: [ApiChain: Double]

    init(totalBalance: BaseCurrencyAmount,
         totalBalanceYesterday: BaseCurrencyAmount,
         totalBalanceUsd: Double,
         totalBalanceChange: Double?,
         totalBalanceUsdByChain: [ApiChain: Double]) {
        self.totalBalance = totalBalance
        self.totalBalanceYesterday = totalBalanceYesterday
        self.totalBalanceUsd = totalBalanceUsd
        self.totalBalanceChange = totalBalanceChange
        self.totalBalanceUsdByChain = totalBalanceUsdByChain
    }
}
