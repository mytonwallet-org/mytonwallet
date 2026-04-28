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

    static public let databaseTableName: String = "accounts"

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
        guard
            let accountsData = KeychainHelper.getAccounts(),
            let account = accountsData[id]
        else {
            return nil
        }

        let rawByChain = account["byChain"] as? [String: Any]
        let tonDict = rawByChain?[ApiChain.ton.rawValue] as? [String: Any]
        let legacyTonDict = account[ApiChain.ton.rawValue] as? [String: Any]

        return tonDict?["version"] as? String ?? legacyTonDict?["version"] as? String
    }

    public var currentTonWalletVersion: String? {
        if AccountStore.accountId == id {
            return AccountStore.walletVersionsData?.currentVersion.nilIfEmpty ?? version?.nilIfEmpty
        }

        return version?.nilIfEmpty
    }

    public func derivation(chain: ApiChain) -> ApiDerivation? {
        if let derivation = getChainInfo(chain: chain)?.derivation {
            return derivation
        }

        guard
            let accounts = KeychainHelper.getAccounts(),
            let account = accounts[id]
        else {
            return nil
        }

        let rawByChain = account["byChain"] as? [String: Any]
        return parseDerivation(from: rawByChain?[chain.rawValue] as? [String: Any])
            ?? parseDerivation(from: account[chain.rawValue] as? [String: Any])
    }

    private func parseDerivation(from rawChain: [String: Any]?) -> ApiDerivation? {
        guard
            let rawDerivation = rawChain?["derivation"] as? [String: Any],
            let path = rawDerivation["path"] as? String,
            let index = rawDerivation["index"] as? Int
        else {
            return nil
        }

        return ApiDerivation(
            path: path,
            index: index,
            label: rawDerivation["label"] as? String
        )
    }

    public func supportsSubwallets(on chain: ApiChain) -> Bool {
        guard supports(chain: chain), let multiWalletSupport = chain.multiWalletSupport else {
            return false
        }

        if chain == .ton && multiWalletSupport == .version {
            return currentTonWalletVersion == ApiTonWalletVersion.W5.rawValue
        }

        return true
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
        components.queryItems = viewAccountQueryItems
        if network == .testnet {
            components.queryItems?.append(URLQueryItem(name: "testnet", value: "true"))
        }
        return components.url!
    }

    private var viewAccountQueryItems: [URLQueryItem] {
        let evmAddress = collapsedEvmAddress
        var didAddEvm = false

        return orderedChains.compactMap { (chain, info) in
            if let evmAddress, chain.isEvm {
                guard !didAddEvm else { return nil }
                didAddEvm = true
                return URLQueryItem(name: ApiChain.viewAccountEvmParam, value: evmAddress)
            }

            return URLQueryItem(name: chain.rawValue, value: info.preferredCopyString)
        }
    }

    private var collapsedEvmAddress: String? {
        let byChain = Dictionary(uniqueKeysWithValues: orderedChains.map { ($0.0, $0.1.preferredCopyString) })
        let evmAddresses = ApiChain.evmChains.map { byChain[$0] }
        guard let firstAddress = evmAddresses.first.flatMap({ $0 }),
              evmAddresses.allSatisfy({ $0 == firstAddress }) else {
            return nil
        }
        return firstAddress
    }
    
    public var dieselAuthLink: URL? {
        guard let tonAddress = getAddress(chain: .ton) else { return nil }
        return URL(string: "https://t.me/\(BOT_USERNAME)?start=auth-\(tonAddress)")!
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
    accountId.contains("testnet") ? .testnet  : .mainnet
}
