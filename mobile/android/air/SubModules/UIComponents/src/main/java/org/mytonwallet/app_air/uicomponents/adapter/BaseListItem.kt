package org.mytonwallet.app_air.uicomponents.adapter

open class BaseListItem(
    val type: Int = NOT_TYPE,
    val key: String? = null
) {
    companion object {
        const val NOT_TYPE = 0
    }
}
