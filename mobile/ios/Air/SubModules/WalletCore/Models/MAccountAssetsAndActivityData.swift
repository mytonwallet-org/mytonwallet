import Foundation
import GRDB
import WalletContext

public struct MAccountAssetsAndActivityData: Equatable, Hashable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public let accountId: String
    public var alwaysHiddenSlugs: [String]
    public var importedSlugs: [String]
    public var pinnedSlugs: [String]?
    public var didAutoPinStaking: Bool

    public init(
        accountId: String,
        alwaysHiddenSlugs: [String],
        importedSlugs: [String],
        pinnedSlugs: [String]?,
        didAutoPinStaking: Bool
    ) {
        self.accountId = accountId
        self.alwaysHiddenSlugs = alwaysHiddenSlugs
        self.importedSlugs = importedSlugs
        self.pinnedSlugs = pinnedSlugs
        self.didAutoPinStaking = didAutoPinStaking
    }

    public init(accountId: String, data: MAssetsAndActivityData, didAutoPinStaking: Bool = false) {
        let dict = data.toDictionary
        self.init(
            accountId: accountId,
            alwaysHiddenSlugs: dict["alwaysHiddenSlugs"] as? [String] ?? [],
            importedSlugs: dict["importedSlugs"] as? [String] ?? [],
            pinnedSlugs: dict["pinnedSlugs"] as? [String],
            didAutoPinStaking: didAutoPinStaking
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
        return MAssetsAndActivityData(dictionary: dict)
    }

    public var hasData: Bool {
        !alwaysHiddenSlugs.isEmpty
            || !importedSlugs.isEmpty
            || (pinnedSlugs?.isEmpty == false)
    }
}
