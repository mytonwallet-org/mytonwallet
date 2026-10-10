package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

internal class AgentContextPublicationState {
    class Publication(val marker: Any, val authority: Any, val shouldPublishAuthority: Boolean)

    private val accountChanging = MutableStateFlow(false)
    val isAccountChanging = accountChanging.asStateFlow()
    var isStarted = false
        private set
    var isStarting = false
        private set
    private var authority = Any()
    private var pendingMarker: Any? = null
    var shouldPublishAuthority = false
        private set
    val hasPendingUpdate get() = pendingMarker != null

    fun start() {
        authority = Any()
        isStarted = true
        isStarting = true
        request(shouldPublishAuthority = true)
    }

    fun request(shouldPublishAuthority: Boolean = false) {
        pendingMarker = Any()
        this.shouldPublishAuthority = this.shouldPublishAuthority || shouldPublishAuthority
    }

    fun beginAccountChange() {
        authority = Any()
        request(shouldPublishAuthority = true)
        accountChanging.value = true
    }

    fun completeAccountChange() {
        authority = Any()
        request(shouldPublishAuthority = true)
        accountChanging.value = false
    }

    fun capture(): Publication? {
        if (!isStarted || accountChanging.value) return null
        return pendingMarker?.let { Publication(it, authority, shouldPublishAuthority) }
    }

    fun isCurrent(publication: Publication) = isStarted &&
        !accountChanging.value && publication.authority === authority

    fun complete(publication: Publication): Boolean {
        if (!isCurrent(publication)) return false
        if (isStarting && pendingMarker !== publication.marker) return false
        if (pendingMarker === publication.marker) pendingMarker = null
        if (publication.shouldPublishAuthority) shouldPublishAuthority = false
        isStarting = false
        return true
    }

    fun stop() {
        isStarted = false
        isStarting = false
        authority = Any()
        pendingMarker = null
        shouldPublishAuthority = false
        accountChanging.value = false
    }
}
