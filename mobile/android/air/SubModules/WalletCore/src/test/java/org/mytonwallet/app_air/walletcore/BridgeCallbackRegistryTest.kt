package org.mytonwallet.app_air.walletcore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mytonwallet.app_air.walletcore.models.MBridgeError

class BridgeCallbackRegistryTest {
    @Test
    fun apiErrorsAreRecoverableExceptionsWithoutRawResponseInMessage() {
        val rawResponse = "sensitive bridge response"
        val throwable: Throwable = JSWebViewBridge.ApiError(
            methodName = "submitTransfer",
            raw = rawResponse,
            parsed = MBridgeError.Type.UNKNOWN
        )

        assertTrue(throwable is Exception)
        assertFalse(throwable is Error)
        assertFalse(throwable.message.orEmpty().contains(rawResponse))
    }

    @Test
    fun completesSuccessfulResponseAndRemovesCallback() {
        val registry = BridgeCallbackRegistry()
        var callbackResult: String? = null
        var callbackError: MBridgeError? = MBridgeError.Type.UNKNOWN
        registry.register(1) { result, error ->
            callbackResult = result
            callbackError = error
        }

        registry.complete(1, success = true, result = "{\"ok\":true}")

        assertEquals("{\"ok\":true}", callbackResult)
        assertNull(callbackError)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun parsesKnownErrorAndRemovesCallback() {
        val registry = BridgeCallbackRegistry()
        var callbackError: MBridgeError? = null
        registry.register(1) { _, error -> callbackError = error }

        registry.complete(
            1,
            success = false,
            result = "{\"error\":{\"name\":\"InvalidAmount\"}}"
        )

        assertSame(MBridgeError.Type.INVALID_AMOUNT, callbackError)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun mapsUnknownErrorWithoutMutatingSharedValue() {
        val registry = BridgeCallbackRegistry()
        var callbackError: MBridgeError? = null
        registry.register(1) { _, error -> callbackError = error }

        registry.complete(
            1,
            success = false,
            result =
                """
                {"error":{"name":"UnexpectedError","displayError":"Request-specific message"}}
                """.trimIndent()
        )

        assertEquals(MBridgeError.Type.UNKNOWN, callbackError?.type)
        assertEquals("Request-specific message", callbackError?.customMessage)
        assertNull(MBridgeError.Type.UNKNOWN.customMessage)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun mapsMalformedResponseToUnknownAndRemovesCallback() {
        val registry = BridgeCallbackRegistry()
        var callbackError: MBridgeError? = null
        registry.register(1) { _, error -> callbackError = error }

        registry.complete(1, success = false, result = "not-json")

        assertEquals(MBridgeError.Type.UNKNOWN, callbackError)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun completesOutstandingResponsesOutOfOrderWithoutSharingMessages() {
        val registry = BridgeCallbackRegistry()
        val errors = mutableMapOf<Int, MBridgeError?>()
        registry.register(1) { _, error -> errors[1] = error }
        registry.register(2) { _, error -> errors[2] = error }

        registry.complete(
            2,
            success = false,
            result = "{\"error\":{\"displayError\":\"Second request\"}}"
        )
        registry.complete(
            1,
            success = false,
            result = "{\"error\":{\"displayError\":\"First request\"}}"
        )

        assertEquals("First request", errors[1]?.customMessage)
        assertEquals("Second request", errors[2]?.customMessage)
        assertNull(MBridgeError.Type.UNKNOWN.customMessage)
        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun removesCallbackBeforeInvokingIt() {
        val registry = BridgeCallbackRegistry()
        registry.register(1) { _, _ -> throw IllegalStateException("Callback failed") }

        assertThrows(IllegalStateException::class.java) {
            registry.complete(1, success = true, result = "null")
        }

        assertEquals(0, registry.pendingCount)
    }

    @Test
    fun failsAllCallbacksWithProvidedError() {
        val registry = BridgeCallbackRegistry()
        val errors = mutableListOf<MBridgeError?>()
        registry.register(1) { _, error -> errors.add(error) }
        registry.register(2) { _, error -> errors.add(error) }

        registry.failAll(MBridgeError.Type.BRIDGE_INTERRUPTED)

        assertEquals(2, errors.size)
        assertTrue(errors.all { it === MBridgeError.Type.BRIDGE_INTERRUPTED })
        assertEquals(0, registry.pendingCount)
    }
}
