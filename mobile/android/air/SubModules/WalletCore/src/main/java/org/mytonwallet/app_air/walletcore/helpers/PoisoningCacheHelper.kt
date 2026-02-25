package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.math.BigInteger
import java.util.concurrent.ConcurrentHashMap

class PoisoningCacheHelper {
    companion object {
        private val cache: ConcurrentHashMap<String, MutableMap<String, CacheEntry>> = ConcurrentHashMap()

        private data class CacheEntry(
            val timestamp: Long,
            val amount: BigInteger,
            val address: String
        )

        private fun getKey(address: String): String {
            return address.formatStartEndAddress(prefix = 4, suffix = 4)
        }

        private fun addToCache(accountId: String, address: String, amount: BigInteger, timestamp: Long) {
            val key = getKey(address)
            if (cache[accountId] == null)
                cache[accountId] = ConcurrentHashMap()
            cache[accountId]!![key] = CacheEntry(timestamp, amount, address)
        }

        private fun getFromCache(accountId: String, address: String): CacheEntry? {
            val key = getKey(address)
            return cache[accountId]?.get(key)
        }

        fun updatePoisoningCache(accountId: String, tx: MApiTransaction) {
            if (tx is MApiTransaction.Transaction) {
                val address = tx.peerAddress
                val amount = tx.amount
                val timestamp = tx.timestamp

                val cached = getFromCache(accountId, address)

                if (cached == null || cached.timestamp > timestamp || (cached.timestamp == timestamp && cached.amount < amount)) {
                    addToCache(accountId, address, amount, timestamp)
                }
            }
        }

        fun getIsTransactionWithPoisoning(accountId: String, tx: MApiTransaction): Boolean {
            if (tx is MApiTransaction.Transaction) {
                val address = tx.fromAddress ?: return false
                val cached = getFromCache(accountId, address)
                return cached != null && cached.address != address
            }
            return false
        }

        fun removeAccount(removingAccountId: String) {
            cache.remove(removingAccountId)
        }

        fun clearCache() {
            cache.clear()
        }
    }
}
