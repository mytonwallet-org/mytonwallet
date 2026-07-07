import Perception
import WalletContext

@Perceptible
@MainActor
final class SplitRootViewModel {

    var selectedTab: AppTabId = .wallet
    var onCurrentTabTap: (AppTabId) -> Void = { _ in }

    func onTabTap(_ tab: AppTabId) {
        if tab != selectedTab {
            selectedTab = tab
        } else {
            onCurrentTabTap(tab)
        }
    }
}
