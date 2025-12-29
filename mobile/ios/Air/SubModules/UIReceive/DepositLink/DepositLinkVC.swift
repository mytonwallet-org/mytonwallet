//
//  DepositLinkVC.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext

final class DepositLinkVC: WViewController {
    
    var hostingController: UIHostingController<DepositLinkView>?
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = WTheme.sheetBackground
        
        navigationItem.title = lang("Deposit Link")
        addCloseNavigationItemIfNeeded()
        
        let hostingController = addHostingController(DepositLinkView(), constraints: .fill)
        self.hostingController = hostingController
        
        bringNavigationBarToFront()
    }
}
