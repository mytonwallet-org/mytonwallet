
import UIKit

public func sheetPreview(_ vc: UIViewController, inNavigationController: Bool  = true) -> UIViewController {
    let host = UIViewController()
    let target = inNavigationController ? UINavigationController(rootViewController: vc) : vc
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        host.present(target, animated: false)
    }
    return host
}
