package org.mytonwallet.app_air.uisettings.viewControllers.notificationSettings.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SwitchCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class NotificationSettingsHeaderCell(
    context: Context,
    onPushNotificationsCheckChanged: (isChecked: Boolean) -> Unit
) : WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    var pushNotificationsChecked: Boolean? = null
    private val pushNotificationsRow = SwitchCell(
        context,
        title = LocaleController.getString("Push Notifications"),
        isChecked = false,
        isFirst = ViewConstants.TOOLBAR_RADIUS > 0,
        isLast = true,
        onChange = { isChecked ->
            if (pushNotificationsChecked != isChecked) {
                onPushNotificationsCheckChanged(isChecked)
                pushNotificationsChecked = isChecked
            }
        })

    private val hintLabel = WLabel(context).apply {
        text = LocaleController.getStringWithKeyValues(
            "Select up to %count% wallets for notifications", listOf(
                Pair("%count%", "3")
            )
        )
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.Tint)
        setStyle(14f, WFont.DemiBold)
        setPaddingDp(20, 17, 20, 9)
    }

    override fun setupViews() {
        super.setupViews()

        addView(pushNotificationsRow, LayoutParams(MATCH_PARENT, 50.dp))
        addView(hintLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(pushNotificationsRow, 0f)
            topToBottom(hintLabel, pushNotificationsRow, ViewConstants.GAP.toFloat())
            toCenterX(hintLabel)
            toBottom(hintLabel)
        }
    }

    override fun updateTheme() {
        pushNotificationsRow.updateTheme()
        hintLabel.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
    }

    fun configure(isPushNotificationsChecked: Boolean, showHint: Boolean) {
        pushNotificationsChecked = isPushNotificationsChecked
        pushNotificationsRow.isChecked = isPushNotificationsChecked
        hintLabel.isGone = !showHint
        updateTheme()
    }

}
