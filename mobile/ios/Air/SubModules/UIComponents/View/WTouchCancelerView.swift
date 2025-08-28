//
//  WTouchCancelerView.swift
//  UIComponents
//
//  Created by Sina on 6/25/24.
//

import UIKit

public class WTouchCancelerView: UIView {
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        self.next?.touchesCancelled(touches, with: event)
    }
}
