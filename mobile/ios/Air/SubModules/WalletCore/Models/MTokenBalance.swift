//
//  MTokenBalance.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import WalletContext

public struct MTokenBalance: Equatable, Hashable, Sendable {
    public static func == (lhs: MTokenBalance, rhs: MTokenBalance) -> Bool {
        lhs.tokenSlug == rhs.tokenSlug && lhs.isStaking == rhs.isStaking
    }

    public let tokenSlug: String
    public let balance: BigInt
    public let isStaking: Bool
    
    public var token: ApiToken? { TokenStore.tokens[tokenSlug] }

    public var tokenPrice: Double?
    public let tokenPriceChange: Double?
    public let toBaseCurrency: Double?
    public let toBaseCurrency24h: Double?
    public let toUsd: Double?
    
    fileprivate let priority: Int
    
    public init(tokenSlug: String, balance: BigInt, isStaking: Bool) {
        self.tokenSlug = tokenSlug
        self.balance = balance
        self.isStaking = isStaking
        if let token = TokenStore.getToken(slug: tokenSlug), let price = token.price, let priceUsd = token.priceUsd {
            self.tokenPrice = price
            self.tokenPriceChange = token.percentChange24h
            let amountDouble = balance.doubleAbsRepresentation(decimals: token.decimals)
            self.toBaseCurrency = amountDouble * price
            let priceYesterday = price * 100 / (100 + (token.percentChange24h ?? 0))
            self.toBaseCurrency24h = amountDouble * priceYesterday
            self.toUsd = amountDouble * priceUsd
        } else {
            self.tokenPrice = nil
            self.tokenPriceChange = nil
            self.toBaseCurrency = nil
            self.toBaseCurrency24h = nil
            self.toUsd = nil
        }
        self.priority = getPriority(tokenSlug: tokenSlug)
    }
    
    init(dictionary: [String: Any]) {
        tokenSlug = (dictionary["token"] as? [String: Any])?["slug"] as? String ?? ""
        isStaking = dictionary["isStaking"] as? Bool ?? false
        if let amountValue = (dictionary["balance"] as? String)?.components(separatedBy: "bigint:")[1] {
            self.balance = BigInt(amountValue) ?? 0
        } else {
            self.balance = 0
        }
        if let token = TokenStore.tokens[tokenSlug == STAKED_TON_SLUG ? "toncoin" : tokenSlug], let price = token.price {
            self.tokenPrice = price
            self.tokenPriceChange = token.percentChange24h
            let amountDouble = balance.doubleAbsRepresentation(decimals: token.decimals)
            self.toBaseCurrency = amountDouble * price
            let priceYesterday = price / (1 + (token.percentChange24h ?? 0) / 100)
            self.toBaseCurrency24h = amountDouble * priceYesterday
            self.toUsd = amountDouble * (token.priceUsd ?? 0)
        } else {
            self.tokenPrice = nil
            self.tokenPriceChange = nil
            self.toBaseCurrency = nil
            self.toBaseCurrency24h = nil
            self.toUsd = nil
        }
        self.priority = getPriority(tokenSlug: tokenSlug)
    }
}


extension MTokenBalance: Comparable {

    
    public static func < (lhs: MTokenBalance, rhs: MTokenBalance) -> Bool {
        
        if lhs.isStaking != rhs.isStaking {
            return lhs.isStaking
        }
        
        if lhs.isStaking && rhs.isStaking {
            return getStakingPriority(tokenSlug: lhs.tokenSlug) < getStakingPriority(tokenSlug: rhs.tokenSlug)
        }
        
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        
        let lv = lhs.toBaseCurrency ?? 0
        let rv = rhs.toBaseCurrency ?? 0
        if lv != rv { return lv > rv }
        
        if lhs.balance != rhs.balance {
            return lhs.balance > rhs.balance
        }
        
        if let token1 = lhs.token, let token2 = rhs.token {
            if token1.name != token2.name {
                return token1.name < token2.name
            }
            if token1.chain != token2.chain {
                return token1.chain > token2.chain
            }
        }
        
        return lhs.tokenSlug < rhs.tokenSlug
    }
}


extension MTokenBalance: CustomStringConvertible {
    public var description: String {
        "MTokenBalance<\(tokenSlug) = \(balance) (price=\(tokenPrice ?? -1) curr=\(toBaseCurrency ?? -1))>"
    }
}
