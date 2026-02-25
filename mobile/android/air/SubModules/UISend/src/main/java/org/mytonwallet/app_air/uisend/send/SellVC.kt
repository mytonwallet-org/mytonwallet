package org.mytonwallet.app_air.uisend.send

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uisend.send.lauouts.ConfirmAmountView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class SellVC(
    context: Context,
    private val initialTokenSlug: String? = null,
    private val initialValues: InitialValues? = null,
) : WViewControllerWithModelStore(context), WalletCore.EventObserver {

    data class InitialValues(
        val address: String?,
        val amount: String? = null,
        val comment: String? = null,
    )

    override val TAG = "Sell"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private var isShowingAccountMultichain =
        WGlobalStorage.isMultichain(AccountStore.activeAccountId!!)

    private val viewModel by lazy { ViewModelProvider(this)[SendViewModel::class.java] }

    private var latestAddressInfo: SendViewModel.AddressInfo? = null
    private var latestUiState: SendViewModel.UiState? = null

    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    private val amountInfoView by lazy {
        ConfirmAmountView(context).apply {
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        }
    }
    private val title1 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Send to"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val addressInputView by lazy {
        CopyTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 19, 20, 14)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            clipLabel = "Address"
            clipToast = LocaleController.getString("Address was copied!")
        }
    }

    private val commentInputView by lazy {
        AppCompatTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 20, 20, 14)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        }
    }

    private val gap1 = ListGapCell(context)
    private val title2 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Amount"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val gap2 = ListGapCell(context)
    private val title3 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Comment or Memo"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val linearLayout by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(title1)
            addView(addressInputView)
            addView(gap1)
            addView(title2)
            addView(amountInfoView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(gap2)
            addView(title3)
            addView(commentInputView, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }

    private val scrollView by lazy {
        ScrollView(context).apply {
            addView(
                linearLayout,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    WRAP_CONTENT
                )
            )
            id = View.generateViewId()
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            isVerticalScrollBarEnabled = false
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering) {
                setHorizontalPadding(0f)
            }
        }

    private val confirmButton by lazy {
        WButton(context, WButton.Type.PRIMARY).apply {
            id = View.generateViewId()
            text = LocaleController.getString("Sell")
            isEnabled = false
            setOnClickListener {
                onConfirmClicked()
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)

        setNavTitle(LocaleController.getString("Sell"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(confirmButton, ViewGroup.LayoutParams(0, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, confirmButton, 20f)
            toBottomPx(
                confirmButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
            topToTop(
                bottomReversedCornerViewUpsideDown,
                confirmButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toLeft(confirmButton)
            toRight(confirmButton)
            setMargin(confirmButton.id, ConstraintSet.START, 20.dp)
            setMargin(confirmButton.id, ConstraintSet.END, 20.dp)
        }

        initialTokenSlug?.let {
            viewModel.onInputToken(it)
        }
        setInitialValues()
        confirmButton.isLoading = true

        collectFlow(viewModel.uiStateFlow) { uiState ->
            latestUiState = uiState
            renderState(uiState)
        }

        collectFlow(viewModel.addressInfoFlow) { info ->
            latestAddressInfo = info
            latestUiState?.let { state ->
                renderAddressAndButton(state)
            }
        }

        collectFlow(viewModel.uiEventFlow) { event ->
            when (event) {
                is SendViewModel.UiEvent.ShowAlert -> showAlert(event.title, event.message)
            }
        }

        updateTheme()
        insetsUpdated()
    }

    private fun renderState(uiState: SendViewModel.UiState) {
        renderAmountAndComment(uiState)
        renderAddressAndButton(uiState)
        renderButton(uiState)
    }

    private fun renderAmountAndComment(uiState: SendViewModel.UiState) {
        val completeInput = uiState.inputState as? SendViewModel.InputStateFull.Complete ?: return
        val draftResult = uiState.draft as? SendViewModel.DraftResult.Result
        val isInsufficientBalance =
            uiState.uiButton.status == SendViewModel.ButtonStatus.NotEnoughToken ||
                uiState.uiButton.status == SendViewModel.ButtonStatus.NotEnoughNativeToken

        val amount = if (isInsufficientBalance) {
            buildSpannedString {
                inSpans(WForegroundColorSpan(WColor.Red)) {
                    append(completeInput.amountEquivalent.getFmt(false))
                }
            }
        } else {
            SpannableStringBuilder(completeInput.amountEquivalent.getFmt(false)).also {
                CoinUtils.setSpanToFractionalPart(it, WForegroundColorSpan(WColor.SecondaryText))
            }
        }
        val feeValue = draftResult?.showingFee?.toString(
            completeInput.token,
            appendNonNative = true
        )
        val feeText = if (isInsufficientBalance || feeValue.isNullOrEmpty()) {
            null
        } else {
            LocaleController.getString("\$fee_value_with_colon").replace(
                "%fee%",
                feeValue
            )
        }
        amountInfoView.set(
            Content.of(completeInput.token, showChain = isShowingAccountMultichain),
            amount = amount,
            currency = completeInput.amountEquivalent.getFmt(true),
            fee = feeText
        )
        val comment = completeInput.input.comment
        commentInputView.text = comment
        updateCommentVisibility(comment)
    }

    private fun renderButton(uiState: SendViewModel.UiState) {
        val tokenSymbol = when (val input = uiState.inputState) {
            is SendViewModel.InputStateFull.Complete -> input.token.symbol
            is SendViewModel.InputStateFull.Incomplete -> input.token?.symbol
        } ?: MBaseCurrency.TON.currencyCode
        val sellButtonTitle = LocaleController.getStringWithKeyValues(
            "Sell %symbol%",
            listOf("%symbol%" to tokenSymbol)
        )
        val isLoading = uiState.uiButton.status.isLoading
        val isReady = uiState.uiButton.status == SendViewModel.ButtonStatus.Ready
        confirmButton.isLoading = isLoading
        confirmButton.text = when {
            isReady -> sellButtonTitle
            isLoading -> sellButtonTitle
            else -> uiState.uiButton.title.ifBlank { sellButtonTitle }
        }
        confirmButton.isEnabled = isReady && !isLoading
    }

    private fun renderAddressAndButton(uiState: SendViewModel.UiState) {
        val input = when (val inputState = uiState.inputState) {
            is SendViewModel.InputStateFull.Complete -> inputState.input
            is SendViewModel.InputStateFull.Incomplete -> inputState.input
        }
        val destination = input.destination.trim()
        if (destination.isEmpty()) {
            confirmButton.type = WButton.Type.PRIMARY
            return
        }
        val draftResult = uiState.draft as? SendViewModel.DraftResult.Result
        val resolvedAddress =
            draftResult?.resolvedAddress ?: latestAddressInfo?.resolvedAddress ?: destination
        val resolvedName = draftResult?.addressName ?: latestAddressInfo?.addressName
        val isScam = draftResult?.isScam == true || latestAddressInfo?.isScam == true

        confirmButton.type = if (isScam) WButton.Type.DESTRUCTIVE else WButton.Type.PRIMARY
        addressInputView.setText(
            buildRecipientPreview(resolvedAddress, resolvedName, isScam),
            resolvedAddress
        )
    }

    private fun onConfirmClicked() {
        val config = viewModel.getConfirmationPageConfig() ?: return
        if (AccountStore.activeAccount?.isHardware == true) {
            confirmHardware(config)
        } else {
            confirmWithPassword(config)
        }
    }

    private fun confirmHardware(config: SendViewModel.DraftResult.Result) {
        Logger.d(
            Logger.LogTag.SEND,
            "confirmHardware: Confirming sell with hardware wallet slug=${viewModel.getTokenSlug()}"
        )
        val transferOptions = viewModel.getTransferOptions(config, "")
        confirmButton.lockView()
        val account = AccountStore.activeAccount ?: run {
            confirmButton.unlockView()
            return
        }
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignTransfer(
                    accountId = account.accountId,
                    transferOptions = transferOptions,
                    slug = viewModel.getTokenSlug()
                ),
                onDone = {
                    onTransferConfirmed(config, null)
                }),
            headerView = PasscodeHeaderSendView(
                WeakReference(this),
                (view.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                configSendingToken(
                    config.request.token,
                    config.request.amountEquivalent.getFmt(false),
                    account.network,
                    config.resolvedAddress
                )
            }
        )
        push(ledgerConnectVC, onCompletion = {
            confirmButton.unlockView()
        })
    }

    private fun confirmWithPassword(config: SendViewModel.DraftResult.Result) {
        Logger.d(
            Logger.LogTag.SEND,
            "confirmWithPassword: Confirming sell with passcode slug=${viewModel.getTokenSlug()}"
        )
        push(
            PasscodeConfirmVC(
                context,
                PasscodeViewState.CustomHeader(
                    PasscodeHeaderSendView(
                        WeakReference(this),
                        (view.height * 0.25f).roundToInt()
                    ).apply {
                        configSendingToken(
                            config.request.token,
                            config.request.amountEquivalent.getFmt(false),
                            AccountStore.activeAccount!!.network,
                            config.resolvedAddress
                        )
                    },
                    LocaleController.getString("Confirm")
                ),
                task = { passcode ->
                    onTransferConfirmed(config, passcode)
                }
            )
        )
    }

    private fun onTransferConfirmed(config: SendViewModel.DraftResult.Result, passcode: String?) {
        lifecycleScope.launch {
            if (AccountStore.activeAccount?.isHardware == true) {
                return@launch
            }
            val password = passcode ?: return@launch
            try {
                val id = viewModel.callSend(config, password).activityId
                sentActivityId = ActivityHelpers.getTxIdFromId(id)
                receivedLocalActivities?.firstOrNull { it.getTxHash() == sentActivityId }?.let {
                    checkReceivedActivity(it)
                }
            } catch (e: JSWebViewBridge.ApiError) {
                showError(e.parsed)
            }
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)

        val topRoundedItems = listOf(
            title1, title2, title3
        )
        val bottomRoundedItems = listOf(
            addressInputView, amountInfoView, commentInputView
        )
        val primaryTextColored = listOf(
            addressInputView, commentInputView
        )

        topRoundedItems.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                0f
            )
        }

        bottomRoundedItems.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BLOCK_RADIUS.dp
            )
        }

        primaryTextColored.forEach {
            it.setTextColor(WColor.PrimaryText.color)
        }

        gap1.showSeparator = false
        gap2.showSeparator = false
        gap1.invalidate()
        gap2.invalidate()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        linearLayout.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        view.setConstraints {
            toBottomPx(
                confirmButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun buildRecipientPreview(
        address: String,
        name: String?,
        isScam: Boolean
    ): CharSequence {
        val resolvedName = name?.takeIf { it.isNotBlank() }
        return buildSpannedString {
            if (isScam) {
                append(" ", scamLabelSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                append(" ")
            }

            if (!isScam && resolvedName != null) {
                inSpans(WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryText.color)) {
                    append(resolvedName)
                }
                append(" · ")
            }

            append(buildAddressSpan(address)).styleDots()
        }.replaceSpacesWithNbsp()
    }

    private fun buildAddressSpan(address: String): CharSequence {
        if (address.length <= 12) {
            return buildSpannedString {
                inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                    append(address)
                }
            }
        }
        val prefix = address.take(6)
        val suffix = address.takeLast(6)
        val middle = address.substring(6, address.length - 6)
        return buildSpannedString {
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                append(prefix)
            }
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.SecondaryText.color)) {
                append(middle)
            }
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                append(suffix)
            }
        }
    }

    private fun setInitialValues() {
        initialValues?.let { values ->
            values.address?.let { address ->
                viewModel.onInputDestination(address)
                viewModel.onDestinationEntered(address)
                addressInputView.setText(buildRecipientPreview(address, null, false), address)
            }
            val initialComment = values.comment.orEmpty()
            commentInputView.text = initialComment
            updateCommentVisibility(initialComment)
            values.amount?.let { amountBigDecimalString ->
                prefillAmount(amountBigDecimalString)
            }
            values.comment?.let { comment ->
                viewModel.onInputComment(comment)
            }
        }
    }

    private fun prefillAmount(amountBigDecimalString: String) {
        val selectedToken = TokenStore.getToken(initialTokenSlug ?: TONCOIN_SLUG)
        val normalizedAmount = selectedToken?.let { token ->
            CoinUtils.fromDecimal(amountBigDecimalString, token.decimals)
                ?.let { amountBigInt ->
                    CoinUtils.toBigDecimal(amountBigInt, token.decimals).stripTrailingZeros()
                        .toPlainString()
                } ?: amountBigDecimalString
        } ?: amountBigDecimalString

        viewModel.onInputAmount(normalizedAmount)

        selectedToken?.let { token ->
            val initialAmount = SpannableStringBuilder(
                if (token.symbol.isNotBlank()) {
                    "$normalizedAmount ${token.symbol}"
                } else {
                    normalizedAmount
                }
            )
            CoinUtils.setSpanToFractionalPart(
                initialAmount,
                WForegroundColorSpan(WColor.SecondaryText)
            )
            amountInfoView.set(
                Content.of(token, showChain = isShowingAccountMultichain),
                amount = initialAmount,
                currency = null,
                fee = null
            )
        }
    }

    private fun updateCommentVisibility(comment: String) {
        val isCommentEmpty = comment.isBlank()
        gap2.isGone = isCommentEmpty
        title3.isGone = isCommentEmpty
        commentInputView.isGone = isCommentEmpty
    }

    private var sentActivityId: String? = null
    private var receivedLocalActivities: ArrayList<MApiTransaction>? = null

    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        if (sentActivityId == null) {
            if (receivedActivity.isLocal()) {
                if (receivedLocalActivities == null) {
                    receivedLocalActivities = ArrayList()
                }
                receivedLocalActivities?.add(receivedActivity)
            }
            return
        }

        val txMatch =
            receivedActivity is MApiTransaction.Transaction && sentActivityId == receivedActivity.getTxHash()
        if (!txMatch) {
            return
        }

        sentActivityId = null
        WalletCore.unregisterObserver(this)
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        window?.dismissLastNav {
            WalletCore.notifyEvent(
                WalletEvent.OpenActivity(
                    displayedAccount.accountId!!,
                    receivedActivity
                )
            )
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.NewLocalActivities -> {
                walletEvent.localActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            else -> {}
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
        confirmButton.setOnClickListener(null)
    }
}
