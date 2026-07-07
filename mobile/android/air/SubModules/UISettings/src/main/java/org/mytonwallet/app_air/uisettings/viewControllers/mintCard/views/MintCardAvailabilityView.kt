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
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MCardInfo
import java.text.NumberFormat
import androidx.core.graphics.withClip

@SuppressLint("ViewConstructor")
class MintCardAvailabilityView(context: Context) : FrameLayout(context) {

    private var progress: Float = 0f

    private val cornerRadius: Float get() = height / 2f

    private val blurView = WBlurryBackgroundView(context, fadeSide = null)

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE.colorWithAlpha(46)
    }
    private val rect = RectF()

    private val leftLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        setTextColor(Color.WHITE)
    }
    private val soldLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        setTextColor(Color.WHITE)
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
            if (progress > 0f) {
                val fillWidth = (w * progress).coerceAtLeast(2 * cornerRadius)
                rect.set(0f, 0f, fillWidth, h)
                canvas.withClip(0f, 0f, w, h) {
                    drawRoundRect(rect, cornerRadius, cornerRadius, fillPaint)
                }
            }
        }
    }

    init {
        clipToOutline = true
        outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: android.view.View, outline: android.graphics.Outline) {
                outline.setRoundRect(0, 0, v.width, v.height, v.height / 2f)
            }
        }
        addView(blurView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(fillOverlay, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(leftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            marginStart = 12.dp
        })
        addView(soldLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            marginEnd = 12.dp
        })
        addView(soldOutLabel, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    fun setupBlur(rootView: ViewGroup) {
        if (!WGlobalStorage.isBlurEnabled()) {
            setBackgroundColor(Color.WHITE.colorWithAlpha(26))
            blurView.isGone = true
            return
        }
        blurView.setupWith(rootView)
        blurView.setOverlayColor(WColor.White, alpha = 26)
    }

    fun configure(cardInfo: MCardInfo?) {
        val all = cardInfo?.all
        val notMinted = cardInfo?.notMinted
        if (all == null || notMinted == null || all <= 0) {
            leftLabel.isGone = true
            soldLabel.isGone = true
            soldOutLabel.isGone = false
            progress = 0f
            fillOverlay.invalidate()
            return
        }
        val sold = all - notMinted
        leftLabel.isGone = false
        soldLabel.isGone = false
        soldOutLabel.isGone = true
        leftLabel.text = LocaleController.getString("%amount% left")
            .replace("%amount%", formatCount(notMinted))
        soldLabel.text = LocaleController.getString("%amount% sold")
            .replace("%amount%", formatCount(sold))
        progress = (notMinted.toFloat() / all.toFloat()).coerceIn(0f, 1f)
        fillOverlay.invalidate()
    }

    private fun formatCount(value: Int): String {
        return NumberFormat.getIntegerInstance().format(value.toLong())
    }
}
