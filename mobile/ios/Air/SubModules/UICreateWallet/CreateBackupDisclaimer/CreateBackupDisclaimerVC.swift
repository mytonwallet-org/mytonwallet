//
//  CreateBackupDisclaimerVC.swift
//  UICreateWallet
//
//  Created by nikstar on 05.09.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext

final class CreateBackupDisclaimerVC: CreateWalletBaseVC {
    
    let introModel: IntroModel

    private var hostingController: UIHostingController<CreateBackupDisclaimerView>!
    
    init(introModel: IntroModel) {
        self.introModel = introModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    private func makeView() -> CreateBackupDisclaimerView {
        CreateBackupDisclaimerView(
            introModel: introModel,
        )
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


@available(iOS 18, *)
#Preview {
    LocalizationSupport.shared.setLanguageCode("ru")
    return CreateBackupDisclaimerVC(introModel: IntroModel(network: .mainnet, password: nil))
}
