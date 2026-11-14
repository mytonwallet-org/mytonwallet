package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionChange
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionToasts
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentReactionChange
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentReactionPressAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.agentReactionSlotAppearance
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.shownReaction
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.applyAlpha

class AgentReactionTest {
    @Test
    fun onlyAnAnswerWithABubbleCarriesItsReaction() {
        val answer = AgentMessage(
            role = AgentMessageRole.ASSISTANT,
            text = "TON is a blockchain.",
            isComplete = true,
            feedback = AgentAnswerFeedback.LIKE
        )

        assertEquals(AgentAnswerFeedback.LIKE, answer.shownReaction)
        assertNull(answer.copy(text = "").shownReaction)
        assertNull(answer.copy(newsPost = true).shownReaction)
        assertNull(answer.copy(role = AgentMessageRole.USER).shownReaction)
    }

    @Test
    fun emojiShowsAtOnceForAnotherMessageOrOneOffTheScreen() {
        val like = AgentAnswerFeedback.LIKE
        assertEquals(AgentReactionChange.SHOW, change(null, like, isSameMessage = false))
        assertEquals(AgentReactionChange.SHOW, change(like, like, isSameMessage = false))
        assertEquals(AgentReactionChange.SHOW, change(null, like, isOnScreen = false))
        assertEquals(AgentReactionChange.NONE, change(like, like))
    }

    @Test
    fun chosenReactionWaitsForItsIconToLand() {
        val like = AgentAnswerFeedback.LIKE
        val dislike = AgentAnswerFeedback.DISLIKE
        assertEquals(AgentReactionChange.AWAIT_LANDING, change(null, like, flying = like))
        assertEquals(AgentReactionChange.AWAIT_LANDING, change(dislike, like, flying = like))
    }

    @Test
    fun emojiGivesWayToTheNextOrShrinksAway() {
        val like = AgentAnswerFeedback.LIKE
        val dislike = AgentAnswerFeedback.DISLIKE
        assertEquals(AgentReactionChange.SWAP, change(null, like))
        assertEquals(AgentReactionChange.SWAP, change(like, dislike))
        assertEquals(AgentReactionChange.WITHDRAW, change(like, null))
        assertEquals(AgentReactionChange.WITHDRAW, change(like, null, flying = like))
    }

    @Test
    fun menuOpensAndClosesWithoutTouchingTheEmoji() {
        // Every place in the cloud plays appear as on an unrated answer, the rated one with its circle
        val appear = AgentReactionAnimation.APPEAR
        assertEquals(appear, agentReactionSlotAppearance(canAnimate = true))
        // Closing without a change leaves the emoji as it is
        val like = AgentAnswerFeedback.LIKE
        assertEquals(AgentReactionChange.NONE, change(like, like))
    }

    @Test
    fun pressedIconPlaysSelectWithMotion() {
        assertEquals(AgentReactionAnimation.SELECT, agentReactionPressAnimation(canAnimate = true))
        assertNull(agentReactionPressAnimation(canAnimate = false))
    }

    @Test
    fun flightHandsOverToTheCornerAsItHits() {
        val like = AgentAnswerFeedback.LIKE
        val dislike = AgentAnswerFeedback.DISLIKE
        // The corner keeps what it shows till then, and the rating arriving after the hit changes nothing
        assertEquals(AgentReactionChange.AWAIT_LANDING, change(dislike, like, flying = like))
        assertEquals(AgentReactionChange.NONE, change(like, like, flying = like))
    }

    @Test
    fun reduceMotionFadesTheEmojiWithoutAFlight() {
        val like = AgentAnswerFeedback.LIKE
        assertEquals(AgentReactionChange.FADE, change(null, like, canAnimate = false))
        assertEquals(AgentReactionChange.FADE, change(like, null, canAnimate = false))
        val chosen = change(null, like, canAnimate = false, flying = like)
        assertEquals(AgentReactionChange.FADE, chosen)
        // The cloud shows its stills at once
        assertNull(agentReactionSlotAppearance(canAnimate = false))
        assertNull(agentReactionPressAnimation(canAnimate = false))
    }

    @Test
    fun firstReactionToastShowsOnceItHasLandedAndBeenSavedWhicheverIsLater() {
        val stored = mutableSetOf<AgentAnswerFeedback>()
        val shown = mutableListOf<String>()
        val toasts = toasts(stored)

        val like = toasts.await("a", AgentAnswerFeedback.LIKE) { _, key -> shown += key }!!
        like.land()
        assertEquals(emptyList<String>(), shown)
        like.confirmSave()
        assertEquals(listOf("\$agent_feedback_liked_toast"), shown)
        assertEquals(setOf(AgentAnswerFeedback.LIKE), stored)

        // Saved before it lands, the other kind shows its own toast as it lands
        val dislike = toasts.await("b", AgentAnswerFeedback.DISLIKE) { _, key -> shown += key }!!
        dislike.confirmSave()
        assertEquals(1, shown.size)
        dislike.land()
        assertEquals("\$agent_feedback_disliked_toast", shown.last())

        // Each kind shows once on the install, also in a later launch
        assertNull(toasts(stored).await("c", AgentAnswerFeedback.LIKE) { _, key -> shown += key })
    }

    @Test
    fun firstReactionToastsKeepAgentAndSupportSeparateForEachReaction() {
        for (isOperatorFirst in listOf(false, true)) {
            val stored = mutableSetOf<AgentAnswerFeedback>()
            val storedSupport = mutableSetOf<AgentAnswerFeedback>()
            val shown = mutableListOf<String>()
            for ((feedback, agentKey, supportKey) in listOf(
                Triple(
                    AgentAnswerFeedback.LIKE,
                    "\$agent_feedback_liked_toast",
                    "\$agent_feedback_support_liked_toast"
                ),
                Triple(
                    AgentAnswerFeedback.DISLIKE,
                    "\$agent_feedback_disliked_toast",
                    "\$agent_feedback_support_disliked_toast"
                )
            )) {
                for (isOperator in listOf(isOperatorFirst, !isOperatorFirst)) {
                    // A later launch restores both kinds without suppressing the other author's first toast
                    val toasts = toasts(stored, storedSupport)
                    toasts.await("a", feedback, isOperator) { _, key -> shown += key }!!.apply {
                        confirmSave()
                        land()
                    }
                    assertEquals(if (isOperator) supportKey else agentKey, shown.last())
                    assertNull(
                        toasts.await("b", feedback, isOperator) { _, _ ->
                            fail("Each author's reaction toast shows once")
                        }
                    )
                }
            }
            assertEquals(4, shown.size)
            assertEquals(setOf(AgentAnswerFeedback.LIKE, AgentAnswerFeedback.DISLIKE), stored)
            assertEquals(stored, storedSupport)
        }
    }

    @Test
    fun firstReactionToastWaitsForASaveThatFailsWithoutShowing() {
        val stored = mutableSetOf<AgentAnswerFeedback>()
        val toasts = toasts(stored)
        toasts.await("a", AgentAnswerFeedback.LIKE) { _, _ ->
            fail("A failed save shows no toast")
        }!!.land()

        assertEquals(emptySet<AgentAnswerFeedback>(), stored)
        assertNotNull(toasts.await("a", AgentAnswerFeedback.LIKE) { _, _ -> })
    }

    @Test
    fun firstReactionToastGoesWithAFailedSave() {
        val stored = mutableSetOf<AgentAnswerFeedback>()
        val toasts = toasts(stored)
        val like = toasts.await("a", AgentAnswerFeedback.LIKE) { _, _ ->
            fail("A cancelled toast does not show")
        }!!
        like.land()
        like.cancel()
        like.confirmSave()

        assertEquals(emptySet<AgentAnswerFeedback>(), stored)
        // The like that saves later still explains itself
        val shown = mutableListOf<String>()
        toasts.await("b", AgentAnswerFeedback.LIKE) { _, key -> shown += key }!!.apply {
            land()
            confirmSave()
        }
        assertEquals(listOf("\$agent_feedback_liked_toast"), shown)
    }

    @Test
    fun firstReactionToastGoesWithAReactionChangedOrWithdrawnBeforeItsSave() {
        val stored = mutableSetOf<AgentAnswerFeedback>()
        val shown = mutableListOf<String>()
        val toasts = toasts(stored)
        for (next in listOf(AgentAnswerFeedback.DISLIKE, null)) {
            val like = toasts.await("a", AgentAnswerFeedback.LIKE) { _, key -> shown += key }!!
            like.land()
            toasts.await("a", next) { _, key -> shown += key }
            like.confirmSave()
        }

        assertEquals(emptyList<String>(), shown)
        assertEquals(emptySet<AgentAnswerFeedback>(), stored)
    }

    @Test
    fun emojiAtRestSetsItsAlphaOnlyWhenItChanges() {
        // Each `setAlpha` invalidates a Lottie drawable, which draws it again
        val emoji = object : Drawable() {
            var alphaSets = 0
            private var value = 255

            override fun getAlpha() = value

            override fun setAlpha(alpha: Int) {
                value = alpha
                alphaSets++
            }

            override fun draw(canvas: Canvas) = Unit

            override fun setColorFilter(colorFilter: ColorFilter?) = Unit

            @Deprecated("Deprecated in Java")
            override fun getOpacity() = PixelFormat.TRANSLUCENT
        }
        emoji.applyAlpha(1f)
        assertEquals(0, emoji.alphaSets)
        emoji.applyAlpha(0.5f)
        emoji.applyAlpha(0.5f)
        assertEquals(1, emoji.alphaSets)
        assertEquals(128, emoji.alpha)
    }

    private fun toasts(
        shown: MutableSet<AgentAnswerFeedback>,
        shownSupport: MutableSet<AgentAnswerFeedback> = mutableSetOf()
    ) = AgentReactionToasts(
        isShown = { feedback, isOperator -> feedback in if (isOperator) shownSupport else shown },
        markShown = { feedback, isOperator ->
            (if (isOperator) shownSupport else shown) += feedback
        }
    )

    private fun change(
        shown: AgentAnswerFeedback?,
        next: AgentAnswerFeedback?,
        isSameMessage: Boolean = true,
        isOnScreen: Boolean = true,
        canAnimate: Boolean = true,
        flying: AgentAnswerFeedback? = null
    ) = agentReactionChange(shown, next, isSameMessage, isOnScreen, canAnimate, flying)
}
