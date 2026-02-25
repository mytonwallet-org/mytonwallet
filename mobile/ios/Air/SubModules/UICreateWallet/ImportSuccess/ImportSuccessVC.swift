//
//  ImportSuccessVC.swift
//  UICreateWallet
//
//  Created by Sina on 4/21/23.
//

import SwiftUI
import UIKit
import WalletContext
import UIPasscode
import UIComponents

public enum SuccessKind {
    case created
    case imported
    case importedView
}

public class ImportSuccessVC: CreateWalletBaseVC {
    
    var introModel: IntroModel
    private let successKind: SuccessKind
    
    public init(_ successKind: SuccessKind, introModel: IntroModel) {
        self.introModel = introModel
        self.successKind = successKind
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private var hostingController: UIHostingController<ImportSuccessView>!
    
    func setupViews() {
        
        addNavigationBar(
            closeIcon: false,
        )
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
    }
    
    private func makeView() -> ImportSuccessView {
        ImportSuccessView(introModel: introModel, successKind: successKind)
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    LocalizationSupport.shared.setLanguageCode("ru")
    return UINavigationController(rootViewController: ImportSuccessVC(.imported, introModel: IntroModel(network: .mainnet, password: nil)))
}
#endif
