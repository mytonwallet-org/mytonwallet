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

        fun filter(
            array: List<MApiTransaction>?,
            hideTinyIfRequired: Boolean,
            checkSlug: String?
        ): List<MApiTransaction>? {
            if (array == null)
                return null
            var transactions = array.filter {
                it.shouldHide != true
            }
            if (checkSlug != null) {
                transactions = transactions.filter { it ->
                    activityBelongsToSlug(it, checkSlug)
                }
            }
            if (hideTinyIfRequired && WGlobalStorage.getAreTinyTransfersHidden()) {
                transactions = transactions.filter { transaction ->
                    !transaction.isTinyOrScam()
                }
            }
            return transactions
        }
    }
}
