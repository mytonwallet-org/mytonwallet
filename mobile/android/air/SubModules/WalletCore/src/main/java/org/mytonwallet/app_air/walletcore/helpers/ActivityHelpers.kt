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

        @JvmName("filterNullable")
        fun filter(
            accountId: String,
            array: List<MApiTransaction>?,
            hideTinyIfRequired: Boolean,
            checkSlug: String?,
        ): List<MApiTransaction>? {
            return array?.let { filter(accountId, it, hideTinyIfRequired, checkSlug) }
        }

        fun filter(
            accountId: String,
            array: List<MApiTransaction>,
            hideTinyIfRequired: Boolean,
            checkSlug: String?,
        ): List<MApiTransaction> {
            val hideTiny = hideTinyIfRequired && WGlobalStorage.getAreTinyTransfersHidden()
            return array.filter { transaction ->
                transaction.shouldHide != true &&
                    !transaction.isPoisoning(accountId) &&
                    !transaction.isHiddenNftActivity(accountId) &&
                    (checkSlug == null || activityBelongsToSlug(transaction, checkSlug)) &&
                    (!hideTiny || !transaction.isTinyOrScam)
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
         *
         * @param fallback consulted when an id is missing from `cachedActivities` so the
         *   comparator stays transitive; mirrors web's `addNewActivities` which extends
         *   `byId` with the incoming activities before merging.
         */
        fun mergeActivityIdsToMaxTime(
            newIds: List<String>,
            existingIds: List<String>,
            cachedActivities: Map<String, MApiTransaction>,
            fallback: List<MApiTransaction> = emptyList()
        ): List<String> {
            if (newIds.isEmpty() && existingIds.isEmpty()) {
                return emptyList()
            } else if (newIds.isEmpty()) {
                return existingIds.distinct().sortedWith { id1, id2 ->
                    compareActivityIds(id1, id2, cachedActivities, fallback)
                }
            } else if (existingIds.isEmpty()) {
                return newIds.distinct().sortedWith { id1, id2 ->
                    compareActivityIds(id1, id2, cachedActivities, fallback)
                }
            }

            val timestamp1 = newIds.lastOrNull()
                ?.let { resolve(it, cachedActivities, fallback)?.timestamp } ?: 0
            val timestamp2 = existingIds.lastOrNull()
                ?.let { resolve(it, cachedActivities, fallback)?.timestamp } ?: 0
            val cutoffTimestamp = maxOf(timestamp1, timestamp2)

            return (newIds + existingIds)
                .distinct()
                .filter { id ->
                    (resolve(id, cachedActivities, fallback)?.timestamp ?: 0) >= cutoffTimestamp
                }
                .sortedWith { id1, id2 ->
                    compareActivityIds(id1, id2, cachedActivities, fallback)
                }
        }

        /**
         * Merge activity IDs without cutoff (for new activities, pagination, etc.)
         *
         * @param fallback consulted when an id is missing from `byId` so the comparator
         *   stays transitive; mirrors web's `addNewActivities` which extends `byId` with
         *   the incoming activities before merging.
         */
        fun mergeSortedActivityIds(
            newIds: List<String>,
            existingIds: List<String>,
            byId: Map<String, MApiTransaction>,
            fallback: List<MApiTransaction> = emptyList()
        ): List<String> {
            return (newIds + existingIds)
                .distinct()
                .sortedWith { id1, id2 -> compareActivityIds(id1, id2, byId, fallback) }
        }

        /**
         * Compare activity IDs by their transaction timestamp (newest first), then by ID.
         * Unresolved ids sort last so the comparator stays transitive (mirrors web's
         * `compareActivities` null-handling: missing → +1, present → -1, both missing → 0).
         */
        private fun compareActivityIds(
            id1: String,
            id2: String,
            byId: Map<String, MApiTransaction>,
            fallback: List<MApiTransaction>
        ): Int {
            val activity1 = resolve(id1, byId, fallback)
            val activity2 = resolve(id2, byId, fallback)
            return when {
                activity1 != null && activity2 != null -> sorter(activity1, activity2)
                activity1 == null && activity2 == null -> 0
                activity1 == null -> 1
                else -> -1
            }
        }

        private fun resolve(
            id: String,
            byId: Map<String, MApiTransaction>,
            fallback: List<MApiTransaction>
        ): MApiTransaction? {
            return byId[id] ?: fallback.firstOrNull { it.id == id }
        }

        /**
         * Hashes of CEX swap activities that are still pending (mid-flight on the
         * exchange side). Used to drive `fetchSwaps` reconciliation polling.
         */
        fun pendingCexSwapHashes(activities: Collection<MApiTransaction>): List<String> {
            return activities.asSequence()
                .filter { it is MApiTransaction.Swap && it.cex != null && it.isPending() }
                .map { it.parsedTxId.hash }
                .filter { it.isNotEmpty() }
                .distinct()
                .toList()
        }

        /**
         * Collect the on-chain tx hashes referenced by any CEX swap's `hashes`
         * field. Transactions matching one of these hashes are owned by the swap
         * row and should be hidden in the activity list.
         */
        fun cexSwapTxHashes(activities: Collection<MApiTransaction>): Set<String> {
            val hashes = HashSet<String>()
            for (a in activities) {
                if (a is MApiTransaction.Swap && a.cex != null) {
                    a.hashes?.forEach { if (it.isNotEmpty()) hashes.add(it) }
                }
            }
            return hashes
        }

        /**
         * True when this activity's on-chain hash (or `externalMsgHashNorm`) is
         * present in `cexSwapHashes`, meaning a CEX swap row already represents it.
         */
        fun isActivityCoveredByCexSwapHashes(
            activity: MApiTransaction,
            cexSwapHashes: Set<String>,
        ): Boolean {
            if (cexSwapHashes.contains(activity.parsedTxId.hash)) return true
            activity.externalMsgHashNorm?.let {
                if (cexSwapHashes.contains(it)) return true
            }
            return false
        }
    }
}
