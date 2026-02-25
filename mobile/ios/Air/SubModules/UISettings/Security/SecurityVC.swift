
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletContext

private let log = Log("SecurityVC")


@MainActor
internal class SecurityVC: SettingsBaseVC {
    
    var hostingController: UIHostingController<SecurityView>? = nil
    var password: String
    
    init(password: String) {
        self.password = password
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        
        navigationItem.title = lang("Security")
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    func makeView() -> SecurityView {
        return SecurityView(
            password: password,
        )
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
}
