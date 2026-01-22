//
//  CrossChainSwapVC.swift
//  UISwap
//
//  Created by Sina on 5/11/24.
//

import Foundation
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

public class CrossChainSwapVC: WViewController, WalletCoreData.EventsObserver {

    var crossChainSwapVM: CrossChainSwapVM!
    private var awaitingActivity = false
    private var accountId: String?
    
    public convenience init(swap: ApiSwapActivity, accountId: String?) {
        let account = AccountStore.get(accountIdOrCurrent: accountId)
        let swapType = getSwapType(from: swap.from, to: swap.to, accountChains: account.supportedChains)

        self.init(sellingToken: (swap.fromToken, swap.fromAmountInt64 ?? 0),
                  buyingToken: (swap.toToken, swap.toAmountInt64 ?? 0),
                  swapType: swapType,
                  swapFee: swap.swapFee ?? 0,
                  networkFee: swap.networkFee ?? 0,
                  payinAddress: swap.cex?.payinAddress ?? "",
                  exchangerTxId: swap.cex?.transactionId ?? "",
                  dt: Date(timeIntervalSince1970: TimeInterval(swap.timestamp / 1000)))
        self.accountId = accountId
    }
    
    init(sellingToken: (ApiToken?, BigInt),
                buyingToken: (ApiToken?, BigInt),
                swapType: SwapType,
                swapFee: MDouble,
                networkFee: MDouble,
                // payin address for cex to ton swaps
                payinAddress: String,
                exchangerTxId: String,
                dt: Date?) {
        super.init(nibName: nil, bundle: nil)
        crossChainSwapVM = CrossChainSwapVM(
            sellingToken: sellingToken,
            buyingToken: buyingToken,
            swapType: swapType,
            swapFee: swapFee,
            networkFee: networkFee,
            payinAddress: payinAddress,
            exchangerTxId: exchangerTxId,
            dt: dt
        )
        accountId = AccountStore.accountId
        WalletCoreData.add(eventObserver: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        
        // observe keyboard events
        WKeyboardObserver.observeKeyboard(delegate: self)
    }

    // top views
    private var overviewVC: UIHostingController<SwapOverviewView>?
    private var continueButton = WButton(style: .primary)
    private var mainContainerBottomConstraint: NSLayoutConstraint!
    
    // cross-chain detail views
    private var crossChainFromTonView: CrossChainFromTonView? = nil
    private var crossChainToTonVC: UIHostingController<CrossChainToTonView>? = nil

    private func setupViews() {
        navigationItem.hidesBackButton = true

        title = crossChainSwapVM.swapType == .crosschainToWallet ? lang("Swapping") : lang("Swap") 
        let subtitle: String? = crossChainSwapVM.swapType == .crosschainToWallet ? lang("Waiting for Payment").lowercased() : nil
        addNavigationBar(
            centerYOffset: crossChainSwapVM.swapType == .crosschainToWallet ? 0 : 1,
            title: title,
            subtitle: subtitle,
            closeIcon: true
        )

        // MARK: Main container
        let mainContainerView = UIView()
        mainContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainContainerView)
        mainContainerBottomConstraint = mainContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            mainContainerView.topAnchor.constraint(equalTo: navigationBarAnchor),
            mainContainerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            mainContainerView.rightAnchor.constraint(equalTo: view.rightAnchor),
            mainContainerBottomConstraint
        ])
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        mainContainerView.addGestureRecognizer(tapGestureRecognizer)
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        mainContainerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: mainContainerView.topAnchor),
            scrollView.leftAnchor.constraint(equalTo: mainContainerView.leftAnchor),
            scrollView.rightAnchor.constraint(equalTo: mainContainerView.rightAnchor),
            scrollView.bottomAnchor.constraint(equalTo: mainContainerView.bottomAnchor)
        ])
        
        // MARK: Swap token selectors
        let headerVC = UIHostingController(
            rootView: SwapOverviewView(
                fromAmount: crossChainSwapVM.sellingToken.1,
                fromToken: crossChainSwapVM.sellingToken.0!,
                toAmount: crossChainSwapVM.buyingToken.1,
                toToken: crossChainSwapVM.buyingToken.0!
            )
        )
        self.overviewVC = headerVC
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
        
        // MARK: CrossChain FromTon View
        switch crossChainSwapVM.swapType {
        case .onChain, .crosschainInsideWallet:
            break
            
        case .crosschainFromWallet:
            crossChainFromTonView = CrossChainFromTonView(buyingToken: crossChainSwapVM.buyingToken.0!,
                                                          onAddressChanged: { [weak self] address in
                guard let self else { return }
                crossChainSwapVM.addressInputString = address
                continueButton.isEnabled = !address.isEmpty
            })
            scrollView.addSubview(crossChainFromTonView!)
            NSLayoutConstraint.activate([
                crossChainFromTonView!.topAnchor.constraint(equalTo: headerVC.view.bottomAnchor, constant: 36),
                crossChainFromTonView!.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32),
                crossChainFromTonView!.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
                crossChainFromTonView!.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -74)
            ])
            // MARK: Continue button
            continueButton.translatesAutoresizingMaskIntoConstraints = false
            continueButton.isEnabled = false
            continueButton.configureTitle(sellingToken: crossChainSwapVM.sellingToken.0!, buyingToken: crossChainSwapVM.buyingToken.0!)
            continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
            
            mainContainerView.addSubview(continueButton)
            NSLayoutConstraint.activate([
                continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                       constant: -16),
                continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
            ])

        case .crosschainToWallet:
            let toTonVC = UIHostingController(rootView: CrossChainToTonView(
                sellingToken: crossChainSwapVM.sellingToken.0!,
                amount: crossChainSwapVM.sellingToken.1.doubleAbsRepresentation(decimals: crossChainSwapVM.sellingToken.0!.decimals),
                address: crossChainSwapVM.payinAddress ?? "",
                dt: crossChainSwapVM.dt ?? Date(),
                exchangerTxId: crossChainSwapVM.exchangerTxId ?? ""
            ))
            self.crossChainToTonVC = toTonVC
            addChild(toTonVC)
            let toTonView: UIView = toTonVC.view
            toTonView.backgroundColor = .clear
            toTonView.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(toTonView)
            NSLayoutConstraint.activate([
                toTonView.topAnchor.constraint(equalTo: headerVC.view.bottomAnchor, constant: 32),
                toTonView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                toTonView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                toTonView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                toTonView.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16)
            ])
            toTonVC.didMove(toParent: self)
        }
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    @objc func containerPressed() {
        view.endEditing(true)
    }
    
    @objc func continuePressed() {
        view.endEditing(true)

        var failureError: BridgeCallError? = nil
        
        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: crossChainSwapVM.sellingToken.1,
            fromToken: crossChainSwapVM.sellingToken.0!,
            toAmount: crossChainSwapVM.buyingToken.1,
            toToken: crossChainSwapVM.buyingToken.0!
        ))
        headerVC.view.backgroundColor = .clear

        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else {return}
                awaitingActivity = true
                crossChainSwapVM.cexFromTonSwap(toAddress: crossChainSwapVM.addressInputString,
                                                passcode: passcode,
                                                onTaskDone: { err in
                    failureError = err as? BridgeCallError
                    onTaskDone()
                })
            },
            onDone: { [weak self] _ in
                guard let self else {return}
                guard failureError == nil else {
                    awaitingActivity = false
                    showAlert(error: failureError!)
                    return
                }
            })
    }

}

extension CrossChainSwapVC {
    public func walletCore(event: WalletCoreData.Event) {
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

extension CrossChainSwapVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) {
            self.mainContainerBottomConstraint.constant = -info.height
            self.view.layoutIfNeeded()
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) {
            self.mainContainerBottomConstraint.constant = 0
            self.view.layoutIfNeeded()
        }
    }
}
