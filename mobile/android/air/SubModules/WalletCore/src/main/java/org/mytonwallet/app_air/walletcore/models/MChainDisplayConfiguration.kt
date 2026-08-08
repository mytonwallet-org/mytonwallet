package org.mytonwallet.app_air.walletcore.models

import org.json.JSONArray
import org.json.JSONObject
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain

enum class MChainDisplayMode(val value: String) {
    VALUE("value"),
    MANUAL("manual");

    companion object {
        fun fromValue(value: String): MChainDisplayMode? = entries.find { it.value == value }
    }
}

data class MChainDisplayConfiguration(
    var displayMode: MChainDisplayMode = MChainDisplayMode.VALUE,
    var hiddenChains: List<String> = emptyList(),
    var manualOrder: List<String> = emptyList()
) {
    init {
        if (displayMode == MChainDisplayMode.VALUE) {
            hiddenChains = emptyList()
            manualOrder = emptyList()
        } else {
            hiddenChains = unique(hiddenChains)
            manualOrder = unique(manualOrder)
        }
    }

    constructor(jsonObject: JSONObject) : this(
        displayMode = displayModeFromJson(jsonObject),
        hiddenChains = jsonArrayToList(jsonObject.optJSONArray("hiddenChains")),
        manualOrder = jsonArrayToList(jsonObject.optJSONArray("manualOrder"))
    )

    val isDefault: Boolean
        get() = displayMode == MChainDisplayMode.VALUE &&
            hiddenChains.isEmpty() && manualOrder.isEmpty()

    val toJSON: JSONObject
        get() = JSONObject().apply {
            put("displayMode", displayMode.value)
            if (hiddenChains.isNotEmpty()) put("hiddenChains", JSONArray(hiddenChains))
            if (manualOrder.isNotEmpty()) put("manualOrder", JSONArray(manualOrder))
        }

    fun updateDisplayMode(displayMode: MChainDisplayMode) {
        this.displayMode = displayMode
        if (displayMode == MChainDisplayMode.VALUE) {
            hiddenChains = emptyList()
            manualOrder = emptyList()
        }
    }

    fun isVisible(chain: String): Boolean = !hiddenChains.contains(chain)

    fun setVisible(chain: String, isVisible: Boolean) {
        hiddenChains = hiddenChains.filterNot { it == chain }
        if (!isVisible) hiddenChains = hiddenChains + chain
    }

    fun updateManualOrder(manualOrder: List<String>) {
        this.manualOrder = unique(manualOrder)
    }

    fun orderedChains(
        accountChainOrder: List<String>,
        chainsSortedByValue: List<String>,
        chainsShownInValueMode: Set<String> = emptySet()
    ): List<String> {
        if (displayMode == MChainDisplayMode.MANUAL && manualOrder.isNotEmpty()) {
            return normalizedManualOrder(accountChainOrder)
        }

        val uniqueAccountChainOrder = unique(accountChainOrder)
        val availableChains = uniqueAccountChainOrder.toSet()
        val availableChainsSortedByValue = unique(chainsSortedByValue).filter {
            it in availableChains
        }
        val chainsInValueOrder = availableChainsSortedByValue.toSet()
        val completeValueOrder = availableChainsSortedByValue +
            uniqueAccountChainOrder.filterNot { it in chainsInValueOrder }

        return if (displayMode == MChainDisplayMode.VALUE) {
            completeValueOrder.filter { it in chainsShownInValueMode } +
                completeValueOrder.filterNot { it in chainsShownInValueMode }
        } else {
            completeValueOrder
        }
    }

    fun normalizedManualOrder(accountChainOrder: List<String>): List<String> {
        if (manualOrder.isEmpty()) return emptyList()
        val uniqueAccountChainOrder = unique(accountChainOrder)
        val availableChains = uniqueAccountChainOrder.toSet()
        val availableManualOrder = manualOrder.filter { it in availableChains }
        val manuallyOrderedChains = availableManualOrder.toSet()
        return availableManualOrder + uniqueAccountChainOrder.filterNot {
            it in manuallyOrderedChains
        }
    }

    fun visibleChains(
        accountChainOrder: List<String>,
        orderedChains: List<String>,
        chainsShownInValueMode: Set<String> = emptySet(),
        includingChain: String? = null
    ): List<String> {
        val visibleChains = orderedChains.filter { chain ->
            chain == includingChain || if (displayMode == MChainDisplayMode.VALUE) {
                chain in chainsShownInValueMode
            } else {
                isVisible(chain)
            }
        }
        if (visibleChains.isNotEmpty()) return visibleChains

        val fallbackChain = if (displayMode == MChainDisplayMode.VALUE) {
            orderedChains.firstOrNull()
        } else {
            accountChainOrder.firstOrNull(::isVisible) ?: accountChainOrder.firstOrNull()
        }
        return fallbackChain?.let(::listOf).orEmpty()
    }

    companion object {
        fun chainsShownInValueMode(
            accountChainOrder: List<String>,
            chainsWithBalance: Set<String>,
            hasTokenBalance: Boolean,
            isGramWallet: Boolean
        ): Set<String> {
            val uniqueAccountChainOrder = unique(accountChainOrder)
            val availableChains = uniqueAccountChainOrder.toSet()
            if (!hasTokenBalance) {
                return if (isGramWallet) {
                    uniqueAccountChainOrder.filter { it == MBlockchain.ton.name }.toSet()
                } else {
                    availableChains
                }
            }

            val availableChainsWithBalance = chainsWithBalance.intersect(availableChains)
            return availableChainsWithBalance.ifEmpty {
                uniqueAccountChainOrder.take(1).toSet()
            }
        }

        private fun displayModeFromJson(jsonObject: JSONObject): MChainDisplayMode =
            MChainDisplayMode.fromValue(jsonObject.optString("displayMode"))
                ?: MChainDisplayMode.MANUAL

        private fun jsonArrayToList(jsonArray: JSONArray?): List<String> {
            if (jsonArray == null) return emptyList()
            return buildList {
                for (i in 0 until jsonArray.length()) {
                    add(jsonArray.getString(i))
                }
            }
        }

        private fun unique(chains: List<String>): List<String> = chains.distinct()
    }
}
