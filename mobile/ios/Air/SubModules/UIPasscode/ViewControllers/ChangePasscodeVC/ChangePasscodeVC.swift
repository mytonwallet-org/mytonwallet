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
    case newPasscode(prevToken: EnclaveToken)
    case verifyPasscode(prevToken: EnclaveToken, passcode: String)
}

public class ChangePasscodeVC: WViewController {

    private let step: ChangePasscodeStep
    private let mismatchTitle = lang("Passcodes don't match. Please try again.")

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
            navigationController?.navigationBar.tintColor = UIColor.label
        }
        setupViews()
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }
    
    private var passcodeScreenView: PasscodeScreenView!

    private func setupViews() {
        if case .currentPasscode = step {
            addCloseNavigationItemIfNeeded()
        }
        passcodeScreenView = PasscodeScreenView(title: stepTitle,
                                                biometricPassAllowed: false,
                                                delegate: self,
                                                matchHeaderColors: false)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passcodeScreenView)
        NSLayoutConstraint.activate([
            passcodeScreenView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            passcodeScreenView.topAnchor.constraint(equalTo: view.topAnchor),
            passcodeScreenView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private var stepTitle: String {
        switch step {
        case .currentPasscode:
            lang("Enter your current password")
        case .newPasscode(_):
            lang("Set a passcode")
        case .verifyPasscode(_, _):
            lang("Confirm Passcode")
        }
    }

    private func showPasscodesDoNotMatch() {
        passcodeScreenView.enterPasscodeLabel.setText(
            mismatchTitle,
            animatedWithDuration: 0.2,
            animateResize: true
        )
    }
}

extension ChangePasscodeVC: PasscodeScreenViewDelegate {
    func passcodeChanged(passcode: String) {
        guard case .newPasscode(_) = step,
              !passcode.isEmpty,
              passcodeScreenView.enterPasscodeLabel.label.text == mismatchTitle else {
            return
        }
        passcodeScreenView.enterPasscodeLabel.setText(
            stepTitle,
            animatedWithDuration: 0.2,
            animateResize: true
        )
    }
    
    func animateSuccess() {
    }
    
    func passcodeSelected(passcode: String) {
        switch step {
        case .currentPasscode:
            Task { @MainActor in
                let enclaveToken = try? await AuthSupport.authorizeWithPasscode(
                    passcode,
                    sessionKind: .oneShot
                )
                if let enclaveToken {
                    view.isUserInteractionEnabled = false
                    try? await Task.sleep(for: .seconds(0.5))
                    view.isUserInteractionEnabled = true
                    navigationController?.pushViewController(ChangePasscodeVC(step: .newPasscode(prevToken: enclaveToken)), animated: true)
                    passcodeScreenView.passcodeInputView.currentPasscode = ""
                } else {
                    Haptics.play(.error)
                    passcodeScreenView.passcodeInputView.currentPasscode = ""
                }
            }
            break
        case .newPasscode(let prevToken):
            view.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else {return}
                view.isUserInteractionEnabled = true
                navigationController?.pushViewController(ChangePasscodeVC(step: .verifyPasscode(prevToken: prevToken, passcode: passcode)),
                                                         animated: true)
                passcodeScreenView.passcodeInputView.currentPasscode = ""
            }
            break
        case let .verifyPasscode(prevToken, currentPass):
            if passcode == currentPass {
                view.isUserInteractionEnabled = false
                Task {
                    do {
                        try await AuthSupport.changePasscode(to: passcode, using: prevToken)
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
                Haptics.play(.error)
                passcodeScreenView.wrongPassFeedback()
                (navigationController?.viewControllers.dropLast().last as? ChangePasscodeVC)?.showPasscodesDoNotMatch()
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
    
    func onAuthenticated(taskDone: Bool, enclaveToken: EnclaveToken) {
        
    }
}
