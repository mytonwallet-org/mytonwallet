package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import androidx.core.view.isVisible
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMarkDrawable
import org.mytonwallet.app_air.uicomponents.emoji.EmojiSpan
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

/**
 * A chat's avatar: a circle in the gradient the thread's id picks, with the thread's emoji, or else the Agent mark
 * in white. The mark's silhouette, not its design box, is centered.
 */
@SuppressLint("ViewConstructor")
internal class AgentThreadAvatarView(context: Context, private val diameter: Int) :
    FrameLayout(context) {
    private val circleDrawable = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        orientation = GradientDrawable.Orientation.TOP_BOTTOM
    }
    private val emojiLabel = WLabel(context).apply {
        useCustomEmoji = true
        gravity = Gravity.CENTER
        includeFontPadding = false
        setTextSize(TypedValue.COMPLEX_UNIT_PX, diameter * EMOJI_SIZE_RATIO)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val markView = View(context).apply {
        id = generateViewId()
        background = AgentMarkDrawable(Color.WHITE)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    init {
        id = generateViewId()
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        background = circleDrawable
        addView(emojiLabel, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        val markSize = (diameter * MARK_SIZE_RATIO).roundToInt()
        addView(markView, LayoutParams(markSize, markSize, Gravity.CENTER))
    }

    private var configuredSeed: String? = null
    private var shownEmoji: String? = null

    /** A chat that gets its emoji while shown, as a new one does once its title comes, swaps the mark for it */
    fun configure(seed: String, emoji: String?) {
        circleDrawable.colors = seed.gradientColors
        val newEmoji = emoji?.takeIf { it.isNotBlank() }
        val isArriving = seed == configuredSeed && shownEmoji == null && newEmoji != null &&
            isAttachedToWindow && WGlobalStorage.getAreAnimationsActive()
        configuredSeed = seed
        shownEmoji = newEmoji
        emojiLabel.animate().cancel()
        markView.animate().cancel()
        emojiLabel.text = newEmoji
        emojiLabel.isVisible = newEmoji != null
        if (isArriving) {
            emojiLabel.alpha = 0f
            emojiLabel.scaleX = EMOJI_ARRIVAL_SCALE
            emojiLabel.scaleY = EMOJI_ARRIVAL_SCALE
            emojiLabel.animate().alpha(1f).scaleX(1f).scaleY(1f)
                .setDuration(EMOJI_ARRIVAL_MS)
                .setInterpolator(WInterpolator.emphasizedDecelerate)
                .start()
            markView.animate().alpha(0f).setDuration(EMOJI_ARRIVAL_MS / 2)
                .withEndAction {
                    markView.isVisible = false
                    markView.alpha = 1f
                }
                .start()
            return
        }
        emojiLabel.alpha = 1f
        emojiLabel.scaleX = 1f
        emojiLabel.scaleY = 1f
        markView.alpha = 1f
        markView.isVisible = newEmoji == null
    }

    private companion object {
        // iOS's emoji across 26/60 of the diameter, as Telegram's 26 pt emoji in its 60 pt circle. Both draw Apple's
        // emoji image: iOS one font size across, the emoji span its own ratio of the text size.
        const val EMOJI_SIZE_RATIO = 26f / 60f / EmojiSpan.TEXT_SIZE_RATIO
        const val MARK_SIZE_RATIO = 0.6f
        const val EMOJI_ARRIVAL_SCALE = 0.6f
        const val EMOJI_ARRIVAL_MS = 250L
    }
}
