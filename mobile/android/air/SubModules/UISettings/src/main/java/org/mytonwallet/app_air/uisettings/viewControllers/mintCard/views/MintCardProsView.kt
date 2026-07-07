package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.lerpColor
import androidx.core.graphics.toColorInt
import androidx.core.view.isNotEmpty

@SuppressLint("ViewConstructor")
class MintCardProsView(context: Context) : LinearLayout(context) {

    private val prosIcons = mutableListOf<AppCompatImageView>()
    private val titleLabels = mutableListOf<WLabel>()
    private val descLabels = mutableListOf<WLabel>()

    companion object {
        private val ON_BLACK_TITLE = Color.WHITE
        private val ON_BLACK_DESC = "#8491A5".toColorInt()
    }

    init {
        orientation = VERTICAL

        addProsRow(
            IconsR.drawable.ic_diamond_30,
            LocaleController.getString("Unique"),
            LocaleController.getString("Get a card with unique background and personalized palette for wallet interface.")
        )
        addProsRow(
            IconsR.drawable.ic_swap_30,
            LocaleController.getString("Transferable"),
            LocaleController.getString("Easily send your upgraded card to any of your friends.")
        )
        addProsRow(
            IconsR.drawable.ic_auction_30,
            LocaleController.getString("Tradable"),
            LocaleController.getString("Sell or auction your card on third-party NFT marketplaces.")
        )
    }

    private fun addProsRow(iconRes: Int, title: String, description: String) {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val iconView = AppCompatImageView(context).apply {
            setImageDrawable(context.requireDrawableCompat(iconRes))
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        prosIcons.add(iconView)
        val textColumn = LinearLayout(context).apply {
            orientation = VERTICAL
        }
        val titleLabel = WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setTextColor(WColor.PrimaryText.color)
            text = title
        }
        val descLabel = WLabel(context).apply {
            setStyle(14f)
            setTextColor(WColor.SecondaryText.color)
            text = description
        }
        titleLabels.add(titleLabel)
        descLabels.add(descLabel)
        textColumn.addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        textColumn.addView(descLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            topMargin = 2.dp
        })
        row.addView(iconView, LayoutParams(36.dp, 36.dp))
        row.addView(textColumn, LayoutParams(0, WRAP_CONTENT, 1f).apply {
            marginStart = 16.dp
        })
        addView(row, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            if (isNotEmpty()) topMargin = 16.dp
        })
    }

    fun setAccentColor(color: Int) {
        prosIcons.forEach { it.setColorFilter(color) }
    }

    fun setBlackProgress(blackProgress: Float) {
        val t = blackProgress.coerceIn(0f, 1f)
        val titleColor = lerpColor(WColor.PrimaryText.color, ON_BLACK_TITLE, t)
        val descColor = lerpColor(WColor.SecondaryText.color, ON_BLACK_DESC, t)
        titleLabels.forEach { it.setTextColor(titleColor) }
        descLabels.forEach { it.setTextColor(descColor) }
    }
}
