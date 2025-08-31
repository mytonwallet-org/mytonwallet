//
//  ExchangeRateHelpers.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/18/24.
//

import Foundation
import WalletContext

public struct SwapRate {
    public let fromToken: ApiToken
    public let toToken: ApiToken
    public let price: Double
}

public class ExchangeRateHelpers {
    
    private init() {}
    
    static let BTC: Set<String> = ["jWBTC", "oWBTC", "BTC"]
    static let ETH: Set<String> = ["jWETH", "oWETH", "ETH"]
    static let USD: Set<String> = ["jUSDT", "oUSDT", "USDT", "jUSDC", "oUSDC", "USDC", "USD₮"]
    static let FIAT: Set<String> = ["USD", "RUB", "EUR", "CNY"]
    
    static let LARGE_NUMBER = Double(1000)
    
    static func getCurrencyPriority(symbol: String) -> Int {
        if FIAT.contains(symbol) {
            return 6
        }
        if USD.contains(symbol) {
            return 5
        }
        if BTC.contains(symbol) {
            return 4
        }
        if ETH.contains(symbol) {
            return 4
        }
        if symbol == "TON" {
            return 2
        }
        return 1
    }
    
    public static func getSwapRate(fromAmount: Double?,
                                   toAmount: Double?,
                                   fromToken: ApiToken?,
                                   toToken: ApiToken?) -> SwapRate? {
        guard var fromToken, var toToken, let fromAmount, let toAmount, (fromAmount > 0 && toAmount > 0) else {
            return nil
        }
        let fromPriority = getCurrencyPriority(symbol: fromToken.symbol)
        let toPriority = getCurrencyPriority(symbol: toToken.symbol)
        
        let ratio: Double
        if toPriority < fromPriority {
            ratio = fromAmount / toAmount
        } else {
            ratio = toAmount / fromAmount
            (fromToken, toToken) = (toToken, fromToken)
        }

        return SwapRate(fromToken: fromToken, toToken: toToken, price: ratio)
    }
}
