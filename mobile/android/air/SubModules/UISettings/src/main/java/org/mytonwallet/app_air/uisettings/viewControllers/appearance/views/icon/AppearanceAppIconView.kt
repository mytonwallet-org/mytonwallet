/*package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.icon

import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.helpers.LauncherIconController
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class AppearanceAppIconView(
    applicationContext: Context,
) : WView(applicationContext), WThemedView {

    private val separatorBackgroundDrawable: SeparatorBackgroundDrawable by lazy {
        SeparatorBackgroundDrawable()
    }

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("App Icon")
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val airIconView = AppearanceAppIconItemView(
        applicationContext,
        LauncherIconController.LauncherIcon.AIR
    ) {
        updateIcons()
    }

    private val classicIconView = AppearanceAppIconItemView(
        applicationContext,
        LauncherIconController.LauncherIcon.CLASSIC
    ) {
        updateIcons()
    }

    private val iconView: WView by lazy {
        val v = WView(context)
        v.addView(airIconView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(classicIconView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(airIconView)
            toLeft(airIconView)
            leftToRight(classicIconView, airIconView)
            toRight(classicIconView)
            toBottom(airIconView)
            createHorizontalChain(
                ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                intArrayOf(airIconView.id, classicIconView.id),
                null,
                ConstraintSet.CHAIN_SPREAD
            )
        }
        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(iconView, LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            topToBottom(iconView, titleLabel, 24f)
            toCenterX(iconView)
            toBottom(iconView, 20f)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }

    private fun updateIcons() {
        airIconView.updateTheme()
        classicIconView.updateTheme()
    }

}
*/
