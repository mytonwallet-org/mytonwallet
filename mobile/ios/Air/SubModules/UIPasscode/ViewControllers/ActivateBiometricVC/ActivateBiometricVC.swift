//
//  ActivateBiometricVC.swift
//  UIPasscode
//
//  Created by Sina on 4/18/23.
//

import UIKit
import SwiftUI
import UIComponents
import Perception
import WalletContext

public class ActivateBiometricVC: WViewController {

    private let viewModel: ActivateBiometricViewModel

    private var onCompletion: (Bool) -> Void
        
    public init(biometryType: BiometryType, onCompletion: @escaping (Bool) -> Void) {
        self.viewModel = ActivateBiometricViewModel(biometryType: biometryType)
        self.onCompletion = onCompletion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        navigationItem.hidesBackButton = true

        _ = addHostingController(makeView(), constraints: .fill)
    }
        
    private func makeView() -> ActivateBiometricView {
        ActivateBiometricView(
            viewModel: viewModel,
            onEnable: { [weak self] in
                self?.activateBiometric()
            },
            onSkip: { [weak self] in
                self?.skip()
            }
        )
    }
    
    private func activateBiometric() {
        viewModel.state = .authenticating
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            let result = await BiometricHelper.authenticate()
            switch result {
            case .success:
                finalizeFlow(biometricActivated: true)
            case .canceled:
                viewModel.state = .idle
            case .userDeniedBiometrics:
                skip()
            case let .error(localizedDescription, title):
                viewModel.state = .idle
                showAlert(title: title, text: localizedDescription, button: lang("OK"))
            }
        }
    }
    
    private func skip() {
        viewModel.state = .skipping
        finalizeFlow(biometricActivated: false)
    }
    
    private func finalizeFlow(biometricActivated: Bool) {
        view.isUserInteractionEnabled = false
        onCompletion(biometricActivated)
    }
}


#if DEBUG
@available(iOS 18.0, *)
#Preview {
    UINavigationController(rootViewController: ActivateBiometricVC(biometryType: .face, onCompletion: { _ in }))
}
#endif
