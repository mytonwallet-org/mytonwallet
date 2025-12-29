
import UIComponents
import WalletContext
import UIKit
import SwiftUI


public final class LedgerSelectWalletsVC: WViewController {
    
    var hostingController: UIHostingController<LedgerSelectWalletsView>? = nil
    var model: LedgerAddAccountModel
    
    public init(model: LedgerAddAccountModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        super.loadView()
        setupViews()
    }
    
    private func setupViews() {
        
        navigationItem.title = lang("Select Ledger Wallets")
        addCloseNavigationItemIfNeeded()
        if #available(iOS 26, *) {
            navigationItem.subtitle = ""
        }
        self.navigationBar?.subtitleLabel?.text = lang("%1$d Selected", arg1: model.selectedCount)
        self.navigationBar?.subtitleLabel?.isHidden = !model.canContinue
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    private func makeView() -> LedgerSelectWalletsView {
        LedgerSelectWalletsView(
            model: self.model,
            onWalletsCountChange: { [weak self] count in
                UIView.animate(withDuration: 0.3) {
                    guard let self else { return }
                    let hide = count == 0
                    self.navigationBar?.subtitleLabel?.text = lang("$n_wallets_selected", arg1: self.model.selectedCount)
                    self.navigationBar?.subtitleLabel?.isHidden = hide
                }
            }
        )
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
}
