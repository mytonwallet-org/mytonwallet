package org.mytonwallet.app_air.walletcore.models

import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

data class MAssetsAndActivityData(
    var hiddenTokens: ArrayList<String> = ArrayList(),
    var visibleTokens: ArrayList<String> = ArrayList(),
    var deletedTokens: ArrayList<String> = ArrayList(),
    var addedTokens: ArrayList<String> = ArrayList(),
) {
    constructor(accountId: String) : this() {
        val jsonObject = WGlobalStorage.getAssetsAndActivityData(accountId) ?: return
        hiddenTokens = jsonArrayToArrayList(jsonObject.optJSONArray("alwaysHiddenSlugs"))
        visibleTokens = jsonArrayToArrayList(jsonObject.optJSONArray("alwaysShownSlugs"))
        deletedTokens = jsonArrayToArrayList(jsonObject.optJSONArray("deletedTokens"))
        addedTokens = jsonArrayToArrayList(jsonObject.optJSONArray("importedSlugs"))
    }

    private fun jsonArrayToArrayList(jsonArray: JSONArray?): ArrayList<String> {
        val list = ArrayList<String>()
        if (jsonArray != null) {
            for (i in 0 until jsonArray.length()) {
                list.add(jsonArray.getString(i))
            }
        }
        return list
    }

    val toJSON: JSONObject
        get() {
            val jsonObject = JSONObject()
            jsonObject.put("alwaysHiddenSlugs", JSONArray(hiddenTokens))
            jsonObject.put("alwaysShownSlugs", JSONArray(visibleTokens))
            jsonObject.put("deletedSlugs", JSONArray(deletedTokens))
            jsonObject.put("importedSlugs", JSONArray(addedTokens))
            return jsonObject
        }

    fun getAllTokens(
        shouldSort: Boolean = true,
        ignorePriorities: Boolean = false,
        addVirtualStakingTokens: Boolean = false,
    ): Array<MTokenBalance> {
        val tokensArray =
            ArrayList(
                BalanceStore.getBalances(AccountStore.activeAccountId)?.mapNotNull { (key, _) ->
                    TokenStore.getToken(key)
                }?.filter { t ->
                    !deletedTokens.contains(t.slug)
                }?.toMutableList() ?: mutableListOf()
            )

        if (!addedTokens.contains(TON_USDT_SLUG))
            addedTokens.add(TON_USDT_SLUG)
        val addedTokenObjects = addedTokens.mapNotNull { tokenSlug ->
            TokenStore.getToken(tokenSlug)
        }

        val shouldBeAddedTokens = addedTokenObjects.filter { addedToken ->
            !tokensArray.any { it.slug == addedToken.slug }
        }

        tokensArray.addAll(shouldBeAddedTokens)

        val tokenBalances = tokensArray.map { token ->
            MTokenBalance.fromParameters(
                token = token,
                amount = BalanceStore.getBalances(AccountStore.activeAccountId)
                    ?.get(token.slug)
                    ?: BigInteger.valueOf(0)
            )!!
        }

        if (!shouldSort)
            return tokenBalances.toTypedArray()
        val result = tokenBalances.sortedWith { lhs, rhs ->
            if (!ignorePriorities) {
                if (lhs.priority != rhs.priority)
                    return@sortedWith if (lhs.priority > rhs.priority) -1 else 1
            }
            return@sortedWith if (
                (lhs.toUsdBaseCurrency ?: 0.0) > (rhs.toUsdBaseCurrency ?: 0.0)
            )
                -1
            else if ((lhs.toUsdBaseCurrency ?: 0.0) < (rhs.toUsdBaseCurrency ?: 0.0))
                1
            else if (lhs.priorityOnSameBalance > rhs.priorityOnSameBalance)
                -1
            else if (lhs.priorityOnSameBalance < rhs.priorityOnSameBalance)
                1
            else (lhs.token ?: "").compareTo(rhs.token ?: "")
        }.toMutableList()

        if (addVirtualStakingTokens) {
            val stakingState = StakingStore.getStakingState(AccountStore.activeAccountId.orEmpty())
            stakingState?.let { state ->
                listOf(
                    USDE_SLUG to state.totalUSDeBalance,
                    MYCOIN_SLUG to state.totalMycoinBalance,
                    TONCOIN_SLUG to state.totalTonBalance
                ).forEach { (slug, balance) ->
                    balance?.takeIf { it > BigInteger.ZERO }?.let { nonZeroBalance ->
                        TokenStore.getToken(slug)?.let { token ->
                            result.add(
                                0,
                                MTokenBalance.fromVirtualStakingData(token, nonZeroBalance)
                            )
                        }
                    }
                }
            }
        }

        return result.toTypedArray()
    }

    fun isTokenRemovable(slug: String): Boolean {
        return addedTokens.contains(slug) &&
            BalanceStore.getBalances(AccountStore.activeAccountId)?.contains(slug) != true &&
            slug != TON_USDT_SLUG
    }
}
