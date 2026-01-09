//
//  AccountSource.swift
//  MyTonWalletAir
//
//  Created by nikstar on 12.12.2025.
//

public enum AccountSource: Equatable, Hashable, Codable, Sendable {
    case accountId(String)
    case current
    case constant(MAccount)
    
    public init(_ accountId: String?) {
        if let accountId {
            self = .accountId(accountId)
        } else {
            self = .current
        }
    }
}

extension AccountSource: ExpressibleByStringLiteral, ExpressibleByNilLiteral {
    
    public init(stringLiteral value: String) {
        self = .accountId(value)
    }
    
    public init(nilLiteral: ()) {
        self = .current
    }
}
