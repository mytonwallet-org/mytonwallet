//
//  AccountTypePickerVC.swift
//  AirAsFramework
//
//  Created by nikstar on 25.08.2025.
//

import UIKit
import SwiftUI
import WalletContext
import WalletCore
import UIComponents

public final class AccountTypePickerVC: CreateWalletBaseVC {
    
    var network: ApiNetwork
    var showCreateWallet: Bool
    var showSwitchToOtherVersion: Bool
    
    var hostingController: UIHostingController<AccountTypePickerView>?
    private let navHeight: CGFloat = 60

    public init(
        network: ApiNetwork,
        showCreateWallet: Bool,
        showSwitchToOtherVersion: Bool,
    ) {
        self.network = network
        self.showCreateWallet = showCreateWallet
        self.showSwitchToOtherVersion = showSwitchToOtherVersion
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let title = showCreateWallet ? lang("Add Wallet") : lang("Import Wallet")
        navigationItem.title = title
        addCloseNavigationItemIfNeeded()
        
        hostingController = addHostingController(makeView(), constraints: .fillWithNavigationBar)

        configureSheetWithOpaqueBackground(color: WTheme.sheetBackground)
        view.backgroundColor = WTheme.sheetBackground
    }
    
    func makeView() -> AccountTypePickerView {
        AccountTypePickerView(
            network: network,
            showCreateWallet: showCreateWallet,
            showSwitchToOtherVersionIfAvailable: showSwitchToOtherVersion,
            onHeightChange: { [weak self] height in self?.onHeightChange(height) }
        )
    }
    
    func onHeightChange(_ height: CGFloat) {
        let size = CGSize(width: maxContentWidth ?? 560, height: height)
        preferredContentSize = size
        navigationController?.preferredContentSize = size
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .content, resolver: { _ in height + self.navHeight })]
        }
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    AccountTypePickerVC(
        network: .mainnet,
        showCreateWallet: true,
        showSwitchToOtherVersion: true
    )
}
#endif
