package org.mytonwallet.app_air.uiagent.agentV2

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.stores.AccountStore

internal data class AgentV2AuthorityBinding(val accountId: String?)

private class AgentV2AuthorityState {
    private var binding: AgentV2AuthorityBinding? = null

    fun invalidate(): Boolean {
        val hadBinding = binding != null
        binding = null
        return hadBinding
    }

    fun publish(accountId: String?) {
        binding = AgentV2AuthorityBinding(accountId)
    }

    fun capture(activeAccountId: String?): AgentV2AuthorityBinding? =
        binding?.takeIf { it.accountId == activeAccountId }

    fun isCurrent(expected: AgentV2AuthorityBinding, activeAccountId: String?): Boolean =
        binding === expected && expected.accountId == activeAccountId
}

class AgentV2HostContextProvider(
    private val client: AgentV2Client,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
) : WalletCore.EventObserver {
    private val authorityState = AgentV2AuthorityState()
    private val messageAuthorityState = AgentV2AuthorityState().apply {
        publish(AccountStore.activeAccountId)
    }
    private val publicationState = AgentContextPublicationState()
    private val updateMutex = Mutex()
    private var updateJob: Job? = null
    private val isStarted get() = publicationState.isStarted
    internal var isRunActive: () -> Boolean = { false }
    internal var onAuthorityContextInvalidated: () -> Unit = {}
    internal var onMessageAuthorityChanged: () -> Unit = {}
    internal var onAuthorityContextPublished: () -> Unit = {}

    suspend fun start(): Boolean {
        if (isStarted) {
            return flushDeferredDynamicUpdate() && captureActionAuthority() != null
        }
        synchronizeMessageAuthority()
        publicationState.start()
        WalletCore.registerObserver(this)
        if (WalletCore.nextAccountId != null) {
            invalidateAuthorityContext(invalidateMessageAuthority = true)
            publicationState.beginAccountChange()
        }
        var failedAttempts = 0
        while (isStarted) {
            publicationState.isAccountChanging.first { !it }
            val publication = publicationState.capture() ?: break
            if (publishHostContext(attemptCount = 1)) return true
            if (!publicationState.isCurrent(publication) ||
                publicationState.capture()?.marker !== publication.marker
            ) {
                continue
            }
            failedAttempts += 1
            if (failedAttempts >= AUTHORITY_UPDATE_ATTEMPTS) break
            delay(AUTHORITY_UPDATE_RETRY_MS)
        }
        stop(invalidateMessageAuthority = true)
        return false
    }

    fun stop(invalidateMessageAuthority: Boolean = false) {
        if (!isStarted) return
        publicationState.stop()
        updateJob?.cancel()
        updateJob = null
        authorityState.invalidate()
        if (invalidateMessageAuthority && messageAuthorityState.invalidate()) {
            onAuthorityContextInvalidated()
        }
        WalletCore.unregisterObserver(this)
    }

    suspend fun flushDeferredDynamicUpdate(): Boolean = flushDynamicUpdate(isRunActive())

    suspend fun flushPendingUpdateBeforeRun(): Boolean = flushDynamicUpdate(isRunActive = false)

    internal fun canRecoverAuthorityContext(): Boolean = isStarted &&
        publicationState.hasPendingUpdate &&
        captureActionAuthority() == null

    internal suspend fun recoverAuthorityContext(): Boolean =
        flushDynamicUpdate(isRunActive = false) && captureActionAuthority() != null

    private suspend fun flushDynamicUpdate(isRunActive: Boolean): Boolean {
        if (isRunActive) return false
        while (publicationState.hasPendingUpdate) {
            updateJob?.cancel()
            updateJob = null
            if (publicationState.isStarting ||
                publicationState.isAccountChanging.value
            ) {
                return false
            }
            if (!publishHostContext(AUTHORITY_UPDATE_ATTEMPTS)) return false
        }
        return true
    }

    internal fun captureActionAuthority(): AgentV2AuthorityBinding? =
        authorityState.capture(AccountStore.activeAccountId)

    internal fun isActionAuthorityCurrent(binding: AgentV2AuthorityBinding): Boolean =
        authorityState.isCurrent(binding, AccountStore.activeAccountId)

    internal fun captureMessageAuthority(): AgentV2AuthorityBinding? =
        messageAuthorityState.capture(AccountStore.activeAccountId)

    internal fun isMessageAuthorityCurrent(binding: AgentV2AuthorityBinding): Boolean =
        messageAuthorityState.isCurrent(binding, AccountStore.activeAccountId)

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (!isStarted) return
        if (walletEvent is WalletEvent.AccountWillChange) {
            updateJob?.cancel()
            updateJob = null
            invalidateAuthorityContext(invalidateMessageAuthority = true)
            publicationState.beginAccountChange()
            return
        }
        val shouldPublishAuthority = walletEvent is WalletEvent.AccountChanged ||
            walletEvent is WalletEvent.AccountChangedInApp ||
            walletEvent is WalletEvent.AccountChangeAborted ||
            walletEvent is WalletEvent.AccountRemoved ||
            walletEvent is WalletEvent.AddNewWalletCompletion ||
            walletEvent is WalletEvent.ByChainUpdated ||
            walletEvent is WalletEvent.TemporaryAccountSaved
        val isImmediate = shouldPublishAuthority ||
            walletEvent is WalletEvent.AccountNameChanged ||
            walletEvent is WalletEvent.AccountSavedAddressesChanged
        if (!isImmediate && walletEvent !in contextEvents) return
        if (shouldPublishAuthority) {
            invalidateAuthorityContext(invalidateMessageAuthority = true)
            messageAuthorityState.publish(AccountStore.activeAccountId)
            publicationState.completeAccountChange()
        }
        scheduleUpdate(isImmediate, shouldPublishAuthority)
        if (shouldPublishAuthority) onMessageAuthorityChanged()
    }

    internal fun makeSnapshot() = AgentHostContextBuilder.build()

    private fun scheduleUpdate(immediately: Boolean, shouldPublishAuthority: Boolean) {
        publicationState.request(shouldPublishAuthority)
        if (publicationState.isStarting || publicationState.isAccountChanging.value) return
        val isImmediate = immediately || publicationState.shouldPublishAuthority
        updateJob?.cancel()
        updateJob = scope.launch {
            if (!isImmediate) delay(CONTEXT_UPDATE_DEBOUNCE_MS)
            if (!isStarted || (!isImmediate && isRunActive())) return@launch
            publishHostContext(
                if (publicationState.shouldPublishAuthority) AUTHORITY_UPDATE_ATTEMPTS else 1
            )
        }
    }

    private suspend fun publishHostContext(attemptCount: Int): Boolean {
        repeat(attemptCount) { attempt ->
            if (attempt > 0) delay(AUTHORITY_UPDATE_RETRY_MS)
            val didPublish = try {
                updateMutex.withLock {
                    val publication = publicationState.capture() ?: return@withLock isStarted &&
                        !publicationState.hasPendingUpdate && captureActionAuthority() != null
                    val snapshot = makeSnapshot()
                    client.updateHostContext(snapshot.json)
                    currentCoroutineContext().ensureActive()
                    if (snapshot.accountId != AccountStore.activeAccountId ||
                        !publicationState.complete(publication)
                    ) {
                        return@withLock false
                    }
                    if (publication.shouldPublishAuthority) {
                        authorityState.publish(snapshot.accountId)
                        onAuthorityContextPublished()
                    }
                    true
                }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Throwable) {
                false
            }
            if (didPublish) return true
        }
        return false
    }

    private fun invalidateAuthorityContext(invalidateMessageAuthority: Boolean) {
        val didInvalidateAuthority = authorityState.invalidate()
        val didInvalidateMessageAuthority = invalidateMessageAuthority &&
            messageAuthorityState.invalidate()
        if (didInvalidateAuthority || didInvalidateMessageAuthority) {
            onAuthorityContextInvalidated()
        }
    }

    private fun synchronizeMessageAuthority() {
        val activeAccountId = AccountStore.activeAccountId
        if (messageAuthorityState.capture(activeAccountId) != null) return
        val didInvalidateMessageAuthority = messageAuthorityState.invalidate()
        messageAuthorityState.publish(activeAccountId)
        if (didInvalidateMessageAuthority) onAuthorityContextInvalidated()
        onMessageAuthorityChanged()
    }

    companion object {
        private const val CONTEXT_UPDATE_DEBOUNCE_MS = 100L
        private const val AUTHORITY_UPDATE_RETRY_MS = 250L
        private const val AUTHORITY_UPDATE_ATTEMPTS = 3

        private val contextEvents = setOf(
            WalletEvent.AccountSavedAddressesChanged,
            WalletEvent.AssetsAndActivityDataUpdated,
            WalletEvent.BalanceChanged,
            WalletEvent.BaseCurrencyChanged,
            WalletEvent.NftsUpdated,
            WalletEvent.NotActiveAccountBalanceChanged,
            WalletEvent.StakingDataUpdated,
            WalletEvent.TokensChanged
        )
    }
}
