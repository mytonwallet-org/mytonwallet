@file:Suppress("ktlint:standard:filename")

package org.mytonwallet.app_air.walletcore.api

import kotlinx.coroutines.CancellationException
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2CachedMessages
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod

/** The SDK's cached first page of the thread list; `null` when none is cached or it cannot be read */
suspend fun WalletCore.getAgentV2CachedThreads(): List<AgentV2ThreadListItem>? =
    readAgentV2Cache { call(ApiMethod.AgentV2.GetCachedThreads()) }

/** The SDK's cached latest messages of the thread; `null` when none are cached or they cannot be read */
suspend fun WalletCore.getAgentV2CachedMessages(threadId: String): AgentV2CachedMessages? =
    readAgentV2Cache { call(ApiMethod.AgentV2.GetCachedMessages(threadId)) }

/** The cache never fails its reader: a bridge or decoding error reads as an absent entry */
internal suspend fun <T> readAgentV2Cache(read: suspend () -> T?): T? = try {
    read()
} catch (e: CancellationException) {
    throw e
} catch (_: Exception) {
    null
}
