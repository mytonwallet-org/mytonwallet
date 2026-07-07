package org.mytonwallet.app_air.uisettings.viewControllers.permissions

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MRevokeWalletPermissionOptions
import org.mytonwallet.app_air.walletcore.moshi.MTonPlugin
import org.mytonwallet.app_air.walletcore.moshi.MWalletPermission
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import java.lang.ref.WeakReference

class PermissionsListVM(
    private val accountId: String?,
    private val chain: MBlockchain,
    delegate: Delegate,
) {
    interface Delegate {
        fun permissionsDataUpdated()
    }

    private val delegate = WeakReference(delegate)
    private val scope = CoroutineScope(Dispatchers.Main)

    var isLoading: Boolean = true
        private set
    var hasError: Boolean = false
        private set
    var permissions: List<MWalletPermission> = emptyList()
        private set
    var plugins: List<MTonPlugin> = emptyList()
        private set

    fun load() {
        val accId = accountId
        if (accId == null) {
            isLoading = false
            notifyUpdated()
            return
        }
        isLoading = true
        hasError = false
        notifyUpdated()
        scope.launch {
            try {
                if (MBlockchain.isEvmChain(chain.name)) {
                    permissions =
                        WalletCore.call(ApiMethod.Permissions.FetchWalletPermissions(accId, chain))
                } else if (chain == MBlockchain.ton) {
                    plugins = WalletCore.call(ApiMethod.Permissions.FetchWalletPlugins(accId))
                }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Logger.e(Logger.LogTag.SETTINGS, "Permissions load failed: ${t.message}")
                hasError = true
            }
            isLoading = false
            notifyUpdated()
        }
    }

    fun revoke(
        permission: MWalletPermission,
        passcode: String,
        onSuccess: () -> Unit,
        onError: (String?) -> Unit
    ) {
        val accId = accountId ?: return
        val options = when (permission) {
            is MWalletPermission.Approval -> MRevokeWalletPermissionOptions.Approval(
                accountId = accId,
                password = passcode,
                tokenAddress = permission.tokenAddress,
                spenderAddress = permission.spenderAddress
            )

            is MWalletPermission.Delegation -> MRevokeWalletPermissionOptions.Delegation(
                accountId = accId,
                password = passcode,
                delegateAddress = permission.delegateAddress
            )
        }
        scope.launch {
            try {
                val result = WalletCore.call(
                    ApiMethod.Permissions.RevokeWalletPermission(chain, options)
                )
                if (result.error != null) {
                    onError(result.error)
                } else {
                    removePermission(permission)
                    onSuccess()
                }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Logger.e(Logger.LogTag.SETTINGS, "Permissions revoke failed: ${t.message}")
                onError(t.message)
            }
        }
    }

    fun dispose() {
        scope.cancel()
    }

    private fun removePermission(permission: MWalletPermission) {
        val key = keyOf(permission)
        permissions = permissions.filter { keyOf(it) != key }
        notifyUpdated()
    }

    private fun notifyUpdated() {
        delegate.get()?.permissionsDataUpdated()
    }

    companion object {
        fun keyOf(permission: MWalletPermission): String = when (permission) {
            is MWalletPermission.Approval ->
                "approval:${permission.tokenSlug}:${permission.spenderAddress}"

            is MWalletPermission.Delegation ->
                "delegation:${permission.delegateAddress}"
        }
    }
}
