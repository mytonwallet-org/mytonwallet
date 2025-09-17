
import UIKit
import SwiftUI
import UIPasscode
import UIComponents
import WalletCore
import WalletContext


public class AddViewWalletVC: WViewController {

    private let introModel: IntroModel
    
    private var hostingController: UIHostingController<AddViewWalletView>?
    private var value: String = ""
    
    public init(introModel: IntroModel) {
        self.introModel = introModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        super.loadView()
        setupViews()
    }

    func setupViews() {
        addNavigationBar(
            title: "",
            closeIcon: AccountStore.accountsById.count > 0,
            addBackButton: (navigationController?.viewControllers.count ?? 1) > 1 ? { [weak self] in
                guard let self else {return}
                navigationController?.popViewController(animated: true)
            } : nil)

        let hc = addHostingController(makeView(), constraints: .fill)
        self.hostingController = hc
        
        bringNavigationBarToFront()

        updateTheme()
    }
    
    func makeView() -> AddViewWalletView {
        AddViewWalletView(introModel: introModel)
    }
    
    public override func updateTheme() {
    }
}


#if DEBUG
@available(iOS 18.0, *)
#Preview {
    let introModel = IntroModel(password: nil)
    AddViewWalletVC(introModel: introModel)
}
#endif

