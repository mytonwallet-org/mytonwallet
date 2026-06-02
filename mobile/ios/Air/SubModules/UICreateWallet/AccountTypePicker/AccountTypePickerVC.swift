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
    private var addWalletVC: AddViewWalletVC?
    private var titleLabel: UILabel?

    public init(network: ApiNetwork) {
        self.network = network
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let title = network == .testnet ? "\(lang("Add Wallet")) (Testnet)" : lang("Add Wallet")
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.accessibilityTraits = .header
        titleLabel.sizeToFit()
        navigationItem.titleView = titleLabel
        self.titleLabel = titleLabel
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
            onViewAddress: { [weak self] in self?.openAddViewWallet() }
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

    private func openAddViewWallet() {
        guard addWalletVC == nil else { return }
        
        let vc = AddViewWalletVC(introModel: IntroModel(network: network, password: nil))
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(vc)
        view.addSubview(vc.view)
        vc.didMove(toParent: self)
        addWalletVC = vc
        
        guard let sheet = navigationController?.sheetPresentationController else {
            assertionFailure()
            return
        }
        
        UIView.performWithoutAnimation {
            vc.view.alpha = 0
            vc.view.layoutIfNeeded()
        }
        sheet.animateChanges {
            sheet.detents = [.large()]
            sheet.selectedDetentIdentifier = .large
            vc.view.alpha = 1.0
            self.titleLabel?.alpha = 0
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
