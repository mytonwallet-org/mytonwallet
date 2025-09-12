package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.view.get
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.MAIN_NETWORK
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class HeaderActionsView(
    context: Context,
    var tabs: List<Item>,
    var onClick: ((Identifier) -> Unit)?,
) : WCell(context), WThemedView {

    private var actionViews = HashMap<Identifier, View>()
    var tabsLocalized = if (LocaleController.isRTL) tabs.asReversed() else tabs

    private var itemViews = ArrayList<WView>()

    init {
        layoutParams = LayoutParams(MATCH_PARENT, 86.dp).apply {
            insetsUpdated()
        }
        layoutDirection = LAYOUT_DIRECTION_LTR

        configureViews()
    }

    fun resetTabs(tabs: List<Item>) {
        this.tabs = tabs
        tabsLocalized = if (LocaleController.isRTL) tabs.asReversed() else tabs
        configureViews()
    }

    private fun generateItems() {
        actionViews.clear()
        itemViews.clear()
        fun itemGenerator(item: Item): WView {
            val tabView = WView(context)
            tabView.setPadding(0, 4.dp, 4, 4.dp)
            val iconView = AppCompatImageView(context)
            iconView.id = generateViewId()
            iconView.setImageDrawable(item.icon)
            tabView.addView(iconView, 0, 0)
            val label = WLabel(context)
            label.setStyle(15f, WFont.SemiBold)
            label.text = item.title
            tabView.addView(label, LayoutParams(WRAP_CONTENT, 24.dp))
            tabView.setConstraints {
                toStart(label)
                toEnd(label)
                toBottom(label)
                toTop(iconView)
                toStart(iconView)
                toEnd(iconView)
                bottomToTop(iconView, label, 6f)
            }
            return tabView
        }

        val arr = ArrayList<WView>()
        for (tab in tabsLocalized) {
            val tabView = itemGenerator(tab)
            actionViews[tab.identifier] = tabView
            arr.add(tabView)
        }
        itemViews = arr
    }

    private fun configureViews() {
        removeAllViews()
        generateItems()
        itemViews.forEachIndexed { index, itemView ->
            addView(
                itemView,
                LayoutParams(if (itemViews.size == 1) MATCH_PARENT else 0, MATCH_PARENT).apply {
                    if (index != 0) {
                        leftMargin = 11.dp
                    }
                })
            itemView.setOnClickListener {
                if (alpha > 0)
                    onClick?.invoke(tabsLocalized[index].identifier)
            }
        }
        setConstraints {
            itemViews.forEachIndexed { index, itemView ->
                toTop(itemView)
                toBottom(itemView)
                when (index) {
                    0 -> leftToLeft(this@HeaderActionsView, itemView)
                    else -> leftToRight(itemViews[index - 1], itemView)
                }
            }
            rightToRight(this@HeaderActionsView, itemViews.last())
            if (itemViews.size > 1) {
                createHorizontalChain(
                    ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                    ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                    itemViews.map { it.id }.toIntArray(),
                    null,
                    ConstraintSet.CHAIN_SPREAD
                )
            }
        }

        updateTheme()
    }

    // px60 refers to the action menu items height
    private val px60 = 60.dp

    data class Item(
        val identifier: Identifier,
        val icon: Drawable,
        val title: String
    )

    enum class Identifier {
        RECEIVE,
        SEND,
        EARN,
        SWAP,
        LOCK_APP,
        TOGGLE_SENSITIVE_DATA_PROTECTION,
        SCAN_QR,
        SCROLL_TO_TOP,
        DETAILS,
        REPEAT,
        SHARE
    }

    fun insetsUpdated() {
        setPadding(
            (17.5f - ViewConstants.HORIZONTAL_PADDINGS).dp.roundToInt(),
            paddingTop,
            (17.5f - ViewConstants.HORIZONTAL_PADDINGS).dp.roundToInt(),
            paddingBottom
        )
    }

    override fun updateTheme() {
        for (itemView in itemViews) {
            (itemView[0] as ImageView).setColorFilter(WColor.Tint.color)
            (itemView[1] as WLabel).setTextColor(WColor.Tint.color)
            itemView.setBackgroundColor(Color.TRANSPARENT)
            itemView.addRippleEffect(
                if (ThemeManager.uiMode.hasRoundedCorners) WColor.Background.color else WColor.SecondaryBackground.color,
                ViewConstants.BIG_RADIUS.dp
            )
        }
    }

    var fadeOutPercent: Float = 0f
        set(value) {
            if (field == value)
                return
            field = value
            setPadding(
                (17 - ViewConstants.HORIZONTAL_PADDINGS).dp,
                (px60 * (1 - value)).toInt(),
                (17 - ViewConstants.HORIZONTAL_PADDINGS).dp,
                16.dp
            )
            itemViews.forEach {
                it.alpha = (value - 0.4f) * 5 / 3
            }
        }

    fun onDestroy() {
        onClick = null
    }

    fun updateActions() {
        val isMainNet = WalletCore.activeNetwork == MAIN_NETWORK
        setSendVisibility(AccountStore.activeAccount?.accountType != MAccount.AccountType.VIEW)
        setEarnVisibility(isMainNet)
        setSwapVisibility(isMainNet && AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC)
    }

    private fun setSendVisibility(visible: Boolean) {
        actionViews[Identifier.SEND]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setSwapVisibility(visible: Boolean) {
        actionViews[Identifier.SWAP]?.visibility = if (visible) VISIBLE else GONE
    }

    private fun setEarnVisibility(visible: Boolean) {
        actionViews[Identifier.EARN]?.visibility = if (visible) VISIBLE else GONE
    }

    companion object {
        fun headerTabs(context: Context, showEarn: Boolean): List<Item> {
            return mutableListOf<Item>().apply {
                add(
                    Item(
                        Identifier.RECEIVE,
                        ContextCompat.getDrawable(context, R.drawable.ic_header_add)!!,
                        LocaleController.getString("Add")
                    )
                )
                add(
                    Item(
                        Identifier.SEND,
                        ContextCompat.getDrawable(context, R.drawable.ic_header_send)!!,
                        LocaleController.getString("\$send_action")
                    )
                )
                add(
                    Item(
                        Identifier.SWAP,
                        ContextCompat.getDrawable(context, R.drawable.ic_header_swap)!!,
                        LocaleController.getString("Swap")
                    )
                )
                if (showEarn) {
                    add(
                        Item(
                            Identifier.EARN,
                            ContextCompat.getDrawable(context, R.drawable.ic_header_earn)!!,
                            LocaleController.getString("Earn")
                        )
                    )
                }
            }
        }
    }
}
