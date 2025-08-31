package org.mytonwallet.app_air.walletcore.stores

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.WalletCore.moshi
import org.mytonwallet.app_air.walletcore.WalletCore.notifyEvent
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import java.util.concurrent.ConcurrentHashMap

object StakingStore {
    private var stakingData = ConcurrentHashMap<String, MUpdateStaking?>()

    fun loadCachedStates() {
        val accountIds = WGlobalStorage.accountIds()
        if (accountIds.isEmpty())
            return
        stakingData.clear()
        for (account in accountIds) {
            WCacheStorage.getStakingData(account)?.let { updateString ->
                val listType = Types.newParameterizedType(
                    List::class.java,
                    MUpdateStaking::class.java
                )
                val jsonAdapter: JsonAdapter<List<MUpdateStaking>> = moshi.adapter(listType)
                try {
                    setStakingState(jsonAdapter.fromJson(updateString) ?: emptyList())
                } catch (e: Throwable) {
                    e.printStackTrace()
                }
            }
        }
        notifyEvent(WalletEvent.StakingDataUpdated)
    }

    private fun setStakingState(stakingData: List<MUpdateStaking>) {
        stakingData.forEach {
            this.stakingData[it.accountId] = it
        }
    }

    fun setStakingState(accountId: String, stakingState: MUpdateStaking?) {
        if (stakingState != null)
            stakingData[accountId] = stakingState
        else
            stakingData.remove(accountId)

        val jsonAdapter: JsonAdapter<List<MUpdateStaking>> =
            moshi.adapter(
                Types.newParameterizedType(
                    List::class.java,
                    MUpdateStaking::class.java
                )
            )
        WCacheStorage.setStakingData(
            accountId,
            jsonAdapter.toJson(stakingData.values.filterNotNull())
        )
    }

    fun getStakingState(accountId: String): MUpdateStaking? {
        return stakingData[accountId]
    }

    fun clean() {
        stakingData.clear()
    }
}
