//
//  InteractivePopRecognizer.swift
//  UIComponents
//
//  Created by Sina on 5/14/23.
//

import UIKit

public class InteractivePopRecognizer: NSObject, UIGestureRecognizerDelegate {

    weak var navigationController: UINavigationController?

    public init(controller: UINavigationController) {
        self.navigationController = controller
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return navigationController?.viewControllers.count ?? 0 > 1
    }

    // This is necessary because without it, subviews of your top controller can
    // cancel out your gesture recognizer on the edge.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
