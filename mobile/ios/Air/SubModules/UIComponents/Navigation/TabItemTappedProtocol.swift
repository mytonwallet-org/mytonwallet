
import UIKit
import WalletContext

public protocol TabItemTappedProtocol {
    @MainActor func tabItemTapped() -> Bool
}


extension UINavigationController: TabItemTappedProtocol {
    
    public func tabItemTapped() -> Bool {
        guard let vc = viewControllers.last else { return true }
        let count = viewControllers.count
        
        if let vc = vc as? TabItemTappedProtocol {
            let handled = vc.tabItemTapped()
            if !handled && count > 1 {
                popViewController(animated: true)
            }
        } else if let vc = vc as? WViewController {
            vc.scrollToTop(animated: true)
        } else if let scrollView = vc.view as? UIScrollView {
            if scrollView.contentOffset == .zero && count > 1 {
                popViewController(animated: true)
            } else {
                scrollView.setContentOffset(.zero, animated: true)
            }
        }
        return true
    }
}
