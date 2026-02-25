package org.mytonwallet.app_air.walletcore.pushNotifications

import com.google.android.gms.tasks.OnCompleteListener
import com.google.android.gms.tasks.Task
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNotificationAddress
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

object AirPushNotifications {
    const val MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT = 3

    fun register(subscribePreviousAccountsIfEmpty: Boolean) {
        FirebaseMessaging.getInstance().isAutoInitEnabled = true
        FirebaseMessaging
            .getInstance()
            .getToken()
            .addOnCompleteListener(
                OnCompleteListener { task: Task<String?>? ->
                    if (task?.isSuccessful != true) {
                        Logger.w(
                            Logger.LogTag.AIR_APPLICATION,
                            LogMessage.Builder()
                                .append(
                                    "register: Failed to fetch FCM token",
                                    LogMessage.MessagePartPrivacy.PUBLIC
                                )
                                .append(
                                    task?.exception,
                                    LogMessage.MessagePartPrivacy.REDACTED
                                )
                                .build()
                        )
                        return@OnCompleteListener
                    }
                    val token = task.getResult() ?: return@OnCompleteListener
                    updateToken(token)
                    WalletCore.doOnBridgeReady {
                        resubscribeAll(subscribePreviousAccountsIfEmpty)
                    }
                }
            )
    }

    private val notificationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()

    // Helper function to ensure sequential execution
    private suspend fun <T> withQueue(block: suspend () -> T): T {
        return mutex.withLock {
            block()
        }
    }

    private fun updateToken(newToken: String) {
        notificationScope.launch {
            withQueue {
                val prevToken = WGlobalStorage.getPushNotificationsToken()
                if (newToken == prevToken)
                    return@withQueue
                WGlobalStorage.setPushNotificationsToken(newToken)

                val prevAccounts = WGlobalStorage.getPushNotificationsEnabledAccounts()
                val prevAccountsAddresses = prevAccounts?.mapNotNull {
                    WGlobalStorage.getAccountTonAddress(it)
                } ?: emptyList()
                if (!prevToken.isNullOrEmpty() && prevAccountsAddresses.isNotEmpty()) {
                    try {
                        WalletCore.call(
                            ApiMethod.Notifications.UnsubscribeNotifications(
                                ApiMethod.Notifications.UnsubscribeNotifications.Props(
                                    prevToken,
                                    prevAccountsAddresses.map {
                                        ApiNotificationAddress(
                                            title = null,
                                            address = it,
                                            chain = MBlockchain.ton
                                        )
                                    }
                                )
                            )
                        )
                    } catch (_: Throwable) {
                    }
                }
            }
        }
    }

    private fun resubscribeAll(subscribePreviousAccountsIfEmpty: Boolean) {
        notificationScope.launch {
            withQueue {
                val token = WGlobalStorage.getPushNotificationsToken() ?: return@withQueue
                val allAccounts = WalletCore.getAllAccounts()
                val activeAccountId = WGlobalStorage.getActiveAccountId() ?: return@withQueue
                val activeAccount =
                    allAccounts.find { it.accountId == activeAccountId } ?: return@withQueue
                val prevAccounts = WGlobalStorage.getPushNotificationsEnabledAccounts()
                var newAccounts: List<MAccount>
                if (prevAccounts.isNullOrEmpty() && subscribePreviousAccountsIfEmpty) {
                    // It's first time, choose accounts
                    newAccounts =
                        allAccounts.filter { it.tonAddress != null }
                            .take(MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT)

                    // Make sure we subscribe active account if contains ton address
                    if (activeAccount.tonAddress != null && newAccounts.find { it.accountId == activeAccountId } == null) {
                        newAccounts =
                            newAccounts.take(MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT - 1) + activeAccount
                    }
                } else {
                    // Some accounts already exist, resubscribe those
                    newAccounts =
                        prevAccounts?.mapNotNull { acc -> allAccounts.find { it.accountId == acc && it.tonAddress != null } }
                            ?: emptyList()
                }
                try {
                    val res = WalletCore.call(
                        ApiMethod.Notifications.SubscribeNotifications(
                            ApiMethod.Notifications.SubscribeNotifications.Props(
                                token,
                                newAccounts.map {
                                    ApiNotificationAddress(
                                        it.name,
                                        it.tonAddress!!,
                                        MBlockchain.ton
                                    )
                                },
                                WGlobalStorage.getLangCode()
                            )
                        )
                    )
                    val resAddressKeys = res.optJSONObject("addressKeys") ?: return@withQueue
                    WGlobalStorage.setPushNotificationAccounts(newAccounts.filter {
                        resAddressKeys.optJSONObject(
                            it.tonAddress
                        ) != null
                    }.map { it.accountId })
                } catch (err: Throwable) {
                    err.printStackTrace()
                }
            }
        }
    }

    fun refreshSubscriptions() {
        resubscribeAll(subscribePreviousAccountsIfEmpty = false)
    }

    fun subscribe(accountId: String, ignoreIfLimitReached: Boolean) {
        WGlobalStorage.getAccount(accountId)?.let { accountObj ->
            subscribe(
                MAccount(accountId, accountObj),
                ignoreIfLimitReached = ignoreIfLimitReached
            )
        }
    }

    fun subscribe(account: MAccount, ignoreIfLimitReached: Boolean) {
        notificationScope.launch {
            withQueue {
                val token = WGlobalStorage.getPushNotificationsToken() ?: return@withQueue
                val tonAddress = account.tonAddress ?: return@withQueue
                val enabledAccounts = WGlobalStorage.getPushNotificationsEnabledAccounts()
                if (enabledAccounts?.contains(account.accountId) == true)
                    return@withQueue
                if ((enabledAccounts?.size ?: 0) >= MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT) {
                    if (ignoreIfLimitReached)
                        return@withQueue
                    val removingAccount = enabledAccounts!!.last()
                    val removingTonAddress =
                        WGlobalStorage.getAccountTonAddress(removingAccount)
                    if (removingTonAddress == null) {
                        // This only happens if that account is removed and unsubscribe failed that time
                        // (TODO:: Should fix this known issue later)
                        // For now, we can just drop it and continue
                        WGlobalStorage.removePushNotificationAccount(removingAccount)
                    } else {
                        unsubscribeAsync(token, removingAccount, removingTonAddress)
                    }
                }
                subscribeAsync(token, account.accountId, tonAddress, account.name)
            }
        }
    }

    fun accountNameChanged(account: MAccount) {
        notificationScope.launch {
            withQueue {
                val token = WGlobalStorage.getPushNotificationsToken() ?: return@withQueue
                val tonAddress = account.tonAddress ?: return@withQueue
                val enabledAccounts = WGlobalStorage.getPushNotificationsEnabledAccounts()
                if (enabledAccounts?.contains(account.accountId) != true)
                    return@withQueue
                subscribeAsync(token, account.accountId, tonAddress, account.name)
            }
        }
    }

    fun unsubscribe(account: MAccount, onCompletion: ((success: Boolean) -> Unit)? = null) {
        notificationScope.launch {
            withQueue {
                val token = WGlobalStorage.getPushNotificationsToken() ?: return@withQueue
                val tonAddress = account.tonAddress
                if (tonAddress == null) {
                    onCompletion?.invoke(true)
                    return@withQueue
                }
                val success = unsubscribeAsync(token, account.accountId, tonAddress)
                onCompletion?.invoke(success)
            }
        }
    }

    fun unsubscribeAll() {
        notificationScope.launch {
            withQueue {
                val accountIds = WGlobalStorage.accountIds()
                for (accountId in accountIds) {
                    val tonAddress = WGlobalStorage.getAccountTonAddress(accountId) ?: continue
                    val token = WGlobalStorage.getPushNotificationsToken() ?: return@withQueue
                    unsubscribeAsync(token, accountId, tonAddress)
                }
            }
        }
    }

    suspend fun subscribeAsync(
        token: String,
        accountId: String,
        tonAddress: String,
        accountName: String
    ) {
        try {
            WalletCore.call(
                ApiMethod.Notifications.SubscribeNotifications(
                    ApiMethod.Notifications.SubscribeNotifications.Props(
                        token,
                        listOf(
                            ApiNotificationAddress(
                                title = accountName,
                                address = tonAddress,
                                chain = MBlockchain.ton
                            )
                        ),
                        WGlobalStorage.getLangCode()
                    )
                )
            )
            WGlobalStorage.setPushNotificationAccount(accountId)
        } catch (err: Throwable) {
            err.printStackTrace()
        }
    }

    suspend fun unsubscribeAsync(token: String, accountId: String, tonAddress: String): Boolean {
        try {
            WalletCore.call(
                ApiMethod.Notifications.UnsubscribeNotifications(
                    ApiMethod.Notifications.UnsubscribeNotifications.Props(
                        token,
                        listOf(
                            ApiNotificationAddress(
                                title = null,
                                address = tonAddress,
                                chain = MBlockchain.ton
                            )
                        )
                    )
                )
            )
            WGlobalStorage.removePushNotificationAccount(accountId)
            return true
        } catch (_: Throwable) {
        }
        return false
    }

}
