//
//  ApiChain.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/16/24.
//

import UIKit
import WalletContext

public let availableChains = [ApiChain.ton, ApiChain.tron]
public let availableChainSlugs = availableChains.map({ it in
    it.tokenSlug
})
public func availableChain(slug: String) -> ApiChain? {
    availableChains.first { $0.rawValue == slug }
}

public enum ApiChain: String, Equatable, Hashable, Codable, Comparable, Sendable, CaseIterable {
    public struct Gas {
        public let maxSwap: BigInt?
        public let maxTransfer: BigInt
        public let maxTransferToken: BigInt
    }
    
    case ton = "ton"
    case tron = "tron"
    
    public var title: String {
        switch self {
        case .ton:
            return "The Open Network"
        case .tron:
            return "Tron"
        }
    }
    
    public var symbol: String {
        switch self {
        case .ton:
            return "TON"
        case .tron:
            return "TRON"
        }
    }
    
    public var tokenSlug: String {
        switch self {
        case .ton:
            return "toncoin"
        case .tron:
            return "trx"
        }
    }
    
    public var nativeToken: ApiToken {
        switch self {
        case .ton:
            return TokenStore.tokens["toncoin"] ?? .TONCOIN
        case .tron:
            return TokenStore.tokens["trx"] ?? .TRX
        }
    }
    
    public var gas: Gas {
        switch self {
        case .ton:
            return Gas(
                maxSwap: BigInt(400000000),
                maxTransfer: BigInt(15000000),
                maxTransferToken: BigInt(60000000)
            )
        case .tron:
            return Gas(
                maxSwap: nil,
                maxTransfer: BigInt(1000000),
                maxTransferToken: BigInt(30000000)
            )
        }
    }
    
    public var image: UIImage {
        UIImage(named: "chain_\(rawValue)", in: AirBundle, compatibleWith: nil)!
    }
    
    public var activeWalletAddressOnChain: String? {
        AccountStore.account?.addressByChain[self.rawValue]
    }
    
    public var activeWalletWalletInvoiceUrl: String? {
        if let address = AccountStore.account?.addressByChain[self.rawValue] {
            return invoiceUrl(address: address)
        }
        return nil
    }

    public func invoiceUrl(address: String, comment: String? = nil, amount: BigInt? = nil, jetton: String? = nil) -> String {
        switch self {
        case .ton:
            var arguments = ""
            if let amount = amount?.nilIfZero {
                arguments += arguments.isEmpty ? "?" : "&"
                arguments += "amount=\(amount)"
            }
            if let comment = comment?.nilIfEmpty {
                arguments += arguments.isEmpty ? "?" : "&"
                arguments += "text=\(urlEncodedStringFromString(comment))"
            }
            if let jetton = jetton?.nilIfEmpty {
                arguments += arguments.isEmpty ? "?" : "&"
                arguments += "jetton=\(urlEncodedStringFromString(jetton))"
            }
            return "ton://transfer/\(address)\(arguments)"
        default:
            return address
        }
    }
    
    private func addressMatches(_ address: String) -> Bool {
        switch self {
        case .ton:
            address.firstMatch(of: /^([\-\w_]{48}|0:[\da-hA-H]{64})$/) != nil
        case .tron:
            address.firstMatch(of: /^T[1-9A-HJ-NP-Za-km-z]{33}$/) != nil
        }
    }
    
    private var isDnsSupported: Bool {
        switch self {
        case .ton:
            return true
        case .tron:
            return false
        }
    }
    
    private var isSendToSelfAllowed: Bool {
        switch self {
        case .ton:
            return true
        case .tron:
            return false
        }
    }
    
    public func validate(address: String) -> Bool {
        return !address.isEmpty &&
            (
                addressMatches(address) ||
                (isDnsSupported && DNSHelpers.isDnsDomain(address))
            ) &&
            (
                isSendToSelfAllowed ||
                address != activeWalletAddressOnChain
            )
    }
    
    public static func chainForAddress(_ address: String?) -> ApiChain {
        if let address {
            for chain in ApiChain.allCases {
                if chain.addressMatches(address) {
                    return chain
                }
            }
        }
        return .ton
    }

    public static func < (lhs: ApiChain, rhs: ApiChain) -> Bool {
        return lhs.symbol < rhs.symbol
    }
    
    public var supportsComment: Bool {
        switch self {
        case .ton:
            true
        case .tron:
            false
        }
    }
}
