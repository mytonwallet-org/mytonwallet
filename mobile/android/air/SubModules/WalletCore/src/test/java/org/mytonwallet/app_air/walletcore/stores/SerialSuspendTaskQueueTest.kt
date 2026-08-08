package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertFalse
import org.junit.Test

class SerialSuspendTaskQueueTest {
    @Test
    fun keepsLaterTasksOrderedWhileTheCurrentTaskIsSuspended() = runBlocking {
        val queue = SerialSuspendTaskQueue()
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val secondStarted = CompletableDeferred<Unit>()

        queue.execute {
            firstStarted.complete(Unit)
            releaseFirst.await()
        }
        queue.execute {
            secondStarted.complete(Unit)
        }

        withTimeout(1_000) { firstStarted.await() }
        assertFalse(secondStarted.isCompleted)

        releaseFirst.complete(Unit)
        withTimeout(1_000) { secondStarted.await() }
    }

    @Test
    fun nestedTasksStayBehindTasksQueuedDuringSuspension() = runBlocking {
        val queue = SerialSuspendTaskQueue()
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val secondCompleted = CompletableDeferred<Unit>()
        val nestedCompleted = CompletableDeferred<Unit>()

        queue.execute {
            firstStarted.complete(Unit)
            releaseFirst.await()
            queue.execute {
                nestedCompleted.complete(Unit)
            }
        }
        withTimeout(1_000) { firstStarted.await() }
        queue.execute {
            assertFalse(nestedCompleted.isCompleted)
            secondCompleted.complete(Unit)
        }

        releaseFirst.complete(Unit)
        withTimeout(1_000) { secondCompleted.await() }
        withTimeout(1_000) { nestedCompleted.await() }
    }
}
