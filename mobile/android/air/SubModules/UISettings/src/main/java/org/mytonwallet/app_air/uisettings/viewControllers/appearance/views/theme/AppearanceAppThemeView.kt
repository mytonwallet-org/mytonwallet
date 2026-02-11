package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.theme

import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class AppearanceAppThemeView(
    context: Context,
) : WView(context), WThemedView {

    private val titleLabel = HeaderCell(context).apply {
        configure(
            LocaleController.getString("Theme"),
            titleColor = WColor.Tint,
            HeaderCell.TopRounding.NORMAL
        )
    }

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val systemView = AppearanceAppThemeItemView(
        context,
        ThemeManager.THEME_SYSTEM,
    )
    private val lightView = AppearanceAppThemeItemView(
        context,
        ThemeManager.THEME_LIGHT,
    )
    private val darkView = AppearanceAppThemeItemView(
        context,
        ThemeManager.THEME_DARK,
    )

    private val themeView: WView by lazy {
        val v = WView(context)
        v.addView(systemView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(lightView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(darkView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(lightView)
            toLeft(lightView)
            leftToRight(systemView, lightView)
            leftToRight(darkView, systemView)
            toRight(darkView)
            toBottom(lightView)
            createHorizontalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                intArrayOf(lightView.id, systemView.id, darkView.id),
                null,
                ConstraintSet.CHAIN_SPREAD
            )
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(themeView, LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            toTop(titleLabel)
            toStart(titleLabel)
            topToBottom(themeView, titleLabel, 8f)
            toCenterX(themeView)
            toBottom(themeView, 20f)
        }

        updateTheme()
    }

    override val isTinted = true
    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        val theme = WGlobalStorage.getActiveTheme()
        arrayOf(systemView, lightView, darkView).forEach {
            it.isActive = theme == it.identifier
        }
    }

}
