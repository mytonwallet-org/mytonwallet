package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mytonwallet.app_air.walletcontext.installationStorage.PlaySnapshot
import org.mytonwallet.app_air.walletcontext.installationStorage.SourceSnapshot

class InstallSourceContractTest {
    private class Service(
        private val response: Int = 0,
        private val connectFailure: Boolean = false,
        private val readFailure: Boolean = false,
        private val held: Boolean = false,
        private val snapshot: ReferrerSnapshot =
            ReferrerSnapshot("utm_source=campaign", 1, "original")
    ) : ReferrerService {
        var closes = 0
        private var callback: (Int) -> Unit = {}
        override fun start(callback: (Int) -> Unit) {
            if (connectFailure) error("connect")
            this.callback = callback
            if (!held) finish()
        }
        fun finish() = callback(response)
        override fun read() = snapshot.also { if (readFailure) error("read") }
        override fun close() = Unit.also { closes++ }
    }

    private fun immediate(operation: () -> Unit) = true.also { operation() }

    @Test fun responsesAndExceptionsPersistDistinctRetryableOutcomes() {
        val cases = listOf(
            Service(-1) to "service_disconnected",
            Service(1) to "service_unavailable",
            Service(2) to "feature_not_supported",
            Service(3) to "developer_error",
            Service(99) to "unexpected_response",
            Service(connectFailure = true) to "connection_exception",
            Service(readFailure = true) to "read_exception"
        )
        cases.forEach { (service, expected) ->
            val saved = mutableListOf<PlaySnapshot>()
            val collector = ReferrerCollection(
                { service },
                ::immediate,
                saved::add,
                { error("persist") }
            ) { it() }
            collector.collect(false) {}
            collector.collect(false) {}
            collector.collect(true) {}
            assertEquals(listOf(expected, expected), saved.map(PlaySnapshot::collectionStatus))
            assertEquals(2, service.closes)
        }
    }

    @Test fun rejectedDispatchFailedPersistenceAndStaleCallbacksRemainRetryable() {
        var attempts = 0
        var notifications = 0
        var persistFailures = 0
        var reject = true
        val retries = ArrayDeque<() -> Unit>()
        val services = mutableListOf<Service>()
        val collector = ReferrerCollection(
            { Service(held = true).also(services::add) },
            { operation -> !reject && immediate(operation) },
            { if (++attempts == 1) error("disk") },
            { persistFailures++ },
            retries::add
        )
        collector.collect(false) { notifications++ }
        collector.collect(false) { notifications++ }
        services.single().finish()
        assertEquals(0, attempts)
        assertEquals(1, retries.size)
        retries.removeFirst()()
        assertEquals(1, retries.size)
        reject = false
        retries.removeFirst()()
        services.first().finish()
        services.last().finish()
        assertEquals(1, attempts)
        assertEquals(0, notifications)
        assertEquals(1, persistFailures)
        collector.collect(false) { notifications++ }
        services.last().finish()
        services.last().finish()
        assertEquals(2, attempts)
        assertEquals(1, notifications)
        assertEquals(1, persistFailures)
    }

    @Test fun successfulPayloadDropsUnavailableOrUnsafeMetadata() {
        val service = Service(snapshot = ReferrerSnapshot("utm_source=campaign", 0, "original"))
        lateinit var saved: PlaySnapshot
        ReferrerCollection({ service }, ::immediate, { saved = it }, {}) { it() }.collect(false) {}
        assertNull(saved.playInstalledAt)
        assertEquals("original", saved.installVersion)
        assertEquals(SourceSnapshot("campaign", "utm", "utm"), saved.source)
        assertNull(readPlayInstallMetadata(9007199254741, null).installedAt)
        assertNull(readPlayInstallMetadata(-1, null).installedAt)
        assertEquals("", readPlayInstallMetadata(1, "v".repeat(65)).installVersion)
    }
}
