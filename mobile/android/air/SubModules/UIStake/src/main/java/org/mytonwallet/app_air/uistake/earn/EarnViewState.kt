package org.mytonwallet.app_air.uistake.earn

import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import java.math.BigInteger

data class EarnViewState(
    var stakingBalance: String? = null,
    var stakingBalanceIsLarge: Boolean = false,
    val enableAddStakeButton: Boolean = false,
    val showAddStakeButton: Boolean = false,
    val showUnstakeButton: Boolean = false,
    val showBiggerUnstakeButton: Boolean = false,

    var totalProfit: String? = null,
    val canAddStake: Boolean,
    val canUnstake: Boolean,
    val historyListState: HistoryListState = HistoryListState.InitialState,

    val unclaimedReward: BigInteger? = null
) {
    fun updateHistoryItems(newHistoryItems: List<EarnItem>, replace: Boolean): EarnViewState {
        return (historyListState as? HistoryListState.HasItem)?.run {
            if (replace) (historyItems as MutableList).clear()
            val allItems = (historyItems as MutableList)
            allItems.addAll(newHistoryItems)

            copy(historyListState = HistoryListState.HasItem(allItems))
        } ?: copy(
            historyListState = run {
                val list = mutableListOf<EarnItem>()
                list.addAll(newHistoryItems)
                HistoryListState.HasItem(list)
            }
        )
    }
}

sealed class HistoryListState {

    object InitialState : HistoryListState()

    object NoItem : HistoryListState()

    data class HasItem(
        val historyItems: List<EarnItem>,
    ) : HistoryListState()

}
