import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletCore
import WalletContext
import SwiftNavigation

private let swapLog = Log("SwapVC")

public final class SwapVC: WViewController, WSensitiveDataProtocol {
    private var swapModel: SwapModel!
    @AccountContext private var account: MAccount
    private let isAccountSwitchingAllowed: Bool
    
    private var hostingController: UIHostingController<SwapView>?

    private var continueButton: WButton?
    private var continueButtonConstraint: NSLayoutConstraint?
    private var pendingButtonConfiguration: SwapButtonConfiguration?
    private var appliedButtonConfiguration: SwapButtonConfiguration?
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .swap)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }
    private let bottomButtonBackgroundView = EdgeGradientView()
    private var bottomButtonBackgroundBottomConstraint: NSLayoutConstraint?
    private var isKeyboardVisible = false
    
    private var startWithKeyboardActive: Bool {
        windowHorizontalSizeClass == .compact
            && isSheetPresentationAttachedToBottom
            && !WKeyboardObserver.isHardwareKeyboardConnected
    }

    private var currentTokenSelectionSide: SwapSide?
    public init(
        accountContext: AccountContext,
        defaultSellingToken: String? = nil,
        defaultBuyingToken: String? = nil,
        defaultSellingAmount: Double? = nil,
        isAccountSwitchingAllowed: Bool = false
    ) {
        self._account = accountContext
        self.isAccountSwitchingAllowed = isAccountSwitchingAllowed
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

        observe { [weak self] in
            guard let self else { return }
            _ = account.id
            updateLeftNavigationItem()
        }
        
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
        navigationItem.leftItemsSupplementBackButton = true
        addCloseNavigationItemIfNeeded()

        let hostingController = addHostingController(makeView(), constraints: .fill)
        self.hostingController = hostingController
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        hostingController.view.addGestureRecognizer(tapGestureRecognizer)

        let continueButton = addBottomButton(bottomConstraint: false)
        self.continueButton = continueButton
        setupBottomButtonBackground(continueButton: continueButton)
        continueButton.isEnabled = false
        continueButton.configureTitle(sellingToken: swapModel.input.sellingToken, buyingToken: swapModel.input.buyingToken)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        if let pendingButtonConfiguration {
            pendingButtonConfiguration.apply(to: continueButton)
            appliedButtonConfiguration = pendingButtonConfiguration
            self.pendingButtonConfiguration = nil
        }
        
        let c = startWithKeyboardActive ? -max(WKeyboardObserver.keyboardHeight, 291) + 50 : -34
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16 + c)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        
        updateTheme()
    }

    private func setupBottomButtonBackground(continueButton: WButton) {
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
                cexLabel: confirmation.cexLabel,
                accountContext: _account,
                onContinue: { [weak self] payoutAddress, authorizationPresenter in
                    self?.startSwapFlow(
                        presentCrosschain: false,
                        payoutAddress: payoutAddress,
                        failureStage: .externalAddress,
                        authorizationPresenter: authorizationPresenter
                    )
                }
            )
            navigationController?.pushViewController(crosschainSwapVC, animated: true)
        }
    }
    private func startSwapFlow(
        presentCrosschain: Bool,
        payoutAddress: String? = nil,
        failureStage: SwapStage = .editing,
        authorizationPresenter: UIViewController? = nil
    ) {
        guard let protectedAction = ProtectedAction.swap(
            model: swapModel,
            presentCrosschainResult: presentCrosschain,
            payoutAddress: payoutAddress
        ) else {
            swapLog.fault("Missing confirmation state while starting protected swap")
            assertionFailure("Missing confirmation state while starting protected swap")
            return
        }
        swapModel.setStage(.confirming)
        Task {
            let context = ExecutionContext(
                authorizationPresenter: authorizationPresenter ?? self,
                flowOrigin: self
            )
            let outcome = await ProtectedActionExecutor.execute(protectedAction, in: context)
            switch outcome {
            case .completed, .partiallyCommitted, .indeterminate:
                swapModel.setStage(.complete)
            case .cancelled, .failed:
                swapModel.setStage(failureStage)
            }
        }
    }

    private func updateLeftNavigationItem() {
        guard isAccountSwitchingAllowed else {
            navigationItem.setLeftBarButtonItems(nil, animated: true)
            return
        }

        accountSwitcher.update(selectedAccountId: account.id)
        let items = accountSwitcher.hasAlternativeAccounts(selectedAccountId: account.id)
            ? [accountSwitcher.barButtonItem]
            : nil
        navigationItem.setLeftBarButtonItems(items, animated: true)
    }

    private func selectAccount(accountId: String) {
        Task {
            do {
                try await swapModel.onAccountSelected(accountId: accountId)
            } catch {
                AppActions.showError(error: error)
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
        case .balanceChanged(let accountId):
            if accountId == account.id {
                swapModel.refreshBalances()
            }
        default:
            break
        }
    }
}

extension SwapVC: SwapModelDelegate {
    func applyButtonConfiguration(_ config: SwapButtonConfiguration) {
        guard let continueButton else {
            if pendingButtonConfiguration?.hasSamePresentation(as: config) == true {
                return
            }
            pendingButtonConfiguration = config
            return
        }
        if appliedButtonConfiguration?.hasSamePresentation(as: config) == true {
            return
        }
        config.apply(to: continueButton)
        appliedButtonConfiguration = config
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
