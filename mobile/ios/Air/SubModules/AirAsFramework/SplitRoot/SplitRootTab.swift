import UIKit
import WalletContext

enum SplitRootTab: CaseIterable, Hashable {
    case home
    case agent
    case explore
    case settings

    static var visibleTabs: [SplitRootTab] {
        allCases
    }
    
    var title: String {
        switch self {
        case .home: lang("Wallet")
        case .agent: lang("Agent")
        case .explore: lang("Explore")
        case .settings: lang("Settings")
        }
    }
    
    var icon: UIImage {
        switch self {
        case .home: UIImage.airBundle("SidebarWallet")
        case .agent: UIImage.airBundle("SidebarAgent")
        case .explore: UIImage.airBundle("SidebarExplore")
        case .settings: UIImage.airBundle("SidebarSettings")
        }
    }
}
