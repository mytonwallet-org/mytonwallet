import Foundation
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

final class CrosschainFromWalletVC: WViewController, WalletCoreData.EventsObserver {
    
    private let model: CrosschainFromWalletModel
    private var awaitingActivity = false
    private var accountId: String?
    
    private var hostingController: UIHostingController<CrosschainFromWalletView>?
    
    init(
        sellingToken: TokenAmount,
        buyingToken: TokenAmount,
        swapFee: MDouble,
        networkFee: MDouble,
        accountContext: AccountContext
    ) {
        self.model = CrosschainFromWalletModel(
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            swapFee: swapFee,
            networkFee: networkFee,
            accountContext: accountContext
        )
        self.accountId = accountContext.accountId
        super.init(nibName: nil, bundle: nil)
        WalletCoreData.add(eventObserver: self)
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
        
        var failureError: BridgeCallError? = nil
        
        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: model.sellingToken,
            toAmount: model.buyingToken
        ))
        headerVC.view.backgroundColor = .clear
        
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else { return }
                awaitingActivity = true
                Task {
                    do {
                        try await self.model.performSwap(passcode: passcode)
                    } catch {
                        failureError = error as? BridgeCallError
                    }
                    onTaskDone()
                }
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                guard failureError == nil else {
                    awaitingActivity = false
                    showAlert(error: failureError!)
                    return
                }
            }
        )
    }
}

extension CrosschainFromWalletVC {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update):
            handleNewActivities(accountId: update.accountId, activities: update.activities)
        case .newActivities(let update):
            handleNewActivities(accountId: update.accountId, activities: update.activities)
        default:
            break
        }
    }
    
    private func handleNewActivities(accountId updateAccountId: String, activities: [ApiActivity]) {
        let expectedAccountId = accountId ?? AccountStore.accountId
        guard awaitingActivity, updateAccountId == expectedAccountId else { return }
        guard let activity = activities.first(where: { activity in
            if case .swap = activity {
                return true
            }
            return false
        }) ?? activities.first else { return }
        awaitingActivity = false
        AppActions.showActivityDetails(accountId: updateAccountId, activity: activity, context: .swapConfirmation)
    }
}
