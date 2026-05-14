import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

final class CrosschainFromWalletVC: WViewController {
    
    private let model: CrosschainFromWalletModel
    private let onContinue: (String, UIViewController) -> Void
    
    private var hostingController: UIHostingController<CrosschainFromWalletView>?
    
    init(
        sellingToken: TokenAmount,
        buyingToken: TokenAmount,
        accountContext: AccountContext,
        onContinue: @escaping (String, UIViewController) -> Void
    ) {
        self.model = CrosschainFromWalletModel(
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            accountContext: accountContext
        )
        self.onContinue = onContinue
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }
    
    private func setupViews() {
        navigationItem.hidesBackButton = true
        navigationItem.titleView = HostingView {
            NavigationHeader {
                HStack(spacing: 4) {
                    Text(model.sellingToken.type.symbol)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .semibold))
                    Text(model.buyingToken.type.symbol)
                }
            }
        }
        addCloseNavigationItemIfNeeded()

        hostingController = addHostingController(
            CrosschainFromWalletView(
                model: model,
                onClose: { [weak self] in
                    self?.closePressed()
                },
                onContinue: { [weak self] in
                    self?.continuePressed()
                }
            ),
            constraints: .fill
        )
        
        updateTheme()
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
    }
    
    private func closePressed() {
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    @objc private func continuePressed() {
        view.endEditing(true)
        guard model.canContinue else { return }
        onContinue(model.toAddress, self)
    }
}
