package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.MFA_BOT_URL
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.refreshStoredMfa
import org.mytonwallet.app_air.walletcore.buildMfaStartParam
import org.mytonwallet.app_air.walletcore.models.AccountMfa
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.math.BigInteger

class MfaFlowViewModel(val accountId: String) {

    companion object {
        val INSTALL_FEE: BigInteger = BigInteger.valueOf(150_000_000L)
    }

    data class State(
        val installRequestId: String? = null,
        val installCandidateUser: AccountMfa.User? = null,
        val removeRequestId: String? = null,
        val isRefreshingMfa: Boolean = false,
    ) {
        val isWaitingForTelegramInstall: Boolean
            get() = installRequestId != null && installCandidateUser == null

        val isWaitingForTelegramRemoval: Boolean
            get() = removeRequestId != null
    }

    private val _stateFlow = MutableStateFlow(State(isRefreshingMfa = true))
    val stateFlow: StateFlow<State> = _stateFlow.asStateFlow()
    val state get() = _stateFlow.value

    var onInstallConfirmationRequested: ((AccountMfa.User) -> Unit)? = null
    var onRemoveConfirmationRequested: ((AccountMfa.User?) -> Unit)? = null

    private var didPresentInstallConfirmation = false

    suspend fun primaryAction(context: Context, mfa: AccountMfa?) {
        if (mfa != null) {
            if (state.removeRequestId != null) return
            onRemoveConfirmationRequested?.invoke(mfa.user)
            return
        }

        state.installCandidateUser?.let { user ->
            onInstallConfirmationRequested?.invoke(user)
            return
        }
        state.installRequestId?.let { reqId ->
            openTelegram(context, startApp = "i-$reqId")
            return
        }

        try {
            val request = WalletCore.call(ApiMethod.Mfa.PublishInstallMfaRequest(accountId))
            _stateFlow.value = state.copy(installRequestId = request.reqId)
            openTelegram(context, startApp = "i-${request.reqId}")
        } catch (e: Throwable) {
            Logger.e(Logger.LogTag.SETTINGS, "publishInstallMfaRequest failed: $e")
            throw e
        }
    }

    suspend fun confirmInstall(passcode: String) {
        val candidate = state.installCandidateUser ?: return
        if (candidate.id.isNullOrEmpty()) {
            throw IllegalStateException("Telegram account is missing required id.")
        }

        val address = WalletCore.call(
            ApiMethod.Mfa.InstallMfaFromRequest(accountId, candidate, passcode)
        )
        AccountStore.updateMfa(
            accountId,
            AccountMfa(address = address, user = candidate)
        )
        _stateFlow.value = state.copy(installCandidateUser = null)
        didPresentInstallConfirmation = false
    }

    suspend fun confirmRemove(context: Context, passcode: String) {
        val request = WalletCore.call(
            ApiMethod.Mfa.PublishRemoveMfaRequest(accountId, passcode)
        )
        _stateFlow.value = state.copy(removeRequestId = request.reqId)
        openTelegram(context, startApp = request.reqId)
    }

    suspend fun refreshStoredMfa() {
        _stateFlow.value = state.copy(isRefreshingMfa = true)
        try {
            WalletCore.refreshStoredMfa(accountId)
        } catch (e: Throwable) {
            Logger.e(Logger.LogTag.SETTINGS, "refreshStoredMfa failed: $e")
        } finally {
            _stateFlow.value = state.copy(isRefreshingMfa = false)
        }
    }

    suspend fun pollIfNeeded() {
        val s = state
        if (s.installRequestId != null && s.installCandidateUser == null) {
            try {
                val req = WalletCore.call(ApiMethod.Mfa.FetchInstallMfaRequest(s.installRequestId))
                req.user?.let { user ->
                    _stateFlow.value = state.copy(
                        installCandidateUser = user,
                        installRequestId = null,
                    )
                    requestInstallConfirmationIfNeeded()
                }
            } catch (e: Throwable) {
                Logger.e(Logger.LogTag.SETTINGS, "fetchInstallMfaRequest failed: $e")
            }
        }

        s.removeRequestId?.let { hash ->
            try {
                val req = WalletCore.call(ApiMethod.Mfa.FetchMfaRequest(hash))
                if (!req.isConfirmed) return
                WalletCore.call(ApiMethod.Mfa.ConfirmMfaRemovalRequest(accountId))
                AccountStore.updateMfa(accountId, null)
                _stateFlow.value = state.copy(removeRequestId = null)
            } catch (e: Throwable) {
                Logger.e(Logger.LogTag.SETTINGS, "fetchMfaRequest (remove) failed: $e")
            }
        }
    }

    private fun requestInstallConfirmationIfNeeded() {
        if (didPresentInstallConfirmation) return
        val user = state.installCandidateUser ?: return
        didPresentInstallConfirmation = true
        onInstallConfirmationRequested?.invoke(user)
    }

    private fun openTelegram(context: Context, startApp: String) {
        val uri = MFA_BOT_URL.toUri()
            .buildUpon()
            .appendQueryParameter("startapp", buildMfaStartParam(startApp))
            .build()
        context.startActivityCatching(
            Intent(Intent.ACTION_VIEW, uri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }
}
