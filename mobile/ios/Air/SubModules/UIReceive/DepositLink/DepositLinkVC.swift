//
//  DepositLinkVC.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

final class DepositLinkVC: WViewController {
    
    var hostingController: UIHostingController<DepositLinkView>?
    private let accountContext: AccountContext
    private let chain: ApiChain
    
    init(accountContext: AccountContext, chain: ApiChain) {
        self.accountContext = accountContext
        self.chain = chain
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .air.sheetBackground
        
        navigationItem.title = lang("Deposit Link")
        addCloseNavigationItemIfNeeded()
        
        let hostingController = addHostingController(
            DepositLinkView(accountContext: accountContext, nativeToken: chain.nativeToken),
            constraints: .fill
        )
        self.hostingController = hostingController
    }
}
