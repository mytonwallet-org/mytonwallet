package org.mytonwallet.app_air.ledger.screens.ledgerConnect.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.Barrier
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.animateHeight
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class LedgerConnectStepView(context: Context, stepText: String) : WView(context) {

    private val stepStatusView = LedgerConnectStepStatusView(context)

    private val stepLabel = WLabel(context).apply {
        setStyle(14f)
        text = stepText
        setTextColor(WColor.PrimaryText)
    }

    private val topElementsBarrier = Barrier(context).apply {
        id = generateViewId()
        type = Barrier.BOTTOM
    }

    private val errorLabel = WLabel(context).apply {
        setStyle(14f)
        setTextColor(WColor.SecondaryText.color)
        gravity = Gravity.START
        alpha = 0f
    }

    var state = LedgerConnectStepStatusView.State.WAITING
        set(value) {
            if (field != value) {
                field = value
                stepStatusView.state = value
                if (value != LedgerConnectStepStatusView.State.ERROR)
                    setError(null)
            }
        }

    override fun setupViews() {
        super.setupViews()

        addView(stepStatusView)
        addView(stepLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        addView(topElementsBarrier)
        addView(errorLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))

        topElementsBarrier.referencedIds = intArrayOf(stepStatusView.id, stepLabel.id)

        setConstraints {
            toStart(stepStatusView)
            toTop(stepStatusView)
            setVerticalBias(stepStatusView.id, 0f)

            setVerticalBias(stepLabel.id, 0f)
            startToEnd(stepLabel, stepStatusView, 4f)
            toEnd(stepLabel)
            toTop(stepLabel, 2.5f)
            toBottom(stepLabel)

            startToStart(errorLabel, stepLabel)
            toBottom(errorLabel)
            toEnd(errorLabel)
        }
    }

    fun setError(errorMessage: CharSequence?) {
        if ((errorLabel.text ?: "") == (errorMessage ?: ""))
            return

        val baseHeight =
            stepStatusView.height.coerceAtLeast(stepLabel.height + 5)

        errorLabel.text = errorMessage
        if (!errorMessage.isNullOrEmpty()) {
            errorLabel.measure(stepLabel.width.exactly, MeasureSpec.UNSPECIFIED)
        }

        if (errorMessage.isNullOrEmpty()) {
            animateHeight(baseHeight)
            errorLabel.fadeOut()
        } else {
            animateHeight(baseHeight + errorLabel.measuredHeight - 4)
            errorLabel.fadeIn()
        }
    }
}
