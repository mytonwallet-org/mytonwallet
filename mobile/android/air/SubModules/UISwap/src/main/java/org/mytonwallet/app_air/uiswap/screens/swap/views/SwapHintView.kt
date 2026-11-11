package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapHint
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class SwapHintView(
    context: Context,
    topPadding: Int = 10,
    private val messageTopMargin: Int = 4,
    onAction: () -> Unit
) : LinearLayout(context) {

    private val alertColor = WColor.Orange.color
    private val paint = Paint().apply {
        color = alertColor
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setLineHeight(20f)
        setTextColor(WColor.StockBadge.color)
    }
    private val messageLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setLineHeight(20f)
        setTextColor(WColor.StockBadge.color)
    }
    private val actionLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setTextColor(alertColor)
        setPaddingDp(12, 6, 12, 6)
        setBackgroundColor(alertColor.colorWithAlpha(31), 16f.dp, true)
        setOnClickListener { onAction() }
    }

    init {
        id = generateViewId()
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setWillNotDraw(false)
        setPaddingDp(16, topPadding, 12, 10)
        setBackgroundColor(alertColor.colorWithAlpha(31), 12f.dp, true)
        addView(
            LinearLayout(context).apply {
                id = generateViewId()
                orientation = VERTICAL
                addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
                addView(
                    messageLabel,
                    LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                        topMargin = messageTopMargin.dp
                    }
                )
            },
            LayoutParams(0, WRAP_CONTENT, 1f)
        )
        addView(
            actionLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 12.dp }
        )
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, 4f.dp, height.toFloat(), paint)
        super.onDraw(canvas)
    }

    fun configure(hint: SwapHint) = configure(hint.title, hint.message, hint.actionTitle)

    /** Empty [title] or [actionTitle] is hidden. */
    fun configure(title: String, message: String, actionTitle: String) {
        titleLabel.text = title
        titleLabel.isVisible = title.isNotEmpty()
        (messageLabel.layoutParams as LayoutParams).topMargin =
            if (title.isEmpty()) 0 else messageTopMargin.dp
        messageLabel.text = message
        actionLabel.text = actionTitle
        actionLabel.isVisible = actionTitle.isNotEmpty()
    }
}
