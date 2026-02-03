package org.mytonwallet.app_air.uicomponents.adapter.implementation

import android.graphics.RectF
import android.graphics.Typeface
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell.TopRounding
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcore.moshi.IApiToken
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction

open class Item(
    type: Int,
    key: String? = null
) : BaseListItem(type, key) {
    enum class Type {
        LIST_TITLE,
        LIST_TITLE_VALUE,
        ICON_DUAL_LINE,
        TEXT,
        COPYABLE_TEXT,
        ACTIVITY,
        ALERT,
        EXPANDABLE_TEXT,
        GAP;

        val value: Int
            get() = -1 - this.ordinal
    }

    data class IconDualLine(
        val image: Content?,
        val title: CharSequence?,
        val subtitle: CharSequence?,
        val allowSeparator: Boolean = false,
        val id: String? = null,
        val isSensitiveData: Boolean = false,
        override val clickable: Clickable? = null
    ) : Item(Type.ICON_DUAL_LINE.value, id), IClickable

    data class ListTitle(
        val title: CharSequence,
        val titleColor: WColor = WColor.Tint,
        val topRounding: TopRounding,
        val startMargin: Float = 20f,
    ) : Item(Type.LIST_TITLE.value, title.toString())

    data class ListTitleValue(
        val title: CharSequence,
        val value: CharSequence?
    ) : Item(Type.LIST_TITLE_VALUE.value, "${title}_$value")

    data class ListText(
        val title: String,
        val paddingDp: RectF = RectF(20f, 16f, 20f, 8f),
        val gravity: Int? = null,
        val font: Typeface? = null,
        val textColor: WColor? = null,
        val textSize: Float? = null
    ) : Item(Type.TEXT.value, title)

    data class ExpandableText(
        val text: String
    ) : Item(Type.EXPANDABLE_TEXT.value, text)

    data class CopyableText(
        val address: String,
        val copyLabel: String,
        val copyToast: String,
    ) : Item(Type.COPYABLE_TEXT.value)

    data class Activity(
        val activity: MApiTransaction,
        val accountId: String,
        val isMultichain: Boolean,
        val isFirst: Boolean,
        val isLast: Boolean,
    ) : Item(Type.ACTIVITY.value)

    data class Alert(
        val text: CharSequence,
    ) : Item(Type.ALERT.value)

    data object Gap : Item(Type.GAP.value)

    interface IClickable {
        val clickable: Clickable?
    }

    sealed class Clickable {
        data class Token(val token: IApiToken) : Clickable()
        data class Items(val items: List<BaseListItem>) : Clickable()
        data class Index(val index: Int) : Clickable()
    }
}
