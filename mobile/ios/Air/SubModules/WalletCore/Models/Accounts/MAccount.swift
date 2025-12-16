//
//  MAccount.swift
//  WalletCore
//
//  Created by Sina on 3/20/24.
//

import UIKit
import WalletContext
import GRDB

public let DUMMY_ACCOUNT = MAccount(id: "dummy-mainnet", title: " ", type: .view, byChain: ["ton": .init(address: " ")])

// see src/global/types.ts > Account

public struct MAccount: Equatable, Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    
    public let id: String
    
    public var title: String?
    public var type: AccountType
    public var byChain: [String: AccountChain] // keys have to be strings because encoding won't work with ApiChain as keys
    public var isTemporary: Bool?

    static public var databaseTableName: String = "accounts"

    public init(id: String, title: String?, type: AccountType, byChain: [String : AccountChain], isTemporary: Bool? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.byChain = byChain
        self.isTemporary = isTemporary
    }
}

extension MAccount {
    public var addressByChain: [String: String] {
        byChain.mapValues(\.address)
    }
    
    public var tonAddress: String? {
        byChain[ApiChain.ton.rawValue]?.address
    }
    
    public var tronAddress: String? {
        byChain[ApiChain.tron.rawValue]?.address
    }
    
    public var firstAddress: String? {
        ApiChain.allCases
            .first(where: { self.supports(chain: $0.rawValue) })
            .flatMap { addressByChain[$0.rawValue] }
    }
    
    public func supports(chain: String?) -> Bool {
        if let chain {
            return byChain[chain] != nil
        }
        return false
    }
    
    public var supportedChains: [ApiChain] {
        ApiChain.allCases.filter { self.supports(chain: $0.rawValue) }
    }
    
    public var isMultichain: Bool {
        byChain.keys.count > 1
    }
    
    public var isHardware: Bool {
        type == .hardware
    }
    
    public var isView: Bool {
        type == .view
    }
    
    public var isTemporaryView: Bool {
        isTemporary == true
    }
    
    public var network: ApiNetwork {
        id.contains("mainnet") ? .mainnet  : .testnet
    }
    
    public var supportsSend: Bool {
        !isView
    }
    
    public var supportsSwap: Bool {
        network == .mainnet && !isHardware && !isView && !ConfigStore.shared.shouldRestrictSwapsAndOnRamp
    }
    
    public var supportsEarn: Bool {
        network == .mainnet && !isView
    }
    
    public var version: String? {
        if let accountsData = KeychainHelper.getAccounts(),
           let tonDict = accountsData[id]?["ton"] as? [String: Any] {
            return tonDict["version"] as? String
        }
        return nil
    }
    
    public var orderedChains: [(ApiChain, AccountChain)] {
        ApiChain.allCases.compactMap { chain  in
            if let info = byChain[chain.rawValue] {
                return (chain, info)
            }
            return nil
        }
    }
    
    public var shareLink: URL {
        var components = URLComponents(string: SHORT_UNIVERSAL_URL + "view")!
        components.queryItems = orderedChains.map { (chain, info) in
            URLQueryItem(name: chain.rawValue, value: info.preferredCopyString)
        }
        return components.url!
    }
}

public extension MAccount {
    static let sampleMnemonic = MAccount(
        id: "sample-mainnet",
        title: "Sample Wallet",
        type: .mnemonic,
        byChain: [
            "ton": .init(address: "748327432974324328094328903428"),
        ]
    )
}
