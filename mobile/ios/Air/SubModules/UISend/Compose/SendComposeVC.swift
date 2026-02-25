//
//  SendComposeVC.swift
//  UISend
//
//  Created by Sina on 4/20/24.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import UIPasscode

class SendComposeVC: WViewController, WSensitiveDataProtocol {

    let model: SendModel
    var hostingController: UIHostingController<SendComposeView>?
    var continueButtonConstraint: NSLayoutConstraint?
    var continueButtonFallbackConstraint: NSLayoutConstraint?
    
    private var continueButton: WButton { self.bottomButton! }
    
    public init(model: SendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        observe { [weak self] in
            guard let self else { return }
            let (canContinue, insufficientFunds, draftStatus, isAddressLoading) = model.continueState
            if draftStatus.status == .loading || isAddressLoading {
                continueButton.showLoading = true
                continueButton.isEnabled = false
            } else {
                continueButton.showLoading = false
                continueButton.isEnabled = canContinue
                
                let title: String = if draftStatus.status == .invalid,
                                       draftStatus.transactionDraft?.resolvedAddress == model.addressOrDomain, !model.addressOrDomain.isEmpty {
                    lang("Invalid address")
                } else if insufficientFunds {
                    lang("Insufficient Balance")
                } else {
                    if model.draftData.transactionDraft?.diesel?.status == .notAuthorized {
                        lang("Authorize %token% Fee", arg1: model.token.symbol)
                    } else {
                        lang("Continue")
                    }
                }
                if continueButton.title(for: .normal) != title {
                    continueButton.setTitle(title, for: .normal)
                }
            }
        }
        observe { [weak self] in
            guard let self else { return }
            navigationItem.setLeftBarButtonItems(model.addressInput.isFocused ? [
                UIBarButtonItem(title: "", image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { _ in endEditing() })
            ] : nil, animated: true)
        }
        observe { [weak self] in
            guard let self else { return }
            let canContinue = model.canContinue
            UIView.animate(withDuration: 0.3) {
                self.continueButtonConstraint?.isActive = canContinue
                self.view.layoutIfNeeded()
            }
        }
    }
    
    private func buildNavigationItem() {
        switch model.mode {
        case .burnNft, .sellToMoonpay:
            assertionFailure("Should not be available on this screen")
            fallthrough
        case .sendNft:
            navigationItem.title = lang("Send")
        case .regular:
            navigationItem.titleView = HostingView {
                SendComposeTitleView(
                    onSellTapped: { [weak self] in self?.showSell() },
                    onMultisendTapped: { [weak self] in self?.showMultisend() }
                )
            }
        }
        addCloseNavigationItemIfNeeded()
    }
    
    private func setupViews() {
        buildNavigationItem()
        
        let hostingController = UIHostingController(rootView: makeView())
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
        hostingController.view.backgroundColor = .clear

        _ = addBottomButton(bottomConstraint: false)
        continueButton.setTitle(lang("Continue"), for: .normal)
        continueButton.isEnabled = model.canContinue
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16)
        self.continueButtonConstraint = constraint

        let constraint2 = continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16).withPriority(.defaultHigh)
        self.continueButtonFallbackConstraint = constraint2

        NSLayoutConstraint.activate([
            constraint,
            constraint2,
        ])
        
        updateTheme()
        
        updateSensitiveData()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    private func makeView() -> SendComposeView {
        SendComposeView(
            model: model,
            isSensitiveDataHidden: AppStorageHelper.isSensitiveDataHidden,
        )
    }
    
    func updateSensitiveData() {
        hostingController?.rootView = makeView()
    }
    
    @objc private func continuePressed() {
        view.resignFirstResponder()
        if model.draftData.transactionDraft?.diesel?.status == .notAuthorized {
            authorizeDiesel()
            return
        }
        if model.token.isPricelessToken || model.token.isStakedToken {
            let alert = UIAlertController(title: lang("Warning"), message: lang("$service_token_transfer_warning"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel) { _ in
                return
            })
            alert.addAction(UIAlertAction(title: lang("OK"), style: .default) { _ in
                self._onContinue()
            })
            present(alert, animated: true, completion: nil)
        } else {
            _onContinue()
        }
    }
    
    func _onContinue() {
        endEditing()
        let vc = SendConfirmVC(model: model)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func authorizeDiesel() {
        guard let telegramURL = model.account.dieselAuthLink else { return }
        UIApplication.shared.open(telegramURL, options: [:], completionHandler: nil)
    }

    private func showSell() {
        dismiss(animated: true)
        AppActions.showSell(account: model.account, tokenSlug: model.token.slug)
    }
    
    private func showMultisend() {
        dismiss(animated: true)
        AppActions.showMultisend()
    }
}



#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc = SendComposeVC(model: SendModel(prefilledValues: .init()))
    previewSheet(vc)
}
#endif
