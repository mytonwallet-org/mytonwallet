//
//  PasscodeInputView.swift
//  UIPasscode
//
//  Created by Sina on 4/16/23.
//

import UIKit
import WalletContext
import WalletCore

protocol PasscodeInputViewDelegate: AnyObject {
    func passcodeChanged(passcode: String)
    func passcodeSelected(passcode: String)
}

class PasscodeInputView: UIStackView, WThemedView {
    
    // MARK: Make view present keyboard
    var _inputView: UIView?
    
    override var canBecomeFirstResponder: Bool { return true }
    override var canResignFirstResponder: Bool { return true }
    
    override var inputView: UIView? {
        set { _inputView = newValue }
        get { return _inputView }
    }

    // MARK: Init and setup view
    weak var delegate: PasscodeInputViewDelegate?
    let theme: WThemePasscodeInput

    var circles = [UIView]()
    var currentPasscode = String() {
        didSet {
            textUpdated()
        }
    }
    static let defaultPasscodeLength = 4
    var maxPasscodeLength = 6
    var passcodeLength = PasscodeInputView.defaultPasscodeLength

    init(delegate: PasscodeInputViewDelegate?, theme: WThemePasscodeInput) {
        self.delegate = delegate
        self.theme = theme
        super.init(frame: CGRect.zero)
        setupView()
    }
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    required init(coder: NSCoder) {
        fatalError()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        // spacing between inputs
        spacing = 16

        // create circles
        for i in 0 ..< maxPasscodeLength {
            let circle = UIView()
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.layer.cornerRadius = 8
            circle.layer.borderWidth = 1
            NSLayoutConstraint.activate([
                circle.widthAnchor.constraint(equalToConstant: 16),
                circle.heightAnchor.constraint(equalToConstant: 16)
            ])
            circles.append(circle)
            if i < passcodeLength {
                addArrangedSubview(circle)
            }
        }
        
        updateTheme()
    }

    func setCirclesCount(to num: Int) {
        if passcodeLength == num {
            return
        }
        passcodeLength = num
        currentPasscode = ""
        if num < 1 || num > maxPasscodeLength {
            return
        }
        for i in 0 ..< num {
            if circles[i].superview == nil {
                addArrangedSubview(circles[i])
            }
        }
        for i in num ..< maxPasscodeLength {
            if circles[i].superview != nil {
                circles[i].removeFromSuperview()
            }
        }
    }
    
    func textUpdated() {
        delegate?.passcodeChanged(passcode: currentPasscode)

        // update circle colors
        let textLength = currentPasscode.count
        for i in 0 ..< maxPasscodeLength {
            if i < textLength {
                fillIn(i)
            } else {
                fillOut(i)
            }
        }
        if currentPasscode.count == passcodeLength {
            delegate?.passcodeSelected(passcode: currentPasscode)
        }
    }
    
    func fillIn(_ i: Int) {
        let newColor = theme.fill
        let circle = circles[i]
        guard circle.backgroundColor != newColor else { return }
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            circle.transform = .init(scaleX: 1.3, y: 1.3)
            circle.backgroundColor = newColor
            if let fillBorder = self.theme.fillBorder {
                circle.layer.borderColor = fillBorder.cgColor
            }
        } completion: { ok in
            if ok {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
                    circle.transform = .identity
                }
            }
        }
    }
    
    func fillOut(_ i: Int) {
        let newColor = theme.empty
        let circle = circles[i]
        guard circle.backgroundColor != newColor else { return }
        UIView.animate(withDuration: 0.1) {
            circle.backgroundColor = newColor
            if self.theme.fillBorder != nil {
                circle.layer.borderColor = self.theme.border.cgColor
            }
        }
    }
    
    func animateSuccess() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            for circle in self.circles {
                circle.layer.removeAllAnimations()
                
                circle.transform = .init(scaleX: 1.3, y: 1.3)
                circle.backgroundColor = self.theme.fill
                if let fillBorder = self.theme.fillBorder {
                    circle.layer.borderColor = fillBorder.cgColor
                }
            }
        } completion: { _ in
            for circle in self.circles {
                let center = self.bounds.center
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
                    circle.transform = .init(translationX: center.x - circle.center.x, y: center.y - circle.center.y).scaledBy(x: 0.9, y: 0.9)
                    circle.alpha = 0.9
                    if self.theme.fillBorder != nil {
                        circle.backgroundColor = UIColor.systemGreen
                    }
                } completion: { _ in
                    UIView.animate(withDuration: 0.2, delay: 0, options: []) {
                        circle.transform = .init(translationX: center.x - circle.center.x, y: center.y - circle.center.y).scaledBy(x: 0.1, y: 0.1)
                        circle.alpha = 0.1
                    }
                }
            }
        }
    }
    
    func fadeIn() {
        for v in arrangedSubviews {
            v.transform = CGAffineTransform(scaleX: 0, y: 0)
        }
        UIView.animate(withDuration: 0.3) { [weak self] in
            guard let self else {return}
            for v in arrangedSubviews {
                v.transform = CGAffineTransform.identity
            }
        }
    }
    
    func updateTheme() {
        for circle in circles {
            circle.layer.borderColor = theme.border.resolvedColor(with: AppStorageHelper.activeNightMode.traitCollection).cgColor
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTheme()
    }

}

// MARK: - UIKeyInput
extension PasscodeInputView: UIKeyInput {
    var hasText: Bool { return true }
    func insertText(_ text: String) {
        guard let num = Int(text.normalizeArabicPersianNumeralStringToWestern()) else {
            return
        }
        if currentPasscode.count < passcodeLength {
            currentPasscode += "\(num)"
        }
    }
    func deleteBackward() {
        currentPasscode = String(currentPasscode.dropLast(1))
    }
    var keyboardType: UIKeyboardType {
        get {
            return .numberPad
        }
        set {}
    }
}
