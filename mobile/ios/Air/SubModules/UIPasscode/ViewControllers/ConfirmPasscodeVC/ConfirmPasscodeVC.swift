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
    
    private let onCompletion: SetPasscodeCompletion

    public init(onCompletion: @escaping SetPasscodeCompletion, setPasscodeVC: SetPasscodeVC, selectedPasscode: String) {
        self.onCompletion = onCompletion
        self.setPasscodeVC = setPasscodeVC
        self.selectedPasscode = selectedPasscode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let selectedPasscode: String
    private weak var setPasscodeVC: SetPasscodeVC? = nil
    private let indicatorView = WActivityIndicator()
    private var isCompleting = false

    private lazy var headerView = HeaderView(
        animationName: "animation_guard",
        animationPlaybackMode: .once,
        title: lang("Wallet is ready!"),
        description: lang("Create a code to protect it")
    )
    private lazy var passcodeInputView = PasscodeInputView(
        delegate: self,
        borderColor: UIColor.separator,
        emptyColor: .air.background,
        fillColor: UIColor.label,
        fillBorderColor: nil
    )
    private lazy var passcodeScreenView = PasscodeScreenView(
        title: "zzz",
        replacedTitle: "xxx",
        subtitle: "rrrr",
        compactLayout: true,
        biometricPassAllowed: false,
        delegate: self,
        matchHeaderColors: false
    )

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

        topView.addSubview(headerView)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topView.topAnchor, constant: -10),
            headerView.centerXAnchor.constraint(equalTo: topView.centerXAnchor),
            headerView.bottomAnchor.constraint(equalTo: topView.bottomAnchor)
        ])

        // setup passcode input view
        passcodeInputView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(passcodeInputView)
        NSLayoutConstraint.activate([
            passcodeInputView.topAnchor.constraint(equalTo: topView.bottomAnchor, constant: 40),
            passcodeInputView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        passcodeInputView.isHidden = true
        
        view.backgroundColor = .air.sheetBackground
        passcodeScreenView.layer.cornerRadius = 16
        
        view.addSubview(passcodeScreenView)
        passcodeScreenView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            passcodeScreenView.leftAnchor.constraint(equalTo: view.leftAnchor),
            passcodeScreenView.rightAnchor.constraint(equalTo: view.rightAnchor),
            passcodeScreenView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        passcodeScreenView.enterPasscodeLabel.label.text = lang("Enter your code again")
        passcodeScreenView.passcodeInputView.setAccessibilityTitle(lang("Enter your code again"))

        view.addSubview(indicatorView)
        NSLayoutConstraint.activate([
            indicatorView.centerXAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerXAnchor),
            indicatorView.centerYAnchor.constraint(equalTo: passcodeScreenView.passcodeInputView.centerYAnchor),
        ])
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
                    ActivateBiometricVC(biometryType: biometryType) { biometricsEnabled in
                        try await self.onCompletion(biometricsEnabled, passcode)
                }, animated: true)
            } else {
                completeWithoutBiometrics(passcode: passcode)
            }
        }
    }

    private func completeWithoutBiometrics(passcode: String) {
        setCompletionLoading(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await onCompletion(false, passcode)
            } catch {
                setCompletionLoading(false)
                showAlert(error: error)
            }
        }
    }

    private func setCompletionLoading(_ isLoading: Bool) {
        isCompleting = isLoading
        passcodeScreenView.isUserInteractionEnabled = !isLoading
        if isLoading {
            passcodeScreenView.passcodeInputView.animateSuccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.isCompleting else { return }
                indicatorView.alpha = 0
                indicatorView.transform = .init(scaleX: 0.2, y: 0.2)
                UIView.animate(withDuration: 0.2) {
                    self.passcodeScreenView.passcodeInputView.alpha = 0
                    self.indicatorView.alpha = 1
                    self.indicatorView.transform = .identity
                    self.indicatorView.startAnimating(animated: true)
                }
            }
        } else {
            indicatorView.stopAnimating(animated: true)
            UIView.animate(withDuration: 0.2) {
                self.passcodeScreenView.passcodeInputView.alpha = 1
            }
            passcodeScreenView.passcodeInputView.currentPasscode = ""
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
