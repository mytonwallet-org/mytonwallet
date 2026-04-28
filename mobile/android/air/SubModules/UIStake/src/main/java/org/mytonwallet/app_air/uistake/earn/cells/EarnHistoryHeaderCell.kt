package org.mytonwallet.app_air.uistake.earn.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class EarnHistoryHeaderCell(context: Context) : WCell(context), WThemedView {

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            text = LocaleController.getString("History")
        }
    }

    private val totalEarnedLabel: WSensitiveDataContainer<WLabel> by lazy {
        val label = WLabel(context)
        label.setStyle(14f, WFont.Regular)
        WSensitiveDataContainer(
            label,
            WSensitiveDataContainer.MaskConfig(
                12,
                3,
                gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL
            )
        )
    }

    init {
        super.setupViews()
        layoutParams.height = 45.dp
        addView(titleLabel)
        addView(totalEarnedLabel)
        setConstraints {
            toTop(titleLabel, 16f)
            toBottom(titleLabel, 10f)
            toStart(titleLabel, 20f)
            centerYToCenterY(totalEarnedLabel, titleLabel)
            toEnd(totalEarnedLabel, 16f)
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        totalEarnedLabel.contentView.setTextColor(WColor.SecondaryText.color)
    }

    @SuppressLint("SetTextI18n")
    fun configure(totalProfitFormatted: String?) {
        totalEarnedLabel.contentView.text = totalProfitFormatted?.let {
            "${LocaleController.getString("Earned")}: $it"
        }
        totalEarnedLabel.isSensitiveData = totalProfitFormatted != null
        updateTheme()
    }
}
