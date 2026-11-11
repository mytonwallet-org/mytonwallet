package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentRevealFrame
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentRevealPlaceholder
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentRevealPlan
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentRevealFadeFraction
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentRevealMorphFraction
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.agentRevealMorphFrame
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.planAgentSkeletonReveal

class AgentSkeletonRevealTest {
    // The skeleton of a chat from the bottom up: an answer, a question, an answer, a question and an answer under the
    // header, which ends at 100
    private val skeleton = listOf(
        placeholder(top = 700f, bottom = 948f, isOutgoing = false),
        placeholder(top = 632f, bottom = 688f, isOutgoing = true),
        placeholder(top = 404f, bottom = 620f, isOutgoing = false),
        placeholder(top = 352f, bottom = 392f, isOutgoing = true),
        placeholder(top = 76f, bottom = 340f, isOutgoing = false)
    ).shuffled()

    @Test
    fun bubblesFromTheBottomUpTakeThePlaceholdersFromTheBottomUp() {
        // A long answer under a question that lies partly under the header
        val answer = AgentRevealFrame(10f, 140f, 380f, 2400f)
        val question = AgentRevealFrame(200f, 40f, 380f, 120f)

        val plan = plan(listOf(answer, question))

        assertEquals(listOf(700f, 632f), plan.sources.map { it.frame.top })
        assertEquals(
            listOf(404f, 352f, 76f),
            plan.surplus.map { (placeholder) -> placeholder.frame.top }
        )
    }

    @Test
    fun surplusPlaceholdersSlideUpAboveTheColumnWithoutOverlapping() {
        val answer = AgentRevealFrame(10f, 140f, 380f, 2400f)

        val surplus = plan(listOf(answer)).surplus

        var columnTop = 100f
        for ((placeholder, destination) in surplus) {
            assertTrue(destination.top <= placeholder.frame.top)
            assertTrue(destination.bottom < columnTop)
            assertEquals(placeholder.frame.height, destination.height, 0f)
            assertEquals(placeholder.frame.left, destination.left, 0f)
            columnTop = destination.top
        }
    }

    @Test
    fun bubblesBeyondThePlaceholdersComeFromAbove() {
        val bubbles = (0 until 7).map { index ->
            AgentRevealFrame(10f, 900f - index * 120f, 380f, 1000f - index * 120f)
        }

        val sources = plan(bubbles).sources

        assertEquals(bubbles.size, sources.size)
        sources.zipWithNext { lower, upper ->
            assertTrue(upper.frame.bottom < lower.frame.top)
        }
        assertTrue(plan(bubbles).surplus.isEmpty())
    }

    @Test
    fun aBubbleMovesFromItsPlaceholderAsAFrameWhoseEdgesMoveOnTheirOwn() {
        // A short, wide placeholder below a tall, narrow question
        val placeholder = AgentRevealFrame(200f, 400f, 380f, 440f)
        val question = AgentRevealFrame(300f, 100f, 380f, 220f)

        assertEquals(placeholder, agentRevealMorphFrame(placeholder, question, 0f))
        assertEquals(question, agentRevealMorphFrame(placeholder, question, 1f))
        // Halfway, the frame is halfway in each edge: its shape is drawn at that size rather than stretched to it
        assertEquals(
            AgentRevealFrame(250f, 250f, 380f, 330f),
            agentRevealMorphFrame(placeholder, question, 0.5f)
        )
    }

    @Test
    fun contentsFadeInWhileTheBubbleMovesAndTheRestOnceItHasSettled() {
        assertEquals(0f, agentRevealMorphFraction(0f), 0f)
        assertEquals(1f, agentRevealMorphFraction(360f), 0f)
        // A bubble's contents from 140 ms to the end of the move
        assertEquals(0f, agentRevealFadeFraction(140f, 140f), 0f)
        assertEquals(1f, agentRevealFadeFraction(360f, 140f), 0f)
        // What lies outside the bubbles once the column has settled
        assertEquals(0f, agentRevealFadeFraction(360f, 360f), 0f)
        assertEquals(1f, agentRevealFadeFraction(580f, 360f), 0f)
    }

    private fun plan(targets: List<AgentRevealFrame>): AgentRevealPlan = planAgentSkeletonReveal(
        skeleton,
        targets,
        viewportTop = 100f,
        viewportBottom = 1000f,
        listWidth = 390f,
        isRtl = false,
        dp = 1f
    )

    private fun placeholder(
        top: Float,
        bottom: Float,
        isOutgoing: Boolean
    ): AgentRevealPlaceholder {
        val left = if (isOutgoing) 200f else 10f
        val right = if (isOutgoing) 380f else 340f
        return AgentRevealPlaceholder(AgentRevealFrame(left, top, right, bottom), isOutgoing)
    }
}
