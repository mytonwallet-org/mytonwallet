
import SwiftUI
import UIKit
import UIComponents
import WalletContext

@MainActor
internal class SecurityVC: SettingsBaseVC {
    
    var hostingController: UIHostingController<SecurityView>? = nil

    init() {
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
        return SecurityView()
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
}
