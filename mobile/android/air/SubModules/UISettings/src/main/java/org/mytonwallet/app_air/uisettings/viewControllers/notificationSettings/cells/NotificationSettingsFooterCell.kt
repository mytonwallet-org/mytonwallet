package org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.cells

import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class NotificationSettingsFooterCell(
    context: Context,
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val soundsRow = SwitchCell(
        context,
        title = LocaleController.getString("Play Sounds"),
        isChecked = WGlobalStorage.getAreSoundsActive(),
        isFirst = true,
        isLast = true,
        onChange = { isChecked ->
            WGlobalStorage.setAreSoundsActive(isChecked)
        })

    override fun setupViews() {
        super.setupViews()

        addView(soundsRow, LayoutParams(MATCH_PARENT, 50.dp))
        setConstraints {
            toTop(soundsRow, ViewConstants.GAP.toFloat())
            toBottom(soundsRow, ViewConstants.GAP.toFloat())
        }
    }

    override fun updateTheme() {
        soundsRow.updateTheme()
    }

    fun configure() {
        updateTheme()
    }

}
