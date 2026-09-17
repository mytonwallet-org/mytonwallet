//
//  AccountChain.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.12.2025.
//

import WalletContext
import WalletCoreTypes

public struct AccountChain: Equatable, Hashable, Sendable, Codable {
    public var address: String
    public var domain: String?
    public var isMultisig: Bool?
    public var derivation: ApiDerivation?
    public var mfa: AccountMfa?
    
    public init(address: String, domain: String? = nil, isMultisig: Bool? = nil, derivation: ApiDerivation? = nil, mfa: AccountMfa? = nil) {
        self.address = address
        self.domain = domain
        self.isMultisig = isMultisig
        self.derivation = derivation
        self.mfa = mfa
    }
}

extension AccountChain {
    public var preferredCopyString: String {
        domain ?? address
    }

    public func preferredCopyString(for chain: ApiChain) -> String {
        domain ?? chain.normalizeAddress(address)
    }
    
    func matches(_ searchString: Regex<Substring>) -> Bool {
        if address.contains(searchString) { return true }
        if let domain, domain.contains(searchString) { return true }
        return false
    }
}
