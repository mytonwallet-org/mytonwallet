//
//  ChangePasscodeVC.swift
//  UIPasscode
//
//  Created by Sina on 5/4/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

public enum ChangePasscodeStep {
    case currentPasscode
    case newPasscode(prevPasscode: String)
    case verifyPasscode(prevPasscode: String, passcode: String)
}

public class ChangePasscodeVC: WViewController {

    private let step: ChangePasscodeStep
    public init(step: ChangePasscodeStep) {
        self.step = step
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        if !IOS_26_MODE_ENABLED {
            navigationController?.navigationBar.tintColor = WTheme.primaryLabel
        }
        setupViews()
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    private var passcodeScreenView: PasscodeScreenView!

    private func setupViews() {
        let title: String
        switch step {
        case .currentPasscode:
            title = lang("Enter your current password")
            addCloseNavigationItemIfNeeded()
            break
        case .newPasscode(_):
            title = lang("Set a passcode")
            break
        case .verifyPasscode(_, _):
            title = lang("Confirm Passcode")
        }
        passcodeScreenView = PasscodeScreenView(title: title,
                                                biometricPassAllowed: false,
                                                delegate: self,
                                                matchHeaderColors: false)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passcodeScreenView)
        NSLayoutConstraint.activate([
            passcodeScreenView.leftAnchor.constraint(equalTo: view.leftAnchor),
            passcodeScreenView.topAnchor.constraint(equalTo: view.topAnchor),
            passcodeScreenView.rightAnchor.constraint(equalTo: view.rightAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

extension ChangePasscodeVC: PasscodeScreenViewDelegate {
    func passcodeChanged(passcode: String) {
    }
    
    func animateSuccess() {
    }
    
    func passcodeSelected(passcode: String) {
        switch step {
        case .currentPasscode:
            Task { @MainActor in
                let success = (try? await AuthSupport.verifyPassword(password: passcode)) ?? false
                if success {
                    view.isUserInteractionEnabled = false
                    try? await Task.sleep(for: .seconds(0.5))
                    view.isUserInteractionEnabled = true
                    navigationController?.pushViewController(ChangePasscodeVC(step: .newPasscode(prevPasscode: passcode)), animated: true)
                    passcodeScreenView.passcodeInputView.currentPasscode = ""
                } else {
                    Haptics.play(.error)
                    passcodeScreenView.passcodeInputView.currentPasscode = ""
                }
            }
            break
        case .newPasscode(let prevPasscode):
            view.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else {return}
                view.isUserInteractionEnabled = true
                navigationController?.pushViewController(ChangePasscodeVC(step: .verifyPasscode(prevPasscode: prevPasscode, passcode: passcode)),
                                                         animated: true)
                passcodeScreenView.passcodeInputView.currentPasscode = ""
            }
            break
        case let .verifyPasscode(prevPasscode, currentPass):
            if passcode == currentPass {
                view.isUserInteractionEnabled = false
                Task {
                    do {
                        try await Api.changePassword(oldPassword: prevPasscode, newPassword: passcode)
                        if let nc = navigationController, let vcs = navigationController?.viewControllers {
                            let filtered = vcs.filter { vc in !(vc is ChangePasscodeVC) }
                            nc.setViewControllers(filtered + [self], animated: false)
                            
                            self.passcodeScreenView.enterPasscodeLabel.setText(lang("Passcode changed"), animatedWithDuration: 0.2, animateResize: true)
                            UIView.animate(withDuration: 0.3) {
                                self.passcodeScreenView.lockImageView?.tintColor = UIColor.systemGreen
                                self.passcodeScreenView.enterPasscodeLabel.label.textColor = UIColor.systemGreen
                                self.passcodeScreenView.passcodeInputView.tintColor = UIColor.systemGreen
                                for circle in self.passcodeScreenView.passcodeInputView.circles {
                                    let green = UIColor.systemGreen.resolvedColor(with: UITraitCollection.current).cgColor
                                    circle.layer.borderColor = green
                                    circle.layer.backgroundColor = green
                                }
                            }
                            try? await Task.sleep(for: .seconds(1.2))
                            nc.setViewControllers(filtered, animated: true)
                        }
                    } catch {
                        topWViewController()?.showAlert(error: error)
                    }
                }
            } else {
                view.isUserInteractionEnabled = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else {return}
                    view.isUserInteractionEnabled = true
                    // go back to get a passcode again
                    passcodeScreenView.passcodeInputView.currentPasscode = ""
                    navigationController?.popViewController(animated: true)
                }
            }
            break
        }
    }
    
    func onAuthenticated(taskDone: Bool, passcode: String) {
        
    }
}
