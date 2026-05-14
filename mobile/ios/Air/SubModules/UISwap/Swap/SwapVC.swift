import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

public final class SwapVC: WViewController, WSensitiveDataProtocol {

    private var swapModel: SwapModel!
    @AccountContext private var account: MAccount
    
    private var hostingController: UIHostingController<SwapView>!

    private var continueButton: WButton { bottomButton! }
    private var continueButtonConstraint: NSLayoutConstraint?
    private let bottomButtonBackgroundView = EdgeGradientView()
    private var bottomButtonBackgroundBottomConstraint: NSLayoutConstraint?
    private var isKeyboardVisible = false
    
    private var startWithKeyboardActive: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var currentTokenSelectionSide: SwapSide?
    private var awaitingActivity = false

    public init(accountContext: AccountContext, defaultSellingToken: String? = nil, defaultBuyingToken: String? = nil, defaultSellingAmount: Double? = nil) {
        self._account = accountContext
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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        swapModel.setStage(.editing)
    }

    private func setupViews() {
        navigationItem.title = lang("Swap")
        addCloseNavigationItemIfNeeded()

        self.hostingController = addHostingController(makeView(), constraints: .fill)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        hostingController.view.addGestureRecognizer(tapGestureRecognizer)

        _ = addBottomButton(bottomConstraint: false)
        setupBottomButtonBackground()
        continueButton.isEnabled = false
        continueButton.configureTitle(sellingToken: swapModel.input.sellingToken, buyingToken: swapModel.input.buyingToken)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        
        let c = startWithKeyboardActive ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        updateTheme()
    }

    private func setupBottomButtonBackground() {
        bottomButtonBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonBackgroundView.isUserInteractionEnabled = false
        bottomButtonBackgroundView.direction = .bottom
        bottomButtonBackgroundView.color = UIColor.air.sheetBackground.withAlphaComponent(0.85)
        view.insertSubview(bottomButtonBackgroundView, belowSubview: continueButton)

        let bottomConstraint = bottomButtonBackgroundView.bottomAnchor.constraint(equalTo: continueButton.bottomAnchor)
        bottomButtonBackgroundBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            bottomButtonBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomButtonBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomButtonBackgroundView.topAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),
            bottomConstraint,
        ])
        updateBottomButtonBackgroundBottomInset()
    }

    private func updateBottomButtonBackgroundBottomInset() {
        bottomButtonBackgroundBottomConstraint?.constant = 16 + (isKeyboardVisible ? 0 : view.safeAreaInsets.bottom)
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomButtonBackgroundBottomInset()
    }
    
    private func updateTheme() {
        view.backgroundColor = .air.sheetBackground
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

        guard let route = swapModel.continueRoute() else { return }
        execute(route)
    }

    private func execute(_ route: SwapRoute) {
        switch route {
        case .priceImpactWarning(let impact, let next):
            showAlert(
                title: lang("The exchange rate is below market value!", arg1: "\(impact.formatted(.number.precision(.fractionLength(0..<1)).locale(.forNumberFormatters)))%"),
                text: lang("We do not recommend to perform an exchange, try to specify a lower amount."),
                button: lang("Swap"),
                buttonStyle: .destructive,
                buttonPressed: { self.execute(next) },
                secondaryButton: lang("Cancel"),
                secondaryButtonPressed: nil,
                preferPrimary: true,
            )
        case .authorizeDiesel:
            authorizeDiesel()
        case .confirmSwap(let presentCrosschainResult):
            startSwapFlow(presentCrosschain: presentCrosschainResult)
        case .crosschainFromWallet(let confirmation):
            swapModel.setStage(.externalAddress)
            let crosschainSwapVC = CrosschainFromWalletVC(
                sellingToken: confirmation.selling,
                buyingToken: confirmation.buying,
                accountContext: _account,
                onContinue: { [weak self] payoutAddress, sourceViewController in
                    self?.startSwapFlow(
                        presentCrosschain: false,
                        payoutAddress: payoutAddress,
                        presentingViewController: sourceViewController,
                        failureStage: .externalAddress
                    )
                }
            )
            navigationController?.pushViewController(crosschainSwapVC, animated: true)
        }
    }
    private enum SwapResult {
        case success(ApiActivity?)
        case failure(BridgeCallError)
    }

    private func startSwapFlow(
        presentCrosschain: Bool,
        payoutAddress: String? = nil,
        presentingViewController: UIViewController? = nil,
        failureStage: SwapStage = .editing
    ) {
        guard let confirmationAmounts = swapModel.confirmationAmounts() else {
            return
        }

        let headerVC = UIHostingController(rootView: SwapConfirmHeaderView(
            fromAmount: confirmationAmounts.selling,
            toAmount: confirmationAmounts.buying
        ))
        headerVC.view.backgroundColor = .clear

        var swapResult: SwapResult?
        swapModel.setStage(.confirming)
        UnlockVC.pushAuth(
            on: presentingViewController ?? self,
            title: lang("Confirm Swap"),
            customHeaderVC: headerVC,
            onAuthTask: { [weak self] passcode, onTaskDone in
                guard let self else { return }
                awaitingActivity = !presentCrosschain
                Task {
                    swapResult = await self.performSwap(
                        passcode: passcode,
                        confirmation: confirmationAmounts,
                        payoutAddress: payoutAddress
                    )
                    onTaskDone()
                }
            },
            onDone: { [weak self] _ in
                guard let self, let swapResult else { return }
                handleSwapResult(swapResult, presentCrosschain: presentCrosschain, failureStage: failureStage)
            })
    }

    private func performSwap(
        passcode: String,
        confirmation: SwapConfirmationAmounts,
        payoutAddress: String? = nil
    ) async -> SwapResult {
        do {
            let activity = try await swapModel.swapNow(
                confirmation: confirmation,
                passcode: passcode,
                payoutAddress: payoutAddress
            )
            return .success(activity)
        } catch {
            let bridgeError = (error as? BridgeCallError) ?? .unknown(baseError: error)
            return .failure(bridgeError)
        }
    }

    private func handleSwapResult(_ result: SwapResult, presentCrosschain: Bool, failureStage: SwapStage = .editing) {
        switch result {
        case .success(let activity):
            swapModel.setStage(.complete)
            if presentCrosschain {
                awaitingActivity = false
                if let swap = activity?.swap {
                    let crosschainSwapVC = CrosschainToWalletVC(swap: swap, accountId: nil)
                    navigationController?.pushViewController(crosschainSwapVC, animated: true)
                }
            }
        case .failure(let error):
            awaitingActivity = false
            swapModel.setStage(failureStage)
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
        isKeyboardVisible = true
        updateBottomButtonBackgroundBottomInset()
        UIView.animate(withDuration: info.animationDuration) { [self] in
            if let continueButtonConstraint {
                continueButtonConstraint.constant = -info.height - 16
                view.layoutIfNeeded()
            }
        }
    }
    
    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        isKeyboardVisible = false
        updateBottomButtonBackgroundBottomInset()
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
        case .balanceChanged(let accountId):
            if accountId == account.id {
                swapModel.refreshBalances()
            }
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

    func executeSwapCommand(_ command: SwapCommand) {
        switch command {
        case .dismissKeyboard:
            view.endEditing(true)
        case .showTokenSelector(let side):
            presentTokenSelector(side: side)
        case .showBuyingAmountDisabledToast:
            Haptics.play(.lightTap)
            AppActions.showToast(message: lang("$swap_reverse_prohibited"))
        }
    }
}

extension SwapVC: TokenSelectionVCDelegate {
    public func didSelect(token: MTokenBalance) {
        dismiss(animated: true)
        if let newToken = TokenStore.tokens[token.tokenSlug] {
            didSelectToken(newToken)
        }
    }

    public func didSelect(token newToken: ApiToken) {
        dismiss(animated: true)
        didSelectToken(newToken)
    }

    func presentTokenSelector(side: SwapSide) {
        currentTokenSelectionSide = side
        let swapTokenSelectionVC: TokenSelectionVC
        switch side {
        case .selling:
            swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: swapModel.input.sellingToken.slug,
                otherSymbolOrMinterAddress: nil,
                myAssetsDisplayMode: .swap,
                title: lang("You sell"),
                delegate: self,
                isModal: true,
                onlySupportedChains: false
            )
        case .buying:
            swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: swapModel.input.buyingToken.slug,
                extraWalletTokenSlugs: ApiChain.allCases
                    .filter(\.isOnchainSwapSupported)
                    .map(\.nativeToken.slug),
                otherSymbolOrMinterAddress: nil,
                myAssetsDisplayMode: .swap,
                title: lang("You buy"),
                delegate: self,
                isModal: true,
                onlySupportedChains: false
            )
        }
        let nc = WNavigationController(rootViewController: swapTokenSelectionVC)
        present(nc, animated: true)
    }

    private func didSelectToken(_ token: ApiToken) {
        guard let side = currentTokenSelectionSide else { return }
        currentTokenSelectionSide = nil
        swapModel.input.userSelectedToken(token, side: side)
    }
}
