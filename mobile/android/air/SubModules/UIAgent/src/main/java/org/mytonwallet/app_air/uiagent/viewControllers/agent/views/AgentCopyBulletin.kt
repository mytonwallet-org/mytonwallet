package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.InsetDrawable
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.doOnLayout
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** Shown only before Android 12L, where the system doesn't confirm a copy itself. */
internal class AgentCopyBulletin {
    private var holder: FrameLayout? = null
    private var bar: View? = null
    private var barSpring: SpringAnimation? = null
    private val hideRunnable = Runnable { hide() }

    fun show(container: ConstraintLayout, text: String, bottomOffset: Int) {
        if (!shouldShow()) return
        dismiss()
        val bar = createBar(container.context, text)
        // The holder clips the bar, so it rises from its bottom edge
        val holder = FrameLayout(container.context).apply {
            id = View.generateViewId()
            addView(bar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        container.addView(
            holder,
            ConstraintLayout.LayoutParams(0, WRAP_CONTENT).apply {
                startToStart = ConstraintLayout.LayoutParams.PARENT_ID
                endToEnd = ConstraintLayout.LayoutParams.PARENT_ID
                bottomToBottom = ConstraintLayout.LayoutParams.PARENT_ID
                bottomMargin = bottomOffset
            }
        )
        this.holder = holder
        this.bar = bar
        bar.visibility = View.INVISIBLE
        bar.doOnLayout {
            if (this.bar !== bar) return@doOnLayout
            bar.translationY = bar.height.toFloat()
            bar.visibility = View.VISIBLE
            animate(bar, 0f)
            bar.postDelayed(hideRunnable, DURATION_MS)
        }
        holder.announceForAccessibility(text)
    }

    fun dismiss() {
        barSpring?.cancel()
        barSpring = null
        bar?.removeCallbacks(hideRunnable)
        bar = null
        holder?.let { (it.parent as? ConstraintLayout)?.removeView(it) }
        holder = null
    }

    private fun hide() {
        val bar = bar ?: return
        animate(bar, bar.height.toFloat()) { if (this.bar === bar) dismiss() }
    }

    private fun animate(bar: View, translation: Float, onEnd: (() -> Unit)? = null) {
        barSpring?.cancel()
        if (!WGlobalStorage.getAreAnimationsActive()) {
            bar.translationY = translation
            onEnd?.invoke()
            return
        }
        barSpring = SpringAnimation(bar, DynamicAnimation.TRANSLATION_Y, translation).apply {
            spring.dampingRatio = DAMPING_RATIO
            spring.stiffness = STIFFNESS
            if (onEnd != null) {
                addEndListener { _, isCanceled, _, _ -> if (!isCanceled) onEnd() }
            }
            start()
        }
    }

    private fun createBar(context: Context, text: String): View = FrameLayout(context).apply {
        minimumHeight = (CONTENT_HEIGHT + 2 * VERTICAL_INSET).dp
        setPadding(HORIZONTAL_INSET.dp, VERTICAL_INSET.dp, HORIZONTAL_INSET.dp, VERTICAL_INSET.dp)
        background = InsetDrawable(
            GradientDrawable().apply {
                cornerRadius = RADIUS.dp.toFloat()
                setColor(BACKGROUND_COLOR)
            },
            HORIZONTAL_INSET.dp,
            VERTICAL_INSET.dp,
            HORIZONTAL_INSET.dp,
            VERTICAL_INSET.dp
        )
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        addView(
            ImageView(context).apply {
                setImageResource(R.drawable.ic_copy_30)
                setColorFilter(TEXT_COLOR)
                scaleType = ImageView.ScaleType.CENTER
            },
            FrameLayout.LayoutParams(ICON_BOX_WIDTH.dp, CONTENT_HEIGHT.dp).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            }
        )
        addView(
            WLabel(context).apply {
                setStyle(TEXT_SIZE, WFont.Regular)
                setTextColor(TEXT_COLOR)
                isSingleLine = true
                ellipsize = TextUtils.TruncateAt.END
                this.text = text
            },
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = ICON_BOX_WIDTH.dp
                marginEnd = TEXT_END.dp
            }
        )
    }

    private companion object {
        const val DURATION_MS = 1500L
        const val DAMPING_RATIO = 0.8f
        const val STIFFNESS = 400f
        const val CONTENT_HEIGHT = 48
        const val HORIZONTAL_INSET = 16
        const val VERTICAL_INSET = 8
        const val RADIUS = 16
        const val ICON_BOX_WIDTH = 56
        const val TEXT_END = 16
        const val TEXT_SIZE = 15f
        const val BACKGROUND_COLOR = 0xEA272F38.toInt()
        const val TEXT_COLOR = 0xFFFFFFFF.toInt()
        const val ONE_UI_4_0 = 40000
        const val ONE_UI_PLATFORM_OFFSET = 90000
        const val ONE_UI_PLATFORM_MIN = 100000

        // Android 12L+ and One UI 4.0 on Android 12 confirm a copy themselves
        fun shouldShow(): Boolean = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2 -> false
            Build.VERSION.SDK_INT == Build.VERSION_CODES.S -> !isOneUi40()
            else -> true
        }

        fun isOneUi40(): Boolean = try {
            val platform = Build.VERSION::class.java
                .getDeclaredField("SEM_PLATFORM_INT")
                .getInt(null)
            platform >= ONE_UI_PLATFORM_MIN && platform - ONE_UI_PLATFORM_OFFSET == ONE_UI_4_0
        } catch (_: Exception) {
            false
        }
    }
}
