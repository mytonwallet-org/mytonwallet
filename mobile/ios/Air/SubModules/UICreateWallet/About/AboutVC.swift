//
//  AboutVC.swift
//  UICreateWallet
//
//  Created by nikstar on 05.09.2025.
//

import UIKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

final class AboutVC: WViewController {
    
    let introModel: IntroModel
    
    private var hostingController: UIHostingController<AboutView>!
    
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
        
        addNavigationBar(
            addBackButton: { topWViewController()?.navigationController?.popViewController(animated: true) }
        )
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    private func makeView() -> AboutView {
        AboutView()
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


@available(iOS 18, *)
#Preview {
    AboutVC(introModel: IntroModel(password: nil))
}
