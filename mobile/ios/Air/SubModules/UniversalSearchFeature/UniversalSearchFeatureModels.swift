import Foundation
import UIUniversalSearch
import WalletCore
import WalletCoreTypes

public enum UniversalSearchFeatureRoute: Sendable {
    case walletAction(UniversalSearchWalletAction)
    case settings(AppSettingsSection)
    case token(accountID: String, token: ApiToken)
    case collectible(accountID: String, nft: ApiNft)
    case collection(accountID: String, collection: NftCollection)
    case application(url: URL, title: String, opensExternally: Bool)
    case wallet(MAccount)
    case externalWallet(
        network: ApiNetwork,
        addressOrDomainByChain: [String: String]
    )
    case agent(query: String?)
    case website(url: URL, title: String?)
    case google(query: String)
}

public enum UniversalSearchWalletAction: String, CaseIterable, Sendable {
    case fund
    case send
    case swap
    case earn
    case buyWithCard = "buy-with-card"
    case sell
    case scan
}

@MainActor
public struct UniversalSearchResolvedResult {
    public let item: UniversalSearchItem
    public let route: UniversalSearchFeatureRoute

    public init(item: UniversalSearchItem, route: UniversalSearchFeatureRoute) {
        self.item = item
        self.route = route
    }
}

@MainActor
public struct UniversalSearchPresentation {
    public let sections: [UniversalSearchSection]
    public let preselectedItemID: String?
    public let routesByItemID: [String: UniversalSearchFeatureRoute]

    public init(
        sections: [UniversalSearchSection],
        preselectedItemID: String?,
        routesByItemID: [String: UniversalSearchFeatureRoute]
    ) {
        self.sections = sections
        self.preselectedItemID = preselectedItemID
        self.routesByItemID = routesByItemID
    }

    public static let empty = UniversalSearchPresentation(
        sections: [],
        preselectedItemID: nil,
        routesByItemID: [:]
    )
}
