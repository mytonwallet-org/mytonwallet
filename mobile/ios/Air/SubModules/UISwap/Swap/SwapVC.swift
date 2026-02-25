import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

public final class SwapVC: WViewController, WSensitiveDataProtocol {

    private var swapModel: SwapModel!
    @AccountContext(source: .current) private var account: MAccount
    
    private var hostingController: UIHostingController<SwapView>!

    private var continueButton: WButton { bottomButton! }
    private var continueButtonConstraint: NSLayoutConstraint?
    
    private var startWithKeyboardActive: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var awaitingActivity = false

    public init(defaultSellingToken: String? = nil, defaultBuyingToken: String? = nil, defaultSellingAmount: Double? = nil) {
        super.init(nibName: nil, bundle: nil)
        self.swapModel = SwapModel(
            delegate: self,
            defaultSellingToken: defaultSellingToken ?? TONCOIN_SLUG,
            defaultBuyingToken: defaultBuyingToken ?? TON_USDT_SLUG,
            defaultSellingAmount: defaultSellingAmount,
            accountContext: _account
        )
        WalletCoreData.add(eventObserver: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        
        WKeyboardObserver.observeKeyboard(delegate: self)
        
        Task {
            _ = try? await TokenStore.updateSwapAssets()
        }
    }

    private func setupViews() {
        navigationItem.title = lang("Swap")
        addCloseNavigationItemIfNeeded()

        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        hostingController.view.addGestureRecognizer(tapGestureRecognizer)

        _ = addBottomButton(bottomConstraint: false)
        continueButton.isEnabled = false
        continueButton.configureTitle(sellingToken: swapModel.input.sellingToken, buyingToken: swapModel.input.buyingToken)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        let c = startWithKeyboardActive ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    func makeView() -> SwapView {
        SwapView(
            swapModel: swapModel,
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
        
        if swapModel.swapType != .onChain,
           account.supports(chain: swapModel.input.sellingToken.chain),
           account.supports(chain: swapModel.input.buyingToken.chain) {
            continueCrosschainImmediate()
        } else {
            switch swapModel.swapType {
            case .onChain:
                warnIfNeededAndContinueInChain()
            case .crosschainFromWallet:
                continueChainFromTon()
            case .crosschainToWallet:
                continueChainToTon()
            case .crosschainInsideWallet:
                continueCrosschainImmediate()
            }
        }
    }
    
    private func warnIfNeededAndContinueInChain() {
        if let impact = swapModel.detailsVM.displayImpactWarning {
            showAlert(
                title: lang("The exchange rate is below market value!", arg1: "\(impact.formatted(.number.precision(.fractionLength(0..<1)).locale(.forNumberFormatters)))%"),
                text: lang("We do not recommend to perform an exchange, try to specify a lower amount."),
                button: lang("Swap"),
                buttonStyle: .destructive,
                buttonPressed: { self.continueInChain() },
                secondaryButton: lang("Cancel"),
                secondaryButtonPressed: nil,
                preferPrimary: true,
            )
        } else {
            continueInChain()
        }
    }
    
    private func continueInChain() {
        guard let swapEstimate = swapModel.onchain.swapEstimate, let lateInit = swapModel.onchain.lateInit else { return }
        
        if lateInit.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
                return
            }
        }
        startSwapFlow(presentCrosschain: false)
    }
    
    private func continueChainFromTon() {
        if let cexEstimate = swapModel.crosschain.cexEstimate {
            let networkFee = cexEstimate.realNetworkFee ?? cexEstimate.networkFee ?? .zero
            let crosschainSwapVC = CrosschainFromWalletVC(
                sellingToken: TokenAmount(swapModel.input.sellingAmount ?? 0, swapModel.input.sellingToken),
                buyingToken: TokenAmount(swapModel.input.buyingAmount ?? 0, swapModel.input.buyingToken),
                swapFee: cexEstimate.swapFee,
                networkFee: networkFee
            )
            navigationController?.pushViewController(crosschainSwapVC, animated: true)
        }
    }
    
    private func continueChainToTon() {
        
        guard let swapEstimate = swapModel.crosschain.cexEstimate else { return }
        
        if swapEstimate.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
            }
            return
        }
        startSwapFlow(presentCrosschain: true)
    }
    
    private func continueCrosschainImmediate() {
        guard let swapEstimate = swapModel.crosschain.cexEstimate else { return }
        
        if swapEstimate.isDiesel == true {
            if swapEstimate.dieselStatus == .notAuthorized {
                authorizeDiesel()
            }
            return
        }
        startSwapFlow(presentCrosschain: false)
    }

    private enum SwapResult {
        case success(ApiActivity?)
        case failure(BridgeCallError)
    }

    private func startSwapFlow(presentCrosschain: Bool) {
        let fromToken = swapModel.input.sellingToken
        let toToken = swapModel.input.buyingToken
        guard
            let fromAmount = swapModel.input.sellingAmount,
            let toAmount = swapModel.input.buyingAmount
        else {
            return
        }

        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: TokenAmount(fromAmount, fromToken),
            toAmount: TokenAmount(toAmount, toToken)
        ))
        headerVC.view.backgroundColor = .clear

        var swapResult: SwapResult?
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else { return }
                let sellingToken = swapModel.input.sellingToken
                let buyingToken = swapModel.input.buyingToken
                awaitingActivity = true
                Task {
                    swapResult = await self.performSwap(passcode: passcode, sellingToken: sellingToken, buyingToken: buyingToken)
                    onTaskDone()
                }
            },
            onDone: { [weak self] _ in
                guard let self, let swapResult else { return }
                handleSwapResult(swapResult, presentCrosschain: presentCrosschain)
            })
    }

    private func performSwap(passcode: String, sellingToken: ApiToken, buyingToken: ApiToken) async -> SwapResult {
        do {
            let activity = try await swapModel.swapNow(sellingToken: sellingToken, buyingToken: buyingToken, passcode: passcode)
            return .success(activity)
        } catch {
            let bridgeError = (error as? BridgeCallError) ?? .unknown(baseError: error)
            return .failure(bridgeError)
        }
    }

    private func handleSwapResult(_ result: SwapResult, presentCrosschain: Bool) {
        switch result {
        case .success(let activity):
            if presentCrosschain, let swap = activity?.swap {
                let crosschainSwapVC = CrosschainToWalletVC(swap: swap, accountId: nil)
                navigationController?.pushViewController(crosschainSwapVC, animated: true)
            }
        case .failure(let error):
            awaitingActivity = false
            showAlert(error: error) { [weak self] in
                guard let self else { return }
                dismiss(animated: true)
            }
        }
    }
    
    func authorizeDiesel() {
        if let telegramURL = account.dieselAuthLink {
            if UIApplication.shared.canOpenURL(telegramURL) {
                UIApplication.shared.open(telegramURL, options: [:], completionHandler: nil)
            }
        }
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
        switch event {
        case .newLocalActivity(let update):
            handleNewActivities(accountId: update.accountId, activities: update.activities)
        case .newActivities(let update):
            handleNewActivities(accountId: update.accountId, activities: (update.pendingActivities ?? []) + update.activities)
        default:
            break
        }
    }

    private func handleNewActivities(accountId: String, activities: [ApiActivity]) {
        guard awaitingActivity, accountId == account.id else { return }
        guard let activity = activities.first(where: { activity in
            if case .swap = activity {
                return true
            }
            return false
        }) else { return }
        awaitingActivity = false
        AppActions.showActivityDetails(accountId: accountId, activity: activity, context: .swapConfirmation)
    }
}

extension SwapVC: SwapModelDelegate {
    func applyButtonConfiguration(_ config: SwapButtonConfiguration) {
        config.apply(to: continueButton)
    }
}
