
import UIKit

public func previewSheet(_ vc: UIViewController, embedInNavigationController: Bool  = true) -> UIViewController {
    let host = UIViewController()
    let target = embedInNavigationController ? UINavigationController(rootViewController: vc) : vc
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
        host.present(target, animated: false)
    }
    return host
}

public func previewNc(_ vc: UIViewController) -> UINavigationController {
    UINavigationController(rootViewController: vc)
}
