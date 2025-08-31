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
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = WTheme.sheetBackground
        
        addNavigationBar(
            title: lang("Deposit Link"),
            closeIcon: true,
            addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) }
        )
        
        let hc = addHostingController(DepositLinkView(
            topPadding: navigationBarHeight,
            onScroll: { [weak self] y in self?.updateNavigationBarProgressiveBlur(y) }
        ), constraints: .fill)
        self.hostingController = hc
        
        bringNavigationBarToFront()
    }
}
