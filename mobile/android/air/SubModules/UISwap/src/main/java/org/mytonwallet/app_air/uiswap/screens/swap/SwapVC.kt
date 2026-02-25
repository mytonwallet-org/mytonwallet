package org.mytonwallet.app_air.uiswap.screens.swap

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.core.widget.NestedScrollView
import androidx.lifecycle.ViewModelProvider
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.extensions.setTextIfDiffer
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.DieselAuthorizationHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.viewControllers.selector.TokenSelectorVC
import org.mytonwallet.app_air.uicomponents.widgets.ExpandableFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uiswap.screens.cex.SwapSendAddressOutputVC
import org.mytonwallet.app_air.uiswap.screens.cex.receiveAddressInput.SwapReceiveAddressInputVC
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapDetailsVisibility
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapAssetInputView
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapChangellyView
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapEstimatedHeader
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapEstimatedInfo
import org.mytonwallet.app_air.uiswap.screens.swap.views.SwapSwapAssetsButton
import org.mytonwallet.app_air.uiswap.screens.swap.views.dexAggregatorDialog.DexAggregatorDialog
import org.mytonwallet.app_air.uiswap.views.SwapConfirmView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.boldSubstring
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class SwapVC(
    context: Context,
    defaultSendingToken: MApiSwapAsset? = null,
    defaultReceivingToken: MApiSwapAsset? = null,
    amountIn: Double? = null
) :
    WViewControllerWithModelStore(context) {
    override val TAG = "Swap"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private val swapViewModel by lazy { ViewModelProvider(this)[SwapViewModel::class.java] }

    private val scrollView = NestedScrollView(context).apply {
        id = View.generateViewId()
        overScrollMode = NestedScrollView.OVER_SCROLL_ALWAYS
        isVerticalScrollBarEnabled = false
    }
    private val contentLayout = FrameLayout(context)
    private val linearLayout = LinearLayout(context)

    private val swapAssetsButton = SwapSwapAssetsButton(context)
    private val sendAmount = SwapAssetInputView(context)
    private val receiveAmount = SwapAssetInputView(context)
    private val alertView = WAlertLabel(
        context,
        alertColor = WColor.Red.color
    ).apply {
        isGone = true
    }

    private val continueButton = WButton(context)

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    private val changellyView = SwapChangellyView(context)

    private val estOuterContainer = ConstraintLayout(context)
    private val estShowMoreContainer = ExpandableFrameLayout(context).apply {
        id = View.generateViewId()
        expanded = true
    }
    private val estShowMore = SwapEstimatedHeader(context)
    private val estLayout = SwapEstimatedInfo(context, onDexPopupPressed = {
        swapViewModel.getLastResponse()?.let { res ->
            res.dex?.let { dex ->
                if ((dex.all?.size ?: 0) < 2)
                    return@SwapEstimatedInfo
                val bestDexLabel = dex.bestDexLabel ?: dex.dexLabel ?: return@SwapEstimatedInfo
                val selectedDex = res.dex.dexLabel ?: return@SwapEstimatedInfo
                lateinit var dialogRef: WDialog
                dialogRef = DexAggregatorDialog.create(
                    context,
                    res.request.tokenToSend,
                    res.request.tokenToReceive,
                    dex.all ?: emptyList(),
                    bestDexLabel,
                    selectedDex,
                    onSelect = {
                        swapViewModel.setDex(if (it == dex.bestDexLabel) null else it)
                        dialogRef.dismiss()
                    }
                )
                dialogRef.presentOn(this)
            }
        }
    }, onSlippageChange = {
        swapViewModel.setSlippage(it)
    }, onDialogShowListener = { title, info ->
        showAlert(title, info, LocaleController.getString("Close"))
    }, onPresentDialog = { dialogRef ->
        dialogRef?.presentOn(this)
    }).apply {
        id = View.generateViewId()
    }

    private var ignoreTextChanges = false

    private val sendAmountTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            if (!ignoreTextChanges) {
                swapViewModel.onTokenToSendAmountInput(s?.toString() ?: "")
            }
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private val receiveAmountTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            if (!ignoreTextChanges) {
                swapViewModel.onTokenToReceiveAmountInput(s?.toString() ?: "")
            }
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    init {
        if (defaultSendingToken != null)
            swapViewModel.setTokenToSend(defaultSendingToken)
        if (defaultReceivingToken != null) {
            estLayout.setEstimated(null, toToken = defaultReceivingToken)
            swapViewModel.setTokenToReceive(defaultReceivingToken)
        }
        if (amountIn != null)
            swapViewModel.setAmount(amountIn)
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Swap"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))

        continueButton.id = View.generateViewId()

        scrollView.addView(contentLayout, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        linearLayout.orientation = LinearLayout.VERTICAL
        contentLayout.addView(linearLayout, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val topSpace = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp

        contentLayout.addView(
            swapAssetsButton,
            FrameLayout.LayoutParams(32.dp, 32.dp).apply {
                gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
                topMargin = 80.dp + topSpace
            })

        sendAmount.setMode(SwapAssetInputView.Mode.SELL)

        linearLayout.addView(
            View(context),
            ViewGroup.LayoutParams(MATCH_PARENT, topSpace)
        )
        linearLayout.addView(sendAmount)
        receiveAmount.setMode(SwapAssetInputView.Mode.BUY)
        linearLayout.addView(receiveAmount)
        linearLayout.addView(
            alertView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = ViewConstants.GAP.dp
            })

        linearLayout.addView(
            View(context),
            ViewGroup.LayoutParams(MATCH_PARENT, ViewConstants.GAP.dp)
        )

        linearLayout.addView(changellyView)
        estShowMoreContainer.addView(estShowMore)
        estOuterContainer.addView(estLayout)
        estOuterContainer.addView(
            estShowMoreContainer,
            ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        estOuterContainer.setConstraints {
            toTop(estShowMoreContainer)
            topToBottom(estLayout, estShowMoreContainer, -8f)
            toBottom(estLayout)
        }
        linearLayout.addView(estOuterContainer)

        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))

        view.setConstraints {
            toCenterX(scrollView)
            toTop(scrollView)
            toBottom(scrollView)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
            topToTop(
                bottomReversedCornerViewUpsideDown,
                continueButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
        }

        updateTheme()

        estShowMore.setOnClickListener {
            estLayout.expanded = !estLayout.expanded
            estShowMore.isExpanded.animatedValue = estLayout.expanded
        }

        continueButton.setOnClickListener {
            if (swapViewModel.shouldAuthorizeDiesel) {
                DieselAuthorizationHelpers.authorizeDiesel(context)
                return@setOnClickListener
            }
            swapViewModel.openSwapConfirmation(null)
        }

        swapAssetsButton.setOnClickListener {
            val send = sendAmount.amountEditText.text.toString()
            val receive = receiveAmount.amountEditText.text.toString()

            ignoreTextChanges = true
            sendAmount.amountEditText.text?.replace(0, send.length, receive)
            receiveAmount.amountEditText.text?.replace(0, receive.length, send)
            ignoreTextChanges = false

            swapViewModel.swapTokens()
        }
        sendAmount.assetView.setOnClickListener { swapViewModel.openTokenToSendSelector() }
        sendAmount.setOnMaxBalanceClickListener { swapViewModel.tokenToSendSetMaxAmount() }
        sendAmount.amountEditText.addTextChangedListener(sendAmountTextWatcher)

        receiveAmount.assetView.setOnClickListener { swapViewModel.openTokenToReceiveSelector() }
        receiveAmount.amountEditText.addTextChangedListener(receiveAmountTextWatcher)
        receiveAmount.amountEditText.setOnClickListener {
            if (!receiveAmount.amountEditText.isFocusable) {
                Haptics.play(context, HapticType.LIGHT_TAP)
                Toast.makeText(
                    context,
                    LocaleController.getString($$"$swap_reverse_prohibited"),
                    Toast.LENGTH_SHORT
                ).show()
            }
        }

        collectFlow(swapViewModel.uiInputStateFlow) {
            changellyView.expanded = it.isCex
            sendAmount.setAsset(it.tokenToSend)
            sendAmount.setBalance(it.tokenToSendMaxAmount)
            receiveAmount.setAsset(it.tokenToReceive)
            if (it.isCex && receiveAmount.amountEditText.isFocused) {
                sendAmount.amountEditText.requestFocus()
            }

            sendAmount.amountEditText.isEnabled = it.tokenToSend != null
            receiveAmount.amountEditText.apply {
                val enabled = it.tokenToReceive != null && !it.isCex
                isFocusable = enabled
                isFocusableInTouchMode = enabled
                isCursorVisible = enabled
            }
            when (it.swapDetailsVisibility) {
                SwapDetailsVisibility.VISIBLE -> {
                    estShowMoreContainer.expanded = true
                    estLayout.setIsCex(false)
                }

                SwapDetailsVisibility.CEX -> {
                    estShowMoreContainer.expanded = true
                    estLayout.setIsCex(true)
                }

                SwapDetailsVisibility.GONE -> {
                    estShowMoreContainer.expanded = false
                    estShowMore.isExpanded.animatedValue = false
                    estLayout.expanded = false
                }
            }

            val editView = if (it.reverse) receiveAmount else sendAmount

            ignoreTextChanges = true
            editView.amountEditText.setTextIfDiffer(it.amountInput, selectionToEnd = false)
            ignoreTextChanges = false
        }

        collectFlow(swapViewModel.simulatedSwapFlow) { est ->
            if (est?.shouldShowPriceImpactWarning == true) {
                alertView.text = priceImpactWarningMessage(est.dex?.impact)
                animateAlertViewIn()
            } else {
                animateAlertViewOut()
            }
            estLayout.setEstimated(
                est,
                toToken = est?.request?.tokenToReceive ?: swapViewModel.tokenToReceive
            )
            ignoreTextChanges = true
            est?.let { estimate ->
                if (!estimate.request.reverse) {
                    if (estimate.request.isFromAmountMax) {
                        if (
                            (estimate.fromAmount ?: BigInteger.ZERO) > BigInteger.ZERO &&
                            estimate.fromAmountDecimalStr != null
                        ) {
                            sendAmount.amountEditText.setTextIfDiffer(
                                estimate.fromAmountDecimalStr,
                                selectionToEnd = false
                            )
                            sendAmount.setBalance(swapViewModel.tokenToSendMaxAmount)
                        }
                    }
                    receiveAmount.amountEditText.setTextIfDiffer(
                        estimate.toAmountDecimalStr,
                        selectionToEnd = false
                    )
                } else {
                    sendAmount.amountEditText.setTextIfDiffer(
                        estimate.fromAmountDecimalStr,
                        selectionToEnd = false
                    )
                }
            } ?: run {
                if (!swapViewModel.isReverse()) {
                    receiveAmount.amountEditText.text?.clear()
                } else {
                    sendAmount.amountEditText.text?.clear()
                }
            }
            ignoreTextChanges = false
        }

        collectFlow(swapViewModel.uiStatusFlow) {
            continueButton.isLoading = it.button.status.isLoading
            if (!it.button.status.isLoading) {
                continueButton.isEnabled = it.button.status.isEnabled
                continueButton.isError = it.button.status.isError
                continueButton.text = it.button.title
            }

            receiveAmount.amountEditText.isLoading.animatedValue = it.tokenToReceive.isLoading
                && (receiveAmount.amountEditText.text?.isNotEmpty() == true)
            receiveAmount.amountEditText.isError.animatedValue = it.tokenToReceive.isError

            sendAmount.amountEditText.isLoading.animatedValue = it.tokenToSend.isLoading
                && (sendAmount.amountEditText.text?.isNotEmpty() == true)
            sendAmount.amountEditText.isError.animatedValue = it.tokenToSend.isError
        }

        collectFlow(swapViewModel.eventsFlow, this::onEvent)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        estShowMoreContainer.setBackgroundColor(WColor.Background.color)
        estOuterContainer.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            true
        )
    }

    var isSwapDone = false
    private fun onEvent(event: SwapViewModel.Event) {
        when (event) {
            is SwapViewModel.Event.ShowSelector -> {
                view.hideKeyboard()
                val titleToShow = when (event.mode) {
                    SwapViewModel.Mode.RECEIVE -> LocaleController.getString("Buy")
                    SwapViewModel.Mode.SEND -> LocaleController.getString("Sell")
                }
                push(
                    TokenSelectorVC(
                        context,
                        titleToShow,
                        event.assets,
                        showMyAssets = true,
                        showChain = true,
                    ).apply {
                        setOnAssetSelectListener { asset ->
                            if (event.mode == SwapViewModel.Mode.SEND) {
                                swapViewModel.setTokenToSend(asset)
                            } else {
                                estLayout.setEstimated(null, toToken = asset)
                                swapViewModel.setTokenToReceive(asset)
                            }
                        }
                    })
            }

            is SwapViewModel.Event.ShowAddressToReceiveInput -> {
                val request = event.request
                view.hideKeyboard()
                push(
                    SwapReceiveAddressInputVC(
                        context,
                        estimate = request,
                        callback = { address ->
                            swapViewModel.openSwapConfirmation(address)
                        }
                    ))
            }

            is SwapViewModel.Event.ShowAddressToSend -> {
                view.hideKeyboard()
                push(
                    SwapSendAddressOutputVC(
                        context,
                        event.estimate.request.tokenToSend,
                        event.estimate.request.tokenToReceive,
                        event.estimate.fromAmount,
                        event.estimate.toAmount,
                        event.cex.payinAddress,
                        event.cex.transactionId
                    )
                )
            }

            is SwapViewModel.Event.ShowConfirm -> {
                if (event.request.shouldShowPriceImpactWarning) {
                    showAlert(
                        title = LocaleController.getString("Warning"),
                        text = priceImpactWarningMessage(event.request.dex?.impact),
                        button = LocaleController.getString("Swap"),
                        buttonPressed = {
                            showConfirm(event)
                        },
                        secondaryButton = LocaleController.getString("Cancel"),
                        primaryIsDanger = true
                    )
                } else {
                    showConfirm(event)
                }
            }

            is SwapViewModel.Event.SwapComplete -> {
                val success = event.success
                Logger.d(Logger.LogTag.SWAP, "onEvent: SwapComplete success=$success")
                if (success) {
                    if (isSwapDone)
                        return
                    isSwapDone = true
                    if (window?.topNavigationController != navigationController) {
                        window?.dismissNav(navigationController)
                        return
                    }
                    window?.dismissLastNav {
                        event.activity?.let { activity ->
                            WalletCore.notifyEvent(
                                WalletEvent.OpenActivity(
                                    displayedAccount?.accountId!!,
                                    activity
                                )
                            )
                        }
                    }
                } else {
                    pop()
                    showError(event.error)
                }
            }

            is SwapViewModel.Event.ClearEstimateLayout -> {
                estLayout.setEstimated(null, null)
            }
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            20.dp +
                ViewConstants.BLOCK_RADIUS.dp.roundToInt() +
                continueButton.buttonHeight +
                max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
        )
        scrollView.clipToPadding = false
        view.setConstraints {
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun showConfirm(event: SwapViewModel.Event.ShowConfirm) {
        val request = event.request
        Logger.d(Logger.LogTag.SWAP, "showConfirm: fromToken=${request.request.tokenToSend.symbol} toToken=${request.request.tokenToReceive.symbol}")
        view.hideKeyboard()
        val confirmActionVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                SwapConfirmView(context).apply {
                    config(
                        request.request.tokenToSend,
                        request.request.tokenToReceive,
                        request.fromAmount,
                        request.toAmount
                    )
                },
                LocaleController.getString("Confirm")
            ), task = { passcode ->
                swapViewModel.doSend(passcode, request, event.addressToReceive)
            })
        push(confirmActionVC)
    }

    private fun priceImpactWarningMessage(impact: Double?): CharSequence {
        val impactValueText = LocaleController.getStringWithKeyValues(
            "The exchange rate is below market value!",
            listOf(
                Pair("%value%", "$impact%")
            )
        )
        val hintText =
            LocaleController.getString("We do not recommend to perform an exchange, try to specify a lower amount.")
        val fullText = "$impactValueText\n$hintText"
        return fullText.boldSubstring(impactValueText)
    }

    private var isShowingAlertView = false

    private fun animateAlertViewIn() {
        if (isShowingAlertView) return
        isShowingAlertView = true

        alertView.apply {
            measure(linearLayout.width.exactly, 0.unspecified)
            val targetHeight = measuredHeight
            val lp = layoutParams as ViewGroup.MarginLayoutParams
            lp.height = 0
            lp.topMargin = 0
            layoutParams = lp
            visibility = View.VISIBLE
            alpha = 0f

            val expandAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION / 2
                addUpdateListener { anim ->
                    val progress = anim.animatedValue as Float
                    lp.height = (targetHeight * progress).toInt()
                    lp.topMargin = (ViewConstants.GAP.dp * progress).toInt()
                    layoutParams = lp
                }
            }

            val fadeInAnimator = ObjectAnimator.ofFloat(this, "alpha", 0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION / 2
            }

            AnimatorSet().apply {
                playSequentially(expandAnimator, fadeInAnimator)
                start()
            }
        }
    }

    private fun animateAlertViewOut() {
        if (!isShowingAlertView) return
        isShowingAlertView = false

        alertView.apply {
            val initialHeight = measuredHeight
            val lp = layoutParams as ViewGroup.MarginLayoutParams
            val initialMargin = lp.topMargin

            val fadeOutAnimator = ObjectAnimator.ofFloat(this, "alpha", 1f, 0f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION / 2
            }

            val collapseAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION / 2
                addUpdateListener { anim ->
                    val progress = anim.animatedValue as Float
                    lp.height = (initialHeight * progress).toInt()
                    lp.topMargin = (initialMargin * progress).toInt()
                    layoutParams = lp
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        visibility = View.GONE
                        lp.height = WRAP_CONTENT
                        lp.topMargin = 0
                        layoutParams = lp
                    }
                })
            }

            AnimatorSet().apply {
                playSequentially(fadeOutAnimator, collapseAnimator)
                start()
            }
        }
    }
}
