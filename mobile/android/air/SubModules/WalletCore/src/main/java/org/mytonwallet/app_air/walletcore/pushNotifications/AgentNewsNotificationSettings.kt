package org.mytonwallet.app_air.walletcore.pushNotifications

import com.squareup.moshi.JsonClass
import java.util.TimeZone
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.MoshiBuilder
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Notifications.SetNewsNotifications.Props

@JsonClass(generateAdapter = false)
enum class AgentNewsNotificationMode { Off, Digest, News }
enum class AgentNewsNotificationOutcome { Ok, PermissionDenied, Failed }

@JsonClass(generateAdapter = true)
data class AgentNewsNotificationState(
    val mode: AgentNewsNotificationMode = AgentNewsNotificationMode.Off,
    val digestHour: Int = 21
)

class AgentNewsNotificationSettings internal constructor(
    private val read: () -> String? = WGlobalStorage::getAgentNewsNotificationSettings,
    private val write: (String) -> Unit = WGlobalStorage::setAgentNewsNotificationSettings,
    private val ensurePushToken: suspend () -> String = AirPushNotifications::ensureToken,
    private val getToken: () -> String? = WGlobalStorage::getPushNotificationsToken,
    private val language: () -> String = WGlobalStorage::getLangCode,
    private val timeZone: () -> String = { TimeZone.getDefault().id },
    private val apply: suspend (Props) -> Boolean = {
        WalletCore.call(ApiMethod.Notifications.SetNewsNotifications(it)).optBoolean("ok")
    }
) {
    companion object {
        val shared by lazy { AgentNewsNotificationSettings() }
    }

    private val mutex = Mutex()
    private var currentModeOperation: Any? = null
    private val adapter = MoshiBuilder.build().adapter(AgentNewsNotificationPreferences::class.java)
    private val stored = read()?.let(adapter::fromJson)
    private val mutableState = MutableStateFlow(stored?.state ?: AgentNewsNotificationState())
    val state = mutableState.asStateFlow()
    val mode: AgentNewsNotificationMode get() = state.value.mode
    val digestHour: Int get() = state.value.digestHour
    private var lastApplied = stored?.lastApplied

    suspend fun setMode(mode: AgentNewsNotificationMode): AgentNewsNotificationOutcome {
        val operation = Any()
        mutex.withLock { currentModeOperation = operation }
        return try {
            val preparedToken = when (mode) {
                AgentNewsNotificationMode.Off -> null
                else -> ensurePushToken()
            }
            mutex.withLock {
                try {
                    if (currentModeOperation !== operation) {
                        return@withLock AgentNewsNotificationOutcome.Failed
                    }
                    val token = preparedToken ?: getToken()
                        ?: return@withLock AgentNewsNotificationOutcome.Failed
                    val request = buildRequest(mode, token)
                    if (!apply(request)) return@withLock AgentNewsNotificationOutcome.Failed
                    lastApplied = request
                    save(state.value.copy(mode = mode))
                    AgentNewsNotificationOutcome.Ok
                } finally {
                    if (currentModeOperation === operation) currentModeOperation = null
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: NewsNotificationPermissionDenied) {
            AgentNewsNotificationOutcome.PermissionDenied
        } catch (_: Exception) {
            AgentNewsNotificationOutcome.Failed
        }
    }

    suspend fun setDigestHour(hour: Int): AgentNewsNotificationOutcome {
        require(hour in 0..23) { "Digest hour must be between 0 and 23" }
        return mutex.withLock {
            save(state.value.copy(digestHour = hour))
            if (mode !=
                AgentNewsNotificationMode.Digest
            ) {
                return@withLock AgentNewsNotificationOutcome.Ok
            }
            val token = getToken() ?: return@withLock AgentNewsNotificationOutcome.Failed
            applyRequest(buildRequest(mode, token))
        }
    }

    suspend fun reapplyIfNeeded(): AgentNewsNotificationOutcome = mutex.withLock {
        val appliedMode = lastApplied?.mode
        if (mode == AgentNewsNotificationMode.Off &&
            (appliedMode == null || appliedMode == "off")
        ) {
            return@withLock AgentNewsNotificationOutcome.Ok
        }
        val token = getToken() ?: return@withLock AgentNewsNotificationOutcome.Failed
        val request = buildRequest(mode, token)
        if (request == lastApplied) return@withLock AgentNewsNotificationOutcome.Ok
        applyRequest(request)
    }

    internal suspend fun reset(): AgentNewsNotificationOutcome = mutex.withLock {
        currentModeOperation = null
        val token = getToken()
        save(state.value.copy(mode = AgentNewsNotificationMode.Off))
        if (token == null) return@withLock AgentNewsNotificationOutcome.Ok
        applyRequest(buildRequest(AgentNewsNotificationMode.Off, token))
    }

    private suspend fun applyRequest(request: Props): AgentNewsNotificationOutcome = try {
        if (apply(request)) {
            lastApplied = request
            save(state.value)
            AgentNewsNotificationOutcome.Ok
        } else {
            AgentNewsNotificationOutcome.Failed
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        AgentNewsNotificationOutcome.Failed
    }

    private fun buildRequest(mode: AgentNewsNotificationMode, token: String) = Props(
        mode = mode.name.lowercase(),
        userToken = token,
        langCode = language(),
        digestHour = digestHour,
        timeZone = timeZone()
    )

    private fun save(value: AgentNewsNotificationState) {
        write(adapter.toJson(AgentNewsNotificationPreferences(value, lastApplied)))
        mutableState.value = value
    }
}

@JsonClass(generateAdapter = true)
internal data class AgentNewsNotificationPreferences(
    val state: AgentNewsNotificationState,
    val lastApplied: Props? = null
)

internal class NewsNotificationPermissionDenied : Exception()
