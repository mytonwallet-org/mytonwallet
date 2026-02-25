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

public final class AboutVC: SettingsBaseVC {
    
    let showLegalSection: Bool
    private var hostingController: UIHostingController<AboutView>!
    
    public init(showLegalSection: Bool) {
        self.showLegalSection = showLegalSection
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
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
        AboutView(showLegalSection: showLegalSection)
    }
    
    override public func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


@available(iOS 18, *)
#Preview {
    AboutVC(showLegalSection: true)
}
