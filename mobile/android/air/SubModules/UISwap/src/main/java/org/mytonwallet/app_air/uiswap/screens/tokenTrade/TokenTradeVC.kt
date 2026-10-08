package org.mytonwallet.app_air.uiswap.screens.tokenTrade

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import java.lang.ref.WeakReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AccountSelectorView
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setSizeBounds
import org.mytonwallet.app_air.uicomponents.helpers.DieselAuthorizationHelpers
import org.mytonwallet.app_air.uicomponents.viewControllers.MfaActionConfirmVC
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorVC
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells.TokenSelectorCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisend.send.SellWithCardLauncher
import org.mytonwallet.app_air.uiswap.BuyWithCardLauncher
import org.mytonwallet.app_air.uiswap.screens.cex.SwapSendAddressOutputVC
import org.mytonwallet.app_air.uiswap.screens.cex.receiveAddressInput.SwapReceiveAddressInputVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapViewModel
import org.mytonwallet.app_air.uiswap.screens.tokenTrade.views.TokenTradeView
import org.mytonwallet.app_air.uiswap.views.SwapConfirmView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.boldSubstring
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore

/** Buys or sells one token for another asset or a card, quoting through the shared swap model. */
@SuppressLint("ViewConstructor")
class TokenTradeVC(context: Context, token: MApiSwapAsset, direction: TokenTradeDirection) :
    WViewControllerWithModelStore(context) {
    @Suppress("PropertyName")
    override val TAG = "TokenTrade"

    override var displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayBottomBar = false

    private val swapViewModel by lazy { ViewModelProvider(this)[SwapViewModel::class.java] }

    private val model = TokenTradeModel(swapViewModel, direction, token)

    private val tradeView = TokenTradeView(
        context,
        model,
        onSelectMethod = ::openMethodSelector,
        onContinue = ::continueTrade
    )

    private val accountSelectorView by lazy {
        AccountSelectorView(
            context,
            accountsProvider = { WalletCore.getAllAccounts().filter { it.supportsSwap } },
            onAccountSelected = ::switchAccount
        )
    }

    private val settingsButton by lazy {
        WImageButton(context).apply {
            updateColors(WColor.PrimaryLightText, WColor.BackgroundRipple)
            setOnClickListener { presentSettingsMenu() }
        }
    }

    private var isShowingSlippageSettings: Boolean? = null
    private var cardMaximumRequest: TokenTradeModel.CardMaximumRequest? = null
    private var cardMaximumJob: Job? = null
    private var isAutoConfirmSubmitting = false
    private var isSwapDone = false

    init {
        swapViewModel.shouldKeepSelectedPair = true
        swapViewModel.setDefaultTokens(
            sendingToken = token.takeIf { direction == TokenTradeDirection.SELL },
            receivingToken = token.takeIf { direction == TokenTradeDirection.BUY }
        )
    }

    override fun setupViews() {
        super.setupViews()

        setTopBlur(visible = false, animated = false)
        setupNavBar(true)
        navigationBar?.addCloseButton()
        if (!AccountStore.isPushedTemporary) {
            AccountStore.activeAccount?.let { accountSelectorView.config(it) }
            navigationBar?.addLeadingView(
                FrameLayout(context).apply {
                    id = View.generateViewId()
                    setPaddingRelative(8.dp, 0, 0, 0)
                    addView(accountSelectorView)
                }
            )
        }
        navigationBar?.addTrailingView(settingsButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        settingsButton.translationX = 8.dp.toFloat() * if (LocaleController.isRTL) -1f else 1f

        view.addView(tradeView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.setConstraints {
            toTop(tradeView)
            toBottom(tradeView)
            toCenterX(tradeView)
        }

        collectFlow(swapViewModel.uiInputStateFlow) {
            model.update(state = it)
            render()
        }
        collectFlow(swapViewModel.simulatedSwapFlow) {
            model.update(estimate = it)
            render()
        }
        collectFlow(swapViewModel.uiStatusFlow) {
            model.update(status = it)
            render()
        }
        collectFlow(swapViewModel.eventsFlow, ::onEvent)

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        tradeView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        tradeView.topInset = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
        tradeView.bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        tradeView.setPaddingRelative(systemBarStartInset, 0, systemBarEndInset, 0)
        tradeView.requestLayout()
    }

    private fun render() {
        tradeView.render()
        if (isAutoConfirmSubmitting) tradeView.continueButton.isLoading = true

        // The settings icon appears only when the menu offers Slippage; otherwise it is info only.
        val hasSlippage = model.cardCurrency == null && !model.isCrossChain
        if (isShowingSlippageSettings != hasSlippage) {
            isShowingSlippageSettings = hasSlippage
            settingsButton.setImageDrawable(
                context.getDrawableCompat(
                    if (hasSlippage) {
                        org.mytonwallet.app_air.icons.R.drawable.ic_token_trade_top_settings
                    } else {
                        org.mytonwallet.app_air.icons.R.drawable.ic_token_trade_top_info
                    }
                )
            )
            settingsButton.setPaddingDp(8)
            settingsButton.contentDescription =
                LocaleController.getString(if (hasSlippage) "Settings" else "Info")
        }
        refreshCardMaximumIfNeeded()
    }

    private fun refreshCardMaximumIfNeeded() {
        val request = model.cardMaximumRequest()
        if (request == cardMaximumRequest) return
        cardMaximumRequest = request
        cardMaximumJob?.cancel()
        model.clearCardMaximum()
        request ?: return
        cardMaximumJob = swapViewModel.viewModelScope.launch {
            if (model.refreshCardMaximum(request)) tradeView.render()
        }
    }

    private fun switchAccount(account: MAccount) {
        accountSelectorView.setLoading(true)
        WalletCore.ensureAccountActivated(account.accountId) { accountChanged ->
            if (accountChanged) {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(persistedAccountsModified = false)
                )
            }
            view.post { onAccountSwitched(account) }
        }
    }

    private fun onAccountSwitched(account: MAccount) {
        displayedAccount = DisplayedAccount(account.accountId, isPushedTemporary = false)
        accountSelectorView.setLoading(false)
        accountSelectorView.config(account)
        model.resetAmount()
        render()
    }

    private fun openMethodSelector() {
        if (model.isBuying) {
            swapViewModel.openTokenToSendSelector()
        } else {
            swapViewModel.openTokenToReceiveSelector(showUnsupportedAssets = true)
        }
    }

    private fun presentSelector(assets: List<MApiSwapAsset>, supportedAssetSlugs: Set<String>?) {
        val window = window ?: return
        val subtitle = LocaleController.getString(
            if (model.isBuying) "Buy with Card" else "Sell on Card"
        )
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        nav.setRoot(
            TokenSelectorVC(
                context,
                LocaleController.getString(if (model.isBuying) "Pay With" else "You Receive"),
                assets,
                showMyAssets = true,
                showChain = true,
                secondaryAmountMode = TokenSelectorCell.SecondaryAmountMode.BALANCE_VALUE_OR_PRICE,
                fiatOptions = model.availableCardCurrencies.map { currency ->
                    TokenSelectorVC.FiatOption(currency, subtitle) {
                        model.selectCard(currency)
                        render()
                    }
                },
                showsAssetCategories = true,
                requiresBalance = model.isBuying,
                showOnlyMyAssets = model.isBuying,
                supportedAssetSlugs = supportedAssetSlugs
            ).apply {
                setOnAssetSelectListener { asset ->
                    model.selectToken(asset)
                    render()
                }
            }
        )
        window.present(nav)
    }

    private fun continueTrade() {
        val currency = model.cardCurrency
        if (currency == null) {
            if (swapViewModel.shouldAuthorizeDiesel) {
                DieselAuthorizationHelpers.authorizeDiesel(context)
                return
            }
            swapViewModel.openSwapConfirmation(null)
            return
        }
        if (!model.canContinue) return
        if (model.isBuying) {
            val chain = model.token.chain ?: return
            BuyWithCardLauncher.buyWithCardUrl(chain, currency) { url ->
                if (url != null) {
                    CustomTabsBrowser.open(context, url)
                } else {
                    showError(MBridgeError.Type.SERVER_ERROR)
                }
            }
        } else {
            val account = AccountStore.activeAccount ?: return
            SellWithCardLauncher.launch(
                caller = WeakReference(this),
                account = account,
                tokenSlug = model.token.slug,
                requestedAmount = model.typedTokenAmount,
                requestedCurrency = currency
            )
        }
    }

    private fun presentSettingsMenu() {
        val items = mutableListOf(
            menuItem(LocaleController.getString("Exchange Rate"), model.rateText)
        )
        model.menuFeeText?.let { items += menuItem(LocaleController.getString("Fee"), it) }
        if (model.cardCurrency == null) {
            if (!model.isCrossChain) {
                items += menuItem(
                    LocaleController.getString("Price Impact"),
                    model.priceImpactText,
                    showsInfo = true,
                    shouldKeepOpen = true
                ) {
                    showAlert(
                        LocaleController.getString("Price Impact"),
                        LocaleController.getString("\$swap_price_impact_tooltip1") + "\n\n" +
                            LocaleController.getString("\$swap_price_impact_tooltip2"),
                        LocaleController.getString("OK")
                    )
                }
                items += menuItem(
                    LocaleController.getString("Minimum Received"),
                    model.minimumReceivedText,
                    showsInfo = true,
                    shouldKeepOpen = true
                ) {
                    showAlert(
                        LocaleController.getString("Minimum Received"),
                        LocaleController.getString("\$swap_minimum_received_tooltip2"),
                        LocaleController.getString("OK")
                    )
                }
                val slippageText = model.swapState?.slippage?.let { slippage ->
                    if (slippage % 1f == 0f) slippage.toInt().toString() else slippage.toString()
                }
                if (!slippageText.isNullOrBlank()) {
                    items.lastOrNull { !it.getSubTitle().isNullOrBlank() }?.hasSeparator = true
                }
                items += menuItem(
                    LocaleController.getString("Slippage"),
                    slippageText?.let { "$it%" },
                    showsChevron = true
                ) { presentSlippage() }
            } else {
                val providerName = model.cexEstimate?.providerName?.takeIf { it.isNotBlank() }
                items += menuItem(
                    LocaleController.getString("Cross-chain Provider"),
                    providerName,
                    showsInfo = providerName != null,
                    onTap = providerName?.let { { presentProvider() } }
                )
            }
        }
        WMenuPopup.present(
            settingsButton,
            items,
            popupWidth = 242.dp,
            positioning = WMenuPopup.Positioning.ALIGNED,
            windowBackgroundStyle = WMenuPopup.BackgroundStyle.Cutout.fromView(
                settingsButton,
                roundRadius = settingsButton.height / 2f
            ),
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    private fun menuItem(
        title: String,
        value: String?,
        showsInfo: Boolean = false,
        showsChevron: Boolean = false,
        shouldKeepOpen: Boolean = false,
        onTap: (() -> Unit)? = null
    ) = WMenuPopup.Item(
        WMenuPopup.Item.Config.Item(
            icon = null,
            title = if (showsInfo) titleWithInfoIcon(title) else title,
            subtitle = value?.ifEmpty { null } ?: "—",
            trailingViewProvider = if (showsChevron) ::menuChevronView else null
        ),
        shouldKeepOpen = shouldKeepOpen,
        onTap = onTap
    )

    private fun titleWithInfoIcon(title: String): CharSequence {
        val icon = context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_info_24)
            ?.mutate() ?: return title
        icon.setTint(WColor.SecondaryText.color)
        icon.alpha = 153
        icon.setSizeBounds(16.dp, 16.dp)
        return buildSpannedString {
            append(title)
            inSpans(
                VerticalImageSpan(icon, startPadding = 4.dp, isRTL = LocaleController.isRTL)
            ) { append(" ") }
        }
    }

    private fun menuChevronView(): View = AppCompatImageView(context).apply {
        setImageDrawable(
            context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_menu_arrow_right)
                ?.mutate()?.apply { setTint(WColor.PrimaryLightText.color) }
        )
        if (LocaleController.isRTL) scaleX = -1f
    }

    private fun presentSlippage() {
        val window = window ?: return
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet,
                aboveKeyboard = true
            )
        )
        nav.setRoot(TokenTradeSlippageVC(context, model.slippage) { swapViewModel.setSlippage(it) })
        window.present(nav)
    }

    private fun presentProvider() {
        val estimate = model.cexEstimate?.takeIf { !it.providerName.isNullOrBlank() } ?: return
        val window = window ?: return
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        nav.setRoot(TokenTradeProviderVC(context, estimate))
        window.present(nav)
    }

    private fun onEvent(event: SwapViewModel.Event) {
        when (event) {
            is SwapViewModel.Event.ShowSelector -> presentSelector(
                event.assets,
                event.supportedAssetSlugs
            )

            is SwapViewModel.Event.ShowAddressToReceiveInput -> {
                push(
                    SwapReceiveAddressInputVC(
                        context,
                        estimate = event.request,
                        callback = { address -> swapViewModel.openSwapConfirmation(address) }
                    )
                )
            }

            is SwapViewModel.Event.ShowAddressToSend -> {
                isSwapDone = true
                push(
                    viewController = SwapSendAddressOutputVC(
                        context,
                        event.estimate.request.tokenToSend,
                        event.estimate.request.tokenToReceive,
                        event.estimate.fromAmount,
                        event.estimate.toAmount,
                        event.cex.payinAddress,
                        event.cex.transactionId,
                        event.response.swap.cexLabel ?: event.estimate.cex?.cexLabel,
                        event.response.swap.cex?.providerName,
                        event.response.swap.cex?.supportUrl,
                        event.response.swap.cex?.supportEmail
                    ),
                    onCompletion = { navigationController?.removePrevViewControllers() }
                )
            }

            is SwapViewModel.Event.ShowConfirm -> {
                if (event.request.shouldShowPriceImpactWarning) {
                    showAlert(
                        title = LocaleController.getString("Warning"),
                        text = priceImpactWarningMessage(event.request.dex?.impact),
                        button = LocaleController.getString("Swap"),
                        buttonPressed = { showConfirm(event) },
                        secondaryButton = LocaleController.getString("Cancel"),
                        primaryIsDanger = true
                    )
                } else {
                    showConfirm(event)
                }
            }

            is SwapViewModel.Event.SwapComplete -> onSwapComplete(event)

            is SwapViewModel.Event.MfaRequested -> {
                stopAutoConfirmSubmitting()
                presentMfaConfirm(event)
            }

            is SwapViewModel.Event.ClearEstimateLayout -> {}
        }
    }

    private fun onSwapComplete(event: SwapViewModel.Event.SwapComplete) {
        if (!event.success) {
            stopAutoConfirmSubmitting()
            if (navigationController?.viewControllers?.lastOrNull() is PasscodeConfirmVC) pop()
            showError(event.error)
            return
        }
        if (isSwapDone) return
        isSwapDone = true
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        window?.dismissLastNav {
            val activity = event.activity ?: return@dismissLastNav
            val accountId = displayedAccount.accountId ?: run {
                Logger.e(
                    Logger.LogTag.SWAP,
                    "Trade activity could not be opened: displayed account is missing"
                )
                return@dismissLastNav
            }
            WalletCore.notifyEvent(
                WalletEvent.OpenActivity(
                    accountId,
                    activity,
                    if (event.isOnchain) LocaleController.getString("Swapped") else null
                )
            )
        }
    }

    private fun stopAutoConfirmSubmitting() {
        if (!isAutoConfirmSubmitting) return
        isAutoConfirmSubmitting = false
        view.unlockView()
        tradeView.continueButton.isLoading = false
    }

    private fun showConfirm(event: SwapViewModel.Event.ShowConfirm) {
        if (isAutoConfirmSubmitting) return
        // The duration notice stays on this screen. An active session confirms from here.
        if (event.request.isBatchTx) {
            showPasscodeConfirm(event, allowsAutoConfirm = true)
            return
        }
        ProtectedActionAuth.confirm(
            onConfirmed = { token ->
                isAutoConfirmSubmitting = true
                view.lockView()
                tradeView.continueButton.isLoading = true
                swapViewModel.doSend(token, event.request, event.addressToReceive)
            },
            onPasscodeRequired = { showPasscodeConfirm(event) }
        )
    }

    private fun showPasscodeConfirm(
        event: SwapViewModel.Event.ShowConfirm,
        allowsAutoConfirm: Boolean = false
    ) {
        val request = event.request
        push(
            PasscodeConfirmVC(
                context,
                PasscodeViewState.CustomHeader(
                    SwapConfirmView(context).apply {
                        config(
                            request.request.tokenToSend,
                            request.request.tokenToReceive,
                            request.fromAmount,
                            request.toAmount
                        )
                        if (request.isBatchTx) {
                            setBatchNotice(
                                LocaleController.getString("\$swap_batch_tx_duration_hint")
                            )
                        }
                    },
                    LocaleController.getString("Confirm")
                ),
                task = { passcode ->
                    swapViewModel.doSend(passcode, request, event.addressToReceive)
                },
                allowsAutoConfirm = allowsAutoConfirm
            )
        )
    }

    private fun presentMfaConfirm(event: SwapViewModel.Event.MfaRequested) {
        val request = event.estimate.request
        val fromAmount = event.estimate.dex?.fromAmount
            ?.stripTrailingZeros()?.toPlainString().orEmpty()
        val toAmount = event.estimate.dex?.toAmount
            ?.stripTrailingZeros()?.toPlainString().orEmpty()
        val chipText = listOf(
            "$fromAmount ${request.tokenToSend.symbol ?: ""}".trim(),
            "→",
            "$toAmount ${request.tokenToReceive.symbol ?: ""}".trim()
        ).joinToString(" ")
        val swapId = event.swapId
        val accountId = AccountStore.activeAccountId
        val mfaVC = MfaActionConfirmVC(
            context,
            requestHash = event.requestHash,
            chip = MfaActionConfirmVC.Chip(leading = request.tokenToSend, text = chipText),
            onConfirmed = { txHash ->
                if (swapId != null && accountId != null && !txHash.isNullOrBlank()) {
                    WalletCore.scope.launch {
                        try {
                            WalletCore.call(
                                ApiMethod.Swap.ConfirmSwapMfaRequest(accountId, swapId, txHash)
                            )
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: JSWebViewBridge.ApiError) {
                            Logger.e(
                                Logger.LogTag.ACCOUNT,
                                "confirmSwapMfaRequest failed for swapId=$swapId " +
                                    "apiError=${e.parsed.type}"
                            )
                        } catch (e: Exception) {
                            Logger.e(
                                Logger.LogTag.ACCOUNT,
                                "confirmSwapMfaRequest failed for swapId=$swapId " +
                                    "error=${e.javaClass.simpleName}"
                            )
                        }
                    }
                }
                swapViewModel.onMfaConfirmed()
            }
        )
        val hasPasscodeScreen =
            navigationController?.viewControllers?.lastOrNull() is PasscodeConfirmVC
        navigationController?.push(mfaVC, onCompletion = {
            if (hasPasscodeScreen) navigationController?.removePrevViewControllerOnly()
        })
    }

    private fun priceImpactWarningMessage(impact: Double?): CharSequence {
        val impactValueText = LocaleController.getStringWithKeyValues(
            "The exchange rate is below market value!",
            listOf(Pair("%value%", "$impact%"))
        )
        val hintText = LocaleController.getString(
            "We do not recommend to perform an exchange, try to specify a lower amount."
        )
        return "$impactValueText\n$hintText".boldSubstring(impactValueText)
    }
}
