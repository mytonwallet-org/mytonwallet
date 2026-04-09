
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext

private let log = Log("NotificationsSettingsVC")

public final class NotificationsSettingsVC: SettingsBaseVC {
    
    var hostingController: UIHostingController<NotificationsSettingsView>?
    let viewModel = NotificationsSettingsViewModel()
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = lang("Notifications & Sounds")
        
        hostingController = addHostingController(makeView(), constraints: .fill)

        updateTheme()
    }
    
    func makeView() -> NotificationsSettingsView {
        NotificationsSettingsView(
            viewModel: viewModel,
        )
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.groupedBackground
    }
}


#if DEBUG
@available(iOS 18, *)
#Preview {
    NotificationsSettingsVC()
}
#endif
