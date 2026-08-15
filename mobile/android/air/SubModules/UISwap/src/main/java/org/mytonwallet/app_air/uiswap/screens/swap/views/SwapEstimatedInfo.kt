package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.commonViews.AnimatedKeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.feeDetailsDialog.FeeDetailsDialog
import org.mytonwallet.app_air.uicomponents.widgets.ExpandableFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapEstimateResponse
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcore.moshi.IApiToken

@SuppressLint("ViewConstructor")
class SwapEstimatedInfo(
    context: Context,
    private var onSlippageChange: ((Float) -> Unit)?,
    private var onDialogShowListener: ((String, CharSequence) -> Unit)?,
    private var onPresentDialog: (dialog: WDialog?) -> Unit
) : ExpandableFrameLayout(context) {
    private val linearLayout = object : LinearLayout(context) {
        override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
            // Reject any multi-touch events
            return if (e.pointerCount > 1) {
                true
            } else {
                super.onInterceptTouchEvent(e)
            }
        }
    }.apply {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        orientation = LinearLayout.VERTICAL
    }

    private val estRate = SwapRateRowView(context)

    private val slippageRowView = SwapSlippageRowView(context) {
        onSlippageChange?.invoke(it)
    }

    private val estBlockchainFee = AnimatedKeyValueRowView(context).apply {
        title = LocaleController.getString("Blockchain Fee")
    }

    private val estPriceImpact = AnimatedKeyValueRowView(context).apply {
        setTitleDrawable(org.mytonwallet.app_air.icons.R.drawable.ic_info_24, 0.5f)
        title = LocaleController.getString("Price Impact")
    }

    private val estMinimumReceived = AnimatedKeyValueRowView(context).apply {
        setTitleDrawable(org.mytonwallet.app_air.icons.R.drawable.ic_info_24, 0.5f)
        title = LocaleController.getString("Minimum Received")
        separator.allowSeparator = false
    }

    init {
        linearLayout.addView(estRate)
        linearLayout.addView(slippageRowView)
        linearLayout.addView(estBlockchainFee)
        linearLayout.addView(estPriceImpact)
        linearLayout.addView(estMinimumReceived)

        estBlockchainFee.setOnClickListener {
            availableFeeDetails?.let { feeDetails ->
                val tokenToSend = est?.request?.tokenToSend ?: return@let
                lateinit var dialogRef: WDialog
                dialogRef = FeeDetailsDialog.create(
                    context,
                    tokenToSend,
                    feeDetails
                ) {
                    dialogRef.dismiss()
                }
                onPresentDialog(dialogRef)
            }
        }

        slippageRowView.setOnClickListener {
            onDialogShowListener?.invoke(
                LocaleController.getString("Slippage"),
                LocaleController.getString("\$swap_slippage_tooltip1") + "\n\n" +
                    LocaleController.getString("\$swap_slippage_tooltip2")
            )
        }
        estPriceImpact.setOnClickListener {
            onDialogShowListener?.invoke(
                LocaleController.getString("Price Impact"),
                LocaleController.getString("\$swap_price_impact_tooltip1") + "\n\n" +
                    LocaleController.getString("\$swap_price_impact_tooltip2")
            )
        }
        estMinimumReceived.setOnClickListener {
            onDialogShowListener?.invoke(
                LocaleController.getString("Minimum Received"),
                LocaleController.getString("\$swap_minimum_received_tooltip1") + "\n\n" +
                    LocaleController.getString("\$swap_minimum_received_tooltip2")
            )
        }

        addView(linearLayout)
    }

    fun setIsCex(isCex: Boolean) {
        val visibility = if (isCex) GONE else VISIBLE
        estPriceImpact.visibility = visibility
        estMinimumReceived.visibility = visibility
        slippageRowView.visibility = visibility
        estBlockchainFee.separator.allowSeparator = false
    }

    var est: SwapEstimateResponse? = null
    private val availableFeeDetails
        get() = est?.explainedFee?.networkFeeDetails?.takeIf { it.supportsLegacyDetailsView }

    fun setEstimated(est: SwapEstimateResponse?, toToken: IApiToken?) {
        val transactionFee = est?.transactionFeeFmt2
        estBlockchainFee.value = transactionFee
        estBlockchainFee.visibility = if (transactionFee == null) GONE else VISIBLE
        this.est = est
        if (availableFeeDetails != null) {
            estBlockchainFee.setTitleDrawable(
                org.mytonwallet.app_air.icons.R.drawable.ic_info_24,
                0.5f
            )
        } else {
            estBlockchainFee.setTitleDrawable(null)
        }
        estPriceImpact.value = est?.priceImpactFmt
        estMinimumReceived.value = est?.minReceivedFmt

        if (est != null && est.rate.sendAmount > java.math.BigDecimal.ZERO) {
            estRate.setTitleAndValue(
                "${LocaleController.getString("Price per")} ${est.rateReceiveFmt}",
                est.rateSendFmt
            )
        } else {
            estRate.clearValue(toToken)
        }
    }
}
