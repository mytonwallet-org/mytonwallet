package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.graphics.toColorInt
import androidx.core.graphics.withClip
import androidx.core.view.isGone
import java.text.NumberFormat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MCardInfo

@SuppressLint("ViewConstructor")
class MintCardAvailabilityView(context: Context) : FrameLayout(context) {

    private var progress: Float = 0f
    private val blurEnabled = WGlobalStorage.isBlurEnabled()
    private val overlayColor = "#8491A5".toColorInt()

    private val cornerRadius: Float get() = height / 2f

    private val blurView = if (blurEnabled) {
        WGlassView(context).apply {
            flavor = GlassFlavor.FROSTED_PLAIN
            liquidGlass = false
            transparentBackstop = true
            setProvider(GlassProviders.plain(overlayColor))
        }
    } else {
        null
    }

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE.colorWithAlpha(41)
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
    }
    private val rect = RectF()
    private val fillInset = 4.dp.toFloat()

    private fun fillWidth(width: Float, height: Float): Float {
        val trackWidth = (width - 2 * fillInset).coerceAtLeast(0f)
        val trackHeight = (height - 2 * fillInset).coerceAtLeast(0f)
        return (trackWidth * progress).coerceIn(minOf(trackHeight, trackWidth), trackWidth)
    }

    private val leftLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(Color.WHITE)
    }
    private val soldLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(Color.WHITE)
    }
    private val filledLeftLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(overlayColor)
    }
    private val filledSoldLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(overlayColor)
    }
    private val soldOutLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        gravity = Gravity.CENTER
        setTextColor(Color.WHITE)
        text = LocaleController.getString("This card has been sold out")
    }

    private val fillOverlay = object : android.view.View(context) {
        override fun onDraw(canvas: Canvas) {
            val w = width.toFloat()
            val h = height.toFloat()
            if (!blurEnabled) {
                rect.set(0f, 0f, w, h)
                canvas.drawRoundRect(rect, cornerRadius, cornerRadius, trackPaint)
            }
            if (progress > 0f) {
                val radius = (h - 2 * fillInset).coerceAtLeast(0f) / 2f
                val fillW = fillWidth(w, h)
                if (layoutDirection == LAYOUT_DIRECTION_RTL) {
                    rect.set(w - fillInset - fillW, fillInset, w - fillInset, h - fillInset)
                } else {
                    rect.set(fillInset, fillInset, fillInset + fillW, h - fillInset)
                }
                canvas.drawRoundRect(rect, radius, radius, fillPaint)
            }
        }
    }

    private val filledLabels = object : FrameLayout(context) {
        override fun dispatchDraw(canvas: Canvas) {
            if (progress <= 0f) return
            val fillW = fillWidth(width.toFloat(), height.toFloat())
            val clipLeft = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
                width - fillInset - fillW
            } else {
                fillInset
            }
            canvas.withClip(
                clipLeft,
                0f,
                clipLeft + fillW,
                height.toFloat()
            ) {
                super.dispatchDraw(canvas)
            }
        }
    }.apply {
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
    }

    init {
        clipToOutline = true
        outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: android.view.View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, v.width, v.height, v.height / 2f)
            }
        }
        blurView?.let { addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT)) }
        addView(fillOverlay, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(
            leftLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = 12.dp
            }
        )
        addView(
            soldLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = 12.dp
            }
        )
        addView(soldOutLabel, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        filledLabels.addView(
            filledLeftLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = 12.dp
            }
        )
        filledLabels.addView(
            filledSoldLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = 12.dp
            }
        )
        addView(filledLabels, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun setupBlur(rootView: ViewGroup) {
        blurView?.setupWith(rootView)
    }

    override fun onRtlPropertiesChanged(layoutDirection: Int) {
        super.onRtlPropertiesChanged(layoutDirection)
        fillOverlay.invalidate()
        filledLabels.invalidate()
    }

    fun configure(cardInfo: MCardInfo?, isComingSoon: Boolean) {
        val showsCountdown = cardInfo?.mintStartsAtMillis != null
        blurView?.isGone = showsCountdown
        fillOverlay.isGone = showsCountdown
        filledLabels.isGone = showsCountdown
        leftLabel.gravity = if (showsCountdown) Gravity.CENTER else Gravity.START
        leftLabel.layoutParams = (leftLabel.layoutParams as LayoutParams).apply {
            width = if (showsCountdown) MATCH_PARENT else WRAP_CONTENT
            gravity = if (showsCountdown) {
                Gravity.CENTER
            } else {
                Gravity.START or Gravity.CENTER_VERTICAL
            }
            marginStart = if (showsCountdown) 0 else 12.dp
        }
        leftLabel.alpha = if (showsCountdown) 0.6f else 1f
        if (showsCountdown) {
            leftLabel.isGone = false
            soldLabel.isGone = true
            soldOutLabel.isGone = true
            leftLabel.text = LocaleController.getPluralOrFormat(
                "%amount% unique cards total",
                (cardInfo?.all ?: 0).coerceAtLeast(0),
                placeholder = "%amount%"
            )
            return
        }
        if (isComingSoon) {
            leftLabel.isGone = false
            filledLeftLabel.isGone = false
            soldLabel.isGone = true
            filledSoldLabel.isGone = true
            soldOutLabel.isGone = true
            leftLabel.text = LocaleController.getString("%amount% left")
                .replace("%amount%", formatCount(0))
            filledLeftLabel.text = leftLabel.text
            progress = 0f
            fillOverlay.invalidate()
            filledLabels.invalidate()
            return
        }
        val all = cardInfo?.all
        val notMinted = cardInfo?.notMinted
        if (all == null || notMinted == null || all <= 0) {
            leftLabel.isGone = true
            filledLeftLabel.isGone = true
            soldLabel.isGone = true
            filledSoldLabel.isGone = true
            soldOutLabel.isGone = false
            progress = 0f
            fillOverlay.invalidate()
            filledLabels.invalidate()
            return
        }
        val sold = all - notMinted
        leftLabel.isGone = false
        filledLeftLabel.isGone = false
        soldLabel.isGone = false
        filledSoldLabel.isGone = false
        soldOutLabel.isGone = true
        leftLabel.text = LocaleController.getString("%amount% left")
            .replace("%amount%", formatCount(notMinted))
        soldLabel.text = LocaleController.getString("%amount% sold")
            .replace("%amount%", formatCount(sold))
        filledLeftLabel.text = leftLabel.text
        filledSoldLabel.text = soldLabel.text
        progress = (notMinted.toFloat() / all.toFloat()).coerceIn(0f, 1f)
        fillOverlay.invalidate()
        filledLabels.invalidate()
    }

    private fun formatCount(value: Int): String =
        NumberFormat.getIntegerInstance().format(value.toLong())
}
