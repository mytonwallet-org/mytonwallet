//
//  MAccount.swift
//  WalletCore
//
//  Created by Sina on 3/20/24.
//

import UIKit
import WalletContext
import GRDB

public let DUMMY_ACCOUNT = MAccount(id: "dummy-mainnet", title: " ", type: .view, addressByChain: ["ton": " "], ledger: nil)

// see src/global/types.ts > Account

public struct MAccount: Equatable, Hashable, Sendable, Codable {
    
    public let id: String
    
    public var type: AccountType
    public var title: String?
    public var addressByChain: [String: String] // keys have to strings because encoding won't work with ApiChain as keys
    public var ledger: Ledger?
    
    init(id: String, title: String?, type: AccountType, addressByChain: [String : String], ledger: Ledger?) {
        self.id = id
        self.title = title
        self.type = type
        self.addressByChain = addressByChain
        self.ledger = ledger
    }
    
    public var tonAddress: String? {
        addressByChain[ApiChain.ton.rawValue]
    }
    
    public var tronAddress: String? {
        addressByChain[ApiChain.tron.rawValue]
    }
    
    public var firstAddress: String? {
        tonAddress ?? addressByChain.first?.value
    }
    
    public func supports(chain: String?) -> Bool {
        if let chain {
            return addressByChain[chain] != nil
        }
        return false
    }
    
    public var isMultichain: Bool {
        addressByChain.keys.count > 1
    }
    
    public var isHardware: Bool {
        type == .hardware
    }
    
    public var isView: Bool {
        type == .view
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
}

extension MAccount: FetchableRecord, PersistableRecord {
    static public var databaseTableName: String = "accounts"
}

public extension MAccount {
    static let sampleMnemonic = MAccount(
        id: "sample-mainnet",
        title: "Sample Wallet",
        type: .mnemonic,
        addressByChain: ["ton":"748327432974324328094328903428"],
        ledger: nil
    )
}
