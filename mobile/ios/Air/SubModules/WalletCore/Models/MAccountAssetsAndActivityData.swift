import Foundation
import GRDB
import WalletContext

public struct MAccountAssetsAndActivityData: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var alwaysHiddenSlugs: [String]
    public var importedSlugs: [String]
    public var pinnedSlugs: [String]?
    public var didAutoPinStaking: Bool
    public var ownedMtwCardAddresses: [String]
    public var chainDisplayConfiguration: MChainDisplayConfiguration?

    public init(
        accountId: String,
        alwaysHiddenSlugs: [String],
        importedSlugs: [String],
        pinnedSlugs: [String]?,
        didAutoPinStaking: Bool,
        ownedMtwCardAddresses: [String] = [],
        chainDisplayConfiguration: MChainDisplayConfiguration? = nil
    ) {
        self.accountId = accountId
        self.alwaysHiddenSlugs = alwaysHiddenSlugs
        self.importedSlugs = importedSlugs
        self.pinnedSlugs = pinnedSlugs
        self.didAutoPinStaking = didAutoPinStaking
        self.ownedMtwCardAddresses = ownedMtwCardAddresses
        self.chainDisplayConfiguration = chainDisplayConfiguration
    }

    public init(
        accountId: String,
        data: MAssetsAndActivityData,
        didAutoPinStaking: Bool = false,
        ownedMtwCardAddresses: [String] = []
    ) {
        let dict = data.toDictionary
        self.init(
            accountId: accountId,
            alwaysHiddenSlugs: dict["alwaysHiddenSlugs"] as? [String] ?? [],
            importedSlugs: dict["importedSlugs"] as? [String] ?? [],
            pinnedSlugs: dict["pinnedSlugs"] as? [String],
            didAutoPinStaking: didAutoPinStaking,
            ownedMtwCardAddresses: ownedMtwCardAddresses,
            chainDisplayConfiguration: dict["chainDisplayConfiguration"] as? MChainDisplayConfiguration
        )
    }

    public static let databaseTableName: String = "account_assets_and_activity_data"
}

extension MAccountAssetsAndActivityData {
    public var data: MAssetsAndActivityData {
        var dict: [String: Any] = [
            "alwaysHiddenSlugs": alwaysHiddenSlugs,
            "importedSlugs": importedSlugs,
        ]
        if let pinnedSlugs {
            dict["pinnedSlugs"] = pinnedSlugs
        }
        if let chainDisplayConfiguration {
            dict["chainDisplayConfiguration"] = chainDisplayConfiguration
        }
        return MAssetsAndActivityData(dictionary: dict)
    }

    public var hasData: Bool {
        !alwaysHiddenSlugs.isEmpty
            || !importedSlugs.isEmpty
            || (pinnedSlugs?.isEmpty == false)
            || !ownedMtwCardAddresses.isEmpty
            || chainDisplayConfiguration != nil
    }
}
