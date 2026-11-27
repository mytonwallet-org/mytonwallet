package org.mytonwallet.app_air.uiswap.screens.swap.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.core.view.ViewCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiswap.screens.swap.models.SwapHint
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapHint

@SuppressLint("ViewConstructor")
class SwapHintView(
    context: Context,
    topPadding: Int = 10,
    private val messageTopMargin: Int = 4,
    onAction: () -> Unit
) : LinearLayout(context),
    WThemedView {

    private val paint = Paint().apply {
        style = Paint.Style.FILL
        isAntiAlias = true
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setLineHeight(20f)
    }
    private val messageLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setLineHeight(20f)
    }
    private val chevron = ImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_14)
        isVisible = false
    }
    private var currentPromo: MApiSwapHint? = null

    private val actionLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setPaddingDp(12, 6, 12, 6)
        setOnClickListener { onAction() }
    }

    init {
        id = generateViewId()
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setWillNotDraw(false)
        setPaddingDp(16, topPadding, 12, 10)
        updateTheme()
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
            chevron,
            LayoutParams(20.dp, 20.dp).apply {
                gravity = Gravity.TOP
                marginStart = 12.dp
            }
        )
        addView(
            actionLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { marginStart = 12.dp }
        )
    }

    override fun updateTheme() {
        val color = when (currentPromo?.type) {
            "oneToOneOffer" -> WColor.Green
            "oneToOneUnavailable" -> WColor.SecondaryText
            else -> WColor.Orange
        }.color
        paint.color = color
        setBackgroundColor(color.colorWithAlpha(31), 12f.dp, true)
        val textColor = if (currentPromo == null) WColor.StockBadge.color else color
        titleLabel.setTextColor(textColor)
        messageLabel.setTextColor(textColor)
        chevron.setColorFilter(color)
        actionLabel.setTextColor(color)
        actionLabel.setBackgroundColor(color.colorWithAlpha(31), 16f.dp, true)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, 4f.dp, height.toFloat(), paint)
        super.onDraw(canvas)
    }

    fun configure(hint: SwapHint) = configure(hint.title, hint.message, hint.actionTitle)

    override fun getAccessibilityClassName(): CharSequence =
        if (currentPromo != null) Button::class.java.name else super.getAccessibilityClassName()

    fun configurePromo(hint: MApiSwapHint) {
        if (hint == currentPromo) return
        configure(hint.title.orEmpty(), hint.description.orEmpty(), "")
        currentPromo = hint
        updateTheme()
        chevron.isVisible = true
        setPromoExpanded(false)
        setOnClickListener { setPromoExpanded(!messageLabel.isVisible) }
    }

    private fun setPromoExpanded(expanded: Boolean) {
        messageLabel.isVisible = expanded
        chevron.rotation = if (expanded) 180f else 0f
        ViewCompat.setStateDescription(
            this,
            LocaleController.getString(if (expanded) "Expanded" else "Collapsed")
        )
    }

    /** Empty [title] or [actionTitle] is hidden. */
    fun configure(title: String, message: String, actionTitle: String) {
        if (currentPromo != null) {
            currentPromo = null
            setOnClickListener(null)
            isClickable = false
            ViewCompat.setStateDescription(this, null)
            updateTheme()
            chevron.isVisible = false
            messageLabel.isVisible = true
        }
        titleLabel.text = title
        titleLabel.isVisible = title.isNotEmpty()
        (messageLabel.layoutParams as LayoutParams).topMargin =
            if (title.isEmpty()) 0 else messageTopMargin.dp
        messageLabel.text = message
        actionLabel.text = actionTitle
        actionLabel.isVisible = actionTitle.isNotEmpty()
    }
}
