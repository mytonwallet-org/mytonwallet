//
//  MAccount.swift
//  WalletCore
//
//  Created by Sina on 3/20/24.
//

import UIKit
import WalletContext
import GRDB

public let DUMMY_ACCOUNT = MAccount(id: "dummy-mainnet", title: " ", type: .view, byChain: [.ton: .init(address: " ")])

// see src/global/types.ts > Account

public struct MAccount: Equatable, Hashable, Sendable, Codable, Identifiable, FetchableRecord, PersistableRecord {
    
    public let id: String
    
    public var title: String?
    public var type: AccountType
    public var byChain: [String: AccountChain] // keys have to be strings because encoding won't work with ApiChain as keys
    public var isTemporary: Bool?

    static public var databaseTableName: String = "accounts"

    init(id: String, title: String?, type: AccountType, byChain: [String : AccountChain], isTemporary: Bool? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.byChain = byChain
        self.isTemporary = isTemporary
    }
    
    public init(id: String, title: String?, type: AccountType, byChain: [ApiChain : AccountChain], isTemporary: Bool? = nil) {
        self.init(
            id: id,
            title: title,
            type: type,
            byChain: Dictionary(byChain.map { ($0.rawValue, $1) }, uniquingKeysWith: { first, _ in first }),
            isTemporary: isTemporary,
        )
    }
}

extension MAccount {
    public func getChainInfo(chain: ApiChain?) -> AccountChain? {
        guard let chain else { return nil }
        return byChain[chain.rawValue]
    }

    public func getAddress(chain: ApiChain?) -> String? {
        getChainInfo(chain: chain)?.address
    }
    
    public var firstChain: ApiChain {
        ApiChain.allCases.first(where: { self.supports(chain: $0) }) ?? FALLBACK_CHAIN
    }
    
    public var firstAddress: String {
        getAddress(chain: firstChain) ?? ""
    }
    
    public func supports(chain: ApiChain?) -> Bool {
        guard let chain, chain.isSupported else { return false }
        return byChain[chain.rawValue] != nil
    }
    
    public var supportedChains: Set<ApiChain> {
        Set(byChain.compactMap { chain, _ in ApiChain(rawValue: chain) }.filter(\.isSupported))
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
        getNetwork(accountId: id)
    }
    
    public var supportsSend: Bool {
        !isView
    }
    
    public var supportsBurn: Bool {
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
            if let info = getChainInfo(chain: chain) {
                return (chain, info)
            }
            return nil
        }
    }
    
    public var shareLink: URL {
        var components = URLComponents(string: SHORT_UNIVERSAL_URL + "view/")!
        components.queryItems = orderedChains.map { (chain, info) in
            URLQueryItem(name: chain.rawValue, value: info.preferredCopyString)
        }
        if network == .testnet {
            components.queryItems?.append(URLQueryItem(name: "testnet", value: "true"))
        }
        return components.url!
    }
    
    public var dieselAuthLink: URL? {
        guard let tonAddress = getAddress(chain: .ton) else { return nil }
        return URL(string: "https://t.me/MyTonWalletBot?start=auth-\(tonAddress)")!
    }
    
    public var dreamwalkersLink: String? {
        guard let tonAddress = getAddress(chain: .ton) else { return nil }
        return "https://dreamwalkers.io/ru/mytonwallet/?wallet=\(tonAddress)&give=CARDRUB&take=TON&type=buy"
    }
    
    public var crosschainIdentifyingFromAddress: String? {
        getAddress(chain: .ton)
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

public func getNetwork(accountId: String) -> ApiNetwork {
    accountId.contains("mainnet") ? .mainnet  : .testnet
}
