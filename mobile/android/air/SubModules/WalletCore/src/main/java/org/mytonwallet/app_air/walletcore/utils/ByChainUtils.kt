package org.mytonwallet.app_air.walletcore.utils

import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

val Map<String, AccountChain>.jsonObject: JSONObject
    get() {
        val jsonObject = JSONObject()
        forEach { (chainKey, accountChain) ->
            jsonObject.put(chainKey, accountChain.jsonObject)
        }
        return jsonObject
    }

fun Map<String, AccountChain>.sortedByBalance(perChainBalance: Map<MBlockchain, Double>?): List<Map.Entry<String, AccountChain>> {
    return entries.sortedWith(
        compareByDescending<Map.Entry<String, AccountChain>> { (chainName, _) ->
            MBlockchain.supportedChains.find { it.name == chainName }
                ?.let { perChainBalance?.get(it) } ?: 0.0
        }.thenBy { (chainName, _) ->
            MBlockchain.supportedChainIndexes[chainName] ?: Int.MAX_VALUE
        })
}
