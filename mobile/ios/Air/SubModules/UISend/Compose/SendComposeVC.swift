//
//  SendConfirmVC.swift
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
    
    private var continueButton: WButton { self.bottomButton! }
    private var startWithKeyboardActive: Bool { model.addressOrDomain.isEmpty }
    
    public init(model: SendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.showToast = { [weak self] animationName, message in
            self?.showToast(animationName: animationName, message: message)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        WKeyboardObserver.observeKeyboard(delegate: self)
        model.continueStateChanged = { [weak self] canContinue, insufficientFunds, draftStatus in
            guard let self else { return }
            if draftStatus.status == .loading {
                continueButton.showLoading = true
                continueButton.isEnabled = false
            } else {
                continueButton.showLoading = false
                continueButton.isEnabled = canContinue
                
                let title: String = if draftStatus.status == .invalid,
                                       draftStatus.address == model.addressOrDomain, !model.addressOrDomain.isEmpty {
                    lang("Invalid address")
                } else if insufficientFunds {
                    lang("Insufficient Balance")
                } else {
                    if model.toAddressDraft?.diesel?.status == .notAuthorized {
                        lang("Authorize %token% Fee", arg1: model.token?.symbol ?? "")
                    } else {
                        lang("Continue")
                    }
                }
                if continueButton.title(for: .normal) != title {
                    continueButton.setTitle(title, for: .normal)
                }
            }
        }
    }
    
    private func setupViews() {
        
        navigationItem.title = model.nftSendMode != nil ? lang("Send NFT") : lang("Send")
        addCloseNavigationItemIfNeeded()
        
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
        
        let c = startWithKeyboardActive ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        updateTheme()
        
        updateSensitiveData()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    func makeView() -> SendComposeView {
        SendComposeView(
            model: model,
            isSensitiveDataHidden: AppStorageHelper.isSensitiveDataHidden,
        )
    }
    
    func updateSensitiveData() {
        hostingController?.rootView = makeView()
    }
    
    @objc func continuePressed() {
        view.resignFirstResponder()
        if model.toAddressDraft?.diesel?.status == .notAuthorized {
            authorizeDiesel()
        }
        if let token = model.token, token.isPricelessToken || token.isStakedToken {
            let alert = UIAlertController(title: lang("Warning"), message: lang("$service_token_transfer_warning"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: lang("Cancel"), style: .cancel) { _ in
                return
            })
            alert.addAction(UIAlertAction(title: lang("OK"), style: .default) { _ in
                self.model.onComposeContinue()
            })
            present(alert, animated: true, completion: nil)
        } else {
            model.onComposeContinue()
        }
    }
    
    private func authorizeDiesel() {
        let telegramURLString = "https://t.me/MyTonWalletBot?start=auth-\(AccountStore.account?.tonAddress ?? "")"
        
        if let telegramURL = URL(string: telegramURLString) {
            if UIApplication.shared.canOpenURL(telegramURL) {
                UIApplication.shared.open(telegramURL, options: [:], completionHandler: nil)
            }
        }
    }
}


extension SendComposeVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant = -info.height - 16
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant =  -view.safeAreaInsets.bottom - 16
                view.layoutIfNeeded()
            }
        }
    }
}
