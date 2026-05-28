//
//  ApiChain.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/16/24.
//

import UIKit
import WalletContext

public let FALLBACK_CHAIN: ApiChain = .ton

@dynamicMemberLookup
public enum ApiChain: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case ton = "ton"
    case tron = "tron"
    
    public var config: ChainConfig {
        getChainConfig(chain: self)
    }
    
    public subscript<V>(dynamicMember keyPath: KeyPath<ChainConfig, V>) -> V {
        config[keyPath: keyPath]
    }
}

public func getChainBySlug(_ tokenSlug: String) -> ApiChain? {
    let items = tokenSlug.split(separator: "-")
    if items.count == 1 {
        return getChainByNativeSlug(tokenSlug)
    }
    if items.count == 2 {
        return ApiChain(rawValue: String(items[0]))
    }
    return nil
}

public func getChainByNativeSlug(_ tokenSlug: String) -> ApiChain? {
    switch tokenSlug {
    case ApiChain.ton.nativeToken.slug: .ton
    case ApiChain.tron.nativeToken.slug: .tron
    default: nil
    }
}

// MARK: - ChainConfig extensions

public extension ApiChain {
    var isOnchainSwapSupported: Bool {
        switch self {
        case .ton: true
        case .tron: false
        }
    }
    
    var isSendToSelfAllowed: Bool {
        switch self {
        case .ton: true
        case .tron: false
        }
    }
}

// MARK: - Helper methods

public extension ApiChain {
    var image: UIImage {
        UIImage(named: "chain_\(rawValue)", in: AirBundle, compatibleWith: nil)!
    }

    func isValidAddressOrDomain(_ addressOrDomain: String) -> Bool {
        return config.addressRegex.matches(addressOrDomain) || isValidDomain(addressOrDomain)
    }

    private func isValidDomain(_ domain: String) -> Bool {
        return config.isDnsSupported && DNSHelpers.isDnsDomain(domain)
    }
}

// MARK: - Gas

public extension ApiChain {
    struct Gas {
        public let maxSwap: BigInt?
        public let maxTransfer: BigInt
        public let maxTransferToken: BigInt
    }
    
    var gas: Gas {
        switch self {
        case .ton:
            return Gas(
                maxSwap: 400_000_000,
                maxTransfer: 15_000_000,
                maxTransferToken: 60_000_000,
            )
        case .tron:
            return Gas(
                maxSwap: nil,
                maxTransfer: 1_000_000,
                maxTransferToken: 30_000_000,
            )
        }
    }
}
