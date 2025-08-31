//
//  UINavigationControllerUtils.swift
//  UIComponents
//
//  Created by Sina on 4/18/23.
//

import UIKit

public extension UINavigationController {

    func pushViewController(_ viewController: UIViewController,
                                   animated: Bool,
                                   completion: (() -> Void)?) {
        pushViewController(viewController, animated: animated)

        guard animated, let coordinator = transitionCoordinator else {
            DispatchQueue.main.async { completion?() }
            return
        }

        coordinator.animate(alongsideTransition: nil) { _ in completion?() }
    }

    func pushViewController(_ viewController: UIViewController,
                            animated: Bool,
                            clearStack: Bool) {
        pushViewController(viewController, animated: animated) { [weak self] in
            guard let self else {return}
            viewControllers = [viewControllers[viewControllers.count - 1]]
        }
    }
    
    func popViewController(animated: Bool, completion: @escaping () -> Void) {
        popViewController(animated: animated)

        if animated, let coordinator = transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                completion()
            }
        } else {
            completion()
        }
    }
}
