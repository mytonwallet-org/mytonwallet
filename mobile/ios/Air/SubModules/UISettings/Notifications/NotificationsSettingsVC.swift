
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext

private let log = Log("NotificationsSettingsVC")

final class NotificationsSettingsVC: SettingsBaseVC {
    
    var hostingController: UIHostingController<NotificationsSettingsView>?
    let viewModel = NotificationsSettingsViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = lang("Notifications & Sounds")
        
        hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    func makeView() -> NotificationsSettingsView {
        NotificationsSettingsView(
            viewModel: viewModel,
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
