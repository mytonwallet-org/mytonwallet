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

class SendComposeVC: WViewController, WSensitiveDataProtocol {

    let model: SendModel
    var hostingController: UIHostingController<SendComposeView>?
    var continueButtonConstraint: NSLayoutConstraint?
    var continueButtonFallbackConstraint: NSLayoutConstraint?
    
    private var continueButton: WButton?
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .send)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }
    
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
            guard let continueButton else { return }
            let (canContinue, hasInsufficientBalanceError, draftStatus, isAddressLoading) = model.continueState
            if draftStatus.status == .loading || isAddressLoading {
                continueButton.showLoading = true
                continueButton.isEnabled = false
            } else {
                continueButton.showLoading = false
                continueButton.isEnabled = canContinue
                
                let title: String = if draftStatus.status == .invalid, !model.addressOrDomain.isEmpty {
                    lang("Invalid address")
                } else if hasInsufficientBalanceError {
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
            _ = model.addressInput.isFocused
            _ = model.account.id
            updateLeftNavigationItem()
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
                    isSellSupported: model.token.chain.isOfframpSupported,
                    onSellTapped: { [weak self] in self?.showSell() },
                    onMultisendTapped: { [weak self] in self?.showMultisend() }
                )
            }
        }
        addCloseNavigationItemIfNeeded()
    }
    
    private func setupViews() {
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
        
        buildNavigationItem()
        addCustomNavigationBarBackground(color: .air.sheetBackground)

        let continueButton = addBottomButton(bottomConstraint: false)
        self.continueButton = continueButton
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
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
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
        if model.shouldConfirmDomainScamWarning {
            showDomainScamWarning()
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

    private func showDomainScamWarning() {
        guard model.isAllowSuspiciousActions else {
            showAlert(
                title: lang("Warning!"),
                text: model.domainScamWarningPlainText,
                button: lang("Close")
            )
            return
        }

        showAlert(
            title: lang("Warning!"),
            text: model.domainScamWarningPlainText,
            button: lang("Continue"),
            buttonStyle: .destructive,
            buttonPressed: { [weak self] in
                self?.model.confirmDomainScamWarning()
                self?.continuePressed()
            },
            secondaryButton: lang("Close"),
            preferPrimary: false
        )
    }

    private func showSell() {
        dismiss(animated: true)
        AppActions.showSell(accountContext: model.$account, tokenSlug: model.token.slug)
    }
    
    private func showMultisend() {
        dismiss(animated: true)
        AppActions.showMultisend()
    }

    private func updateLeftNavigationItem() {
        if model.addressInput.isFocused {
            navigationItem.setLeftBarButtonItems([
                UIBarButtonItem(title: "", image: UIImage(systemName: "chevron.backward"), primaryAction: UIAction { _ in endEditing() })
            ], animated: true)
            return
        }

        guard IS_DEBUG_OR_TESTFLIGHT, model.isAccountSwitchingAllowed else {
            navigationItem.setLeftBarButtonItems(nil, animated: true)
            return
        }

        accountSwitcher.update(selectedAccountId: model.account.id)
        let items = accountSwitcher.hasAlternativeAccounts(selectedAccountId: model.account.id)
            ? [accountSwitcher.barButtonItem]
            : nil
        navigationItem.setLeftBarButtonItems(items, animated: true)
    }

    private func selectAccount(accountId: String) {
        Task {
            do {
                try await model.onAccountSelected(accountId: accountId)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
}



#if DEBUG
@available(iOS 18, *)
#Preview {
    let vc = SendComposeVC(model: SendModel(accountContext: AccountContext(source: .current), prefilledValues: .init()))
    previewSheet(vc)
}
#endif
