import Foundation
import UniversalSearchCore
import WalletContext
import WalletCore

public enum WalletCoreUniversalSearchFactory {
    /// Retains the normalized local corpus across search presentations. Search
    /// is opened and closed frequently; rebuilding thousands of token fields
    /// for every presentation would throw away the main benefit of indexing.
    public static let sharedCoordinator = makeCoordinator()

    public static func makeSources() -> [any UniversalSearchSource] {
        [
            WalletCoreTokenSearchSource(),
            WalletCoreWalletSearchSource(),
            WalletCoreCollectibleSearchSource(),
            WalletCoreConnectedAppSearchSource(),
            WalletCoreExploreAppSearchSource(),
            WalletCoreFuturesSearchSource(),
            WalletCoreFuturesPositionSearchSource(),
            WalletCoreSearchInteractionSource(),
        ]
    }

    public static func makeCoordinator(
        rankingPolicy: UniversalSearchRankingPolicy = .initial
    ) -> UniversalSearchCoordinator {
        UniversalSearchCoordinator(
            sources: makeSources(),
            engine: UniversalSearchEngine(policy: rankingPolicy)
        )
    }

    public static func currentContext(
        localeIdentifier: String = LocalizationSupport.shared.langCode
    ) -> UniversalSearchContext {
        UniversalSearchContext(
            scopeID: AccountStore.accountId,
            network: AccountStore.account?.network.rawValue,
            localeIdentifier: localeIdentifier
        )
    }
}
