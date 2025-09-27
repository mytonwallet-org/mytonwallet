
import UIComponents
import WalletContext
import WalletCore
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
        
        addNavigationBar(
            title: lang("Select Ledger Wallets"),
            subtitle: "",
            closeIcon: self.navigationController?.sheetPresentationController != nil,
        )
        self.navigationBar?.subtitleLabel?.text = lang("$n_wallets_selected", arg1: model.selectedCount)
        self.navigationBar?.subtitleLabel?.isHidden = !model.canContinue
        
        
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    private func makeView() -> LedgerSelectWalletsView {
        LedgerSelectWalletsView(
            model: self.model,
            navigationBarHeight: navigationBarHeight,
            onScroll: weakifyUpdateProgressiveBlur(),
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
