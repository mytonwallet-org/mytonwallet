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
    
    private var overviewVC: UIHostingController<SwapOverviewView>?
    private var continueButton = WButton(style: .primary)
    private var crosschainFromWalletView: CrosschainFromWalletView!
    
    init(
        sellingToken: TokenAmount,
        buyingToken: TokenAmount,
        swapFee: MDouble,
        networkFee: MDouble
    ) {
        self.model = CrosschainFromWalletModel(
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            swapFee: swapFee,
            networkFee: networkFee
        )
        self.accountId = AccountStore.accountId
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
        navigationItem.title = lang("Swap")
        addCloseNavigationItemIfNeeded()
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(tapGestureRecognizer)

        let headerVC = UIHostingController(
            rootView: SwapOverviewView(
                fromAmount: model.sellingToken,
                toAmount: model.buyingToken
            )
        )
        overviewVC = headerVC
        addChild(headerVC)
        scrollView.addSubview(headerVC.view)
        headerVC.view.backgroundColor = .clear
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerVC.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 28),
            headerVC.view.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            headerVC.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            headerVC.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16)
        ])
        headerVC.didMove(toParent: self)
        
        crosschainFromWalletView = CrosschainFromWalletView(
            buyingToken: model.buyingToken.type,
            onAddressChanged: { [weak self] address in
                guard let self else { return }
                model.addressInputString = address
                continueButton.isEnabled = !address.isEmpty
            }
        )
        scrollView.addSubview(crosschainFromWalletView)
        NSLayoutConstraint.activate([
            crosschainFromWalletView.topAnchor.constraint(equalTo: headerVC.view.bottomAnchor, constant: 36),
            crosschainFromWalletView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
            crosschainFromWalletView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            crosschainFromWalletView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -74)
        ])
        
        continueButton = addBottomButton(bottomConstraint: true)
        continueButton.isEnabled = false
        continueButton.configureTitle(sellingToken: model.sellingToken.type, buyingToken: model.buyingToken.type)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        updateTheme()
    }
    
    override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    @objc private func containerPressed() {
        view.endEditing(true)
    }
    
    @objc private func continuePressed() {
        view.endEditing(true)
        
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
                        try await self.model.performSwap(toAddress: self.model.addressInputString, passcode: passcode)
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
