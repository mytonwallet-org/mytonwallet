package org.mytonwallet.app_air.uistake.earn.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.DateUtils
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import kotlin.math.abs

class EarnItemCell(context: Context) : WCell(context), WThemedView {

    private var isFirst = false
    private var isLast = false

    private val historyTitleLabel: WLabel by lazy {
        val wLabel = WLabel(context)
        wLabel.setStyle(14f, WFont.DemiBold)
        wLabel.visibility = GONE
        wLabel.text = LocaleController.getString("History")
        wLabel
    }

    private val totalEarnedLabel: WSensitiveDataContainer<WLabel> by lazy {
        val wLabel = WLabel(context)
        wLabel.setStyle(14f, WFont.Regular)
        WSensitiveDataContainer(
            wLabel,
            WSensitiveDataContainer.MaskConfig(
                12,
                3,
                gravity = Gravity.RIGHT or Gravity.CENTER_VERTICAL
            )
        ).apply {
            visibility = GONE
        }
    }

    private val iconView: IconView by lazy {
        val iv = IconView(context)
        iv
    }

    private val groupIcon: IconView by lazy {
        val iv = IconView(context)
        iv.visibility = GONE
        iv
    }

    private val groupIconShadow1: IconView by lazy {
        val iv = IconView(context, viewSize = 44.dp)
        iv.alpha = 0.6f
        iv.visibility = GONE
        iv
    }

    private val groupIconShadow2: IconView by lazy {
        val iv = IconView(context, viewSize = 40.dp)
        iv.alpha = 0.3f
        iv.visibility = GONE
        iv
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val itemDateLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val amountLabel: WSensitiveDataContainer<WLabel> by lazy {
        val label = WLabel(context)
        label.setStyle(16f, WFont.Regular)
        WSensitiveDataContainer(
            label,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    private val fiatValueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val label = WLabel(context)
        label.setStyle(14f, WFont.Regular)
        WSensitiveDataContainer(
            label,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.RIGHT or Gravity.CENTER_VERTICAL)
        )
    }

    init {
        super.setupViews()

        layoutParams.height = WRAP_CONTENT

        addView(historyTitleLabel)
        addView(totalEarnedLabel)

        addView(iconView, LayoutParams(48.dp, 48.dp))
        addView(groupIconShadow2, LayoutParams(40.dp, 40.dp))
        addView(groupIconShadow1, LayoutParams(44.dp, 44.dp))
        addView(groupIcon, LayoutParams(48.dp, 48.dp))
        addView(titleLabel)
        addView(itemDateLabel)
        addView(amountLabel)
        addView(fiatValueLabel)

        addRippleEffect(WColor.SecondaryBackground.color)

        setConstraints {
            toTop(historyTitleLabel, 16f)
            toStart(historyTitleLabel, 20f)

            centerYToCenterY(totalEarnedLabel, historyTitleLabel)
            toEnd(totalEarnedLabel, 16f)

            topToBottom(iconView, historyTitleLabel, 18f)
            setGoneMargin(iconView.id, ConstraintSet.TOP, 8.dp)
            toBottom(iconView, 8f)
            toStart(iconView, 12f)

            edgeToEdge(groupIcon, iconView)
            centerXToCenterX(groupIconShadow1, groupIcon)
            topToTop(groupIconShadow1, groupIcon, 7f)
            centerXToCenterX(groupIconShadow2, groupIcon)
            topToTop(groupIconShadow2, groupIconShadow1, 7f)

            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)
            topToTop(titleLabel, iconView)
            startToEnd(titleLabel, iconView, 12f)
            bottomToTop(titleLabel, itemDateLabel)
            endToStart(titleLabel, amountLabel, 8f)

            topToBottom(itemDateLabel, titleLabel, -1f)
            startToStart(itemDateLabel, titleLabel)
            endToStart(itemDateLabel, fiatValueLabel, 4f)
            constrainedWidth(itemDateLabel.id, true)
            setHorizontalBias(itemDateLabel.id, 0f)
            toBottom(itemDateLabel, 9f)

            topToTop(amountLabel, iconView)
            toEnd(amountLabel, 16f)
            bottomToTop(amountLabel, fiatValueLabel)

            topToBottom(fiatValueLabel, amountLabel)
            endToEnd(fiatValueLabel, amountLabel)
            toBottom(fiatValueLabel, 9f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )

        historyTitleLabel.setTextColor(WColor.PrimaryText.color)
        totalEarnedLabel.contentView.setTextColor(WColor.SecondaryText.color)

        titleLabel.setTextColor(WColor.PrimaryText.color)
        itemDateLabel.setTextColor(WColor.SecondaryText.color)

        amountLabel.contentView.setTextColor(WColor.PrimaryText.color)
        fiatValueLabel.contentView.setTextColor(WColor.SecondaryText.color)
    }

    // TODO:: Header should be a separate cell!
    @SuppressLint("SetTextI18n")
    fun configure(
        item: EarnItem,
        tokenSymbol: String,
        totalProfitFormatted: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    ) {
        this.isFirst = isFirst
        this.isLast = isLast
        updateTheme()

        titleLabel.setTextIfChanged(item.getTitle())
        if (item is EarnItem.Profit || item is EarnItem.ProfitGroup || item is EarnItem.Unstaked) {
            amountLabel.contentView.text = "+$signSpace${item.formattedAmount} $tokenSymbol"
            amountLabel.contentView.setTextColor(WColor.Green.color)
            amountLabel.maskView.skin = SensitiveDataMaskView.Skin.GREEN
        } else {
            amountLabel.contentView.text = "${item.formattedAmount} $tokenSymbol"
            amountLabel.contentView.setTextColor(WColor.PrimaryText.color)
            amountLabel.maskView.skin = null
        }
        fiatValueLabel.contentView.text = item.amountInBaseCurrency
        arrayListOf(iconView, groupIcon, groupIconShadow1, groupIconShadow2).forEach {
            it.config(
                item.getIcon(),
                item.getGradientColors()?.first,
                item.getGradientColors()?.second,
            )
        }
        if (item is EarnItem.ProfitGroup) {
            groupIcon.visibility = VISIBLE
            groupIconShadow1.visibility = VISIBLE
            groupIconShadow2.visibility = VISIBLE
            iconView.visibility = INVISIBLE

            val firstDate = DateUtils.formatDayMonth(item.profitItems.first().timestamp)
            val lastDate = DateUtils.formatDayMonth(item.profitItems.last().timestamp)
            itemDateLabel.text = "$firstDate…$lastDate"
        } else {
            groupIcon.visibility = GONE
            groupIconShadow1.visibility = GONE
            groupIconShadow2.visibility = GONE
            iconView.visibility = VISIBLE

            itemDateLabel.text = DateUtils.formatDateAndTimeDotSeparated(item.timestamp)
        }

        if (isFirst) {
            totalProfitFormatted?.let {
                totalEarnedLabel.contentView.text =
                    "${LocaleController.getString("Earned")}: $totalProfitFormatted"
            } ?: run {
                totalEarnedLabel.contentView.text = null
            }
            historyTitleLabel.visibility = VISIBLE
            totalEarnedLabel.visibility = VISIBLE
        } else {
            historyTitleLabel.visibility = GONE
            totalEarnedLabel.visibility = GONE
        }

        setOnClickListener {
            onTap()
        }

        val amountCols = 4 + abs(item.timestamp.hashCode() % 8)
        amountLabel.setMaskCols(amountCols)
        val fiatAmountCols = 5 + (amountCols % 6)
        fiatValueLabel.setMaskCols(fiatAmountCols)
        amountLabel.isSensitiveData = true
        fiatValueLabel.isSensitiveData = true
    }

}
