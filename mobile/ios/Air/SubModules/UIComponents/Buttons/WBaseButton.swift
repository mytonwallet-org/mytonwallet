//
//  WBaseButton.swift
//  UIComponents
//
//  Created by Sina on 4/28/23.
//

import UIKit
import WalletContext

@IBDesignable
public class WBaseButton: UIButton {
    // if `highlightBackgroundColor` is set, the button background will be changed to the new color on highlight
    public var highlightBackgroundColor: UIColor? = nil {
        didSet {
            if !isHighlighted {
                oldBackground = highlightBackgroundColor
            } else {
                backgroundColor = highlightBackgroundColor
            }
        }
    }
    // old background holds background color before highlight state change
    private var oldBackground: UIColor? = nil
    override open var isHighlighted: Bool {
        didSet {
            if oldBackground == nil {
                return
            }
            if isHighlighted != oldValue {
                let switchBackgroundColor = oldBackground
                oldBackground = backgroundColor
                UIView.animate(withDuration: isHighlighted ? 0.1 : 0.5, delay: 0, options: UIView.AnimationOptions.allowUserInteraction) {
                    self.backgroundColor = switchBackgroundColor
                }
            }
        }
    }
}
