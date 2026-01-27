//
//  MFee.swift
//  MyTonWalletAir
//
//  Created by Sina on 12/22/24.
//

import WalletContext


public struct MFee: Equatable, Hashable, Codable, Sendable {
    
    public var precision: MFee.FeePrecision
    public var terms: MFee.FeeTerms
    /** The sum of `terms` measured in the native token */
    public var nativeSum: BigInt?
    
    public struct FeeTerms: Equatable, Hashable, Codable, Sendable {
        /** The fee part paid in the transferred token */
        let token: BigInt?

        /** The fee part paid in the chain's native token */
        let native: BigInt?

        /**
         * The fee part paid in stars.
         * The BigInt assumes the same number of decimal places as the transferred token.
         */
        let stars: BigInt?
        
        public init(token: BigInt?, native: BigInt?, stars: BigInt?) {
            self.token = token
            self.native = native
            self.stars = stars
        }
    }

    public enum FeePrecision: String, Codable, Sendable {
        case exact = "exact"
        case approximate = "approximate"
        case lessThan = "lessThan"
        
        var prefix: String {
            switch self {
            case .exact:
                return ""
            case .approximate:
                return "~"
            case .lessThan:
                return "< "
            }
        }
    }

    public init(precision: MFee.FeePrecision, terms: MFee.FeeTerms, nativeSum: BigInt?) {
        self.precision = precision
        self.terms = terms
        self.nativeSum = nativeSum
    }
    
    public func toString(
        token: ApiToken,
        nativeToken: ApiToken
    ) -> String {
        var result = ""
        if let native = terms.native, native > 0 {
            let nativeAmount = TokenAmount(native, nativeToken)
            result += nativeAmount.formatted(.defaultAdaptive)
        }
        if let tokenAmount = terms.token, tokenAmount > 0 {
            if !result.isEmpty {
                result += " + "
            }
            let tokenAmount = TokenAmount(tokenAmount, token)
            result += tokenAmount.formatted(.defaultAdaptive)
        }
        if let stars = terms.stars, stars > 0 {
            if !result.isEmpty {
                result += " + "
            }
            let starsAmount = AnyDecimalAmount(stars, decimals: 0, symbol: "⭐️", forceCurrencyToRight: true)
            result += starsAmount.formatted(.none)
        }
        if result.isEmpty {
            let zero = AnyDecimalAmount(0, decimals: 0, symbol: nativeToken.symbol, forceCurrencyToRight: true)
            result += zero.formatted(.none)
        }
        return precision.prefix + result
    }
}
