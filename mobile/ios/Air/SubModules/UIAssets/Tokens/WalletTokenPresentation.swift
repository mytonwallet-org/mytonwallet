import UIKit
import WalletCore

struct WalletTokenPresentation: Equatable {
    let tokenBalance: MTokenBalance
    // MTokenBalance.token reads the live store; retain its value for change detection.
    let token: ApiToken?
    let badgeContent: BadgeContent?
    let stakingAccessory: StakingAccessoryContent?
    let isMultichain: Bool
    let isPinned: Bool
    let baseCurrency: MBaseCurrency
    let baseCurrencyRate: Double
    let accentColor: UIColor
}
