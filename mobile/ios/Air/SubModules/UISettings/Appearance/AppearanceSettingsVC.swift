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

private let log = Log("AppearanceSettingsVC")

public final class AppearanceSettingsVC: WViewController {
    
    var hostingController: UIHostingController<AppearanceSettingsView>?
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = lang("Appearance")
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    func makeView() -> AppearanceSettingsView {
        AppearanceSettingsView(
            tintColor: Color.air.tint,
        )
    }
    
    public  override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
        withAnimation {
            hostingController?.rootView = makeView()
        }
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    AppearanceSettingsVC()
}
#endif
