//
//  AppearanceVC.swift
//  UISettings
//
//  Created by Sina on 6/29/24.
//

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext

public final class AppearanceSettingsVC: SettingsBaseVC {
    
    var hostingController: UIHostingController<AppearanceSettingsView>?
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = lang("Appearance")
        
        view.backgroundColor = WTheme.groupedBackground
        
        hostingController = addHostingController(makeView(), constraints: .fill)
    }
    
    func makeView() -> AppearanceSettingsView {
        AppearanceSettingsView()
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    AppearanceSettingsVC()
}
#endif
