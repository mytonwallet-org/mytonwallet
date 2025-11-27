//
//  UpdateAccount.swift
//  MyTonWalletAir
//
//  Created by nikstar on 27.11.2025.
//

import Foundation

//accountId: string;
//chain: ApiChain;
//address?: string;
///** `false` means that the account has no domain; `undefined` means that the domain has not changed */
//domain?: string | false;
//isMultisig?: boolean;

extension ApiUpdate {
    
    public struct UpdateAccount: Equatable, Hashable, Decodable, Sendable {
        public var type = "updateAccount"
        public var accountId: String
        public var chain: ApiChain
        public var address: String?
        public var domain: Domain
        public var isMultisig: Bool?

        public enum Domain: Equatable, Hashable, Decodable, Sendable {
            case unchanged
            case changed(String)
            case removed

            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let value = try? container.decode(String.self) {
                    self = .changed(value)
                } else if (try? container.decode(Bool.self)) == false {
                    self = .removed
                } else {
                    self = .unchanged
                }
            }
        }

        private enum CodingKeys: CodingKey {
            case type
            case accountId
            case chain
            case address
            case domain
            case isMultisig
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.type = try container.decode(String.self, forKey: .type)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.chain = try container.decode(ApiChain.self, forKey: .chain)
            self.address = try container.decodeIfPresent(String.self, forKey: .address)
            self.domain = try container.decodeIfPresent(Domain.self, forKey: .domain) ?? .unchanged
            self.isMultisig = try container.decodeIfPresent(Bool.self, forKey: .isMultisig)
        }
    }
}
