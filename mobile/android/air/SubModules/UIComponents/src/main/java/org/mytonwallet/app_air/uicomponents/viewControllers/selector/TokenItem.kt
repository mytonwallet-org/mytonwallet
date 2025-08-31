package org.mytonwallet.app_air.uicomponents.viewControllers.selector

import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem

sealed class TokenItem(
    type: Int,
    key: String? = null
) : BaseListItem(type, key) {
    enum class Type {
        TITLE;

        val value: Int
            get() = this.ordinal
    }

    data class Title(
        val title: String
    ) : TokenItem(Type.TITLE.value, title)
}
