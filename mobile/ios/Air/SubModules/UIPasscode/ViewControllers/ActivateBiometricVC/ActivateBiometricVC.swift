//
//  ActivateBiometricVC.swift
//  UIPasscode
//
//  Created by Sina on 4/18/23.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext
import LocalAuthentication

public class ActivateBiometricVC: WViewController {
    
    var onCompletion: (Bool, @escaping () -> Void) -> Void
    var selectedPasscode: String

    public init(onCompletion: @escaping (Bool, @escaping () -> Void) -> Void,
                selectedPasscode: String) {
        self.onCompletion = onCompletion
        self.selectedPasscode = selectedPasscode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var headerView: HeaderView!
    var passcodeInputView: PasscodeInputView!
    var passcodeOptionsView: PasscodeOptionsView!
    var bottomConstraint: NSLayoutConstraint!
    var bottomActionsView: BottomActionsView!
    
    public static let passcodeOptionsFromBottom = CGFloat(8)
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    func setupViews() {
        navigationItem.hidesBackButton = true

        let biometricType = BiometricHelper.biometricType()
        
        let topImage: UIImage
        let titleString, descriptionString, enableString, skipString: String
        if biometricType == .face {
            topImage = UIImage(named: "FaceIDIcon", in: AirBundle, compatibleWith: nil)!
            titleString = lang("Enable Face ID")
            descriptionString = lang("Face ID allows you to open your wallet faster without having to enter your password.")
            enableString = lang("Enable Face ID")
            skipString = lang("Skip")
        } else {
            topImage = UIImage(named: "TouchIDIcon", in: AirBundle, compatibleWith: nil)!
            titleString = lang("Enable Touch ID")
            descriptionString = lang("Touch ID allows you to open your wallet faster without having to enter your password.")
            enableString = lang("Enable Touch ID")
            skipString = lang("Skip")
        }

        let enableButtonAction = BottomAction(
            title: enableString,
            onPress: { [weak self] in
                self?.activateBiometricPressed()
            }
        )
        
        let skipButtonAction = BottomAction(
            title: skipString,
            onPress: { [weak self] in
                self?.bottomActionsView.secondaryButton.showLoading = true
                self?.finalizeFlow(biometricActivated: false)
            }
        )
        
        bottomActionsView = BottomActionsView(primaryAction: enableButtonAction,
                                              secondaryAction: skipButtonAction)
        view.addSubview(bottomActionsView)
        NSLayoutConstraint.activate([
            bottomActionsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -58),
            bottomActionsView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 48),
            bottomActionsView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -48),
        ])
        
        let topView = UIView()
        topView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topView)
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            topView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor),
            topView.bottomAnchor.constraint(equalTo: bottomActionsView.topAnchor)
        ])

        let headerView = HeaderView(icon: topImage,
                                    iconWidth: 124, iconHeight: 124,
                                    iconTintColor: WTheme.tint,
                                    title: titleString,
                                    description: descriptionString)
        topView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.leftAnchor.constraint(equalTo: topView.leftAnchor, constant: 32),
            headerView.rightAnchor.constraint(equalTo: topView.rightAnchor, constant: -32),
            headerView.centerYAnchor.constraint(equalTo: topView.centerYAnchor)
        ])
    }
    
    func activateBiometricPressed() {
        let context = LAContext()
            var error: NSError?

            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                let reason = lang("MyTonWallet uses biometric authentication to unlock and authorize transactions")

                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
                    [weak self] success, authenticationError in

                    DispatchQueue.main.async { [weak self] in
                        if success {
                            self?.bottomActionsView.primaryButton.showLoading = true
                            self?.finalizeFlow(biometricActivated: true)
                        } else {
                            // error
                        }
                    }
                }
            } else {
                showAlert(title: lang("Biometric authentication not available."),
                          text: lang("Please set a passcode on your device, and then try to use biometric authentication."),
                          button: lang("OK"))
            }
    }
    
    func finalizeFlow(biometricActivated: Bool) {
        view.isUserInteractionEnabled = false
        onCompletion(biometricActivated, { [weak self] in
            guard let self else {return}
            view.isUserInteractionEnabled = true
        })
    }
}
