package org.mytonwallet.app_air.walletcore.stores

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.STAKING_SLUGS
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import java.math.BigInteger
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

object BalanceStore {

    // Observable Flow
    private val _balancesFlow = MutableStateFlow<Map<String, Map<String, BigInteger>>>(emptyMap())
    val balancesFlow = _balancesFlow.asStateFlow()
    /////

    fun loadFromCache() {
        processorQueue.execute {
            for (accountId in WGlobalStorage.accountIds()) {
                val updatedBalancesDict = WGlobalStorage.getBalancesDict(accountId) ?: continue
                val accountBalances = ConcurrentHashMap<String, BigInteger>()
                for (key in updatedBalancesDict.keys()) {
                    val amountValueString: String =
                        updatedBalancesDict.optString(key).substringAfter("bigint:")
                    accountBalances[key] = if (amountValueString.isNotEmpty())
                        amountValueString.toBigInteger()
                    else
                        BigInteger.ZERO
                }
                balances[accountId] = accountBalances
                _balancesFlow.value = _balancesFlow.value.toMutableMap().apply {
                    put(accountId, accountBalances.toMap())
                }
            }
        }
    }

    fun removeBalances(accountId: String) {
        balances.remove(accountId)
    }

    fun clean() {
        balances.clear()
    }

    private val processorQueue = Executors.newSingleThreadExecutor()

    private val balances = ConcurrentHashMap<String, ConcurrentHashMap<String, BigInteger>>()

    fun getBalances(accountId: String?): ConcurrentHashMap<String, BigInteger>? {
        if (accountId == null)
            return null
        return balances[accountId]
    }

    fun setBalances(
        accountId: String,
        accountBalances: HashMap<String, BigInteger>,
        removeOtherTokens: Boolean,
        onCompletion: () -> Unit
    ) {
        processorQueue.execute {
            val newBalances: ConcurrentHashMap<String, BigInteger> =
                if (removeOtherTokens || balances[accountId]?.keys.isNullOrEmpty()) {
                    ConcurrentHashMap()
                } else {
                    ConcurrentHashMap(balances[accountId]!!)
                }
            for (it in accountBalances.keys) {
                val balanceToUpdate = accountBalances[it]!!
                newBalances[it] = balanceToUpdate
            }
            _balancesFlow.value = _balancesFlow.value.toMutableMap().apply {
                put(accountId, newBalances.toMap())
            }
            balances[accountId] = newBalances
            val jsonObject = JSONObject()
            for (key in newBalances.keys) {
                jsonObject.put(key, "bigint:${newBalances[key]}")
            }
            WGlobalStorage.setBalancesDict(accountId, jsonObject)
            onCompletion()
        }
    }

    fun totalBalanceInBaseCurrency(
        accountId: String,
        baseCurrency: MBaseCurrency = WalletCore.baseCurrency
    ): Double? {
        val currencyRate = TokenStore.currencyRates?.get(baseCurrency.currencyCode) ?: return null
        val accountBalances = balances[accountId]
        val walletTokens = accountBalances?.filter { !STAKING_SLUGS.contains(it.key) }
            ?.mapNotNull { (tokenSlug, balance) ->
                val token =
                    TokenStore.getToken(if (tokenSlug == STAKE_SLUG) "toncoin" else tokenSlug)
                if (token != null)
                    MTokenBalance.fromParameters(token, balance)
                else
                    null
            } ?: return null
        val stakingBalance =
            StakingStore.getStakingState(accountId)?.totalBalanceInUSD() ?: 0.0

        return (walletTokens.sumOf { it.toUsdBaseCurrency ?: 0.0 } + stakingBalance) * currencyRate
    }

}
