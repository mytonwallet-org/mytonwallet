package org.mytonwallet.app_air.walletcontext.secureStorage

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WSecureStorageOrderingTest {
    @Test
    fun cleanupRemovesWritesQueuedBeforeIt() {
        val storage = StorageHarness()
        try {
            storage.setFailedLoginAttempts(2)
            storage.setLastFailedAttempt(100)

            storage.cleanup()

            assertTrue(storage.cachedValues.isEmpty())
            assertTrue(storage.persistedValues.isEmpty())
        } finally {
            storage.close()
        }
    }

    @Test
    fun concurrentSettersStartingDuringCleanupAreIncludedAfterIt() {
        val storage = StorageHarness()
        val callers = Executors.newFixedThreadPool(3)
        val cleanupStarted = CountDownLatch(1)
        val finishCleanup = CountDownLatch(1)
        try {
            val cleanup = callers.submit {
                storage.cleanup {
                    cleanupStarted.countDown()
                    assertTrue(finishCleanup.await(5, TimeUnit.SECONDS))
                }
            }
            assertTrue(cleanupStarted.await(5, TimeUnit.SECONDS))

            val writersStarted = CountDownLatch(2)
            val failedAttemptsWrite = callers.submit {
                writersStarted.countDown()
                storage.setFailedLoginAttempts(2)
            }
            val lastAttemptWrite = callers.submit {
                writersStarted.countDown()
                storage.setLastFailedAttempt(100)
            }
            assertTrue(writersStarted.await(5, TimeUnit.SECONDS))
            assertFalse(failedAttemptsWrite.isDone)
            assertFalse(lastAttemptWrite.isDone)

            finishCleanup.countDown()
            cleanup.get(5, TimeUnit.SECONDS)
            failedAttemptsWrite.get(5, TimeUnit.SECONDS)
            lastAttemptWrite.get(5, TimeUnit.SECONDS)
            storage.awaitPendingWrites()

            assertEquals("2", storage.cachedValues[FAILED_LOGIN_ATTEMPTS])
            assertEquals("100", storage.cachedValues[LAST_FAILED_ATTEMPT])
            assertEquals("2", storage.persistedValues[FAILED_LOGIN_ATTEMPTS])
            assertEquals("100", storage.persistedValues[LAST_FAILED_ATTEMPT])
        } finally {
            finishCleanup.countDown()
            callers.shutdownNow()
            storage.close()
        }
    }

    private class StorageHarness {
        val cachedValues = ConcurrentHashMap<String, String>()
        val persistedValues = ConcurrentHashMap<String, String>()
        private val executor = Executors.newSingleThreadExecutor()
        private val operationLock = Any()

        fun setFailedLoginAttempts(value: Int) = write(FAILED_LOGIN_ATTEMPTS, value.toString())

        fun setLastFailedAttempt(value: Long) = write(LAST_FAILED_ATTEMPT, value.toString())

        fun cleanup(beforeClear: () -> Unit = {}) {
            synchronized(operationLock) {
                executor.submit {
                    beforeClear()
                    cachedValues.clear()
                    persistedValues.clear()
                }.get()
            }
        }

        fun awaitPendingWrites() {
            synchronized(operationLock) {
                executor.submit {}.get()
            }
        }

        fun close() = executor.shutdownNow()

        private fun write(key: String, value: String) {
            synchronized(operationLock) {
                cachedValues[key] = value
                executor.execute {
                    persistedValues[key] = value
                }
            }
        }
    }

    private companion object {
        const val FAILED_LOGIN_ATTEMPTS = "failedLoginAttempts"
        const val LAST_FAILED_ATTEMPT = "lastFailedAttempt"
    }
}
