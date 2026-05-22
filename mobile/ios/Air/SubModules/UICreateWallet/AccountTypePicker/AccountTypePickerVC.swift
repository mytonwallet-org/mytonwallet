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
    
    private let network: ApiNetwork
    
    private var hostingController: UIHostingController<AccountTypePickerView>?
    private let navHeight: CGFloat = 60

    public init(network: ApiNetwork) {
        self.network = network
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = network == .testnet ? "\(lang("Add Wallet")) (Testnet)" : lang("Add Wallet")
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
            onHeightChange: { [weak self] height in self?.onHeightChange(height) }
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
