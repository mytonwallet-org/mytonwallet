package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.ApiSwapStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

class ActivityHelpers {
    companion object {
        fun getTxIdFromId(id: String): String? = id.split(":").firstOrNull()

        fun isSuitableToGetTimestamp(activity: MApiTransaction): Boolean =
            !activity.isLocal() && !activity.isBackendSwapId() && !activity.isPending()

        fun activityBelongsToSlug(activity: MApiTransaction, slug: String?): Boolean =
            slug == null || slug == activity.getTxSlug() ||
                (
                    activity is MApiTransaction.Swap &&
                        (activity.from == slug || activity.to == slug)
                    )

        fun getActivityTokenSlugs(activity: MApiTransaction): List<String> = when (activity) {
            is MApiTransaction.Swap -> listOf(activity.from, activity.to).distinct()
            is MApiTransaction.Transaction -> listOf(activity.slug)
        }

        fun preserveStatusProgress(
            existingActivity: MApiTransaction?,
            incomingActivity: MApiTransaction
        ): MApiTransaction {
            val adjustedActivity = when {
                existingActivity == null || existingActivity.kind != incomingActivity.kind ->
                    incomingActivity

                statusRank(existingActivity) <= statusRank(incomingActivity) ->
                    incomingActivity

                existingActivity is MApiTransaction.Transaction &&
                    incomingActivity is MApiTransaction.Transaction ->
                    incomingActivity.copy(status = existingActivity.status)

                existingActivity is MApiTransaction.Swap &&
                    incomingActivity is MApiTransaction.Swap ->
                    incomingActivity.copy(status = existingActivity.status)

                else -> incomingActivity
            }

            adjustedActivity.replacedStableId = incomingActivity.replacedStableId
                ?: existingActivity?.takeIf {
                    it.id == incomingActivity.id && it.kind == incomingActivity.kind
                }?.replacedStableId
            return adjustedActivity
        }

        private fun statusRank(activity: MApiTransaction): Int = when (activity) {
            is MApiTransaction.Transaction -> when (activity.status) {
                ApiTransactionStatus.PENDING -> 1
                ApiTransactionStatus.PENDING_TRUSTED -> 2
                ApiTransactionStatus.CONFIRMED -> 3
                ApiTransactionStatus.COMPLETED, ApiTransactionStatus.FAILED -> 4
            }

            is MApiTransaction.Swap -> when (activity.status) {
                ApiSwapStatus.PENDING -> 1
                ApiSwapStatus.PENDING_TRUSTED -> 2
                ApiSwapStatus.CONFIRMED -> 3
                ApiSwapStatus.COMPLETED, ApiSwapStatus.FAILED, ApiSwapStatus.EXPIRED -> 4
            }
        }

        @JvmName("filterNullable")
        fun filter(
            accountId: String,
            array: List<MApiTransaction>?,
            hideTinyIfRequired: Boolean,
            checkSlug: String?
        ): List<MApiTransaction>? = array?.let {
            filter(accountId, it, hideTinyIfRequired, checkSlug)
        }

        fun filter(
            accountId: String,
            array: List<MApiTransaction>,
            hideTinyIfRequired: Boolean,
            checkSlug: String?
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

        fun sorter(t1: MApiTransaction, t2: MApiTransaction): Int = when {
            t1.timestamp != t2.timestamp -> t2.timestamp.compareTo(t1.timestamp)
            else -> t2.id.compareTo(t1.id)
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
        ): List<String> = (newIds + existingIds)
            .distinct()
            .sortedWith { id1, id2 -> compareActivityIds(id1, id2, byId, fallback) }

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
        ): MApiTransaction? = byId[id] ?: fallback.firstOrNull { it.id == id }

        /**
         * Hashes of CEX swap activities that are still pending (mid-flight on the
         * exchange side). Used to drive `fetchSwaps` reconciliation polling.
         */
        fun pendingCexSwapHashes(activities: Collection<MApiTransaction>): List<String> =
            activities.asSequence()
                .filter { it is MApiTransaction.Swap && it.cex != null && it.isPending() }
                .map { it.parsedTxId.hash }
                .filter { it.isNotEmpty() }
                .distinct()
                .toList()
    }
}
