package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import kotlin.math.absoluteValue

class ActivityHelpers {
    companion object {
        fun getTxIdFromId(id: String): String? {
            return id.split(":").firstOrNull()
        }

        fun isSuitableToGetTimestamp(activity: MApiTransaction): Boolean {
            return !activity.isLocal() && !activity.isBackendSwapId() && !activity.isPending()
        }

        fun activityBelongsToSlug(activity: MApiTransaction, slug: String?): Boolean {
            return slug == null || slug == activity.getTxSlug() ||
                (activity is MApiTransaction.Swap &&
                    (activity.from == slug || activity.to == slug))
        }

        fun localActivityMatches(
            it: MApiTransaction,
            newActivity: MApiTransaction
        ): Boolean {
            if (it.extra?.withW5Gasless == true) {
                when (it) {
                    is MApiTransaction.Swap -> {
                        if (newActivity is MApiTransaction.Swap) {
                            return it.from == newActivity.from &&
                                it.to == newActivity.to &&
                                it.fromAmount.absoluteValue == newActivity.fromAmount.absoluteValue
                        }
                    }

                    is MApiTransaction.Transaction -> {
                        if (newActivity is MApiTransaction.Transaction) {
                            return !newActivity.isIncoming &&
                                it.normalizedAddress == newActivity.normalizedAddress &&
                                it.amount == newActivity.amount &&
                                it.slug == newActivity.slug
                        }
                    }
                }
            }

            it.externalMsgHashNorm?.let { localHash ->
                return localHash == newActivity.externalMsgHashNorm && newActivity.shouldHide != true
            }

            return it.parsedTxId.hash == newActivity.parsedTxId.hash
        }

        fun filter(
            accountId: String,
            array: List<MApiTransaction>?,
            hideTinyIfRequired: Boolean,
            checkSlug: String?,
        ): List<MApiTransaction>? {
            return array?.filter { transaction ->
                transaction.shouldHide != true &&
                    !transaction.isPoisoning(accountId) &&
                    (checkSlug == null || activityBelongsToSlug(transaction, checkSlug)) &&
                    (!hideTinyIfRequired || !WGlobalStorage.getAreTinyTransfersHidden() || !transaction.isTinyOrScam)
            }
        }

        fun sorter(t1: MApiTransaction, t2: MApiTransaction): Int {
            return when {
                t1.timestamp != t2.timestamp -> t2.timestamp.compareTo(t1.timestamp)
                else -> t2.id.compareTo(t1.id)
            }
        }
        /**
         * Merge activity IDs for initial activities, applying a cutoff timestamp.
         * The cutoff is the max of the last timestamps from both arrays.
         * Activities older than the cutoff are filtered out.
         *
         * This ensures that when we receive initial activities, we don't keep old stale
         * activities that might have been cached from before.
         */
        fun mergeActivityIdsToMaxTime(
            newIds: List<String>,
            existingIds: List<String>,
            cachedActivities: Map<String, MApiTransaction>
        ): List<String> {
            if (newIds.isEmpty() && existingIds.isEmpty()) {
                return emptyList()
            } else if (newIds.isEmpty()) {
                return existingIds.distinct().sortedWith { id1, id2 ->
                    compareActivityIds(id1, id2, cachedActivities)
                }
            } else if (existingIds.isEmpty()) {
                return newIds.distinct().sortedWith { id1, id2 ->
                    compareActivityIds(id1, id2, cachedActivities)
                }
            }

            val timestamp1 = newIds.lastOrNull()?.let { cachedActivities[it]?.timestamp } ?: 0
            val timestamp2 = existingIds.lastOrNull()?.let { cachedActivities[it]?.timestamp } ?: 0
            val cutoffTimestamp = maxOf(timestamp1, timestamp2)

            return (newIds + existingIds)
                .distinct()
                .filter { id -> (cachedActivities[id]?.timestamp ?: 0) >= cutoffTimestamp }
                .sortedWith { id1, id2 -> compareActivityIds(id1, id2, cachedActivities) }
        }

        /**
         * Merge activity IDs without cutoff (for new activities, pagination, etc.)
         */
        fun mergeSortedActivityIds(
            newIds: List<String>,
            existingIds: List<String>,
            byId: Map<String, MApiTransaction>
        ): List<String> {
            return (newIds + existingIds)
                .distinct()
                .sortedWith { id1, id2 -> compareActivityIds(id1, id2, byId) }
        }

        /**
         * Compare activity IDs by their transaction timestamp (newest first), then by ID.
         */
        private fun compareActivityIds(
            id1: String,
            id2: String,
            byId: Map<String, MApiTransaction>
        ): Int {
            val activity1 = byId[id1]
            val activity2 = byId[id2]
            return when {
                activity1 != null && activity2 != null -> {
                    sorter(activity1, activity2)
                }
                else -> id2.compareTo(id1)
            }
        }
    }
}
