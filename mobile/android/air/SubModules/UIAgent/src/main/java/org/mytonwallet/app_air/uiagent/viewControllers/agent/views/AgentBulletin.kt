package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.os.Build
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.doOnLayout
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import com.airbnb.lottie.LottieDrawable
import org.mytonwallet.app_air.blur3.drawable.color.BlurredBackgroundProvider
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentBulletinDurations
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProvider
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/**
 * Telegram's bulletin: a bar with an icon and a line or two of text that rises for a moment from the given offset above
 * the bottom of the container it shows in, and follows that offset as it changes. Its panel is iOS's overlay toast, a
 * tint over a blur of the given root.
 */
internal class AgentBulletin {
    private var holder: FrameLayout? = null
    private var bar: View? = null
    private var barSpring: SpringAnimation? = null
    private var follower: ViewTreeObserver.OnGlobalLayoutListener? = null
    private var followedTree: ViewTreeObserver? = null
    private val hideRunnable = Runnable { hide() }

    /** Confirms a copy with [text], before Android 12L only, where the system doesn't confirm it itself */
    fun showCopied(
        container: ConstraintLayout,
        blurRoot: ViewGroup?,
        text: String,
        bottomOffset: () -> Int
    ) {
        if (!shouldConfirmCopy()) return
        present(container, blurRoot, text, bottomOffset, AgentBulletinDurations.COPY_MS) {
            setImageResource(R.drawable.ic_copy_30)
            setColorFilter(contentColor)
            scaleType = ImageView.ScaleType.CENTER
        }
    }

    /**
     * Shows [text] beside [animation] in the icon's place, which plays once as the bar rises and rests on its last
     * frame; without motion, it shows that frame at once. The bar stays up for [durationMs].
     */
    fun show(
        container: ConstraintLayout,
        blurRoot: ViewGroup?,
        text: String,
        bottomOffset: () -> Int,
        animation: LottieDrawable,
        durationMs: Long = AgentBulletinDurations.COPY_MS
    ) {
        present(container, blurRoot, text, bottomOffset, durationMs) {
            setImageDrawable(animation)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        if (WGlobalStorage.getAreAnimationsActive()) {
            animation.progress = 0f
            animation.playAnimation()
        } else {
            animation.progress = 1f
        }
    }

    private fun present(
        container: ConstraintLayout,
        blurRoot: ViewGroup?,
        text: String,
        bottomOffset: () -> Int,
        durationMs: Long,
        icon: ImageView.() -> Unit
    ) {
        dismiss()
        val bar = createBar(container.context, blurRoot, text, icon)
        // The holder clips the bar, so it rises from the holder's bottom edge
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
            }
        )
        this.holder = holder
        this.bar = bar
        follow(container, holder, bottomOffset)
        bar.visibility = View.INVISIBLE
        bar.doOnLayout {
            if (this.bar !== bar) return@doOnLayout
            bar.translationY = bar.height.toFloat()
            bar.visibility = View.VISIBLE
            animate(bar, 0f)
            bar.postDelayed(hideRunnable, durationMs)
        }
        holder.announceForAccessibility(text)
    }

    fun dismiss() {
        barSpring?.cancel()
        barSpring = null
        bar?.removeCallbacks(hideRunnable)
        bar = null
        unfollow()
        holder?.let { (it.parent as? ConstraintLayout)?.removeView(it) }
        holder = null
    }

    // The holder's bottom edge keeps to the offset after every layout, as the composer it stands on rides the keyboard,
    // as Telegram's bulletin keeps to its chat's input. A layout precedes the frame's glass sampling, so the blur
    // samples where the bar is in that frame.
    private fun follow(container: View, holder: View, bottomOffset: () -> Int) {
        holder.translationY = -bottomOffset().toFloat()
        val follower = ViewTreeObserver.OnGlobalLayoutListener {
            holder.translationY = -bottomOffset().toFloat()
        }
        val tree = container.viewTreeObserver
        tree.addOnGlobalLayoutListener(follower)
        this.follower = follower
        followedTree = tree
        // A screen leaving the window stops the following, which would otherwise keep it from being collected
        holder.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(v: View) = Unit

            override fun onViewDetachedFromWindow(v: View) {
                v.removeOnAttachStateChangeListener(this)
                if (this@AgentBulletin.holder === v) unfollow()
            }
        })
    }

    private fun unfollow() {
        val follower = follower ?: return
        val tree = followedTree?.takeIf { it.isAlive } ?: holder?.viewTreeObserver
        tree?.removeOnGlobalLayoutListener(follower)
        this.follower = null
        followedTree = null
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

    private fun createBar(
        context: Context,
        blurRoot: ViewGroup?,
        text: String,
        icon: ImageView.() -> Unit
    ): View {
        val panel = createPanel(context, text, icon)
        val bar = FrameLayout(context).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            addView(
                panel,
                FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                    marginStart = HORIZONTAL_INSET.dp
                    marginEnd = HORIZONTAL_INSET.dp
                    topMargin = VERTICAL_INSET.dp
                    bottomMargin = VERTICAL_INSET.dp
                }
            )
        }
        // The app's frosted glass, as its own toast's, which blurs and leaves the root as the bar comes and goes. It
        // takes the panel's size, its shadow's room around it, once the panel has one, so it never sizes the bar; the
        // panel's margins hold that room.
        WGlassView.attachTo(
            panel,
            RADIUS.dp.toFloat(),
            AgentBulletinGlass(),
            blurRoot,
            flavor = GlassFlavor.FROSTED
        ).apply {
            liquidGlass = false
            layoutParams = FrameLayout.LayoutParams(0, 0)
        }
        return bar
    }

    private fun createPanel(context: Context, text: String, icon: ImageView.() -> Unit): View =
        FrameLayout(context).apply {
            minimumHeight = CONTENT_HEIGHT.dp
            addView(
                ImageView(context).apply(icon),
                FrameLayout.LayoutParams(ICON_BOX_WIDTH.dp, CONTENT_HEIGHT.dp).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                }
            )
            addView(
                WLabel(context).apply {
                    setStyle(TEXT_SIZE, WFont.Regular)
                    setTextColor(contentColor)
                    // A longer line, as a reaction's explanation is in some languages, takes a second one
                    isSingleLine = false
                    maxLines = 2
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

    // The toast's text colour over the dark theme's panel, white over the light theme's black
    private val contentColor: Int
        get() = if (ThemeManager.isDark) WColor.PrimaryText.color else WColor.White.color

    /**
     * iOS's overlay toast: Telegram's undo-overlay tint over the blur, opaque where the app's glass doesn't blur, as
     * that glass is, with no rim and a soft black shadow
     */
    private class AgentBulletinGlass : BlurredBackgroundProvider {
        private val panel = GlassProvider(
            panelColor = { if (ThemeManager.isDark) DARK_PANEL else WColor.Black.color },
            panelAlpha = { if (ThemeManager.isDark) DARK_PANEL_ALPHA else LIGHT_PANEL_ALPHA },
            rim = false,
            shadow = false
        )

        override fun getBackgroundColor(): Int = panel.getBackgroundColor()

        override fun getShadowColor(): Int = SHADOW_COLOR

        override fun getStrokeColorTop(): Int = 0

        override fun getStrokeColorBottom(): Int = 0

        override fun getStrokeWidthTop(): Float = 0f

        override fun getStrokeWidthBottom(): Float = 0f

        override fun getShadowRadius(): Float = SHADOW_RADIUS.dp

        override fun getShadowDx(): Float = 0f

        override fun getShadowDy(): Float = SHADOW_DY.dp
    }

    private companion object {
        const val DAMPING_RATIO = 0.8f
        const val STIFFNESS = 400f
        const val CONTENT_HEIGHT = 48
        const val HORIZONTAL_INSET = 16
        const val VERTICAL_INSET = 8
        const val RADIUS = 16
        const val ICON_BOX_WIDTH = 56
        const val TEXT_END = 16
        const val TEXT_SIZE = 15f

        // iOS's toast background in the light theme, black at 65 %, and Telegram's undo overlay, iOS's in the dark one
        const val LIGHT_PANEL_ALPHA = 0.65f
        const val DARK_PANEL = 0xFF1D1D1D.toInt()
        const val DARK_PANEL_ALPHA = 0.9f

        // iOS's toast shadow, black at 20 % and 1 dp down, as wide as the room around the glass allows
        const val SHADOW_COLOR = 0x33000000
        const val SHADOW_RADIUS = 4f
        const val SHADOW_DY = 1f

        const val ONE_UI_4_0 = 40000
        const val ONE_UI_PLATFORM_OFFSET = 90000
        const val ONE_UI_PLATFORM_MIN = 100000

        // Android 12L+ and One UI 4.0 on Android 12 confirm a copy themselves
        fun shouldConfirmCopy(): Boolean = when {
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
