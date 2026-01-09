package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

class ActivityHelpers {
    companion object {
        fun getTxIdFromId(id: String): String? {
            return id.split(":").firstOrNull()
        }

        fun isSuitableToGetTimestamp(activity: MApiTransaction): Boolean {
            return !activity.isLocal() && !activity.isBackendSwapId()
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
                                it.fromAmount == newActivity.fromAmount
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
            checkSlug: String?
        ): List<MApiTransaction>? {
            if (array == null)
                return null
            var transactions = array.filter {
                it.shouldHide != true && !it.isPoisoning(accountId)
            }
            if (checkSlug != null) {
                transactions = transactions.filter { it ->
                    activityBelongsToSlug(it, checkSlug)
                }
            }
            if (hideTinyIfRequired && WGlobalStorage.getAreTinyTransfersHidden()) {
                transactions = transactions.filter { transaction ->
                    !transaction.isTinyOrScam
                }
            }
            return transactions
        }
    }
}
