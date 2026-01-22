//
//  AccountChain.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.12.2025.
//

import WalletContext

public struct AccountChain: Equatable, Hashable, Sendable, Codable {
    public var address: String
    public var domain: String?
    public var isMultisig: Bool?
    
    public init(address: String, domain: String? = nil, isMultisig: Bool? = nil) {
        self.address = address
        self.domain = domain
        self.isMultisig = isMultisig
    }
}

extension AccountChain {
    public var preferredCopyString: String {
        domain ?? address
    }
    
    func matches(_ searchString: Regex<Substring>) -> Bool {
        if address.contains(searchString) { return true }
        if let domain, domain.contains(searchString) { return true }
        return false
    }
}
