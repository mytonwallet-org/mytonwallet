//
//  MWalletVersionsData.swift
//  WalletCore
//
//  Created by Sina on 7/14/24.
//

import Foundation
import WalletContext

public struct MWalletVersionsData {
    
    public struct Version {
        public let address: String
        public let balance: BigInt
        public let isInitialized: Bool
        public let version: String

        public init(dictionary: [String: Any]) {
            self.address = dictionary["address"] as? String ?? ""
            if let balance = (dictionary["balance"] as? String)?.components(separatedBy: "bigint:")[1] {
                self.balance = BigInt(balance) ?? 0
            } else {
                self.balance = 0
            }
            self.isInitialized = dictionary["isInitialized"] as? Bool ?? false
            self.version = dictionary["version"] as? String ?? ""
        }
    }
    
    public let currentVersion: String
    public var versions: [Version]

    public init(dictionary: [String: Any]) {
        self.currentVersion = dictionary["currentVersion"] as? String ?? ""
        if let versions = dictionary["versions"] as? [[String: Any]] {
            self.versions = []
            for version in versions {
                self.versions.append(Version(dictionary: version))
            }
        } else {
            self.versions = []
        }
    }

}
