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

public final class UseResponsiblyVC: SettingsBaseVC {
    
    private var hostingController: UIHostingController<UseResponsiblyView>!
    
    public init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    private func makeView() -> UseResponsiblyView {
        UseResponsiblyView()
    }
    
    override public func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


@available(iOS 18, *)
#Preview {
    UseResponsiblyVC()
}
