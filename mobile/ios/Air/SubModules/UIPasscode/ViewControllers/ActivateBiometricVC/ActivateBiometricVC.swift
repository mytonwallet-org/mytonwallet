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
    var passcodeInputView: PasscodeInputView?
    var passcodeOptionsView: PasscodeOptionsView?
    var bottomConstraint: NSLayoutConstraint?
    var bottomActionsView: BottomActionsView?
    
    public static let passcodeOptionsFromBottom = CGFloat(8)
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    func setupViews() {
        navigationItem.hidesBackButton = true

        _ = addHostingController(makeView(), constraints: .fill)
        
//        let biometricType = BiometricHelper.biometricType()
//        
//        let topImage: UIImage
//        let titleString, descriptionString, enableString, skipString: String
//        if biometricType == .face {
//            topImage = UIImage(named: "FaceIDIcon", in: AirBundle, compatibleWith: nil)!
//            titleString = lang("Enable Face ID")
//            descriptionString = lang("Face ID allows you to open your wallet faster without having to enter your password.")
//            enableString = lang("Enable Face ID")
//            skipString = lang("Skip")
//        } else {
//            topImage = UIImage(named: "TouchIDIcon", in: AirBundle, compatibleWith: nil)!
//            titleString = lang("Enable Touch ID")
//            descriptionString = lang("Touch ID allows you to open your wallet faster without having to enter your password.")
//            enableString = lang("Enable Touch ID")
//            skipString = lang("Skip")
//        }
    }
    
    func makeView() -> ActivateBiometricView {
        ActivateBiometricView(
            onEnable: { [weak self] in
                self?.activateBiometricPressed()
            },
            onSkip: { [ self] in
                self.finalizeFlow(biometricActivated: false)
            }
        )
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
                            self?.bottomActionsView?.primaryButton.showLoading = true
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


#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let _ = UIFont.registerAirFonts()
    UINavigationController(rootViewController: ActivateBiometricVC(onCompletion: { _, _ in }, selectedPasscode: ""))
}
#endif
