package org.mytonwallet.app_air.walletcore.helpers

object DappDeeplinkReturnTracker {
    private sealed interface RequestKey {
        data class WalletConnectPairing(val topic: String) : RequestKey
        data class WalletConnectSession(val topic: String) : RequestKey
        data class TonConnect(val appClientId: String) : RequestKey
    }

    // The deeplink was seen first; wait for the bridge update that provides its promise ID.
    private val pendingRequests = mutableMapOf<RequestKey, ArrayDeque<Boolean>>()

    // The bridge update was seen first; wait for the matching external deeplink.
    private val observedRequests = mutableMapOf<RequestKey, ArrayDeque<String>>()

    // Completed promises in this set should return the wallet task to the background.
    private val expectedPromiseIds = mutableSetOf<String>()

    @Synchronized
    fun expectWalletConnect(url: String, shouldReturn: Boolean) {
        val topic = extractPairingTopic(url) ?: return
        expect(RequestKey.WalletConnectPairing(topic), shouldReturn)
    }

    @Synchronized
    fun expectWalletConnectSessionRequest(sessionTopic: String, shouldReturn: Boolean) {
        if (sessionTopic.isNotBlank()) {
            expect(RequestKey.WalletConnectSession(sessionTopic), shouldReturn)
        }
    }

    @Synchronized
    fun expectTonConnect(appClientId: String?, shouldReturn: Boolean) {
        if (!appClientId.isNullOrBlank()) expect(RequestKey.TonConnect(appClientId), shouldReturn)
    }

    @Synchronized
    fun bindWalletConnectRequest(pairingTopic: String?, promiseId: String) {
        if (!pairingTopic.isNullOrBlank()) {
            bind(RequestKey.WalletConnectPairing(pairingTopic), promiseId)
        }
    }

    @Synchronized
    fun bindWalletConnectSessionRequest(sessionTopic: String?, promiseId: String) {
        if (!sessionTopic.isNullOrBlank()) {
            bind(RequestKey.WalletConnectSession(sessionTopic), promiseId)
        }
    }

    @Synchronized
    fun bindTonConnectRequest(appClientId: String?, promiseId: String) {
        if (!appClientId.isNullOrBlank()) bind(RequestKey.TonConnect(appClientId), promiseId)
    }

    @Synchronized
    fun consumeCompletedRequest(promiseId: String?): Boolean {
        if (promiseId == null) return false
        observedRequests.entries.removeAll { (_, requests) ->
            requests.remove(promiseId)
            requests.isEmpty()
        }
        return expectedPromiseIds.remove(promiseId)
    }

    private fun expect(requestKey: RequestKey, shouldReturn: Boolean) {
        val observed = observedRequests[requestKey]
        val promiseId = observed?.removeFirstOrNull()
        if (observed?.isEmpty() == true) observedRequests.remove(requestKey)
        if (promiseId != null) {
            if (shouldReturn) expectedPromiseIds.add(promiseId)
        } else {
            pendingRequests
                .getOrPut(requestKey) { ArrayDeque() }
                .addLast(shouldReturn)
        }
    }

    private fun bind(requestKey: RequestKey, promiseId: String) {
        val pending = pendingRequests[requestKey]
        val shouldReturn = pending?.removeFirstOrNull()
        if (pending?.isEmpty() == true) pendingRequests.remove(requestKey)
        if (shouldReturn != null) {
            if (shouldReturn) expectedPromiseIds.add(promiseId)
        } else {
            observedRequests
                .getOrPut(requestKey) { ArrayDeque() }
                .addLast(promiseId)
        }
    }

    internal fun extractPairingTopic(url: String): String? {
        val prefix = "wc:"
        if (!url.startsWith(prefix, ignoreCase = true)) return null
        val separatorIndex = url.indexOf('@', prefix.length)
        if (separatorIndex <= prefix.length) return null
        return url.substring(prefix.length, separatorIndex)
    }

    @Synchronized
    internal fun reset() {
        pendingRequests.clear()
        observedRequests.clear()
        expectedPromiseIds.clear()
    }
}
