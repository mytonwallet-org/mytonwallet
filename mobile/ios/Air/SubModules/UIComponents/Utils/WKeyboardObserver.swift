//
//  WKeyboardObserver.swift
//  UIComponents
//
//  Created by Sina on 3/16/24.
//

import UIKit

public struct WKeyboardDisplayInfo {
    
    public var animationDuration: Double
    public var animationCurve: Int
    public var beginFrame: CGRect
    public var endFrame: CGRect
    public var screen: UIScreen
    
    public var height: CGFloat { endFrame.height }
}

@MainActor public protocol WKeyboardObserverDelegate: AnyObject {
    func keyboardWillShow(info: WKeyboardDisplayInfo)
    func keyboardWillHide(info: WKeyboardDisplayInfo)
}

public class WKeyboardObserver {
    
    private weak var delegate: WKeyboardObserverDelegate?
    
    public static var displayedKeyboardOnce: Bool = false
    public static var keyboardHeight: CGFloat {
        get { CGFloat(UserDefaults.standard.float(forKey: "keyboardHeight"))  }
        set { UserDefaults.standard.set(newValue, forKey: "keyboardHeight") }
    }
    
    public static func observeKeyboard(delegate: WKeyboardObserverDelegate) {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                               object: nil,
                                               queue: .main) { [weak delegate] notification in
            MainActor.assumeIsolated {
                guard let info = notification.userInfo,
                      let animationDuration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                      let animationCurve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
                      let beginFrame = info[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
                      let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                keyboardHeight = endFrame.height
                let screen = notification.object as? UIScreen ?? UIScreen.main
                let showInfo = WKeyboardDisplayInfo(animationDuration: animationDuration, animationCurve: animationCurve, beginFrame: beginFrame, endFrame: endFrame, screen: screen)
                delegate?.keyboardWillShow(info: showInfo)
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification,
                                               object: nil,
                                               queue: .main) { [weak delegate] notification in
            MainActor.assumeIsolated {
                displayedKeyboardOnce = true
                guard let info = notification.userInfo,
                      let animationDuration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
                      let animationCurve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
                      let beginFrame = info[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
                      let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                let screen = notification.object as? UIScreen ?? UIScreen.main
                let showInfo = WKeyboardDisplayInfo(animationDuration: animationDuration, animationCurve: animationCurve, beginFrame: beginFrame, endFrame: endFrame, screen: screen)
                delegate?.keyboardWillHide(info: showInfo)
            }
        }
    }
}
