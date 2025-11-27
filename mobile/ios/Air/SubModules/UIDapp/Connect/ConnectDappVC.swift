//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Ledger

public class ConnectDappVC: WViewController, UISheetPresentationControllerDelegate {
    
    var request: ApiUpdate.DappConnect?
    var onConfirm: ((_ accountId: String, _ password: String) -> ())?
    var onCancel: (() -> ())?
    
    var placeholderAccountId: String?
    
    private var didConfirm = false
    var hostingController: UIHostingController<ConnectDappViewOrPlaceholder>?
    
    public init(
        request: ApiUpdate.DappConnect,
        onConfirm: @escaping (_ accountId: String, _ password: String) -> (),
        onCancel: @escaping () -> ()
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    
    init(placeholderAccountId: String?) {
        self.placeholderAccountId = placeholderAccountId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func replacePlaceholder(
        request: ApiUpdate.DappConnect,
        onConfirm: @escaping (_ accountId: String, _ password: String) -> (),
        onCancel: @escaping () -> ()
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        updateAccountView()
        updateDappViews()
        UIView.animate(withDuration: 0.3) {
            self.hostingController?.view.alpha = 0
            self.contentView.alpha = 1
        }
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
        sheetPresentationController?.delegate = self
    }
    
    var selectedAccount = AccountStore.account
    
    public private(set) lazy var sheetHeight = view.safeAreaInsets.bottom + 418
    
    private lazy var appIconView = {
        let img = UIImageView()
        img.translatesAutoresizingMaskIntoConstraints = false
        img.layer.cornerRadius = 16
        img.layer.masksToBounds = true
        return img
    }()
    
    private lazy var titleLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = UIFont.systemFont(ofSize: 24, weight: .semibold)
        lbl.textAlignment = .center
        return lbl
    }()
    
    private lazy var subtitleLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        lbl.textAlignment = .center
        return lbl
    }()
    
    private lazy var hintLabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        lbl.textAlignment = .center
        lbl.text = lang("Connected apps can only see your wallet address and will not be able to move your assets without permission.")
        lbl.numberOfLines = 0
        return lbl
    }()
    
    private lazy var accountIconView = {
        let iconView = IconView(size: 40)
        return iconView
    }()
    
    private lazy var accountNameLabel = {
        let accountNameLabel = UILabel()
        accountNameLabel.translatesAutoresizingMaskIntoConstraints = false
        accountNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        return accountNameLabel
    }()
    
    private lazy var accountAddressLabel = {
        let accountAddressLabel = UILabel()
        accountAddressLabel.translatesAutoresizingMaskIntoConstraints = false
        accountAddressLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        return accountAddressLabel
    }()
    
    private var rightArrow: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "RightArrowIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var activeWalletView = {
        let v = WHighlightView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(accountIconView)
        v.addSubview(accountNameLabel)
        v.addSubview(accountAddressLabel)
        v.addSubview(rightArrow)
        NSLayoutConstraint.activate([
            accountIconView.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            accountIconView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            accountNameLabel.leadingAnchor.constraint(equalTo: accountIconView.trailingAnchor, constant: 12),
            accountNameLabel.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            accountAddressLabel.leadingAnchor.constraint(equalTo: accountIconView.trailingAnchor, constant: 12),
            accountAddressLabel.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            rightArrow.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16),
            rightArrow.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])
        v.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(chooseWalletPressed)))
        return v
    }()
    
    private lazy var connectButton = {
        let btn = WButton(style: .primary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle(lang("Connect Wallet"), for: .normal)
        btn.addTarget(self, action: #selector(connectPressed), for: .touchUpInside)
        return btn
    }()
    
    private lazy var contentView = {
        var constraints = [NSLayoutConstraint]()
        
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        
        v.addSubview(appIconView)
        constraints.append(contentsOf: [
            appIconView.widthAnchor.constraint(equalToConstant: 64),
            appIconView.heightAnchor.constraint(equalToConstant: 64),
            appIconView.topAnchor.constraint(equalTo: v.topAnchor, constant: 48),
            appIconView.centerXAnchor.constraint(equalTo: v.centerXAnchor)
        ])
        
        v.addSubview(titleLabel)
        constraints.append(contentsOf: [
            titleLabel.topAnchor.constraint(equalTo: appIconView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 35),
            titleLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -35),
        ])
        
        v.addSubview(subtitleLabel)
        constraints.append(contentsOf: [
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 35),
            subtitleLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -35),
        ])
        
        v.addSubview(hintLabel)
        constraints.append(contentsOf: [
            hintLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 35),
            hintLabel.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -35),
        ])
        
        v.addSubview(activeWalletView)
        constraints.append(contentsOf: [
            activeWalletView.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 12),
            activeWalletView.heightAnchor.constraint(equalToConstant: 56),
            activeWalletView.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            activeWalletView.trailingAnchor.constraint(equalTo: v.trailingAnchor)
        ])
        
        v.addSubview(connectButton)
        constraints.append(contentsOf: [
            connectButton.topAnchor.constraint(equalTo: activeWalletView.bottomAnchor, constant: 16),
            connectButton.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -16),
            connectButton.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16),
            connectButton.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16)
        ])
        
        NSLayoutConstraint.activate(constraints)
        
        return v
    }()
    
    private func setupViews() {
        var constraints = [NSLayoutConstraint]()
        
        addNavigationBar(title: nil, subtitle: nil, closeIcon: true)
        
        view.addSubview(contentView)
        let contentToBottomConstraint = contentView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        contentToBottomConstraint.priority = UILayoutPriority(500)
        constraints.append(contentsOf: [
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentToBottomConstraint,
            contentView.leftAnchor.constraint(equalTo: view.leftAnchor),
            contentView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
        
        NSLayoutConstraint.activate(constraints)
                
        bringNavigationBarToFront()
        
        updateAccountView()
        
        updateDappViews()
        
        reportHeight()
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        hostingController?.view.alpha = request != nil ? 0 : 1
        contentView.alpha = request != nil ? 1 : 0
        
        updateTheme()
    }
    
    private func makeView() -> ConnectDappViewOrPlaceholder {
        if let request {
            return ConnectDappViewOrPlaceholder(content: .connectDapp(ConnectDappView()))
        } else {
            let account = placeholderAccountId.flatMap { AccountStore.accountsById[$0] }
            return ConnectDappViewOrPlaceholder(content: .placeholder(TonConnectPlaceholder(
                account: account,
                connectionType: .connect,
                navigationBarInset: navigationBarHeight
            )))
        }
    }
    
    private func updateDappViews() {
        if let request {
            titleLabel.text = request.dapp.name
            if let url = URL(string: request.dapp.url) {
                subtitleLabel.text = url.host(percentEncoded: false)
            }
            if let imageUrl = URL(string: request.dapp.iconUrl) {
                appIconView.kf.setImage(with: imageUrl)
            }
        } else {
            titleLabel.text = "Placeholder"
            subtitleLabel.text = "placeholder"
        }
    }
    
    func reportHeight() {
        view.layoutIfNeeded()
        sheetHeight = contentView.frame.height + view.safeAreaInsets.bottom + 34
        UIView.animate(withDuration: 0.3) { [weak self] in
            guard let self else {return}
            sheetPresentationController?.animateChanges {
                self.sheetPresentationController?.detents = [
                    .custom(resolver: { [weak self] context in
                        return self?.sheetHeight ?? 0
                    })
                ]
            }
        }
    }
    
    private func updateAccountView() {
        let selectedAccount = selectedAccount
        accountIconView.config(with: selectedAccount, showIcon: true)
        accountNameLabel.text = selectedAccount?.displayName
        accountAddressLabel.attributedText = formatAddressAttributed(selectedAccount?.tonAddress ?? "", startEnd: true)
    }
    
    public override func updateTheme() {
        contentView.backgroundColor = WTheme.modularBackground
        subtitleLabel.textColor = WTheme.tint
        accountAddressLabel.textColor = WTheme.secondaryLabel
        activeWalletView.backgroundColor = WTheme.modularBackground
        activeWalletView.highlightBackgroundColor = WTheme.highlight
        if WTheme.tint == .label {
            subtitleLabel.textColor = WTheme.backgroundReverse
        } else {
            subtitleLabel.textColor = WTheme.tint
        }
    }
    
    @objc func chooseWalletPressed() {
        guard let request else { return }
        var hint = "\(lang("Choose Wallet to Use On")) \(URL(string: request.dapp.url)?.host ?? "")"
        if !IOS_26_MODE_ENABLED {
            hint = hint.uppercased()
        }
        present(ChooseWalletVC(hint: hint,
                               selectedAccountId: selectedAccount?.id ?? "",
                               isModal: true,
                               onSelect: { [weak self] newAccount in
            guard let self else { return }
            Task { @MainActor in
                do {
                    _ = try await AccountStore.activateAccount(accountId: newAccount.id)
                    self.selectedAccount = AccountStore.account
                    self.updateAccountView()
                } catch {
                    topViewController()?.showAlert(error: error)
                }
            }
        }), animated: true)
    }
    
    @objc private func connectPressed() {
        if AccountStore.account?.isHardware == true {
            Task {
                await confirmLedger()
            }
        } else {
            confirmMnemonic()
        }
    }
    
    private func confirmMnemonic() {
        guard let request else { return }
        UnlockVC.presentAuth(on: self,
                             title: lang("Confirm Connect"),
                             subtitle: URL(string: request.dapp.url)?.host, onDone: { [weak self] passcode in
            guard let self, let passcode, let onConfirm else {
                return
            }
            didConfirm = true
            onConfirm(selectedAccount?.id ?? "", passcode)
            self.presentingViewController?.dismiss(animated: true)
        }, cancellable: true)
    }
    
    private func confirmLedger() async {
        guard
            let account = AccountStore.account,
            let fromAddress = account.tonAddress?.nilIfEmpty,
            let request,
            let onConfirm
        else { return }
        
        let signModel = await LedgerSignModel(
            accountId: account.id,
            fromAddress: fromAddress,
            signData: .signLedgerProof(
                promiseId: request.promiseId,
                proof: request.proof
            )
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: EmptyView()
        )
        vc.onDone = { vc in
            self.didConfirm = true
            onConfirm(self.selectedAccount?.id ?? "", "")
            self.dismiss(animated: true, completion: {
                self.presentingViewController?.dismiss(animated: true)
            })
        }
        vc.onCancel = { vc in
            self.dismiss(animated: true, completion: {
                self.presentingViewController?.dismiss(animated: true)
            })
        }
        present(vc, animated: true)
    }
    
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if !didConfirm {
            onCancel?()
        }
    }
}
