
import UIKit

/**
 Returns a new `_UIPortalView` instance
 that replicates the given `view`.
 */
public func makePortalView(of view: UIView) -> UIView? {
    guard let Cls = NSClassFromString(String("weiVlatroPIU_".reversed())) as? UIView.Type else { return nil }
    let portalView = Cls.init()
    portalView.perform(NSSelectorFromString("setSourceView:"), with: view)
    return portalView
}

