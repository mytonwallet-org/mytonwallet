import ContextMenuKit
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
    private var tradeModel: TokenTradeModel?
    private var tradeMenuInteraction: ContextMenuInteraction?
    
    private var hostingController: UIHostingController<SwapView>?

    private let bottomButtonContainer = WTouchPassView()
    private var presentationDisplayLink: CADisplayLink?
    private var compensatedAnimations: [String: CFTimeInterval] = [:]
    private var isSheetPresentationInFlight = false
    private var continueButton: WButton?
    private var continueButtonConstraint: NSLayoutConstraint?
    private var buttonPresentationController: DraftButtonPresenter?
    private lazy var accountSwitcher = AccountSwitcher(configuration: .init(accountSupport: .swap)) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }
    private let bottomButtonBackgroundView = EdgeGradientView()
    private var bottomButtonBackgroundBottomConstraint: NSLayoutConstraint?
    private var isKeyboardVisible = false
    private var keyboardFrameInScreen: CGRect?
    private weak var keyboardScreen: UIScreen?
    private enum BottomButtonLayout {
        static let keyboardSpacing: CGFloat = 16

        static func restingSpacing(isAttachedToBottom: Bool) -> CGFloat {
            IOS_26_MODE_ENABLED && isAttachedToBottom ? 2 : 16
        }
    }

    private var currentTokenSelectionSide: SwapSide?
    public init(
        accountContext: AccountContext,
        defaults: ApiSwapDefaults,
        defaultSellingAmount: Double? = nil,
        defaultBuyingAmount: Double? = nil,
        isAccountSwitchingAllowed: Bool = true,
        tradeDirection: TokenTradeDirection? = nil
    ) {
        self._account = accountContext
        self.isAccountSwitchingAllowed = isAccountSwitchingAllowed
        super.init(nibName: nil, bundle: nil)
        self.swapModel = SwapModel(
            delegate: self,
            defaults: defaults,
            defaultSellingAmount: defaultSellingAmount,
            defaultBuyingAmount: defaultBuyingAmount,
            accountContext: _account
        )
        if let tradeDirection, let token = tradeDirection == .buy ? swapModel.input.buyingToken : swapModel.input.sellingToken {
            self.tradeModel = TokenTradeModel(swap: swapModel, direction: tradeDirection, token: token, accountContext: _account)
        }
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
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !swapModel.isSubmitting {
            swapModel.setStage(tradeModel?.cardCurrency == nil ? .editing : .externalAddress)
        }
        swapModel.refreshBalances()
        prepareBottomButtonForPresentation()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        finishPresentationCompensation()
    }

    private func prepareBottomButtonForPresentation() {
        guard isBeingPresented || navigationController?.isBeingPresented == true,
              let coordinator = transitionCoordinator,
              coordinator.isAnimated else { return }
        isSheetPresentationInFlight = true
        let link = CADisplayLink(target: self, selector: #selector(updatePresentationCompensation))
        presentationDisplayLink = link
        link.add(to: .main, forMode: .common)
        let registered = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.finishPresentationCompensation()
        }
        if !registered {
            finishPresentationCompensation()
        }
    }

    @objc private func updatePresentationCompensation() {
        guard isSheetPresentationInFlight else { return }
        // UIKit may reposition an iPad sheet without laying out this controller's view again.
        updateBottomButtonLayout()
        guard keyboardIntersectsContent,
              view.keyboardLayoutGuide.layoutFrame.minY < view.bounds.maxY else {
            removePresentationCompensation()
            return
        }
        // The keyboard guide animates in window coordinates, while the sheet also moves its
        // descendants. Cancel that extra movement without reparenting the Liquid Glass button.
        // UIKit can animate intermediate layers that have no corresponding UIView.
        var ancestor = bottomButtonContainer.layer.superlayer
        while let candidate = ancestor {
            for key in candidate.animationKeys() ?? [] {
                guard let animation = candidate.animation(forKey: key) as? CABasicAnimation,
                      animation.keyPath == "position",
                      let from = (animation.fromValue as? NSValue)?.cgPointValue,
                      let to = (animation.toValue as? NSValue)?.cgPointValue else { continue }
                let compensationKey = "sheetMotion.\(ObjectIdentifier(candidate)).\(key)"
                guard compensatedAnimations[compensationKey] != animation.beginTime else { continue }
                guard let counter = animation.copy() as? CABasicAnimation else { continue }
                let restingY = animation.isAdditive ? 0 : candidate.position.y
                counter.keyPath = "transform.translation.y"
                counter.fromValue = -(from.y - restingY)
                counter.toValue = -(to.y - restingY)
                counter.byValue = nil
                counter.isAdditive = true
                counter.delegate = nil
                // Copy the original spring and its clock so discovery on a later frame does
                // not restart the motion or introduce a display-link-sized delay.
                counter.beginTime = bottomButtonContainer.layer.convertTime(animation.beginTime, from: candidate)
                counter.isRemovedOnCompletion = true
                bottomButtonContainer.layer.add(counter, forKey: compensationKey)
                compensatedAnimations[compensationKey] = animation.beginTime
            }
            ancestor = candidate.superlayer
        }
    }

    private var keyboardIntersectsContent: Bool {
        guard isKeyboardVisible, let keyboardFrameInScreen,
              let window = view.window,
              let screen = keyboardScreen, screen === window.screen else { return false }
        let frameInWindow = window.convert(keyboardFrameInScreen, from: screen.coordinateSpace)
        // Match the guide's default behavior of ignoring floating and undocked keyboards.
        guard frameInWindow.maxY >= window.bounds.maxY else { return false }
        let frameInView = view.convert(frameInWindow, from: window)
        // Use the final sheet geometry: a detached iPad sheet can stay entirely above the
        // keyboard even though it passes through the keyboard's frame during presentation.
        return view.bounds.intersects(frameInView)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateBottomButtonLayout()
        if isSheetPresentationInFlight {
            updatePresentationCompensation()
        }
    }

    private func finishPresentationCompensation() {
        isSheetPresentationInFlight = false
        presentationDisplayLink?.invalidate()
        presentationDisplayLink = nil
        removePresentationCompensation()
        updateBottomButtonLayout()
    }

    private func removePresentationCompensation() {
        for key in compensatedAnimations.keys {
            bottomButtonContainer.layer.removeAnimation(forKey: key)
        }
        compensatedAnimations.removeAll()
    }

    private func setupViews() {
        if let tradeModel {
            setupTradeViews(tradeModel)
            return
        }
        navigationItem.title = lang("Swap")
        navigationItem.leftItemsSupplementBackButton = true
        addCloseNavigationItemIfNeeded()

        let hostingController = addHostingController(makeView(), constraints: .fill)
        self.hostingController = hostingController
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(containerPressed))
        tapGestureRecognizer.cancelsTouchesInView = true
        hostingController.view.addGestureRecognizer(tapGestureRecognizer)

        if #available(iOS 17.0, *) {
            // Start at the screen bottom when the keyboard is absent, so its first frame
            // already has the same spacing as its last. Apply the resting safe area below.
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        bottomButtonContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomButtonContainer)
        NSLayoutConstraint.activate([
            bottomButtonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomButtonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomButtonContainer.topAnchor.constraint(equalTo: view.topAnchor),
            bottomButtonContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let continueButton = WButton(style: .primary)
        bottomButton = continueButton
        self.continueButton = continueButton
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonContainer.addSubview(continueButton)
        let horizontalInset: CGFloat = IOS_26_MODE_ENABLED ? 36 : 16
        NSLayoutConstraint.activate([
            continueButton.leadingAnchor.constraint(equalTo: bottomButtonContainer.leadingAnchor, constant: horizontalInset),
            continueButton.trailingAnchor.constraint(equalTo: bottomButtonContainer.trailingAnchor, constant: -horizontalInset),
        ])
        let buttonPresentationController = DraftButtonPresenter(button: continueButton)
        self.buttonPresentationController = buttonPresentationController
        setupBottomButtonBackground(continueButton: continueButton)
        continueButton.isEnabled = false
        continueButton.isUserInteractionEnabled = false
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        observe { [weak self] in
            guard let self, let buttonPresentationController = self.buttonPresentationController else { return }
            buttonPresentationController.apply(swapModel.currentButtonConfiguration)
        }
        
        let constraint = continueButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        constraint.isActive = true
        self.continueButtonConstraint = constraint
        updateBottomButtonLayout()
        
        updateTheme()
        addCustomNavigationBarBackground(color: .air.sheetBackground)
    }

    private func setupBottomButtonBackground(continueButton: WButton) {
        bottomButtonBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        bottomButtonBackgroundView.isUserInteractionEnabled = false
        bottomButtonBackgroundView.direction = .bottom
        bottomButtonBackgroundView.color = UIColor.air.sheetBackground.withAlphaComponent(0.85)
        bottomButtonContainer.insertSubview(bottomButtonBackgroundView, belowSubview: continueButton)

        let bottomConstraint = bottomButtonBackgroundView.bottomAnchor.constraint(equalTo: continueButton.bottomAnchor)
        bottomButtonBackgroundBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            bottomButtonBackgroundView.leadingAnchor.constraint(equalTo: bottomButtonContainer.leadingAnchor),
            bottomButtonBackgroundView.trailingAnchor.constraint(equalTo: bottomButtonContainer.trailingAnchor),
            bottomButtonBackgroundView.topAnchor.constraint(equalTo: continueButton.topAnchor, constant: -16),
            bottomConstraint,
        ])
    }

    private func updateBottomButtonLayout() {
        let intersectsKeyboard = keyboardIntersectsContent
        let spacing = intersectsKeyboard ? BottomButtonLayout.keyboardSpacing
            : BottomButtonLayout.restingSpacing(isAttachedToBottom: isSheetPresentationAttachedToBottom)
        let safeAreaInset = intersectsKeyboard ? 0 : view.safeAreaInsets.bottom
        var inset = spacing
        if #available(iOS 17.0, *), !intersectsKeyboard {
            inset += safeAreaInset
        }
        continueButtonConstraint?.constant = -inset
        bottomButtonBackgroundBottomConstraint?.constant = spacing + safeAreaInset
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateBottomButtonLayout()
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

        if let tradeModel, let currency = tradeModel.cardCurrency {
            guard tradeModel.canContinue else { return }
            if tradeModel.isBuying {
                guard let vc = BuyWithCardVC(accountContext: _account, chain: tradeModel.token.chain, selectedCurrency: currency) else { return }
                navigationController?.pushViewController(vc, animated: true)
            } else {
                AppActions.showTokenTradeOfframp(accountContext: _account, amount: tradeModel.typedTokenAmount, currency: currency)
            }
            return
        }

        guard let route = swapModel.continueRoute() else { return }
        execute(route)
    }

    private func execute(_ route: SwapRoute) {
        switch route {
        case .priceImpactWarning(let impact, let next):
            showAlert(
                title: L10n.theExchangeRateIsBelowMarketValue(value: "\(impact.formatted(.number.precision(.fractionLength(0..<1)).locale(.forNumberFormatters)))%"),
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
            Task {
                await startSwapFlow(presentCrosschain: presentCrosschainResult)
            }
        case .crosschainFromWallet(let confirmation):
            swapModel.setStage(.externalAddress)
            let crosschainSwapVC = CrosschainFromWalletVC(
                sellingToken: confirmation.selling,
                buyingToken: confirmation.buying,
                cexLabel: confirmation.cexLabel,
                accountContext: _account,
                onContinue: { [weak self] payoutAddress, authorizationPresenter in
                    await self?.startSwapFlow(
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
    ) async {
        guard !swapModel.isSubmitting else { return }
        guard let protectedAction = ProtectedAction.swap(
            model: swapModel,
            presentCrosschainResult: presentCrosschain,
            payoutAddress: payoutAddress
        ) else {
            swapLog.info("Swap confirmation is no longer available")
            return
        }
        swapModel.setStage(.confirming)
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

    private func updateLeftNavigationItem() {
        guard isAccountSwitchingAllowed else {
            navigationItem.setLeftBarButtonItems(nil, animated: true)
            return
        }

        accountSwitcher.update(selectedAccountId: account.id)
        let items = tradeModel != nil || accountSwitcher.hasAlternativeAccounts(selectedAccountId: account.id)
            ? [accountSwitcher.barButtonItem]
            : nil
        navigationItem.setLeftBarButtonItems(items, animated: true)
    }

    private func selectAccount(accountId: String) {
        Task {
            do {
                try await swapModel.onAccountSelected(accountId: accountId)
                tradeModel?.resetAmount()
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
        keyboardFrameInScreen = info.endFrame
        keyboardScreen = info.screen ?? view.window?.screen
        UIView.performWithoutAnimation {
            updateBottomButtonLayout()
            view.layoutIfNeeded()
        }
        updatePresentationCompensation()
    }

    public func keyboardWillHide(info: WKeyboardDisplayInfo) {
        isKeyboardVisible = false
        updateBottomButtonLayout()
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
        let fiatOptions: [TokenSelectionVC.FiatOption] = tradeModel.map { model in
            model.availableCardCurrencies.map { currency in
                .init(currency: currency, subtitle: lang(model.isBuying ? "Buy with Card" : "Sell on Card")) { [weak self] in
                    model.selectCard(currency)
                    self?.currentTokenSelectionSide = nil
                    self?.dismiss(animated: true)
                }
            }
        } ?? []
        let swapTokenSelectionVC: TokenSelectionVC
        switch side {
        case .selling:
            swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: swapModel.input.sellingToken?.slug,
                otherSymbolOrMinterAddress: nil,
                showOnlyMyAssets: tradeModel != nil,
                myAssetsDisplayMode: .swap,
                title: lang(tradeModel == nil ? "You Sell" : "Pay With"),
                delegate: self,
                isModal: true,
                onlySupportedChains: false,
                fiatOptions: fiatOptions,
                showsAssetCategories: tradeModel != nil
            )
        case .buying:
            swapTokenSelectionVC = TokenSelectionVC(
                forceAvailable: swapModel.input.buyingToken?.slug,
                extraWalletTokenSlugs: ApiChain.allCases
                    .filter(\.isOnchainSwapSupported)
                    .map(\.nativeToken.slug),
                otherSymbolOrMinterAddress: nil,
                myAssetsDisplayMode: .swap,
                title: lang(tradeModel == nil ? "You Buy" : "You Receive"),
                delegate: self,
                isModal: true,
                onlySupportedChains: false,
                fiatOptions: fiatOptions,
                showsAssetCategories: tradeModel != nil
            )
        }
        let nc = WNavigationController(rootViewController: swapTokenSelectionVC)
        if tradeModel != nil {
            nc.sheetPresentationController?.detents = [.large()]
        }
        present(nc, animated: true)
    }

    private func didSelectToken(_ token: ApiToken) {
        guard let side = currentTokenSelectionSide else { return }
        currentTokenSelectionSide = nil
        if let tradeModel { tradeModel.selectToken(token) }
        else { swapModel.input.userSelectedToken(token, side: side) }
    }
}

private extension SwapVC {
    func setupTradeViews(_ model: TokenTradeModel) {
        view.backgroundColor = .air.sheetBackground
        navigationItem.title = nil
        configureNavigationItemWithTransparentBackground()
        addCloseNavigationItemIfNeeded()
        let settingsButton = UIButton(type: .system)
        settingsButton.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        settingsButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        settingsButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        if #available(iOS 26, *), IOS_26_MODE_ENABLED {
            settingsButton.configuration = .glass()
        }
        settingsButton.tintColor = .label
        settingsButton.accessibilityIdentifier = "tokenTrade.settings"
        let settings = UIBarButtonItem(customView: settingsButton)
        if #available(iOS 26, *) { settings.hidesSharedBackground = true }
        let closeItems = navigationItem.rightBarButtonItems ?? []
        navigationItem.rightBarButtonItems = closeItems + [settings]
        let interaction = ContextMenuInteraction(triggers: [.tap, .longPress], presentationMode: .zoomPopover) { [weak self] _ in
            guard let self else { return nil }
            return TokenTradeMenu.configuration(model: model,
                showSlippage: { [weak self] in self?.showTradeSlippage() },
                showProvider: { [weak self] in self?.showTradeProvider() })
        }
        interaction.attach(to: settingsButton)
        settingsButton.addAction(UIAction { [weak interaction] _ in interaction?.present() }, for: .primaryActionTriggered)
        tradeMenuInteraction = interaction
        observe {
            let isCard = model.cardCurrency != nil
            settingsButton.setImage(isCard ? UIImage(systemName: "info")
                : UIImage(named: "TokenTradeSettings", in: AirBundle, compatibleWith: nil), for: .normal)
            settingsButton.accessibilityLabel = lang(isCard ? "Info" : "Settings")
        }
        _ = addHostingController(TokenTradeView(model: model, selectMethod: { [weak self] in
            self?.showTradeMethods()
        }, continueAction: { [weak self] in
            self?.continuePressed()
        }), constraints: .fill)
    }

    func showTradeMethods() {
        guard let model = tradeModel else { return }
        presentTokenSelector(side: model.isBuying ? .selling : .buying)
    }

    func showTradeSlippage() {
        let vc = TokenTradeSlippageVC(slippage: swapModel.slippage) { [weak self] value in
            self?.swapModel.commitSlippage(value)
        }
        present(WNavigationController(rootViewController: vc), animated: true)
    }

    func showTradeProvider() {
        guard let estimate = swapModel.estimateState.cexEstimate,
              let provider = estimate.providerName else { return }
        let termsUrl = URL.sanitizedHttpUrl(from: estimate.termsOfUseUrl)
        let privacyUrl = URL.sanitizedHttpUrl(from: estimate.privacyPolicyUrl)
        let amlUrl = URL.sanitizedHttpUrl(from: estimate.amlKycPolicyUrl)
        let terms = termsUrl.map { _ in lang("$swap_cex_terms_of_use") }
        let policy = privacyUrl.map { _ in lang("$swap_cex_privacy_policy") }
        let aml = amlUrl.map { _ in L10n.swapCexAmlKycPolicyWithProvider(provider: provider) }
        let message: String
        if let terms, let policy, let aml {
            message = L10n.swapCexLegalMessageWithAml(terms: terms, policy: policy, aml: aml)
        } else if let terms, let policy {
            message = L10n.swapCexLegalMessage(terms: terms, policy: policy)
        } else {
            message = langJoin([terms, policy, aml].compactMap { $0 }, .and)
        }

        let alert = UIAlertController(
            title: L10n.crossChainExchangeProvidedByProvider(provider: provider),
            message: message.nilIfEmpty,
            preferredStyle: .alert
        )
        for (title, url) in [
            (lang("Terms of Use"), termsUrl),
            (lang("Privacy Policy"), privacyUrl),
            (lang("AML/KYC Policy"), amlUrl),
        ] {
            guard let url else { continue }
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                AppActions.openInBrowser(url, title: nil, injectDappConnect: false)
            })
        }
        alert.addAction(UIAlertAction(title: lang("OK"), style: .cancel))
        view.endEditing(true)
        present(alert, animated: true)
    }
}
