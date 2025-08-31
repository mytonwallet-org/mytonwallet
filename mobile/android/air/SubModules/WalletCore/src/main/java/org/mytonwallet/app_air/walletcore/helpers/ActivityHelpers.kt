package org.mytonwallet.app_air.walletcore.helpers

import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.math.BigInteger

class ActivityHelpers {
    companion object {
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
                it.shouldHide != true &&
                    /*
                        Temporary workaround to fix a SDK bug (returning same identifier for different transactions!)
                        Let's filter out contract call transactions on TRON chain
                     */
                    (it !is MApiTransaction.Transaction ||
                        (it.type != ApiTransactionType.CONTRACT_DEPLOY &&
                            it.type != ApiTransactionType.CALL_CONTRACT) ||
                        it.amount != BigInteger.ZERO ||
                        it.token?.chain == TONCOIN_SLUG)
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
