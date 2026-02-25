import UIKit
import SwiftUI
import WalletContext
import WalletCore
import UIComponents

public final class ImportExistingPickerVC: CreateWalletBaseVC {
    
    let introModel: IntroModel

    var hostingController: UIHostingController<ImportExistingPickerView>?
    private let navHeight: CGFloat = 60

    public init(introModel: IntroModel) {
        self.introModel = introModel
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        addNavigationBar(
            navHeight: navHeight,
            title: lang("Import Wallet"),
            closeIcon: true,
        )
        
        hostingController = addHostingController(makeView(), constraints: .fillWithNavigationBar)
        
        updateTheme()
    }
    
    func makeView() -> ImportExistingPickerView {
        ImportExistingPickerView(
            introModel: introModel,
            onHeightChange: { [weak self] height in self?.onHeightChange(height) }
        )
    }
    
    public override func updateTheme() {
        super.updateTheme()
        view.backgroundColor = WTheme.sheetBackground
    }
    
    func onHeightChange(_ height: CGFloat) {
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom(identifier: .content, resolver: { [navHeight] _ in height + navHeight })]
        }
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    static let content = UISheetPresentationController.Detent.Identifier("content")
}

#if DEBUG
@available(iOS 18, *)
#Preview {
    AccountTypePickerVC(
        network: .mainnet, 
        showCreateWallet: true,
        showSwitchToOtherVersion: true
    )
}
#endif
