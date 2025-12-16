package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.commonViews.AccountIconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SettingsShowAllAccountsCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, 56.dp)), ISettingsItemCell,
    WThemedView {
    private val icon1 by lazy {
        AccountIconView(context, AccountIconView.Usage.THUMB)
    }

    private val icon2 by lazy {
        AccountIconView(context, AccountIconView.Usage.THUMB)
    }

    private val icon3 by lazy {
        AccountIconView(context, AccountIconView.Usage.THUMB)
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
        }
    }

    private val separatorView = WBaseView(context)

    private val contentView = WView(context).apply {
        clipChildren = false
        clipToPadding = false
        addView(icon3, LayoutParams(28.dp, 28.dp))
        addView(icon2, LayoutParams(28.dp, 28.dp))
        addView(icon1, LayoutParams(28.dp, 28.dp))
        addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        addView(separatorView, LayoutParams(0, ViewConstants.SEPARATOR_HEIGHT))

        setConstraints {
            toStart(icon1)
            toStart(icon2)
            toStart(icon3)
            toCenterY(icon1)
            toCenterY(icon2)
            toCenterY(icon3)

            // Title
            toCenterY(titleLabel)
            toStart(titleLabel, 72f)
            setHorizontalBias(titleLabel.id, 0f)
            constrainedWidth(titleLabel.id, true)

            // Separator
            toStart(separatorView, 72f)
            toEnd(separatorView, 16f)
            toBottom(separatorView)
        }
    }

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
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
        showSeparator: Boolean,
        onTap: () -> Unit
    ) {
        val accounts = item.accounts!!
        setOnClickListener {
            onTap()
        }

        // Icons
        accounts.firstOrNull()?.let {
            icon1.isGone = false
            icon1.config(it)
            icon1.translationX = 10.dp + 6.25f.dp * (3 - accounts.size)
        } ?: run {
            icon1.isGone = true
        }
        accounts.getOrNull(1)?.let {
            icon2.isGone = false
            icon2.config(it)
            icon2.translationX = 22.dp + 6.25f.dp * (3 - accounts.size)
        } ?: run {
            icon2.isGone = true
        }
        accounts.getOrNull(2)?.let {
            icon3.isGone = false
            icon3.config(it)
            icon3.translationX = 34.dp + 6.25f.dp * (3 - accounts.size)
        } ?: run {
            icon3.isGone = true
        }

        titleLabel.text = item.title
        separatorView.visibility = if (isLast && ThemeManager.isDark) INVISIBLE else VISIBLE

        setOnClickListener {
            onTap()
        }

        updateTheme()
    }

    override fun updateTheme() {
        contentView.setBackgroundColor(WColor.Background.color)
        contentView.addRippleEffect(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(WColor.PrimaryText.color)
        separatorView.setBackgroundColor(WColor.Separator.color)
    }

}
