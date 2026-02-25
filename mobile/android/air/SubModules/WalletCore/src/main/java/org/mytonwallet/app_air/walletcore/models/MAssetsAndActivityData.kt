package org.mytonwallet.app_air.walletcore.models

import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.DEFAULT_SHOWN_TOKENS
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.StakingStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

data class MAssetsAndActivityData(
    var accountId: String = "",
    var hiddenTokens: ArrayList<String> = ArrayList(),
    var visibleTokens: ArrayList<String> = ArrayList(),
    var deletedTokens: ArrayList<String> = ArrayList(),
    var addedTokens: ArrayList<String> = ArrayList(),
    var pinnedTokens: ArrayList<String> = ArrayList(),
) {

    constructor(accountId: String) : this() {
        this.accountId = accountId
        val jsonObject = WGlobalStorage.getAssetsAndActivityData(accountId) ?: return
        hiddenTokens = jsonArrayToArrayList(jsonObject.optJSONArray("alwaysHiddenSlugs"))
        visibleTokens = jsonArrayToArrayList(jsonObject.optJSONArray("alwaysShownSlugs"))
        deletedTokens = jsonArrayToArrayList(
            jsonObject.optJSONArray("deletedSlugs") ?: jsonObject.optJSONArray("deletedTokens")
        )
        addedTokens = jsonArrayToArrayList(jsonObject.optJSONArray("importedSlugs"))
        pinnedTokens = jsonArrayToArrayList(jsonObject.optJSONArray("pinnedSlugs"))
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
            jsonObject.put("pinnedSlugs", JSONArray(pinnedTokens))
            return jsonObject
        }

    fun isPinned(slug: String): Boolean {
        return pinnedTokens.contains(slug)
    }

    fun deleteToken(slug: String) {
        pinnedTokens.removeAll { it == slug }
        hiddenTokens.removeAll { it == slug }
        visibleTokens.removeAll { it == slug }
        addedTokens.removeAll { it == slug }
        if (!deletedTokens.contains(slug)) {
            deletedTokens.add(slug)
        }
    }

    fun getAllTokens(
        shouldSort: Boolean = true,
        ignorePriorities: Boolean = false,
        addVirtualStakingTokens: Boolean = false,
    ): Array<MTokenBalance> {
        val tokensArray =
            ArrayList(
                BalanceStore.getBalances(accountId)?.mapNotNull { (key, _) ->
                    TokenStore.getToken(key)
                }?.filter { t ->
                    !deletedTokens.contains(t.slug)
                }?.toMutableList() ?: mutableListOf()
            )

        val account = AccountStore.accountById(accountId)
        val defaultShownSlugs = DEFAULT_SHOWN_TOKENS[account?.network] ?: emptySet()
        val slugsToAdd = mutableListOf<String>().apply {
            addAll(defaultShownSlugs)
            addAll(addedTokens)
        }
        val addedTokenObjects = slugsToAdd
            .distinct()
            .filterNot { deletedTokens.contains(it) }
            .mapNotNull { tokenSlug -> TokenStore.getToken(tokenSlug) }
            .filter { token -> account == null || account.isChainSupported(token.chain) }
            .toList()

        val shouldBeAddedTokens = addedTokenObjects.filter { addedToken ->
            !tokensArray.any { it.slug == addedToken.slug }
        }

        tokensArray.addAll(shouldBeAddedTokens)

        val tokenBalances = tokensArray.map { token ->
            MTokenBalance.fromParameters(
                token = token,
                amount = BalanceStore.getBalances(accountId)
                    ?.get(token.slug)
                    ?: BigInteger.valueOf(0)
            )!!
        }.toMutableList()

        if (addVirtualStakingTokens) {
            val stakingState = StakingStore.getStakingState(accountId)
            stakingState?.let { state ->
                listOf(
                    USDE_SLUG to state.totalUSDeBalance,
                    MYCOIN_SLUG to state.totalMycoinBalance,
                    TONCOIN_SLUG to state.totalTonBalance
                ).forEach { (slug, balance) ->
                    balance?.takeIf { it > BigInteger.ZERO }?.let { nonZeroBalance ->
                        TokenStore.getToken(slug)?.let { token ->
                            tokenBalances.add(
                                MTokenBalance.fromVirtualStakingData(
                                    baseToken = token,
                                    amount = nonZeroBalance
                                )
                            )
                        }
                    }
                }
            }
        }

        if (!shouldSort) {
            return tokenBalances.toTypedArray()
        }
        val pinnedIndexBySlug = pinnedTokens.withIndex().associate { it.value to it.index }

        val result = tokenBalances.sortedWith { left, right ->
            val leftSlug = left.virtualStakingToken ?: ""
            val rightSlug = right.virtualStakingToken ?: ""
            val leftPinnedIndex = pinnedIndexBySlug[leftSlug]
            val rightPinnedIndex = pinnedIndexBySlug[rightSlug]

            if (leftPinnedIndex != null && rightPinnedIndex != null) {
                return@sortedWith leftPinnedIndex.compareTo(rightPinnedIndex)
            }
            if (leftPinnedIndex != null) {
                return@sortedWith -1
            }
            if (rightPinnedIndex != null) {
                return@sortedWith 1
            }

            return@sortedWith left.compareByDisplayOrder(right, ignorePriorities)
        }

        return result.toTypedArray()
    }

    fun isTokenRemovable(slug: String, isStaking: Boolean): Boolean {
        if (isStaking) {
            return isStakingTokenRemovable(slug)
        }
        val tokenBalance = BalanceStore.getBalances(accountId)?.get(slug) ?: BigInteger.ZERO
        return tokenBalance == BigInteger.ZERO
    }

    private fun isStakingTokenRemovable(slug: String?): Boolean {
        val stakingState = StakingStore.getStakingState(accountId)
        val stakingBalance = when (slug) {
            TONCOIN_SLUG -> stakingState?.totalTonBalance
            MYCOIN_SLUG -> stakingState?.totalMycoinBalance
            USDE_SLUG -> stakingState?.totalUSDeBalance
            else -> null
        } ?: BigInteger.ZERO
        return stakingBalance == BigInteger.ZERO
    }
}
