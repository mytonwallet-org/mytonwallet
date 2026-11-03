package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * Telegram's scroll-to-latest button: a chevron on a glass circle, which the chat attaches. It grows in from 20%
 * on a critically damped spring and shrinks back away, fading so no drop of glass lingers.
 */
@SuppressLint("ViewConstructor")
class AgentScrollToBottomButton(context: Context) :
    View(context),
    WThemedView {
    private val chevronPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        strokeWidth = CHEVRON_STROKE.dp
    }
    private val chevron = Path()
    private val ripple = WRippleDrawable.create(SIZE.dp / 2f)

    private var isRevealed = false

    init {
        id = UIComponentsR.id.agent_scroll_to_bottom
        contentDescription = LocaleController.getString("Scroll To Bottom")
        foreground = ripple
        alpha = 0f
        scaleX = HIDDEN_SCALE
        scaleY = HIDDEN_SCALE
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        updateTheme()
    }

    fun setShown(shouldShow: Boolean, isAnimated: Boolean) {
        if (isRevealed == shouldShow) return
        isRevealed = shouldShow
        isClickable = shouldShow
        isFocusable = shouldShow
        importantForAccessibility = if (shouldShow) {
            IMPORTANT_FOR_ACCESSIBILITY_YES
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        val scale = if (shouldShow) 1f else HIDDEN_SCALE
        animate().cancel()
        if (!isAnimated || !WGlobalStorage.getAreAnimationsActive()) {
            alpha = if (shouldShow) 1f else 0f
            scaleX = scale
            scaleY = scale
            return
        }
        animate().scaleX(scale).scaleY(scale)
            .setDuration(SCALE_DURATION_MS)
            .setInterpolator(WInterpolator.smooth)
            .start()
        // The glass mirrors the button's alpha, so it fades out before the button has shrunk
        animate().alpha(if (shouldShow) 1f else 0f)
            .setDuration(FADE_DURATION_MS)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val halfWidth = CHEVRON_WIDTH.dp / 2f
        val halfHeight = CHEVRON_HEIGHT.dp / 2f
        val centerX = w / 2f
        val centerY = h / 2f + CHEVRON_DROP.dp
        chevron.rewind()
        chevron.moveTo(centerX - halfWidth, centerY - halfHeight)
        chevron.lineTo(centerX, centerY + halfHeight)
        chevron.lineTo(centerX + halfWidth, centerY - halfHeight)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawPath(chevron, chevronPaint)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = Button::class.java.name
    }

    override fun updateTheme() {
        chevronPaint.color = WColor.SecondaryText.color
        ripple.rippleColor = WColor.BackgroundRipple.color
        invalidate()
    }

    companion object {
        const val SIZE = 44
        private const val HIDDEN_SCALE = 0.2f
        private const val SCALE_DURATION_MS = 300L
        private const val FADE_DURATION_MS = 150L
        private const val CHEVRON_WIDTH = 15f
        private const val CHEVRON_HEIGHT = 7.3f
        private const val CHEVRON_STROKE = 1.7f
        private const val CHEVRON_DROP = 0.8f
    }
}
