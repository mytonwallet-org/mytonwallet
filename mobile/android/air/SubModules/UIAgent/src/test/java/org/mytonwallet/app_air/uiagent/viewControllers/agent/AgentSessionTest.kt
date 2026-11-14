package org.mytonwallet.app_air.uiagent.viewControllers.agent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class AgentSessionTest {
    private class Model(
        var shouldRetain: Boolean = false,
        var onIdle: (() -> Unit)? = null,
        var canKeep: Boolean = true
    )

    @Test
    fun keepsTheLatestLeftChatsLoadedAndDestroysTheOldestBeyondTheLimit() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed, recentLimit = 2)
        val first = sessions.acquire("first", keepsRecent = true) { Model() }
        val second = sessions.acquire("second", keepsRecent = true) { Model() }
        val third = sessions.acquire("third", keepsRecent = true) { Model() }

        sessions.release("first", first)
        sessions.release("second", second)
        assertEquals(emptyList<Model>(), destroyed)
        assertSame(first, sessions.acquire("first") { error("A chat left lately stays loaded") })
        sessions.release("first", first)
        sessions.release("third", third)

        assertEquals(listOf(second), destroyed)
        assertSame(first, sessions.acquire("first") { error("Reopening refreshed its place") })
        assertSame(third, sessions.acquire("third") { error("The latest chat must stay loaded") })
    }

    @Test
    fun destroysALeftChatThatCannotStayAndForgetsKeptOnesOnRequest() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed, recentLimit = 2)
        val failed = sessions.acquire("failed", keepsRecent = true) { Model(canKeep = false) }
        val kept = sessions.acquire("kept", keepsRecent = true) { Model() }
        val running = sessions.acquire("running", keepsRecent = true) { Model() }
        val owned = sessions.acquire("owned") { Model() }

        sessions.release("owned", owned)
        assertEquals(listOf(owned), destroyed)
        destroyed.clear()
        sessions.release("failed", failed)
        sessions.release("kept", kept)
        sessions.release("running", running)
        assertEquals(listOf(failed), destroyed)

        running.shouldRetain = true
        sessions.forgetRecent()
        assertEquals(listOf(failed, kept), destroyed)
        running.shouldRetain = false
        checkNotNull(running.onIdle)()
        assertEquals(listOf(failed, kept, running), destroyed)
        assertNotSame(kept, sessions.acquire("kept") { Model() })
    }

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

    @Test
    fun aDeletedThreadsChatGoesOnceNoOneOwnsItThoughItHasWorkUnderWay() {
        val destroyed = mutableListOf<Model>()
        val sessions = createSessions(destroyed, recentLimit = 2)
        val queued = sessions.acquire("queued") { Model(shouldRetain = true) }
        val kept = sessions.acquire("kept", keepsRecent = true) { Model() }
        val open = sessions.acquire("open") { Model(shouldRetain = true) }
        sessions.release("queued", queued)
        sessions.release("kept", kept)
        val queuedIdle = checkNotNull(queued.onIdle)
        assertEquals(emptyList<Model>(), destroyed)

        // A left chat goes at once, though it has questions queued or is kept for reopening
        sessions.dropDeleted("queued")
        sessions.dropDeleted("kept")
        sessions.dropDeleted("open")
        assertEquals(listOf(queued, kept), destroyed)
        assertNull(queued.onIdle)
        queuedIdle()
        assertEquals(listOf(queued, kept), destroyed)

        // An open one goes once its last owner leaves
        sessions.release("open", open)
        assertEquals(listOf(queued, kept, open), destroyed)
        assertNotSame(kept, sessions.acquire("kept") { Model() })
    }

    private fun createSessions(destroyed: MutableList<Model>, recentLimit: Int = 0) =
        AgentThreadSessions<Model>(
            shouldRetain = { it.shouldRetain },
            setIdleHandler = { model, handler -> model.onIdle = handler },
            destroy = { destroyed += it },
            recentLimit = recentLimit,
            canKeep = { it.canKeep }
        )
}
