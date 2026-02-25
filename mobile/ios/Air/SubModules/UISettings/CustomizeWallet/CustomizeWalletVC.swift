//
//  WalletSettingsVC.swift
//  UISettings
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

public final class CustomizeWalletVC: SettingsBaseVC {
    
    let viewModel: CustomizeWalletViewModel
    var hostingController: UIHostingController<CustomizeWalletView>?
    
    public init(accountId: String?) {
        self.viewModel = CustomizeWalletViewModel(initialAccountId: accountId)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = lang("Customize Wallet")
        addCloseNavigationItemIfNeeded()
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        hostingController?.view.backgroundColor = isPresentationModal ? WTheme.sheetBackground : WTheme.groupedBackground
    }
    
    func makeView() -> CustomizeWalletView {
        CustomizeWalletView(viewModel: viewModel)
    }
}

@available(iOS 26, *)
#Preview {
    let nc = UINavigationController(rootViewController: CustomizeWalletVC(accountId: nil))
    nc
}
