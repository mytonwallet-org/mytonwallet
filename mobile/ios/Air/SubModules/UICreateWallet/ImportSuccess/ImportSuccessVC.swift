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
    private let importedAccountsCount: Int

    public override var hideNavigationBar: Bool { true }
    
    public init(_ successKind: SuccessKind, introModel: IntroModel, importedAccountsCount: Int) {
        self.introModel = introModel
        self.successKind = successKind
        self.importedAccountsCount = importedAccountsCount
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
        hostingController = addHostingController(makeView(), constraints: .fill)
    }
    
    private func makeView() -> ImportSuccessView {
        ImportSuccessView(
            introModel: introModel,
            successKind: successKind,
            importedAccountsCount: importedAccountsCount
        )
    }
}

#if DEBUG
@available(iOS 18.0, *)
#Preview {
    LocalizationSupport.shared.setLanguageCode("ru")
    return UINavigationController(rootViewController: ImportSuccessVC(.imported, introModel: IntroModel(network: .mainnet, password: nil), importedAccountsCount: 2))
}
#endif
