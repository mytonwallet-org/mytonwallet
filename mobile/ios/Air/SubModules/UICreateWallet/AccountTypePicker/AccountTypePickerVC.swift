//
//  AccountTypePickerVC.swift
//
//  Created by nikstar on 25.08.2025.
//

import UIKit
import SwiftUI
import WalletContext
import WalletCore
import UIComponents
import UIPasscode
import Ledger

public final class AccountTypePickerVC: CreateWalletBaseVC {
    
    private let network: ApiNetwork
    
    private var hostingController: UIHostingController<AccountTypePickerView>?
    private let authorizationState = AccountTypePickerAuthorizationState()
    private let navHeight: CGFloat = 60
    private let navHeader = NavigationHeader2()
    private var vcSwitchingInProgress = false
    private var hasReplacedContent = false
    
    public init(network: ApiNetwork) {
        self.network = network
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navHeader.setTitle(network == .testnet ? "\(lang("Add Wallet")) (Testnet)" : lang("Add Wallet"))
        navigationItem.titleView = navHeader
        
        addCloseNavigationItemIfNeeded()
        
        hostingController = addHostingController(makeView()) { [view] child in
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }

        configureSheetWithOpaqueBackground(color: .air.sheetBackground)
        view.backgroundColor = .air.sheetBackground
    }
    
    private func makeView() -> AccountTypePickerView {
        AccountTypePickerView(
            network: network,
            authorizationState: authorizationState,
            onHeightChange: { [weak self] height in self?.onHeightChange(height) },
            onCreate: { [weak self] in self?.createWallet() },
            onCreateSubwallet: { [weak self] in self?.createSubwallet() },
            onImport: { [weak self] in self?.importWallet() },
            onViewAddress: { [weak self] in self?.openAddViewWallet() },
            onLedger: { [weak self] in self?.openAddLedgerWallet() }
        )
    }

    private func createWallet() {
        authorize(.createWallet) { [weak self] enclaveToken in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let words = try await Api.generateMnemonic()
                    let introModel = IntroModel(
                        network: network,
                        authMode: IntroAuthMode(enclaveToken: enclaveToken),
                        words: words
                    )
                    let addAccountVC = WordDisplayVC(introModel: introModel, wordList: words)
                    let title = localizedIntegerDigits(in: words.count == 24 ? lang("24 Words") : lang("12 Words"))
                    replaceContent(with: addAccountVC, newTitle: title)
                } catch {
                    resetTransitionState()
                    AppActions.showError(error: error)
                }
            }
        }
    }

    private func createSubwallet() {
        authorize(.createSubwallet) { [weak self] enclaveToken in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let enclaveToken else {
                    resetTransitionState()
                    return
                }
                do {
                    let account = try await AccountStore.createSubWallet(enclaveToken: enclaveToken)
                    AppActions.showHome(popToRoot: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        AppActions.showToast(
                            style: .large,
                            icon: .symbolImage("plus"),
                            message: lang("Subwallet Created"),
                            actionTitle: lang("Set Name")
                        ) {
                            AppActions.showRenameAccount(accountId: account.id)
                        }
                    }
                } catch {
                    resetTransitionState()
                    AppActions.showError(error: error)
                }
            }
        }
    }

    private func importWallet() {
        authorize(.importWallet) { [weak self] enclaveToken in
            guard let self else { return }
            let introModel = IntroModel(
                network: network,
                authMode: IntroAuthMode(enclaveToken: enclaveToken)
            )
            let importWalletVC = ImportWalletVC(introModel: introModel)
            replaceContent(with: importWalletVC, newTitle: nil)
        }
    }

    private func authorize(
        _ action: AccountTypePickerAuthorizationAction,
        onDone: @escaping (EnclaveToken?) -> Void
    ) {
        guard !vcSwitchingInProgress, authorizationState.begin(action) else { return }
        vcSwitchingInProgress = true

        UnlockVC.presentAuth(
            on: self,
            tryBiometricsBeforePresentation: true,
            onDone: onDone,
            cancellable: true,
            onCancel: { [weak self] in
                self?.resetTransitionState()
            }
        )
    }
    
    private func onHeightChange(_ height: CGFloat) {
        guard !hasReplacedContent else { return }
        let isPopover = navigationController?.modalPresentationStyle == .popover
        let size = CGSize(width: isPopover ? 400 : 560, height: height)
        preferredContentSize = size
        navigationController?.preferredContentSize = size
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .content, resolver: { [navHeight] _ in height + navHeight })]
        }
    }

    private func replaceContent(with vc: UIViewController, newTitle: String?, completion: (() -> Void)? = nil) {
        guard let navigationController else {
            resetTransitionState()
            return
        }
        let preferredSize = CGSize(width: 640, height: 900)
        if navigationController.modalPresentationStyle == .popover {
            guard let presenter = navigationController.presentingViewController else {
                resetTransitionState()
                return
            }
            let flow = WNavigationController(rootViewController: vc)
            flow.modalPresentationStyle = .formSheet
            flow.preferredContentSize = preferredSize
            flow.sheetPresentationController?.detents = [.large()]
            vc.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak flow] _ in
                flow?.dismiss(animated: true)
            })
            navigationController.dismiss(animated: true) {
                presenter.present(flow, animated: true, completion: completion)
            }
            return
        }

        hasReplacedContent = true
        preferredContentSize = preferredSize
        navigationController.preferredContentSize = preferredSize
        let coordinator = ContentReplaceAnimationCoordinator()
        guard coordinator.replaceContentInPresentedSheet(self, with: vc, completion: completion) else {
            hasReplacedContent = false
            resetTransitionState()
            return 
        }
        navHeader.setTitleAnimated(newTitle ?? "")
    }
    
    private func openAddLedgerWallet() {
        guard !vcSwitchingInProgress else { return }
        vcSwitchingInProgress = true

        Task { @MainActor in
            let introModel = IntroModel(network: network, authMode: .requiresPasscodeSetup)
            let model = LedgerAddAccountModel()
            let importWalletVC = LedgerAddAccountVC(model: model, autoStart: false)
            let hadExistingAccounts = !AccountStore.accountsById.isEmpty
            importWalletVC.onDone = { _ in
                introModel.onDone(
                    successKind: .imported,
                    hadExistingAccounts: hadExistingAccounts,
                    accountIds: model.importedAccountIds
                )
            }
            replaceContent(with: importWalletVC, newTitle: importWalletVC.title) {
                importWalletVC.start()
            }
        }
    }
    
    private func openAddViewWallet() {
        guard !vcSwitchingInProgress else { return }
        vcSwitchingInProgress = true
        
        let vc = AddViewWalletVC(introModel: IntroModel(network: network, authMode: .requiresPasscodeSetup))
        replaceContent(with: vc, newTitle: nil)
    }

    private func resetTransitionState() {
        vcSwitchingInProgress = false
        authorizationState.reset()
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    AccountTypePickerVC(network: .mainnet)
}
#endif
