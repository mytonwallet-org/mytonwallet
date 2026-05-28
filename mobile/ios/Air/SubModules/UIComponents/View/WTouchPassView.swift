//
//  WTouchPassView.swift
//  UIComponents
//
//  Created by Sina on 5/26/23.
//

import UIKit

open class WTouchPassView: UIView {
    open var shouldPassTouches: Bool = true
    open var shouldAcceptTouchesOutside: Bool = false
    // pass touch events to the below view
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard shouldPassTouches else {
            return super.hitTest(point, with: event)
        }
        let hitView = super.hitTest(point, with: event)
        if hitView == self {
            return nil
        } else {
            return hitView
        }
    }
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard shouldAcceptTouchesOutside else {
            return super.point(inside: point, with: event)
        }
        for subview in subviews as [UIView] {
            if !subview.isHidden
               && subview.alpha > 0
               && subview.isUserInteractionEnabled
               && subview.point(inside: convert(point, to: subview), with: event) {
                 return true
            }
        }
        return false
    }
}

open class WTouchPassStackView: UIStackView {
    open var shouldAcceptTouchesOutside: Bool = false
    // pass touch events to the below view
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        if hitView == self {
            return nil
        } else {
            return hitView
        }
    }
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard shouldAcceptTouchesOutside else {
            return super.point(inside: point, with: event)
        }
        for subview in subviews as [UIView] {
            if !subview.isHidden
               && subview.alpha > 0
               && subview.isUserInteractionEnabled
               && subview.point(inside: convert(point, to: subview), with: event) {
                 return true
            }
        }
        return false
    }
}
