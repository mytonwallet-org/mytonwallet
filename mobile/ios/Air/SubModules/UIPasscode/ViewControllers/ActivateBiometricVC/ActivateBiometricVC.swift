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
import WalletCore
import WalletContext

public class ActivateBiometricVC: WViewController {

    public override var maxContentWidth: CGFloat? { 560 }
    public override var prefersViewCenteredContent: Bool { true }

    private let viewModel: ActivateBiometricViewModel
    private let authorizationToken: EnclaveToken

    private var onCompletion: SetPasscodeCompletion
    #if DEBUG
    /// Debug menu preview: pretends Face ID was enabled, with no real token to enable it for.
    public var debugSimulatesSuccess = false
    #endif
        
    public init(
        biometryType: BiometryType,
        authorizationToken: EnclaveToken,
        onCompletion: @escaping SetPasscodeCompletion
    ) {
        self.viewModel = ActivateBiometricViewModel(biometryType: biometryType)
        self.authorizationToken = authorizationToken
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

            do {
                #if DEBUG
                if debugSimulatesSuccess {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    await succeed(enclaveToken: authorizationToken)
                    return
                }
                #endif
                let finalToken = try await AuthSupport.enableBiometrics(using: authorizationToken)
                await succeed(enclaveToken: finalToken)
            } catch AuthSupportBiometricsError.canceled {
                viewModel.state = .idle
            } catch AuthSupportBiometricsError.userDeniedBiometrics {
                skip()
            } catch {
                viewModel.state = .idle
                showAlert(title: lang("Error"), text: error.localizedDescription, button: lang("OK"))
            }
        }
    }
    
    /// Lets the icon show that Face ID is on before moving to the next screen.
    private func succeed(enclaveToken: EnclaveToken) async {
        viewModel.state = .succeeded
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        finalizeFlow(enclaveToken: enclaveToken)
    }

    private func skip() {
        viewModel.state = .skipping
        finalizeFlow(enclaveToken: authorizationToken)
    }
    
    private func finalizeFlow(enclaveToken: EnclaveToken) {
        view.isUserInteractionEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await onCompletion(enclaveToken)
            } catch {
                view.isUserInteractionEnabled = true
                viewModel.state = .idle
                showAlert(error: error)
            }
        }
    }
}


#if DEBUG
@available(iOS 18.0, *)
#Preview {
    UINavigationController(
        rootViewController: ActivateBiometricVC(
            biometryType: .face,
            authorizationToken: "token",
            onCompletion: { _ in }
        )
    )
}
#endif
