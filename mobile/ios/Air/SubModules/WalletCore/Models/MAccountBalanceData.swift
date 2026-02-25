//
//  MAccountBalanceData.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import Foundation
import OrderedCollections

public struct MAccountBalanceData: Equatable, Hashable, Sendable {
    public let walletTokensDict: OrderedDictionary<String, MTokenBalance>
    public let walletStakedDict: OrderedDictionary<String, MTokenBalance>
    
    public let totalBalance: BaseCurrencyAmount
    public let totalBalanceYesterday: BaseCurrencyAmount
    public let totalBalanceUsd: Double
    public let totalBalanceChange: Double?
    
    public var walletTokens: [MTokenBalance] { Array(walletTokensDict.values) }
    public var walletStaked: [MTokenBalance] { Array(walletStakedDict.values) }
    
    init(walletTokens: [MTokenBalance],
         walletStaked: [MTokenBalance],
         totalBalance: BaseCurrencyAmount,
         totalBalanceYesterday: BaseCurrencyAmount,
         totalBalanceUsd: Double,
         totalBalanceChange: Double?) {
        self.walletTokensDict = walletTokens.orderedDictionaryByKey(\.tokenSlug)
        self.walletStakedDict = walletStaked.orderedDictionaryByKey(\.tokenSlug)
        self.totalBalance = totalBalance
        self.totalBalanceYesterday = totalBalanceYesterday
        self.totalBalanceUsd = totalBalanceUsd
        self.totalBalanceChange = totalBalanceChange
    }
}

extension MAccountBalanceData: CustomStringConvertible {
    public var description: String {
        return "MAccountBalanceData(\(totalBalance.formatted(.baseCurrencyEquivalent)) tokens#=\(walletTokens.count))"
    }
}
