
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

private let log = Log("SecurityVC")


@MainActor
internal class SecurityVC: WViewController, Sendable {
    
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
        
        addNavigationBar(title: lang("Security"), addBackButton: { [weak self] in self?.navigationController?.popViewController(animated: true) })
        navigationBarProgressiveBlurDelta = 10
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)

        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    func makeView() -> SecurityView {
        return SecurityView(
            password: password,
            navigationBarInset: navigationBarHeight,
            onScroll: { [weak self] y in self?.updateNavigationBarProgressiveBlur(y) }
        )
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
}
