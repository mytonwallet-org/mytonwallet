package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import kotlin.math.abs
import kotlin.math.roundToInt

class SettingsAccountCell(context: Context) : WCell(context), ISettingsItemCell, WThemedView {

    private var isFirst = false
    private var isLast = false

    private val iconView: IconView by lazy {
        val iv = IconView(context, 40.dp)
        iv
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val badgeLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(11f, WFont.Medium)
            setTextColor(WColor.SecondaryText.color)
            setPadding(4.5f.dp.roundToInt(), 0, 4.5f.dp.roundToInt(), 0)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
        }
    }

    private val valueLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.gravity = Gravity.LEFT
        lbl.layoutDirection = LAYOUT_DIRECTION_LTR
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val separatorView = WBaseView(context)

    private val contentView = WView(context).apply {
        addView(iconView, LayoutParams(40.dp, 40.dp))
        addView(
            titleLabel,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        addView(
            badgeLabel,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        addView(
            subtitleLabel,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        addView(valueLabel)
        addView(separatorView, LayoutParams(0, 1))

        setConstraints {
            // Icon
            toStart(iconView, 12f)
            toCenterY(iconView)

            // Title
            toTop(titleLabel, 6f)
            toStart(titleLabel, 68f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            // Badge
            centerYToCenterY(badgeLabel, titleLabel)
            startToEnd(badgeLabel, titleLabel, 4f)

            // Value
            toTop(valueLabel, 16f)
            toEnd(valueLabel, 16f)
            setHorizontalBias(valueLabel.id, 1f)

            // Subtitle
            topToBottom(subtitleLabel, titleLabel)
            startToStart(subtitleLabel, titleLabel)
            endToStart(subtitleLabel, valueLabel, 4f)
            setHorizontalBias(subtitleLabel.id, 0f)
            constrainedWidth(subtitleLabel.id, true)

            // Separator
            toStart(separatorView, 68f)
            toEnd(separatorView, 16f)
            toBottom(separatorView)
        }
    }

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, 56.dp))
        setConstraints {
            toTop(contentView)
            toCenterX(contentView)
        }

        updateTheme()
    }

    override fun configure(
        item: SettingsItem,
        value: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    ) {
        this.isFirst = isFirst
        this.isLast = isLast

        if (item.identifier == SettingsItem.Identifier.ACCOUNT) {
            iconView.config(item.account!!)
        } else {
            throw Exception()
        }
        if (titleLabel.text != item.title) {
            titleLabel.text = item.title
            subtitleLabel.text =
                SpannableStringBuilder(item.account.firstAddress?.formatStartEndAddress()).apply {
                    updateDotsTypeface()
                }
            badgeLabel.text = item.account.accountType.badge
            badgeLabel.isGone = badgeLabel.text.isNullOrEmpty()
            contentView.setConstraints {
                val badgeWidth =
                    if (badgeLabel.isGone)
                        0
                    else
                        badgeLabel.paint.measureText(badgeLabel.text.toString()).roundToInt()
                endToStartPx(titleLabel, valueLabel, 16.dp + badgeWidth)
            }
        }
        if (valueLabel.contentView.text != value)
            valueLabel.contentView.text = value
        titleLabel.setTextColor(if (item.hasTintColor) WColor.Tint.color else WColor.PrimaryText.color)

        if (ThemeManager.uiMode.hasRoundedCorners) {
            separatorView.visibility = if (isLast) INVISIBLE else VISIBLE
        } else {
            separatorView.visibility = if (isLast && ThemeManager.isDark) INVISIBLE else VISIBLE
            contentView.setConstraints {
                toStart(separatorView, if (isLast) 0f else 68f)
                toEnd(separatorView, if (isLast) 0f else 16f)
            }
        }

        ((56 + if (isLast) ViewConstants.GAP else 0).dp).let {
            if (layoutParams.height != it)
                layoutParams.height = it
        }

        setOnClickListener {
            onTap()
        }

        updateTheme()

        valueLabel.isSensitiveData = true
        valueLabel.setMaskCols(8 + abs(item.title.hashCode()) % 8)
    }

    override fun updateTheme() {
        contentView.setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f.dp
        )
        contentView.addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BIG_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BIG_RADIUS.dp else 0f.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        badgeLabel.setBackgroundColor(WColor.SecondaryBackground.color, 8f.dp)
        badgeLabel.setTextColor(WColor.SecondaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        valueLabel.contentView.setTextColor(WColor.SecondaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
    }
}
