
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext

private let log = Log("NotificationsSettingsVC")

final class NotificationsSettingsVC: WViewController {
    
    var hostingController: UIHostingController<NotificationsSettingsView>?
    let viewModel = NotificationsSettingsViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addNavigationBar(
            title: lang("Notifications & Sounds"),
            addBackButton: weakifyGoBack(),
        )
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    func makeView() -> NotificationsSettingsView {
        NotificationsSettingsView(
            viewModel: viewModel,
            navigationBarHeight: navigationBarHeight,
            onScroll: weakifyUpdateProgressiveBlur(),
        )
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.groupedBackground
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    NotificationsSettingsVC()
}
#endif
