package org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.BALANCE_PRIMARY_SIZE
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.balanceChangeColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.toBalanceText
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.formatPnlChange
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsNativePosition

@SuppressLint("ViewConstructor")
class FuturesPositionHeaderCell(context: Context) :
    WCell(context, RecyclerView.LayoutParams(MATCH_PARENT, WRAP_CONTENT)),
    WThemedView {

    private var position: MApiPerpsNativePosition? = null

    private val iconView = WCustomImageView(context)

    private val valueLabel = WLabel(context).apply {
        setStyle(BALANCE_PRIMARY_SIZE, WFont.Balance)
        setSingleLine()
        setOnClickListener { WGlobalStorage.toggleSensitiveDataHidden() }
    }

    private val pnlLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
    }

    private val valueView = WSensitiveDataContainer(
        valueLabel,
        WSensitiveDataContainer.MaskConfig(
            16,
            4,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(
                196f,
                30f,
                globalReveal = true,
                softwareSnapshot = true
            )
        )
    ).apply {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val pnlView = WSensitiveDataContainer(
        pnlLabel,
        WSensitiveDataContainer.MaskConfig(
            16,
            3,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(130f, 26f, softwareSnapshot = true)
        )
    ).apply {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    init {
        clipChildren = false
        clipToPadding = false
        addView(iconView, LayoutParams(ICON_SIZE.dp, ICON_SIZE.dp))
        addView(valueView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(pnlView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(iconView, 4f)
            toCenterX(iconView)
            topToBottom(valueView, iconView, 12f)
            toCenterX(valueView)
            topToBottom(pnlView, valueView, 4f)
            toCenterX(pnlView)
            toBottom(pnlView, 24f)
        }
    }

    fun configure(position: MApiPerpsNativePosition) {
        this.position = position
        position.image?.let {
            iconView.set(Content.ofUrl(it, position.asset?.isRwaStock == true))
        } ?: iconView.clear()
        updateTheme()
    }

    override fun updateTheme() {
        val position = position ?: return
        valueLabel.setTextColor(WColor.PrimaryText.color)
        valueLabel.text = position.value.toBalanceText()
        pnlLabel.text = formatPnlChange(position.pnl, position.pnlPercent)
        val color = balanceChangeColor(position.pnl)
        pnlLabel.setTextColor(color)
        valueView.setHeroColors(WColor.PrimaryText.color)
        pnlView.setHeroColors(color)
    }

    private companion object {
        const val ICON_SIZE = 80
    }
}
