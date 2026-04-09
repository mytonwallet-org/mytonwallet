
import UIComponents
import WalletContext
import UIKit
import SwiftUI
import Perception


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
        navigationItem.titleView = HostingView {
            LedgerSelectWalletsNavigationHeader(model: model)
        }
        addCloseNavigationItemIfNeeded()
        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        updateTheme()
    }
    
    private func makeView() -> LedgerSelectWalletsView {
        LedgerSelectWalletsView(model: self.model)
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
}

private struct LedgerSelectWalletsNavigationHeader: View {
    var model: LedgerAddAccountModel

    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(lang("Select Ledger Wallets"))
            } subtitle: {
                if model.canContinue {
                    Text(lang("$n_wallets_selected", arg1: model.selectedCount))
                }
            }
        }
    }
}
