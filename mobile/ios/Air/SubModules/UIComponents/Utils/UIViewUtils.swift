//
//  UIViewUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 9/16/25.
//

import UIKit

public extension UIView {
    /// Uses spring animation on iOS 26+ for smoother transitions,
    /// and falls back to linear animation on earlier versions to match
    /// UITableView's default behavior.
    static func animateAdaptive(
        duration: TimeInterval,
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        if #available(iOS 26.0, *) {
            UIView.animate(
                withDuration: duration + 0.1,
                delay: 0.005,
                usingSpringWithDamping: 1.0,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction],
                animations: animations,
                completion: completion
            )
        } else {
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [.allowUserInteraction],
                animations: animations,
                completion: completion
            )
        }
    }
    
    var windowFrame: CGRect {
        self.convert(bounds, to: nil)
    }
}
