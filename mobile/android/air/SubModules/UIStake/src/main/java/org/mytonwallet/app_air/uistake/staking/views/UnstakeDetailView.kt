package org.mytonwallet.app_air.uistake.staking.views

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ImageSpan
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.widgets.WLinearLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.StakingState

@SuppressLint("ViewConstructor")
class UnstakeDetailView(
    context: Context,
) : WLinearLayout(context), WThemedView {

    private var updateHandler: Handler? = null
    private var updateRunnable: Runnable? = null
    private var currentStakingState: StakingState? = null

    private val receivingRow = KeyValueRowView(
        context,
        LocaleController.getString("Receiving"),
        "",
        KeyValueRowView.Mode.SECONDARY,
        false
    )

    private val instantWithdrawalRow = KeyValueRowView(
        context,
        LocaleController.getString("Instant Withdrawal"),
        "",
        KeyValueRowView.Mode.SECONDARY,
        true
    )

    init {
        addView(receivingRow)
        addView(instantWithdrawalRow)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
    }

    override fun updateTheme() {
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopUpdateTimer()
    }

    fun setInstantWithdrawDetails(instantlyAvailableAmount: String?) {
        stopUpdateTimer()
        val ssb = SpannableStringBuilder(" ")
        ssb.setSpan(
            ImageSpan(
                context,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_bolt,
                ImageSpan.ALIGN_BASELINE
            ),
            0,
            1,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        ssb.append(" ${LocaleController.getString("Instantly")}")
        receivingRow.setValue(ssb)
        receivingRow.setLast(false)
        instantlyAvailableAmount?.let {
            instantWithdrawalRow.isGone = false
            instantWithdrawalRow.setValue(
                LocaleController.getFormattedString(
                    "Up to %1$@",
                    listOf(instantlyAvailableAmount)
                )
            )
            receivingRow.setLast(false)
        } ?: run {
            instantWithdrawalRow.isGone = true
            receivingRow.setLast(true)
        }
    }

    fun setWithdrawTime(state: StakingState) {
        currentStakingState = state
        receivingRow.setValue(state.getRemainingToEndTimeString())
        receivingRow.setLast(true)
        instantWithdrawalRow.isGone = true
        startUpdateTimer()
    }

    fun setWithdrawTime(text: String) {
        stopUpdateTimer()
        receivingRow.setValue(text)
        receivingRow.setLast(true)
        instantWithdrawalRow.isGone = true
    }

    private fun startUpdateTimer() {
        stopUpdateTimer()

        updateHandler = Handler(Looper.getMainLooper())
        updateRunnable = object : Runnable {
            override fun run() {
                updateReceivingRow()
                updateHandler?.postDelayed(this, 1000)
            }
        }
        updateHandler?.postDelayed(updateRunnable!!, 1000)
    }

    private fun stopUpdateTimer() {
        updateRunnable?.let { updateHandler?.removeCallbacks(it) }
        updateHandler = null
        updateRunnable = null
    }

    private fun updateReceivingRow() {
        currentStakingState?.let { state ->
            receivingRow.setValue(state.getRemainingToEndTimeString())
        }
    }
}
