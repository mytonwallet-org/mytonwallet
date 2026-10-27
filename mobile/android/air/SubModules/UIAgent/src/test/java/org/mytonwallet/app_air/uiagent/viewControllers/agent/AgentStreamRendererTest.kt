package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentStreamRendererTest {
    @Test
    fun rendersEachMessageOncePerFrameUsingTheLatestStateIncludingCompletion() {
        val frames = mutableListOf<Runnable>()
        val messages = mutableMapOf<String, AgentMessage>()
        val rendered = mutableListOf<AgentMessage>()
        val renderer = AgentStreamRenderer(frames::add, frames::remove) { ids ->
            ids.forEach { rendered.add(messages.getValue(it)) }
        }
        renderer.setActive(true)

        repeat(100) { index ->
            messages["answer"] = AgentMessage(
                id = "answer",
                role = AgentMessageRole.ASSISTANT,
                text = "Text $index",
                isStreaming = true
            )
            renderer.enqueue("answer")
        }
        assertEquals(1, frames.size)
        frames.removeAt(0).run()
        assertEquals(listOf("Text 99"), rendered.map { it.text })

        messages["answer"] = messages.getValue("answer").copy(
            text = "Final text",
            isStreaming = false
        )
        renderer.enqueue("answer")
        renderer.enqueue("answer")
        assertEquals(1, frames.size)
        frames.removeAt(0).run()
        assertEquals(listOf("Text 99", "Final text"), rendered.map { it.text })
        assertEquals(false, rendered.last().isStreaming)
        assertTrue(frames.isEmpty())
    }

    @Test
    fun pausesPendingRenderingUntilVisibleAndKeepsTheLastUpdate() {
        val frames = mutableListOf<Runnable>()
        var text = "First"
        val rendered = mutableListOf<String>()
        val renderer = AgentStreamRenderer(frames::add, frames::remove) {
            rendered.add(text)
        }
        renderer.setActive(true)
        renderer.enqueue("answer")
        renderer.setActive(false)
        assertTrue(frames.isEmpty())

        repeat(100) { index ->
            text = "Text $index"
            renderer.enqueue("answer")
        }
        text = "Final text"
        renderer.enqueue("answer")
        assertTrue(frames.isEmpty())
        assertTrue(rendered.isEmpty())

        renderer.setActive(true)
        assertEquals(1, frames.size)
        frames.removeAt(0).run()
        assertEquals(listOf("Final text"), rendered)

        renderer.enqueue("answer")
        renderer.clear()
        assertTrue(frames.isEmpty())
    }
}
