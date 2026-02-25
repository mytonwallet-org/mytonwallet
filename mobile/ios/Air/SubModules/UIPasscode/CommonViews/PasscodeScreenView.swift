//
//  PasscodeScreenView.swift
//  UIPasscode
//
//  Created by Sina on 5/4/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

protocol PasscodeScreenViewDelegate: PasscodeInputViewDelegate {
    @MainActor func animateSuccess()
    func onAuthenticated(taskDone: Bool, passcode: String)
}

public class PasscodeScreenView: UIView {
    
    /// An external config used for `effectiveBiometryType` in the work context.
    private let biometricPassAllowed: Bool
    private weak var delegate: PasscodeScreenViewDelegate? = nil
        
    init(
        title: String,
        replacedTitle: String? = nil,
        subtitle: String? = nil,
        compactLayout: Bool = false,
        biometricPassAllowed: Bool,
        delegate: PasscodeScreenViewDelegate,
        matchHeaderColors: Bool = true
    ) {
            self.biometricPassAllowed = biometricPassAllowed
            self.delegate = delegate
            super.init(frame: .zero)
        setupViews(
            title: title,
            replacedTitle: replacedTitle,
            subtitle: subtitle,
            compactLayout: compactLayout,
            matchHeaderColors: matchHeaderColors
        )
    }

    public override var canBecomeFirstResponder: Bool {
        true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }
    
    private var unlockScreenBackground: UIColor {
        WTheme.unlockScreen.background != .label ? WTheme.unlockScreen.background : WTheme.groupedItem
    }
    private var unlockScreenTintColor: UIColor {
        WTheme.unlockScreen.background != .label ? .white : WTheme.backgroundReverse
    }

    /// If not nil, indicates that authentication using the available biometry type is permitted.
    /// This property takes into account both the `biometricPassAllowed` configuration and whether 
    /// the user has enabled biometrics.
    private var effectiveBiometryType: BiometryType? {
        guard biometricPassAllowed, AppStorageHelper.isBiometricActivated() else {
            return nil
        }
        return BiometricHelper.biometryType
    }
    
    private(set) var passcodeInputView: PasscodeInputView!
    internal var lockImageView: UIImageView?
    internal var enterPasscodeLabel: WReplacableLabel!
    private var customHeader: UIView?
    
    private func setupViews(title: String,
                            replacedTitle: String?,
                            subtitle: String?,
                            compactLayout: Bool,
                            matchHeaderColors: Bool) {
        semanticContentAttribute = .forceLeftToRight

        backgroundColor = matchHeaderColors ? unlockScreenBackground : WTheme.groupedItem
        if matchHeaderColors {
            let darkOverlayView = UIView()
            darkOverlayView.translatesAutoresizingMaskIntoConstraints = false
            darkOverlayView.backgroundColor = .black.withAlphaComponent(0.1)
            addSubview(darkOverlayView)
            NSLayoutConstraint.activate([
                darkOverlayView.topAnchor.constraint(equalTo: topAnchor),
                darkOverlayView.leftAnchor.constraint(equalTo: leftAnchor),
                darkOverlayView.rightAnchor.constraint(equalTo: rightAnchor),
                darkOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        
        let unlockView = UIStackView()
        unlockView.translatesAutoresizingMaskIntoConstraints = false
        unlockView.axis = .vertical
        unlockView.alignment = .center
        addSubview(unlockView)
        
        // placement of entire stack
        if compactLayout {
            NSLayoutConstraint.activate([
                unlockView.topAnchor.constraint(equalTo: topAnchor, constant: 32),
                unlockView.bottomAnchor.constraint(equalTo: bottomAnchor),
                unlockView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
                unlockView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ])
        } else {
            // top constraint should be breaked in some situations like bottom sheet mode, if device is small.
            let topConstraint = unlockView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 16)
            topConstraint.priority = UILayoutPriority(749)
            // centerYConstraint is optional and should be breaked first of all.
            let centerYConstraint = unlockView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor, constant: -32)
            centerYConstraint.priority = UILayoutPriority(748)
            NSLayoutConstraint.activate([
                unlockView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
                unlockView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
                topConstraint,
                centerYConstraint
            ])
        }
        
        // lock icon
        if !compactLayout {
            let lockImageView = UIImageView()
            self.lockImageView = lockImageView
            lockImageView.image = UIImage(systemName: "lock.fill")
            lockImageView.contentMode = .scaleAspectFit
            lockImageView.tintColor = matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
            lockImageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                lockImageView.widthAnchor.constraint(equalToConstant: 24),
                lockImageView.heightAnchor.constraint(equalToConstant: 24)
            ])
            unlockView.addArrangedSubview(lockImageView)
            unlockView.setCustomSpacing(40, after: lockImageView)
        }
        
        let biometryType = effectiveBiometryType
        
        // enter passcode hint
        enterPasscodeLabel = WReplacableLabel()
        enterPasscodeLabel.translatesAutoresizingMaskIntoConstraints = false
        enterPasscodeLabel.label.textAlignment = .center
        if compactLayout {
            enterPasscodeLabel.label.font = .systemFont(ofSize: 17)
            let hintText: String
            switch biometryType {
            case .touch: hintText = lang("Enter code or use Touch ID")
            case .face: hintText = lang("Enter code or use Face ID")
            case nil: hintText = lang("Enter code")
            }
            enterPasscodeLabel.label.text = hintText
            enterPasscodeLabel.label.textColor = WTheme.secondaryLabel
        } else {
            enterPasscodeLabel.label.font = .systemFont(ofSize: 20)
            enterPasscodeLabel.label.numberOfLines = 2
            if let subtitle {
                let attr = NSMutableAttributedString()
                attr.append(NSAttributedString(string: title, attributes: [
                    .foregroundColor: matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
                ]))
                attr.append(NSAttributedString(string: "\n\(subtitle)", attributes: [
                    .foregroundColor: matchHeaderColors ? unlockScreenTintColor.withAlphaComponent(0.5) : WTheme.secondaryLabel
                ]))
                enterPasscodeLabel.label.attributedText = attr
            } else {
                enterPasscodeLabel.label.text = title
                enterPasscodeLabel.label.textColor = matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
            }
            if let replacedTitle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.enterPasscodeLabel.setText(replacedTitle, animatedWithDuration: 0.3, animateResize: true)
                }
            }
        }
        unlockView.addArrangedSubview(enterPasscodeLabel)
        
        // gap
        unlockView.setCustomSpacing(compactLayout ? 32 : 20, after: enterPasscodeLabel)

        // passcode input view
        passcodeInputView = PasscodeInputView(delegate: delegate,
                                              theme: matchHeaderColors && WTheme.unlockScreen.background != .label ? WTheme.unlockPasscodeInput : WTheme.unlockTaskPasscodeInput)
        passcodeInputView.isUserInteractionEnabled = false
        passcodeInputView.setCirclesCount(to: KeychainHelper.passcodeLength())
        unlockView.addArrangedSubview(passcodeInputView)

        // gap
        unlockView.setCustomSpacing(compactLayout ? 32 : 61, after: passcodeInputView)

        // create and add buttons
        // we have 4 rows
        for r in 0 ... 3 {
            let rowView = UIStackView()
            rowView.translatesAutoresizingMaskIntoConstraints = false
            rowView.spacing = compactLayout ? 40 : 24
            rowView.semanticContentAttribute = .forceLeftToRight
            // each row contains 3 columns
            for c in 1 ... 3 {
                let button = WBaseButton(type: .system)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: 78),
                    button.heightAnchor.constraint(equalToConstant: 78)
                ])
                button.layer.cornerRadius = 39
                button.backgroundColor = if matchHeaderColors {
                    unlockScreenTintColor.withAlphaComponent(0.12)
                } else if compactLayout{
                    UIColor.clear
                } else {
                    WTheme.backgroundReverse.withAlphaComponent(0.12)
                }
                button.highlightBackgroundColor = if matchHeaderColors {
                    unlockScreenTintColor.withAlphaComponent(0.4)
                } else if compactLayout {
                    WTheme.backgroundReverse.withAlphaComponent(0.12)
                } else {
                    WTheme.backgroundReverse.withAlphaComponent(0.4)
                }
                button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
                button.tag = r * 3 + c
                // check if button should contain a number label on top and a alphabet label on bottom
                if r < 3 || c == 2 {
                    // numbers 0 to 9
                    let buttonTitleLabel = UILabel()
                    buttonTitleLabel.translatesAutoresizingMaskIntoConstraints = false
                    buttonTitleLabel.font = .systemFont(ofSize: 37)
                    buttonTitleLabel.textColor = matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
                    let num: Int
                    if r < 3 {
                        // numbers between 1 and 9
                        num = r * 3 + c
                    } else {
                        // number 0
                        num = 0
                    }
                    buttonTitleLabel.text = "\(num)"
                    button.addSubview(buttonTitleLabel)
                    NSLayoutConstraint.activate([
                        buttonTitleLabel.heightAnchor.constraint(equalToConstant: 32),
                        buttonTitleLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                        buttonTitleLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor, constant: num > 0 ? -6 : 0)
                    ])
                    let buttonAlphabetLabel = UILabel()
                    buttonAlphabetLabel.translatesAutoresizingMaskIntoConstraints = false
                    buttonAlphabetLabel.font = .systemFont(ofSize: num > 0 ? 10 : 16, weight: .medium)
                    buttonAlphabetLabel.textColor = matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
                    buttonAlphabetLabel.text = alphabetText(forNum: num)
                    button.addSubview(buttonAlphabetLabel)
                    NSLayoutConstraint.activate([
                        buttonAlphabetLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                        buttonAlphabetLabel.topAnchor.constraint(equalTo: buttonTitleLabel.bottomAnchor, constant: 1)
                    ])
                } else {
                    button.backgroundColor = .clear
                    button.highlightBackgroundColor = .clear
                    let image: UIImage
                    if c == 1 {
                        var imageName: String
                        switch biometryType {
                        case .face:
                            imageName = "FaceIDIcon"
                        case .touch:
                            imageName = "TouchIDIcon"
                        case nil:
                            imageName = "FaceIDIcon" // just a placeholder. if will be hidden
                            hideButton(button)
                        }
                        image = UIImage(named: imageName, in: AirBundle, compatibleWith: nil)!
                    } else {
                        // backspace!
                        image = UIImage(named: "BackspaceIcon", in: AirBundle, compatibleWith: nil)!
                    }
                    let buttonImageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
                    buttonImageView.tintColor = matchHeaderColors ? unlockScreenTintColor : WTheme.primaryLabel
                    buttonImageView.translatesAutoresizingMaskIntoConstraints = false
                    buttonImageView.contentMode = .scaleAspectFit
                    button.addSubview(buttonImageView)
                    NSLayoutConstraint.activate([
                        // backspace should be a little left!
                        buttonImageView.centerXAnchor.constraint(equalTo: button.centerXAnchor, constant: c == 3 ? -1 : 0),
                        buttonImageView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                        buttonImageView.heightAnchor.constraint(equalToConstant: 32)
                    ])
                }
                rowView.addArrangedSubview(button)
            }
            
            if !compactLayout {
                let gapView = UIView()
                gapView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    gapView.widthAnchor.constraint(equalToConstant: 0),
                    gapView.heightAnchor.constraint(equalToConstant: 18)
                ])
                unlockView.addArrangedSubview(gapView)
            }
            unlockView.addArrangedSubview(rowView)
        }
    }
    
    public func fadeIn() {
        enterPasscodeLabel.fadeIn()
        passcodeInputView.alpha = 0
        animateViewsWithTag(from: 1, to: 12, containerView: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else {return}
            passcodeInputView.alpha = 1
            self.passcodeInputView.fadeIn()
        }
    }
    
    private func animateViewsWithTag(from startTag: Int, to endTag: Int, containerView: UIView) {
        for tag in startTag...endTag {
            if let view = containerView.viewWithTag(tag) {
                view.transform = CGAffineTransform(scaleX: 0, y: 0)
                let delay = 0.15 + Double(tag - startTag) * 0.03
                UIView.animate(withDuration: 0.25, delay: delay, options: [], animations: {
                    view.transform = CGAffineTransform.identity
                }, completion: nil)
            }
        }
    }
    
    private func alphabetText(forNum num: Int) -> String {
        switch num {
        case 0, 1:
            return ""
        case 7:
            return "P Q R S"
        case 8:
            return "T U V"
        case 9:
            return "W X Y Z"
        default:
            var txt = ""
            let startIndex = Int(UnicodeScalar("A").value) + num * 3 - 6
            for charIndex in startIndex ... startIndex + 2 {
                let char = String(UnicodeScalar(charIndex)!)
                txt = "\(txt)\(char) "
            }
            txt.removeLast()
            return txt
        }
    }
    
    private func hideButton(_ button: UIView) {
        button.alpha = 0 // if we set isHidden, stackView will not consider it's space
    }
    
    private let biometricButtonTag = 10
    
    @objc func buttonPressed(button: UIButton) {
        switch button.tag {
        case biometricButtonTag:
            tryBiometric()
        case 11:    // 0 number
            passcodeInputView.currentPasscode += "0"
        case 12:
            passcodeInputView.deleteBackward()
        default:
            passcodeInputView.currentPasscode += "\(button.tag)"
        }
    }

    public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            handled = handleHardwareKeyboardKey(key) || handled
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    private func handleHardwareKeyboardKey(_ key: UIKey) -> Bool {
        if !key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty {
            return false
        }
        if key.keyCode == .keyboardDeleteOrBackspace {
            passcodeInputView.deleteBackward()
            return true
        }
        let text = key.charactersIgnoringModifiers
        if text.isEmpty {
            return false
        }
        var handled = false
        for char in text {
            if let value = char.wholeNumberValue {
                passcodeInputView.insertText(String(value))
                handled = true
            }
        }
        return handled
    }

    func tryBiometric() {
        guard effectiveBiometryType != nil else {
            return
        }
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let result = await BiometricHelper.authenticate()
            switch result {
            case .canceled:
                break
            case .userDeniedBiometrics:
                guard let button = viewWithTag(biometricButtonTag) else {
                    assertionFailure("Unable to get the biometric button")
                    break
                }
                hideButton(button)
            case .success:
                delegate?.passcodeSelected(passcode: KeychainHelper.biometricPasscode())
            case let .error(localizedDescription, title):
                let topVC = topViewController() as? WViewController
                topVC?.showAlert(title: title, text: localizedDescription, button: lang("OK"))
            }
        }
    }
    
    func wrongPassFeedback() {
        lockImageView?.shake()
        passcodeInputView.shake()
    }
}
