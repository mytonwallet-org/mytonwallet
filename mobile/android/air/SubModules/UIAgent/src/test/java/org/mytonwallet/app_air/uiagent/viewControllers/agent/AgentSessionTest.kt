package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class AgentSessionTest {
    private class Model(var shouldRetain: Boolean = false, var onIdle: (() -> Unit)? = null)

    @Test
    fun sharesOneModelPerThreadUntilItsLastOwnerLeaves() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed)
        val first = sessions.acquire("first") { Model() }
        val secondOwner = sessions.acquire("first") { error("Thread already has a model") }
        val other = sessions.acquire("other") { Model() }

        assertSame(first, secondOwner)
        assertNotSame(first, other)
        sessions.release("first", first)
        sessions.release("first", other)
        assertEquals(emptyList<Model>(), destroyed)
        sessions.release("first", secondOwner)
        assertEquals(listOf(first), destroyed)
        assertSame(other, sessions.acquire("other") { error("Other thread must stay alive") })
    }

    @Test
    fun keepsABackgroundRunAndDoesNotDestroyItsReopenedChat() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed)
        val model = sessions.acquire("thread") { Model(shouldRetain = true) }
        sessions.release("thread", model)
        val previousIdle = checkNotNull(model.onIdle)
        assertEquals(emptyList<Model>(), destroyed)

        assertSame(model, sessions.acquire("thread") { error("Running model must be reused") })
        assertNull(model.onIdle)
        model.shouldRetain = false
        previousIdle()
        assertEquals(emptyList<Model>(), destroyed)
        sessions.release("thread", model)
        assertEquals(listOf(model), destroyed)

        val replacement = sessions.acquire("thread") { Model() }
        previousIdle()
        assertSame(
            replacement,
            sessions.acquire("thread") {
                error("Stale callback destroyed new model")
            }
        )
        assertEquals(listOf(model), destroyed)
    }

    @Test
    fun destroysAnUnownedModelWhenItsBackgroundRunFinishes() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed)
        val model = sessions.acquire("thread") { Model(shouldRetain = true) }
        sessions.release("thread", model)
        val onIdle = checkNotNull(model.onIdle)
        model.shouldRetain = false
        onIdle()

        assertEquals(listOf(model), destroyed)
        assertNull(model.onIdle)
        assertNotSame(model, sessions.acquire("thread") { Model() })
    }

    @Test
    fun evictedModelIsNotReusedAndItsOwnersCannotAffectItsReplacement() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed)
        val deleted = sessions.acquire("thread") { Model() }
        sessions.acquire("thread") { error("Thread already has a model") }

        sessions.evict("thread", deleted)
        val replacement = sessions.acquire("thread") { Model() }
        assertNotSame(deleted, replacement)

        sessions.evict("thread", deleted)
        sessions.release("thread", deleted)
        sessions.release("thread", deleted)
        assertSame(replacement, sessions.acquire("thread") { error("Replacement must stay") })
        assertEquals(emptyList<Model>(), destroyed)
    }

    private fun createSessions(destroyed: MutableList<Model>) = AgentThreadSessions<Model>(
        shouldRetain = { it.shouldRetain },
        setIdleHandler = { model, handler -> model.onIdle = handler },
        destroy = { destroyed += it }
    )
}
