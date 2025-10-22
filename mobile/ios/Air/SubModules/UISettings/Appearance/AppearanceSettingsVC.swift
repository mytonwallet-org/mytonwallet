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

final class AppearanceSettingsVC: WViewController {
    
    var hostingController: UIHostingController<AppearanceSettingsView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addNavigationBar(
            title: lang("Appearance"),
            addBackButton: weakifyGoBack(),
        )
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    func makeView() -> AppearanceSettingsView {
        AppearanceSettingsView(
            navigationBarHeight: navigationBarHeight,
            onScroll: weakifyUpdateProgressiveBlur(),
            tintColor: Color.air.tint,
        )
    }
    
    override func updateTheme() {
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
