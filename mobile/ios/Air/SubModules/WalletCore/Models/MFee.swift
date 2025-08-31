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
            result += formatBigIntText(native,
                                      currency: nativeToken.symbol,
                                      tokenDecimals: nativeToken.decimals,
                                      decimalsCount: tokenDecimals(for: native, tokenDecimals: nativeToken.decimals))
        }
        if let tokenAmount = terms.token, tokenAmount > 0 {
            if !result.isEmpty {
                result += " + "
            }
            result += formatBigIntText(tokenAmount,
                                      currency: token.symbol,
                                      tokenDecimals: token.decimals,
                                      decimalsCount: tokenDecimals(for: tokenAmount, tokenDecimals: token.decimals))
        }
        if let stars = terms.stars, stars > 0 {
            if !result.isEmpty {
                result += " + "
            }
            result += formatBigIntText(stars,
                                      currency: "⭐️",
                                      tokenDecimals: 1,
                                      decimalsCount: tokenDecimals(for: stars, tokenDecimals: 1))
        }
        if result.isEmpty {
            result += formatBigIntText(0,
                                      currency: nativeToken.symbol,
                                      tokenDecimals: 0,
                                      decimalsCount: 0)
        }
        return precision.prefix + result
    }
}
