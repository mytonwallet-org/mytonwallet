import Perception

@Perceptible
@MainActor
final class SplitRootViewModel {
    
    var selectedTab: SplitRootTab = .home
    var onCurrentTabTap: (SplitRootTab) -> () = { _ in }
    
    func onTabTap(_ tab: SplitRootTab) {
        if tab != selectedTab {
            selectedTab = tab
        } else {
            onCurrentTabTap(tab)
        }
    }
}
