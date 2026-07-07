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
import Ledger

public final class AccountTypePickerVC: CreateWalletBaseVC {
    
    private let network: ApiNetwork
    
    private var hostingController: UIHostingController<AccountTypePickerView>?
    private let navHeight: CGFloat = 60
    private let navHeader = NavigationHeader2()
    private var vcSwitchingInProgress = false
    
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
            onHeightChange: { [weak self] height in self?.onHeightChange(height) },
            onViewAddress: { [weak self] in self?.openAddViewWallet() },
            onLedger: { [weak self] in self?.openAddLedgerWallet() }
        )
    }
    
    private func onHeightChange(_ height: CGFloat) {
        let size = CGSize(width: maxContentWidth ?? 560, height: height)
        preferredContentSize = size
        navigationController?.preferredContentSize = size
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .content, resolver: { [navHeight] _ in height + navHeight })]
        }
    }

    private func replaceContent(with vc: UIViewController, newTitle: String?, completion: (() -> Void)? = nil) {
        let coordinator = ContentReplaceAnimationCoordinator()
        guard coordinator.replaceContentInPresentedSheet(self, with: vc, completion: completion) else {
            vcSwitchingInProgress = false
            return 
        }
        navHeader.setTitleAnimated(newTitle ?? "")
    }
    
    private func openAddLedgerWallet() {
        guard !vcSwitchingInProgress else { return }
        vcSwitchingInProgress = true

        Task { @MainActor in
            let introModel = IntroModel(network: network, password: nil)
            let model = await LedgerAddAccountModel()
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
        
        let vc = AddViewWalletVC(introModel: IntroModel(network: network, password: nil))
        replaceContent(with: vc, newTitle: nil)
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
