//
//  SetPasscodeVC.swift
//  UIPasscode
//
//  Created by Sina on 4/16/23.
//

import UIKit
import UIComponents
import WalletContext

public class SetPasscodeVC: WViewController, PasscodeScreenViewDelegate {
    func animateSuccess() {
        
    }
    
    func onAuthenticated(taskDone: Bool, passcode: String) {
        
    }
    
    var onCompletion: (_ biometricsEnabled: Bool, _ passcode: String) -> Void

    public init(onCompletion: @escaping (Bool, String) -> Void) {
        self.onCompletion = onCompletion
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var headerView: HeaderView!
    var passcodeOptionsButton: WButton!
    var passcodeInputView: PasscodeInputView!
    var passcodeScreenView: PasscodeScreenView!
    var bottomConstraint: NSLayoutConstraint!

    private static let passcodeOptionsFromBottom = CGFloat(8)
    
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

        // listen for keyboard
        WKeyboardObserver.observeKeyboard(delegate: self)

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
//        passcodeScreenView.enterPasscodeLabel.label.text = "aa"
        
        
        bringNavigationBarToFront()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    // Called from ConfirmPasscodeVC when passcode is wrong
    func passcodesDoNotMatch() {
        headerView.lblDescription.text = lang("Passcodes don't match. Please try again.")
    }
}

extension SetPasscodeVC: PasscodeInputViewDelegate {
    func passcodeChanged(passcode: String) {
        headerView.animatedSticker?.toggle(!passcode.isEmpty)
    }
    func passcodeSelected(passcode: String) {
        view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else {return}
            view.isUserInteractionEnabled = true
            // push `ConfirmPasscode` view controller
            let confirmPasscodeVC = ConfirmPasscodeVC(onCompletion: onCompletion,
                                                      setPasscodeVC: self,
                                                      selectedPasscode: passcode)
            navigationController?.pushViewController(confirmPasscodeVC,
                                                     animated: true,
                                                     completion: { [weak self] in
                // make passcode empty on completion
                self?.passcodeInputView.currentPasscode = ""
                self?.passcodeScreenView.passcodeInputView.currentPasscode = ""
            })
        }
    }
}

extension SetPasscodeVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        bottomConstraint.constant = -info.height - SetPasscodeVC.passcodeOptionsFromBottom
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        bottomConstraint.constant = -SetPasscodeVC.passcodeOptionsFromBottom
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    UINavigationController(rootViewController: SetPasscodeVC(onCompletion: { _, _ in }))
}
#endif
