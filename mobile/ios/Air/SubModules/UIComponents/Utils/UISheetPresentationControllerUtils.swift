import UIKit

public extension UISheetPresentationController {
    func configureFullScreen(_ isEnabled: Bool) {
        setValue(isEnabled, forKey: "wantsFullScreen")
    }
    
    func configureAllowsInteractiveDismiss(_ isAllowed: Bool) {
        setValue(isAllowed, forKey: "allowsInteractiveDismissWhenFullScreen")
    }
}
