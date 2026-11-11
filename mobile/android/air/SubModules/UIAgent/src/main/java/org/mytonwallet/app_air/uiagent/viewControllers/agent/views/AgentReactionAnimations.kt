package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.graphics.drawable.Drawable
import com.airbnb.lottie.LottieComposition
import com.airbnb.lottie.LottieCompositionFactory
import com.airbnb.lottie.LottieDrawable
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation

/** The TGS file of Telegram's [animation] of this reaction */
internal fun AgentAnswerFeedback.animationRes(animation: AgentReactionAnimation): Int =
    when (this) {
        AgentAnswerFeedback.LIKE -> when (animation) {
            AgentReactionAnimation.APPEAR -> R.raw.agent_reaction_heart_appear
            AgentReactionAnimation.SELECT -> R.raw.agent_reaction_heart_select
            AgentReactionAnimation.CENTER -> R.raw.agent_reaction_heart_center
            AgentReactionAnimation.BURST -> R.raw.agent_reaction_heart_burst
        }

        AgentAnswerFeedback.DISLIKE -> when (animation) {
            AgentReactionAnimation.APPEAR -> R.raw.agent_reaction_heart_broken_appear
            AgentReactionAnimation.SELECT -> R.raw.agent_reaction_heart_broken_select
            AgentReactionAnimation.CENTER -> R.raw.agent_reaction_heart_broken_center
            AgentReactionAnimation.BURST -> R.raw.agent_reaction_heart_broken_burst
        }
    }

/**
 * Sets this drawable's alpha to [alpha], from 0 to 1, only when it changes: Lottie invalidates its drawable on every
 * `setAlpha`, so a drawing that set it each time would schedule the next frame forever
 */
internal fun Drawable.applyAlpha(alpha: Float) {
    val value = (alpha * 255).roundToInt()
    if (this.alpha != value) this.alpha = value
}

/**
 * Telegram's reaction animations, decoded once per session and kept, so that every player after the first starts at
 * once
 */
internal object AgentReactionAnimations {
    private val compositions = mutableMapOf<Int, LottieComposition>()

    /** Starts decoding every reaction animation off the main thread */
    fun preload(context: Context) {
        val appContext = context.applicationContext
        for (feedback in AgentAnswerFeedback.entries) {
            for (animation in AgentReactionAnimation.entries) {
                val res = feedback.animationRes(animation)
                if (res in compositions) continue
                LottieCompositionFactory.fromRawRes(appContext, res)
                    .addListener { compositions[res] = it }
            }
        }
    }

    /**
     * A drawable of [feedback]'s [animation] at its first frame, or null when the file can't be read. Whoever draws it
     * becomes its callback, so that its frames redraw them.
     */
    fun drawable(
        context: Context,
        feedback: AgentAnswerFeedback,
        animation: AgentReactionAnimation
    ): LottieDrawable? {
        val res = feedback.animationRes(animation)
        val composition = compositions[res]
            ?: LottieCompositionFactory.fromRawResSync(context.applicationContext, res).value
                ?.also { compositions[res] = it }
            ?: return null
        return LottieDrawable().apply { setComposition(composition) }
    }
}
