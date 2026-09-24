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
import androidx.core.graphics.toColorInt
import androidx.core.view.isNotEmpty
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.requireDrawableCompat
import org.mytonwallet.app_air.walletcontext.utils.lerpColor

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
            R.drawable.ic_diamond,
            LocaleController.getString("Unique"),
            LocaleController.getString(
                "Get a card with unique background and personalized palette for wallet interface."
            )
        )
        addProsRow(
            R.drawable.ic_transferable,
            LocaleController.getString("Transferable"),
            LocaleController.getString("Easily send your upgraded card to any of your friends.")
        )
        addProsRow(
            R.drawable.ic_auction,
            LocaleController.getString("Tradable"),
            LocaleController.getString("Sell or auction your card on third-party NFT marketplaces.")
        )
    }

    private fun addProsRow(iconRes: Int, title: String, description: String) {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.TOP
        }
        val iconView = AppCompatImageView(context).apply {
            setImageDrawable(context.requireDrawableCompat(iconRes))
            scaleType = ImageView.ScaleType.FIT_CENTER
            translationY = -(1.dp).toFloat()
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
        textColumn.addView(
            descLabel,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 1.dp
            }
        )
        row.addView(
            iconView,
            LayoutParams(36.dp, 36.dp).apply {
                marginStart = 4.dp
            }
        )
        row.addView(
            textColumn,
            LayoutParams(0, WRAP_CONTENT, 1f).apply {
                marginStart = 8.dp
            }
        )
        addView(
            row,
            LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = if (isNotEmpty()) 32.dp else 13.dp
            }
        )
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
