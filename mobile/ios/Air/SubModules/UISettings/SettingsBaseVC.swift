import UIComponents
import UIKit

open class SettingsBaseVC: WViewController {
    open override var maxContentWidth: CGFloat? {
        900
    }

    public func popToRootAfterDelay(_ delay: TimeInterval = 0.25) {
        let navigationController = navigationController
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak navigationController] in
            navigationController?.popToRootViewController(animated: false)
        }
    }
}
