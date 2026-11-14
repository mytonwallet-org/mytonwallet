package org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.NestedScrollView
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.GradientDrawables
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WActivityImageView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.formatFuturesChange
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toUsdString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity.FuturesActivityHeaderView
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.futuresOperationSymbol
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.futuresOperationTitle
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.futuresSubmissionFailure
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsDraftRequest
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsQuote
import org.mytonwallet.app_air.walletcore.moshi.PERPS_FUNDING_BALANCE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_COMPLETED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_FAILED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_PARTIAL
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_RUNNING
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PARTIAL_FILL_ERROR
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_CLOSE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_INCREASE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_OPEN
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_REDUCE
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

enum class FuturesPositionChange(
    private val kind: String,
    val titleKey: String,
    val paymentKey: String
) {
    INCREASE(PERPS_QUOTE_INCREASE, "Increase Position", "You Pay"),
    REDUCE(PERPS_QUOTE_REDUCE, "Reduce Position", "You Receive"),
    CLOSE(PERPS_QUOTE_CLOSE, "Close Position", "You Receive"),
    OPEN(PERPS_QUOTE_OPEN, "Open Position", "You Pay");

    companion object {
        fun of(quote: MApiPerpsQuote): FuturesPositionChange? =
            entries.firstOrNull { it.kind == quote.kind }
    }
}

/** Shows the effect of an opening, margin change or close, and submits it after confirmation */
@SuppressLint("ViewConstructor")
class FuturesModifyReviewVC(
    context: Context,
    private val accountId: String,
    /** The position being changed; a new one has none yet. */
    private val position: MApiPerpsNativePosition?,
    private val displayName: String,
    initialQuote: MApiPerpsQuote,
    private val draft: MApiPerpsDraftRequest
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesModifyReview"

    override val shouldDisplayBottomBar = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    override val displayedAccount =
        DisplayedAccount(accountId, AccountStore.isPushedTemporary)
    private var isSubmitting = false
    private var isRefreshing = false
    private var quote = initialQuote

    // Kept from the initial quote, as a refresh of another kind closes the review
    private val change = FuturesPositionChange.of(initialQuote)!!

    private val margin
        get() = quote.previousCollateral?.toDoubleOrNull() ?: position?.invested
    private val newMargin
        get() = (quote.estimatedCollateral ?: quote.collateral).toDoubleOrNull()
            ?: position?.invested
            ?: 0.0
    private val badgeText
        get() = "${quote.leverage}x ${quote.side.title}"
    private val estimatedFee
        get() = quote.estimatedFees?.total?.toDoubleOrNull()

    private val scrollView = NestedScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
    }
    private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val sections = mutableListOf<View>()

    private val bottomPanel by lazy { ReversedCornerViewUpsideDown(context, scrollView) }

    private val feeLabel = WLabel(context).apply {
        id = View.generateViewId()
        setStyle(14f)
        gravity = Gravity.CENTER
    }

    private val confirmButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.PRIMARY
        text = LocaleController.getString("Confirm")
        setOnClickListener { confirm() }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.addCloseButton()
        setNavTitle(LocaleController.getString(change.titleKey))

        addSections()

        scrollView.addView(content, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(bottomPanel, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(feeLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(confirmButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toTop(scrollView)
            toCenterX(scrollView)
            bottomToTop(scrollView, feeLabel, 12f)
            toCenterX(feeLabel, 20f)
            bottomToTop(feeLabel, confirmButton, 12f)
            toCenterX(confirmButton, 20f)
            topToTop(bottomPanel, feeLabel, -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS)
            toBottom(bottomPanel)
        }
        insetsUpdated()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        sections.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                clipToBounds = true
            )
        }
        feeLabel.setTextColor(WColor.SecondaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        content.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        view.setConstraints {
            toBottomPx(confirmButton, bottomInset + BUTTON_BOTTOM_MARGIN.dp)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun addSections() {
        addSection(headerCard())
        if (change == FuturesPositionChange.CLOSE) addCloseSections() else addChangeSections()
        feeLabel.text = estimatedFee?.let { fee ->
            LocaleController.getStringWithKeyValues(
                "\$fee_value_with_colon",
                listOf("%fee%" to futuresFeeText(fee))
            )
        }
    }

    private fun refreshReview() {
        if (isRefreshing) return
        isRefreshing = true
        confirmButton.isLoading = true
        scope.launch {
            val refreshed = prepareFuturesQuote(accountId, draft, loadsFunding = false)
            isRefreshing = false
            confirmButton.isLoading = false
            val updated = refreshed.quote
            if (updated == null) {
                showAlert(
                    LocaleController.getString("Error"),
                    failureText(refreshed.error)
                )
                return@launch
            }
            if (updated.kind != quote.kind || updated.assetId != quote.assetId) {
                showAlert(
                    LocaleController.getString("Error"),
                    LocaleController.getString("PerpsPositionChanged"),
                    buttonPressed = { window?.dismissLastNav() }
                )
                return@launch
            }
            quote = updated
            sections.clear()
            content.removeAllViews()
            addSections()
            updateTheme()
            showAlert(null, LocaleController.getString("PerpsReviewUpdated"))
        }
    }

    private fun addChangeSections() {
        addSection(
            card(
                listOf(
                    row(
                        "Position Size",
                        formatFuturesChange(quote.previousNotional, quote.notional),
                        "\$perps_position_size_change_hint"
                    )
                )
            )
        )
        addSection(
            card(
                listOf(
                    row(priceTitle("\$perps_asset_price"), markPriceText()),
                    row(
                        "Liquidation Price",
                        formatFuturesChange(
                            quote.liquidationPrice,
                            quote.estimatedLiquidationPrice,
                            isAfterKnown = false,
                            isPrice = true
                        ),
                        "\$perps_liquidation_price_hint"
                    )
                )
            )
        )
        addSection(card(listOf(row(change.paymentKey, paymentText()))))
        quote.networkFeeText()?.let {
            addSection(card(listOf(row("Network Fee", it, "\$perps_network_fee_hint"))))
        }
        quote.estimatedRemainingCollateral?.toDoubleOrNull()?.takeIf { it > 0 }?.let {
            addSection(
                card(
                    listOf(
                        row(
                            "PerpsUnallocatedCollateral",
                            "≈ ${usdcText(it)}",
                            "PerpsUnallocatedCollateralHint"
                        )
                    )
                )
            )
        }
        if (quote.switchesToUnified == true) {
            addSection(noticeCard(LocaleController.getString("PerpsSwitchesToUnifiedAccount")))
        }
        addSection(warningCard())
    }

    // From the quote, so a refreshed review stays current
    private fun addCloseSections() {
        val invested = quote.previousCollateral?.toDoubleOrNull() ?: position?.invested
        val value = quote.equity?.toDoubleOrNull() ?: position?.value
        val entryPrice = quote.entryPrice?.toDoubleOrNull() ?: position?.entryPrice
        addSection(
            card(
                listOf(
                    row("Invested", invested?.toUsdString() ?: "—", "\$perps_invested_hint"),
                    row(
                        "Current Value",
                        value?.toUsdString() ?: "—",
                        "\$perps_current_value_hint"
                    )
                )
            )
        )
        addSection(
            card(
                listOf(
                    row(
                        priceTitle("\$perps_price_when_opened"),
                        entryPrice?.toPriceString() ?: "—"
                    ),
                    row(priceTitle("\$perps_price_now"), markPriceText())
                )
            )
        )
        addSection(paymentRow())
    }

    private fun priceTitle(key: String) =
        LocaleController.getStringWithKeyValues(key, listOf("%asset%" to displayName))

    private fun markPriceText() = quote.markPrice.toDoubleOrNull()?.toPriceString() ?: "—"

    private fun paymentRow() = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = PAYMENT_ROW_HEIGHT.dp
        setPaddingRelative(12.dp, 0, 20.dp, 0)
        addView(
            WActivityImageView(context, 28.dp).apply {
                chainSize = 12.dp
                set(
                    TokenStore.getToken(PERPS_PAYMENT_TOKEN_SLUG)?.let {
                        Content.of(it, showChain = true)
                    }?.let {
                        if (quote.funding == PERPS_FUNDING_BALANCE) {
                            it.copy(subImageRes = MBlockchain.hyperliquid.icon)
                        } else {
                            it
                        }
                    }
                )
            },
            LinearLayout.LayoutParams(30.dp, 30.dp)
        )
        addView(
            WLabel(context).apply {
                setStyle(17f, WFont.Medium)
                setSingleLine()
                setTextColor(WColor.PrimaryText.color)
                text = LocaleController.getString(change.paymentKey)
            },
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = 8.dp }
        )
        addView(
            WLabel(context).apply {
                setStyle(17f)
                setSingleLine()
                setTextColor(WColor.PrimaryText.color)
                text = paymentText()
            },
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
    }

    private fun addSection(view: View) {
        sections += view
        content.addView(
            view,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = ViewConstants.GAP.dp
            }
        )
    }

    private fun headerCard() = FrameLayout(context).apply {
        setPadding(0, HEADER_VERTICAL_PADDING.dp, 0, HEADER_VERTICAL_PADDING.dp)
        addView(headerView(), FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    }

    private fun headerView() = if (change == FuturesPositionChange.CLOSE) {
        FuturesActivityHeaderView(
            context,
            PerpsStore.assetsById[quote.assetId],
            quote.side,
            badgeText,
            quote.profitLoss?.toDoubleOrNull() ?: position?.pnl ?: 0.0,
            showsSign = true
        )
    } else {
        FuturesActivityHeaderView(
            context,
            PerpsStore.assetsById[quote.assetId],
            quote.side,
            badgeText,
            newMargin,
            previousAmount = margin
        )
    }

    private fun card(rows: List<KeyValueRowView>) = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        rows.forEachIndexed { index, row ->
            row.setLast(index == rows.lastIndex)
            addView(row)
        }
    }

    private fun row(key: String, value: CharSequence, hintKey: String? = null) =
        KeyValueRowView(context, LocaleController.getString(key), value).apply {
            hintKey?.let { setHint { showAlert(this.key, LocaleController.getString(it)) } }
        }

    private fun paymentText(): String {
        val isPaid = change == FuturesPositionChange.OPEN ||
            change == FuturesPositionChange.INCREASE
        val amount = (if (isPaid) quote.paymentAmount else quote.estimatedReceiveAmount)
            ?.toDoubleOrNull()
            ?: return "—"
        val text = usdcText(amount)
        return when {
            !isPaid -> "≈ $text"

            quote.funding == PERPS_FUNDING_BALANCE ->
                "$text · ${MBlockchain.hyperliquid.displayName}"

            else -> text
        }
    }

    private fun usdcText(amount: Double) = amount.toString(
        PAYMENT_DISPLAY_DECIMALS,
        futuresPaymentSymbol,
        PAYMENT_DISPLAY_DECIMALS,
        smartDecimals = true,
        forceCurrencyToRight = true
    ).orEmpty()

    private fun noticeCard(text: String) = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        setTextColor(WColor.SecondaryText.color)
        setPaddingRelative(20.dp, 14.dp, 20.dp, 14.dp)
        this.text = text
    }

    private fun warningCard() = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPaddingRelative(12.dp, 14.dp, 20.dp, 14.dp)
        addView(
            AppCompatImageView(context).apply {
                setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_warning_triangle_28)
                scaleType = ImageView.ScaleType.CENTER
                setPadding(0, 0, 0, 4.dp)
                background = GradientDrawables.redDrawable
            },
            LinearLayout.LayoutParams(WARNING_ICON_SIZE.dp, WARNING_ICON_SIZE.dp)
        )
        addView(
            WLabel(context).apply {
                setStyle(14f)
                setLineHeight(20f)
                setTextColor(WColor.PrimaryText.color)
                text = LocaleController.getString("\$perps_liquidation_acknowledgment")
            },
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).apply { marginStart = 12.dp }
        )
    }

    private fun confirm() {
        if (isSubmitting || isRefreshing) return
        if (quote.expiresAt <= System.currentTimeMillis()) {
            refreshReview()
            return
        }
        val reviewedQuote = quote
        val task = { enclaveToken: String -> submit(reviewedQuote, enclaveToken) }
        ProtectedActionAuth.confirm(
            onConfirmed = task,
            requiresFreshAuthentication = true,
            onPasscodeRequired = {
                push(
                    PasscodeConfirmVC(
                        context,
                        PasscodeViewState.CustomHeader(
                            FrameLayout(context).apply {
                                setPadding(0, CONFIRM_HEADER_GAP.dp, 0, CONFIRM_HEADER_GAP.dp)
                                addView(
                                    headerView(),
                                    FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                                )
                            },
                            LocaleController.getString("Confirm")
                        ),
                        task = task
                    )
                )
            }
        )
    }

    /** Signs the quote shown at confirmation, even if it has expired since. */
    private fun submit(reviewedQuote: MApiPerpsQuote, enclaveToken: String) {
        if (isSubmitting) return
        isSubmitting = true
        view.lockView()
        confirmButton.isLoading = true
        val operationId = UUID.randomUUID().toString()
        // Saved before execution so a restart reconciles it instead of allowing a second order
        val execution = PerpsStore.execute(
            MApiPerpsOperation(
                id = operationId,
                accountId = accountId,
                assetId = reviewedQuote.assetId,
                kind = reviewedQuote.kind,
                state = PERPS_OPERATION_RUNNING,
                stage = "preparing",
                createdAt = System.currentTimeMillis(),
                reviewedQuote = reviewedQuote
            ),
            submit = {
                WalletCore.call(
                    ApiMethod.Perps.ExecuteReviewedOrder(
                        accountId,
                        enclaveToken,
                        reviewedQuote.id,
                        operationId
                    )
                )
            },
            resolveFailure = ::futuresSubmissionFailure
        )
        scope.launch {
            val result = execution.await()
            isSubmitting = false
            view.unlockView()
            confirmButton.isLoading = false
            when (result.state) {
                PERPS_OPERATION_COMPLETED -> {
                    if (result.error != PERPS_PARTIAL_FILL_ERROR) {
                        finish()
                        return@launch
                    }
                    PerpsStore.dismissOperationStatus(result.id)
                    popPasscodeIfShown()
                    showAlert(
                        futuresOperationTitle(result),
                        partialFillText(result),
                        buttonPressed = ::finish
                    )
                }

                PERPS_OPERATION_FAILED -> {
                    popPasscodeIfShown()
                    if (result.error in REVIEW_CHANGED_ERRORS) {
                        refreshReview()
                        return@launch
                    }
                    showAlert(
                        LocaleController.getString("Error"),
                        failureText(result.error)
                    )
                }

                PERPS_OPERATION_PARTIAL -> {
                    popPasscodeIfShown()
                    showAlert(
                        LocaleController.getString("Position Closed"),
                        LocaleController.getString("PerpsWithdrawalPending"),
                        buttonPressed = ::finish
                    )
                }

                // Unconfirmed; must not be repeated
                else -> {
                    popPasscodeIfShown()
                    showAlert(
                        LocaleController.getString("Error"),
                        LocaleController.getString("PerpsExecutionUnknown"),
                        buttonPressed = ::finish
                    )
                }
            }
        }
    }

    private fun failureText(error: String?): String = when (error) {
        "InsufficientBalance" -> LocaleController.getString("Insufficient Balance")
        else -> futuresErrorText(error.orEmpty())
    }

    // The text refers to the amount below
    private fun partialFillText(operation: MApiPerpsOperation): String {
        val text = LocaleController.getString(PERPS_PARTIAL_FILL_ERROR)
        val filled = operation.filledSize ?: return text
        return "$text\n\n$filled ${futuresOperationSymbol(operation)}"
    }

    private fun popPasscodeIfShown() {
        if (navigationController?.viewControllers?.lastOrNull() is PasscodeConfirmVC) pop()
    }

    private fun finish() {
        window?.dismissLastNav()
    }

    private companion object {
        const val HEADER_VERTICAL_PADDING = 24
        const val BUTTON_BOTTOM_MARGIN = 16
        const val WARNING_ICON_SIZE = 40
        const val CONFIRM_HEADER_GAP = 20
        const val PAYMENT_DISPLAY_DECIMALS = 4
        const val PAYMENT_ROW_HEIGHT = 50
        val REVIEW_CHANGED_ERRORS = setOf(PERPS_QUOTE_EXPIRED_ERROR, "PerpsReviewChanged")
    }
}
