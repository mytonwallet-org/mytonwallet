import UIComponents
import UIKit
import WalletContext
import WalletCore

public enum SendNavigation {
    @MainActor
    public static func makeViewController(
        accountContext: AccountContext,
        prefilledValues: SendPrefilledValues,
        isAccountSwitchingAllowed: Bool
    ) throws -> UIViewController {
        let rootViewController: UIViewController
        switch try SendRoute(prefilledValues: prefilledValues) {
        case .nftCompose(let configuration):
            let model = NftSendModel(
                accountContext: accountContext,
                configuration: configuration
            )
            rootViewController = NftSendComposeViewController(
                model: model
            )
        case .nftReview(let configuration):
            let model = NftSendModel(
                accountContext: accountContext,
                configuration: configuration
            )
            rootViewController = NftSendReviewViewController(
                model: model
            )
        case .tokenCompose(let configuration):
            let model = TokenSendModel(
                accountContext: accountContext,
                configuration: configuration,
                isAccountSwitchingAllowed:
                    isAccountSwitchingAllowed
            )
            rootViewController = TokenSendComposeViewController(
                model: model
            )
        case .tokenReview(let configuration):
            let model = TokenSendModel(
                accountContext: accountContext,
                configuration: configuration,
                isAccountSwitchingAllowed:
                    isAccountSwitchingAllowed
            )
            rootViewController = TokenSendReviewViewController(
                model: model
            )
        }
        return WNavigationController(
            rootViewController: rootViewController
        )
    }
}
