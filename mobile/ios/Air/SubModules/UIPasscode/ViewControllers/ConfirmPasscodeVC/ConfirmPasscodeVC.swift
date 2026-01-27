//
//  ConfirmPasscodeVC.swift
//  UIPasscode
//
//  Created by Sina on 4/17/23.
//

import UIKit
import UIComponents
import WalletContext

public class ConfirmPasscodeVC: WViewController, PasscodeScreenViewDelegate {
    func animateSuccess() {
        
    }
    
    func onAuthenticated(taskDone: Bool, passcode: String) {
        
    }
    
    var onCompletion: (_ biometricsEnabled: Bool, _ passcode: String) -> Void

    public init(onCompletion: @escaping (Bool, String) -> Void, setPasscodeVC: SetPasscodeVC, selectedPasscode: String) {
        self.onCompletion = onCompletion
        self.setPasscodeVC = setPasscodeVC
        self.selectedPasscode = selectedPasscode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var selectedPasscode: String!
    private weak var setPasscodeVC: SetPasscodeVC? = nil

    var headerView: HeaderView!
    var passcodeInputView: PasscodeInputView!
    var passcodeScreenView: PasscodeScreenView!
    
    var bottomConstraint: NSLayoutConstraint!

    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    func setupViews() {
        navigationItem.hidesBackButton = true

        // top animation and header
        let topView = UIView()
        topView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topView)
        NSLayoutConstraint.activate([
            topView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor),
            topView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor)
        ])

        headerView = HeaderView(
            animationName: "animation_guard",
            animationPlaybackMode: .once,
            title: lang("Wallet is ready!"),
            description: lang(
                "Create a code to protect it"
            )
        )
        topView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topView.topAnchor, constant: -10),
            headerView.centerXAnchor.constraint(equalTo: topView.centerXAnchor),
            headerView.bottomAnchor.constraint(equalTo: topView.bottomAnchor)
        ])

        // setup passcode input view
        passcodeInputView = PasscodeInputView(delegate: self, theme: WTheme.setPasscodeInput)
        passcodeInputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passcodeInputView)
        NSLayoutConstraint.activate([
            passcodeInputView.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 40),
            passcodeInputView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        passcodeInputView.isHidden = true
        
        passcodeScreenView = PasscodeScreenView(
            title: "zzz",
            replacedTitle: "xxx",
            subtitle: "rrrr",
            compactLayout: true,
            biometricPassAllowed: false,
            delegate: self,
            matchHeaderColors: false
        )
        view.backgroundColor = WTheme.sheetBackground
        passcodeScreenView.layer.cornerRadius = 16
        
        view.addSubview(passcodeScreenView)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passcodeScreenView.leftAnchor.constraint(equalTo: view.leftAnchor),
            passcodeScreenView.rightAnchor.constraint(equalTo: view.rightAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        passcodeScreenView.enterPasscodeLabel.label.text = lang("Enter your code again")
        
        
        bringNavigationBarToFront()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
}

extension ConfirmPasscodeVC: PasscodeInputViewDelegate {
    func passcodeChanged(passcode: String) {
        headerView.animatedSticker?.toggle(!passcode.isEmpty)
    }

    func passcodeSelected(passcode: String) {
        if passcode != selectedPasscode {
            // wrong passcode, return to setPasscodeVC
            setPasscodeVC?.passcodesDoNotMatch()
            navigationController?.popViewController(animated: true)
            return
        }
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {return}
            view.isUserInteractionEnabled = true
            
            // Suggest to enable a biometry protection, if available
            // Note that all incomplete biometric configurations are ignored.
            // So user with non-enrolled faceID will not receive a dialog
            if let biometryType = BiometricHelper.biometryType {
                navigationController?.pushViewController(
                    ActivateBiometricVC(biometryType: biometryType) { [weak self] biometricsEnabled in
                        self?.onCompletion(biometricsEnabled, passcode)
                }, animated: true)
            } else {
                onCompletion(false, passcode)
            }
        }
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let setVC = SetPasscodeVC(onCompletion: { _, _ in})
    UINavigationController(
        rootViewController: ConfirmPasscodeVC(
            onCompletion: { _, _ in },
            setPasscodeVC: setVC,
            selectedPasscode: "1111")
    )
}
#endif
