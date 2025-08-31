//
//  SwapVC.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import Foundation
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

@MainActor
public class SwapVC: WViewController, WSensitiveDataProtocol {

    private var swapVM: SwapVM!
    
    private let defaultSellingToken: String
    private let defaultBuyingToken: String
    private let defaultSellingAmount: Double?
    
    private var tokensSelectorVM: SwapSelectorsVM! = nil
    private var detailsVM: SwapDetailsVM!
    private var hostingController: UIHostingController<SwapView>!

    private var continueButton: WButton { bottomButton! }
    private var continueButtonConstraint: NSLayoutConstraint?
    
    private var startWithKeyboardActive: Bool { true }

    private var enqueueTask: (() -> ())?
    private var updateTask: Task<Void, Never>?

    public init(defaultSellingToken: String? = nil, defaultBuyingToken: String? = nil, defaultSellingAmount: Double? = nil) {
        self.defaultSellingToken = defaultSellingToken ?? TONCOIN_SLUG
        self.defaultBuyingToken = defaultBuyingToken ?? TON_USDT_SLUG
        self.defaultSellingAmount = defaultSellingAmount
        super.init(nibName: nil, bundle: nil)

        let sellingToken = TokenStore.getToken(slugOrAddress: self.defaultSellingToken) ?? TokenStore.tokens[TONCOIN_SLUG]!
        let buyingToken = TokenStore.getToken(slugOrAddress: self.defaultBuyingToken)  ?? TokenStore.tokens[TON_USDT_SLUG]!
        let vm = SwapSelectorsVM(
            sellingAmount: defaultSellingAmount.flatMap { doubleToBigInt($0, decimals: sellingToken.decimals) },
            sellingToken: sellingToken,
            buyingAmount: nil,
            buyingToken: buyingToken,
            maxAmount: BalanceStore.currentAccountBalances[self.defaultSellingToken] ?? 0
        )
        vm.delegate = self
        self.tokensSelectorVM = vm

        self.swapVM = SwapVM(delegate: self, tokensSelector: tokensSelectorVM)
        self.detailsVM = SwapDetailsVM(swapVM: swapVM, tokensSelectorVM: tokensSelectorVM)
        detailsVM.onSlippageChanged = { [weak self] slippage in
            self?.swapVM.updateSlippage(slippage)
        }
        detailsVM.onPreferredDexChanged = { [weak self] pref in
            self?.swapVM.updateDexPreference(pref)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        
        // observe keyboard events
        WKeyboardObserver.observeKeyboard(delegate: self)
        
        Task {
            _ = try? await TokenStore.updateSwapAssets()
        }
    }

    private func setupViews() {
        view.semanticContentAttribute = .forceLeftToRight

        title = lang("Swap")
        addNavigationBar(
            centerYOffset: 1,
            title: title,
            closeIcon: true
        )

        // MARK: Main container
        let mainContainerView = UIView()
        mainContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainContainerView)
        NSLayoutConstraint.activate([
            mainContainerView.topAnchor.constraint(equalTo: navigationBarAnchor),
            mainContainerView.leftAnchor.constraint(equalTo: view.leftAnchor),
            mainContainerView.rightAnchor.constraint(equalTo: view.rightAnchor),
            mainContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        mainContainerView.addGestureRecognizer(tapGestureRecognizer)
        
        self.hostingController = UIHostingController(rootView: makeView())
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        mainContainerView.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: mainContainerView.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: mainContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: mainContainerView.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: mainContainerView.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        
        _ = addBottomButton(bottomConstraint: false)
        continueButton.isEnabled = false
        continueButton.setTitle(lang("Enter Amounts"), for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        let c = startWithKeyboardActive ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    func makeView() -> SwapView {
        return SwapView(
            swapVM: swapVM,
            selectorsVM: tokensSelectorVM,
            detailsVM: detailsVM,
            isSensitiveDataHidden: AppStorageHelper.isSensitiveDataHidden
        )
    }
    
    public func updateSensitiveData() {
        hostingController?.rootView = makeView()
    }
    
    @objc func containerPressed() {
        view.endEditing(true)
    }
    
    @objc func continuePressed() {
        view.endEditing(true)
        
        if let account = AccountStore.account, swapVM.swapType != .inChain, account.supports(chain: self.tokensSelectorVM.sellingToken.chain), account.supports(chain: self.tokensSelectorVM.buyingToken.chain) {
            continueCrossChainImmediate()
        } else {
            switch swapVM.swapType {
            case .inChain:
                continueInChain()
            case .crossChainFromTon:
                continueChainFromTon()
            case .crossChainToTon:
                continueChainToTon()
            @unknown default:
                break
            }
        }
    }
    
    private func continueInChain() {
        guard let swapEstimate = swapVM.swapEstimate, let lateInit = swapVM.lateInit else { return }
        
        if lateInit.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
                return
            }
        }
        
        var failureError: BridgeCallError? = nil    // filled if any error occures

        let fromToken = tokensSelectorVM.sellingToken
        let toToken = tokensSelectorVM.buyingToken
        guard
            let fromAmount = tokensSelectorVM.sellingAmount,
            let toAmount = tokensSelectorVM.buyingAmount
        else {
            return
        }
            
        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: fromAmount,
            fromToken: fromToken,
            toAmount: toAmount,
            toToken: toToken
        ))
        headerVC.view.backgroundColor = .clear
        
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else {return}
                let sellingToken = tokensSelectorVM.sellingToken
                let buyingToken = tokensSelectorVM.buyingToken
                swapVM.swapNow(sellingToken: sellingToken,
                               buyingToken: buyingToken,
                               passcode: passcode, onTaskDone: { _, error in
                    failureError = error
                    onTaskDone()
                })
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                if let failureError {
                    showAlert(error: failureError) { [weak self] in
                        guard let self else { return }
                        dismiss(animated: true)
                    }
                } else {
                    dismiss(animated: true)
                }
            })
    }
    
    private func continueChainFromTon() {
        if let cexEstimate = swapVM.cexEstimate {
            let crossChainSwapVC = CrossChainSwapVC(
                sellingToken: (tokensSelectorVM.sellingToken, tokensSelectorVM.sellingAmount ?? 0),
                buyingToken: (tokensSelectorVM.buyingToken, tokensSelectorVM.buyingAmount ?? 0),
                swapType: swapVM.swapType,
                swapFee: String(cexEstimate.swapFee),
                networkFee: String(0),
                payinAddress: "",
                exchangerTxId: "",
                dt: Date()
            )
            navigationController?.pushViewController(crossChainSwapVC, animated: true)
        }
    }
    
    private func continueChainToTon() {
        
        guard let swapEstimate = swapVM.cexEstimate else { return }
        
        if swapEstimate.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
            }
            return
        }
        
        var toTonTransaction: ApiActivity? = nil   // filled if cex to ton done, to present cross-chain-swap info
        var failureError: BridgeCallError? = nil    // filled if any error occures

        let fromToken = tokensSelectorVM.sellingToken
        let toToken = tokensSelectorVM.buyingToken
        guard
            let fromAmount = tokensSelectorVM.sellingAmount,
            let toAmount = tokensSelectorVM.buyingAmount
        else {
            return
        }
            
        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: fromAmount,
            fromToken: fromToken,
            toAmount: toAmount,
            toToken: toToken
        ))
        headerVC.view.backgroundColor = .clear
        
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else {return}
                let sellingToken = tokensSelectorVM.sellingToken
                let buyingToken = tokensSelectorVM.buyingToken
                swapVM.swapNow(sellingToken: sellingToken,
                               buyingToken: buyingToken,
                               passcode: passcode, onTaskDone: { cexTransactionToTon, error in
                    toTonTransaction = cexTransactionToTon
                    failureError = error
                    onTaskDone()
                })
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                guard failureError == nil else {
                    showAlert(error: failureError!) { [weak self] in
                        guard let self else { return }
                        dismiss(animated: true)
                    }
                    return
                }
                if let transaction = toTonTransaction {
                    let crossChainSwapVC = CrossChainSwapVC(transaction: transaction)
                    navigationController?.pushViewController(crossChainSwapVC, animated: true)
                } else {
                    dismiss(animated: true)
                }
            })
    }
    
    private func continueCrossChainImmediate() {
        guard let swapEstimate = swapVM.cexEstimate else { return }
        
        if swapEstimate.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
            }
            return
        }
        
        var toTonTransaction: ApiActivity? = nil   // filled if cex to ton done, to present cross-chain-swap info
        var failureError: BridgeCallError? = nil    // filled if any error occures

        let fromToken = tokensSelectorVM.sellingToken
        let toToken = tokensSelectorVM.buyingToken
        guard
            let fromAmount = tokensSelectorVM.sellingAmount,
            let toAmount = tokensSelectorVM.buyingAmount
        else {
            return
        }
            
        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: fromAmount,
            fromToken: fromToken,
            toAmount: toAmount,
            toToken: toToken
        ))
        headerVC.view.backgroundColor = .clear
        
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else {return}
                let sellingToken = tokensSelectorVM.sellingToken
                let buyingToken = tokensSelectorVM.buyingToken
                swapVM.swapNow(sellingToken: sellingToken,
                               buyingToken: buyingToken,
                               passcode: passcode, onTaskDone: { cexTransactionToTon, error in
                    toTonTransaction = cexTransactionToTon
                    failureError = error
                    onTaskDone()
                })
            },
            onDone: { [weak self] _ in
                guard let self else { return }
                guard failureError == nil else {
                    showAlert(error: failureError!) { [weak self] in
                        guard let self else { return }
                        dismiss(animated: true)
                    }
                    return
                }
                if let transaction = toTonTransaction {
                    let crossChainSwapVC = CrossChainSwapVC(transaction: transaction)
                    navigationController?.pushViewController(crossChainSwapVC, animated: true)
                } else {
                    dismiss(animated: true)
                }
            })
    }
}


extension SwapVC: WKeyboardObserverDelegate {
    public func keyboardWillShow(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant = -info.height - 16
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant =  -view.safeAreaInsets.bottom - 16
                view.layoutIfNeeded()
            }
        }
    }
}


extension SwapVC: WalletCoreData.EventsObserver {
    public func walletCore(event: WalletCoreData.Event) {
    }
}


extension SwapVC: SwapSelectorsDelegate {
    // called once anything changes...
    func swapDataChanged(
        swapSide: SwapSide,
        selling: TokenAmount,
        buying: TokenAmount
    ) {
        var selling = selling
        var buying = buying
        
        // to get full token object containing minter address!
        selling.token = TokenStore.tokens[selling.token.slug] ?? selling.token
        buying.token = TokenStore.tokens[buying.token.slug] ?? buying.token

        // update swap type
        
        swapVM.updateSwapType(selling: selling, buying: buying)
        
        // receive estimatations
        self.enqueueTask = { [weak self] in
            guard let self else { return }
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                do {
                    try await self?.swapVM.swapDataChanged(changedFrom: swapSide, selling: selling, buying: buying)
                } catch {
                }
                try? await Task.sleep(for: .seconds(2)) // regardless if failed or not, wait until trying again
                guard !Task.isCancelled else {
                    return
                }
                self?.enqueueTask?()
            }
        }

        self.enqueueTask?()
        
        // if all are 0, just show enter amounts!
        if (swapSide == .selling && selling.amount <= 0) || (swapSide == .buying && buying.amount <= 0) {
            continueButton.isEnabled = false
            continueButton.showLoading = false
            continueButton.setTitle(swapVM.isValidPair ? lang("Enter Amounts") : lang("Invalid Pair"),
                                    for: .normal)
            return
        }
    }

    func maxAmountPressed(maxAmount: BigInt?) {
        var maxAmount = maxAmount ?? BalanceStore.currentAccountBalances[tokensSelectorVM.sellingToken.slug] ?? 0
        let feeData = FeeEstimationHelpers.networkFeeBigInt(
            sellToken: tokensSelectorVM.sellingToken,
            swapType: swapVM.swapType,
            networkFee: swapVM.swapEstimate?.networkFee.value
        )
        if feeData?.isNativeIn == true {
            maxAmount -= feeData!.fee
            
            if (swapVM.swapType == .inChain) {
                let amountForNextSwap = feeData?.chain?.gas.maxSwap ?? 0
                let amountIn = tokensSelectorVM.sellingAmount ?? 0
                let shouldIgnoreNextSwap = amountIn > 0 && (maxAmount - amountIn) <= amountForNextSwap
                if (!shouldIgnoreNextSwap && maxAmount > amountForNextSwap) {
                    maxAmount -= amountForNextSwap
                }
            }
        }
        tokensSelectorVM.sellingAmount = max(0, maxAmount)
        swapDataChanged(
            swapSide: .selling,
            selling: TokenAmount(tokensSelectorVM.sellingAmount ?? 0, tokensSelectorVM.sellingToken),
            buying: TokenAmount(tokensSelectorVM.buyingAmount ?? 0, tokensSelectorVM.buyingToken)
        )
    }
    
    private func authorizeDiesel() {
        let telegramURLString = "https://t.me/MyTonWalletBot?start=auth-\(AccountStore.account?.tonAddress ?? "")"
        
        if let telegramURL = URL(string: telegramURLString) {
            if UIApplication.shared.canOpenURL(telegramURL) {
                UIApplication.shared.open(telegramURL, options: [:], completionHandler: nil)
            }
        }
    }
}


extension SwapVC: SwapVMDelegate {
    
    @MainActor
    func updateIsValidPair() {
        if !swapVM.isValidPair {
            continueButton.setTitle(lang("Invalid Pair"), for: .normal)
            continueButton.isEnabled = false
            continueButton.showLoading = false
        } else {
            continueButton.setTitle(
                WStrings.Swap_Submit_Text(
                    from: tokensSelectorVM.sellingToken.symbol,
                    to: tokensSelectorVM.buyingToken.symbol
                ),
                for: .normal
            )
        }
    }
    
    // called on estimate data received!
    @MainActor
    func receivedEstimateData(swapEstimate: Api.SwapEstimateResponse?, selectedDex: ApiSwapDexLabel?, lateInit: MSwapEstimate.LateInitProperties?) {
        
        guard swapVM.isValidPair else {
            continueButton.setTitle(lang("Invalid Pair"), for: .normal)
            continueButton.isEnabled = false
            continueButton.showLoading = false
            return
        }

        guard let swapEstimate, let lateInit else {
            continueButton.isEnabled = false
            continueButton.showLoading = false
            return
        }
        
        // update token selector data
        let displayEstimate = swapEstimate.displayEstimate(selectedDex: selectedDex)
        tokensSelectorVM.updateWithEstimate(.init(fromAmount: displayEstimate.fromAmount?.value ?? 0,
                                                toAmount: displayEstimate.toAmount?.value ?? 0,
                                                maxAmount: lateInit.maxAmount))

        // check if swap is possible
        let swapError = swapVM.checkDexSwapError(swapEstimate: swapEstimate, lateInit: lateInit)
        continueButton.showLoading = false
        if let swapError {
            continueButton.setTitle(swapError, for: .normal)
        } else {
            if lateInit.isDiesel == true {
                if swapEstimate.dieselStatus == .notAuthorized {
                    continueButton.setTitle(WStrings.Swap_AuthorizeDiesel_Text(symbol: tokensSelectorVM.sellingToken.symbol.uppercased()), for: .normal)
                    continueButton.isEnabled = true
                    return
                }
            }
            if swapVM.swapType == .crossChainFromTon && AccountStore.account?.supports(chain: tokensSelectorVM.buyingToken.chain) == false {
                continueButton.setTitle(lang("Continue"), for: .normal)
            } else {
                continueButton.setTitle(
                    WStrings.Swap_Submit_Text(
                        from: tokensSelectorVM.sellingToken.symbol,
                        to: tokensSelectorVM.buyingToken.symbol
                    ),
                    for: .normal
                )
            }
        }
        continueButton.isEnabled = swapError == nil
    }
    
    @MainActor
    func receivedCexEstimate(swapEstimate: MSwapEstimate) {
        
        if !swapVM.isValidPair {
            continueButton.setTitle(lang("Invalid Pair"), for: .normal)
            continueButton.isEnabled = false
            continueButton.showLoading = false
        }

        // update token selector data
        tokensSelectorVM.updateWithEstimate(.init(fromAmount: swapEstimate.fromAmount, toAmount: swapEstimate.toAmount))
                
        // check if swap is possible
        if swapVM.isValidPair {
            let swapError = swapVM.checkCexSwapError(swapEstimate: swapEstimate)
            continueButton.showLoading = false
            if let swapError {
                continueButton.setTitle(swapError, for: .normal)
            } else {
                if swapEstimate.isDiesel == true {
                    if swapEstimate.dieselStatus == .notAuthorized {
                        continueButton.setTitle(WStrings.Swap_AuthorizeDiesel_Text(symbol: tokensSelectorVM.sellingToken.symbol.uppercased()), for: .normal)
                        continueButton.isEnabled = true
                        return
                    }
                }
                if swapVM.swapType == .crossChainFromTon && AccountStore.account?.supports(chain: tokensSelectorVM.buyingToken.chain) == false {
                    continueButton.setTitle(lang("Continue"), for: .normal)
                } else {
                    continueButton.setTitle(
                        WStrings.Swap_Submit_Text(
                            from: tokensSelectorVM.sellingToken.symbol,
                            to: tokensSelectorVM.buyingToken.symbol
                        ),
                        for: .normal
                    )
                }
            }
            continueButton.isEnabled = swapError == nil
        }
    }
}

