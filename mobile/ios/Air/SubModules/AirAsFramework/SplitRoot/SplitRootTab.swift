import UIKit
import WalletContext

enum SplitRootTab: CaseIterable, Hashable {
    case home
    case explore
    case settings
    
    var title: String {
        switch self {
        case .home: lang("Wallet")
        case .explore: lang("Explore")
        case .settings: lang("Settings")
        }
    }
    
    var icon: UIImage {
        switch self {
        case .home: UIImage.airBundle("SidebarWallet")
        case .explore: UIImage.airBundle("SidebarExplore")
        case .settings: UIImage.airBundle("SidebarSettings")
        }
    }
}

