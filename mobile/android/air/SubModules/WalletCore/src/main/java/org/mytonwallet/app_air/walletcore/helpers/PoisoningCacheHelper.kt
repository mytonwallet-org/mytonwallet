package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.math.BigInteger
import java.util.concurrent.ConcurrentHashMap

class PoisoningCacheHelper {
    companion object {
        private val cache: MutableMap<String, CacheEntry> = ConcurrentHashMap()

        private data class CacheEntry(
            val timestamp: Long,
            val amount: BigInteger,
            val address: String
        )

        private fun getKey(address: String): String {
            return address.formatStartEndAddress()
        }

        private fun addToCache(address: String, amount: BigInteger, timestamp: Long) {
            val key = getKey(address)
            cache[key] = CacheEntry(timestamp, amount, address)
        }

        private fun getFromCache(address: String): CacheEntry? {
            val key = getKey(address)
            return cache[key]
        }

        fun updatePoisoningCache(tx: MApiTransaction) {
            if (tx is MApiTransaction.Transaction) {
                val address = tx.fromAddress
                val amount = tx.amount
                val timestamp = tx.timestamp

                val cached = getFromCache(address)

                if (cached == null || cached.timestamp < timestamp || (cached.timestamp == timestamp && cached.amount > amount)) {
                    addToCache(address, amount, timestamp)
                }
            }
        }

        fun getIsTransactionWithPoisoning(tx: MApiTransaction): Boolean {
            if (tx is MApiTransaction.Transaction) {
                val address = tx.fromAddress
                val cached = getFromCache(address)
                return cached != null && cached.address != address
            }
            return false
        }

        fun clearPoisoningCache() {
            cache.clear()
        }
    }
}
