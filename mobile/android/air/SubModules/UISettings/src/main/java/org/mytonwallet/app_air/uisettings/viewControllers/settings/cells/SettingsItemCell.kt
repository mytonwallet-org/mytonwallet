package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color

interface ISettingsItemCell {
    fun configure(
        item: SettingsItem,
        value: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    )
}

class SettingsItemCell(context: Context) : WCell(context), ISettingsItemCell, WThemedView {

    private var isFirst = false
    private var isLast = false

    private val iconView: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
            setPadding(8.dp)
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            isHorizontalFadingEdgeEnabled = true
            isSelected = true
        }
    }

    private val valueLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl
    }

    private val separatorView = WBaseView(context)

    private val contentView = WView(context).apply {
        addView(iconView, LayoutParams(40.dp, 40.dp))
        addView(titleLabel)
        addView(valueLabel)
        addView(separatorView, LayoutParams(0, 1))

        setConstraints {
            toStart(iconView, 16f)
            toCenterY(iconView)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)
            toStart(titleLabel, 72f)
            toTop(titleLabel, 16f)
            endToStart(titleLabel, valueLabel, 8f)
            toEnd(valueLabel, 16f)
            toTop(valueLabel, 16f)
            toBottom(separatorView)
            toStart(separatorView, 72f)
            toEnd(separatorView, 16f)
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

        if (item.icon != null)
            iconView.setImageDrawable(ContextCompat.getDrawable(context, item.icon)?.apply {
                setTint(if (item.hasTintColor) WColor.Tint.color else WColor.SecondaryText.color)
            })
        else {
            iconView.setImageDrawable(null)
        }
        titleLabel.text = item.title
        valueLabel.text = value
        titleLabel.setTextColor(if (item.hasTintColor) WColor.Tint.color else WColor.PrimaryText.color)

        if (ThemeManager.uiMode.hasRoundedCorners) {
            separatorView.visibility = if (isLast) INVISIBLE else VISIBLE
        } else {
            separatorView.visibility = if (isLast && ThemeManager.isDark) INVISIBLE else VISIBLE
            contentView.setConstraints {
                toStart(separatorView, if (isLast) 0f else 72f)
                toEnd(separatorView, if (isLast) 0f else 16f)
            }
        }

        layoutParams.height = (56 + if (isLast) ViewConstants.GAP else 0).dp

        setOnClickListener {
            onTap()
        }

        updateTheme()
    }

    fun setSeparator(toStart: Float? = null, toEnd: Float? = null) {
        contentView.setConstraints {
            if (toStart != null)
                toStart(separatorView, toStart)
            if (toEnd != null)
                toEnd(separatorView, toEnd)
        }
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
        valueLabel.setTextColor(WColor.SecondaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
    }
}
