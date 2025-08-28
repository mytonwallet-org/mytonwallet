//
//  MAccountBalanceData.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/24/24.
//

import Foundation
import OrderedCollections

public struct MAccountBalanceData {
    public let walletTokensDict: OrderedDictionary<String, MTokenBalance>
    public let walletStakedDict: OrderedDictionary<String, MTokenBalance>
    public let totalBalance: Double
    public let totalBalanceYesterday: Double
    
    public var walletTokens: [MTokenBalance] { Array(walletTokensDict.values) }
    public var walletStaked: [MTokenBalance] { Array(walletStakedDict.values) }
    
    init(walletTokens: [MTokenBalance], walletStaked: [MTokenBalance], totalBalance: Double, totalBalanceYesterday: Double) {
        self.walletTokensDict = walletTokens.orderedDictionaryByKey(\.tokenSlug)
        self.walletStakedDict = walletStaked.orderedDictionaryByKey(\.tokenSlug)
        self.totalBalance = totalBalance
        self.totalBalanceYesterday = totalBalanceYesterday
    }
}

extension MAccountBalanceData: CustomStringConvertible {
    public var description: String {
        let first = walletTokens.prefix(5).map { $0.tokenSlug }.joined(separator: ",")
        return "MAccountBalanceData<\(totalBalance.rounded(decimals: 2)) tokens#=\(walletTokens.count) \(first)>"
    }
}
