package org.mytonwallet.app_air.walletcore.stores

import com.squareup.moshi.JsonAdapter
import com.squareup.moshi.Types
import org.mytonwallet.app_air.walletcontext.cacheStorage.WCacheStorage
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore.moshi
import org.mytonwallet.app_air.walletcore.WalletCore.notifyEvent
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.buildVirtualStakingSlug
import org.mytonwallet.app_air.walletcore.models.MAssetsAndActivityData
import org.mytonwallet.app_air.walletcore.moshi.MUpdateStaking
import java.math.BigInteger
import java.util.concurrent.ConcurrentHashMap

object StakingStore : IStore {
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
        val prevState = stakingData[accountId]

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

        if (stakingState == null) {
            return
        }

        val prevBalances = mapOf(
            TONCOIN_SLUG to (prevState?.totalTonBalance ?: BigInteger.ZERO),
            MYCOIN_SLUG to (prevState?.totalMycoinBalance ?: BigInteger.ZERO),
            USDE_SLUG to (prevState?.totalUSDeBalance ?: BigInteger.ZERO),
        )
        val newBalances = mapOf(
            TONCOIN_SLUG to (stakingState.totalTonBalance ?: BigInteger.ZERO),
            MYCOIN_SLUG to (stakingState.totalMycoinBalance ?: BigInteger.ZERO),
            USDE_SLUG to (stakingState.totalUSDeBalance ?: BigInteger.ZERO),
        )

        // find new added stakings
        val newVirtualStakingSlugs = newBalances
            .filter { (slug, balance) ->
                balance > BigInteger.ZERO && (prevBalances[slug]
                    ?: BigInteger.ZERO) <= BigInteger.ZERO
            }
            .map { (slug, _) -> buildVirtualStakingSlug(slug) }

        if (newVirtualStakingSlugs.isEmpty()) {
            return
        }

        // new added stakings have to be placed on the top
        val data = MAssetsAndActivityData(accountId)
        val updatedPinned = (newVirtualStakingSlugs + data.pinnedTokens)
            .distinct()
            .toMutableList()
        data.pinnedTokens = ArrayList(updatedPinned)

        if (AccountStore.activeAccountId == accountId) {
            AccountStore.updateAssetsAndActivityData(
                newValue = data,
                notify = false,
                saveToStorage = true
            )
        } else {
            WGlobalStorage.setAssetsAndActivityData(accountId, data.toJSON)
        }
    }

    fun getStakingState(accountId: String): MUpdateStaking? {
        return stakingData[accountId]
    }

    override fun wipeData() {
        clearCache()
    }

    override fun clearCache() {
        stakingData.clear()
    }
}
