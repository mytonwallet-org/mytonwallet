package org.mytonwallet.app_air.walletcontext.models

import org.json.JSONArray
import org.json.JSONObject

/** Hidden items keep their place in [order] */
data class MToolbarConfiguration(
    val order: List<MToolbarItem>,
    val hiddenItems: Set<MToolbarItem>,
    val isSharedBackground: Boolean,
    val actionsOrder: List<MToolbarItem> = MToolbarItem.ACTION_ITEMS,
    /** The top bar side of the profile while it is off the toolbar */
    val isAccountsAtStart: Boolean = false
) {
    fun isShown(item: MToolbarItem): Boolean = item !in hiddenItems

    fun withShown(item: MToolbarItem, isShown: Boolean): MToolbarConfiguration =
        copy(hiddenItems = if (isShown) hiddenItems - item else hiddenItems + item)

    fun toJson(): JSONObject = JSONObject().apply {
        put(ORDER_KEY, JSONArray(order.map { it.value }))
        put(HIDDEN_KEY, JSONArray(hiddenItems.map { it.value }))
        put(SHARED_BACKGROUND_KEY, isSharedBackground)
        put(ACTIONS_ORDER_KEY, JSONArray(actionsOrder.map { it.value }))
        put(ACCOUNTS_AT_START_KEY, isAccountsAtStart)
    }

    companion object {
        private const val ORDER_KEY = "order"
        private const val HIDDEN_KEY = "hidden"
        private const val SHARED_BACKGROUND_KEY = "sharedBackground"
        private const val ACTIONS_ORDER_KEY = "actionsOrder"
        private const val ACCOUNTS_AT_START_KEY = "accountsAtStart"

        val DEFAULT = MToolbarConfiguration(
            order = MToolbarItem.entries,
            hiddenItems = MToolbarItem.entries.filter {
                it == MToolbarItem.ACCOUNTS || (it.isAction && it != MToolbarItem.SCAN)
            }.toSet(),
            isSharedBackground = true
        )

        fun fromJson(json: JSONObject?): MToolbarConfiguration {
            json ?: return DEFAULT
            val stored = readItems(json.optJSONArray(ORDER_KEY)).distinct()
            val missing = MToolbarItem.entries.filter { it !in stored }
            // New items take their default visibility
            val hiddenItems = readItems(json.optJSONArray(HIDDEN_KEY)).filter { it.isHideable } +
                missing.filter { it in DEFAULT.hiddenItems }
            val storedActions = readItems(json.optJSONArray(ACTIONS_ORDER_KEY))
                .filter { it.isAction }
                .distinct()
            return MToolbarConfiguration(
                order = stored + missing,
                hiddenItems = hiddenItems.toSet(),
                isSharedBackground = json.optBoolean(
                    SHARED_BACKGROUND_KEY,
                    DEFAULT.isSharedBackground
                ),
                actionsOrder = storedActions +
                    MToolbarItem.ACTION_ITEMS.filter { it !in storedActions },
                isAccountsAtStart = json.optBoolean(ACCOUNTS_AT_START_KEY, false)
            )
        }

        private fun readItems(array: JSONArray?): List<MToolbarItem> {
            array ?: return emptyList()
            return (0 until array.length()).mapNotNull {
                MToolbarItem.fromValue(array.optString(it))
            }
        }
    }
}
