package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.content.pm.PackageManager
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.pm.PackageInfoCompat
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.DebugMenuHelpers
import org.mytonwallet.app_air.uicomponents.helpers.MultiTapDetector
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SettingsVersionCell(private val window: WWindow) : WCell(window), WThemedView {

    companion object {
        const val HEIGHT = 40
    }

    private val multiTapDetector = MultiTapDetector(
        requiredTaps = 5,
        timeoutMs = 1000L
    ) {
        presentDebugMenu()
    }

    private val lbl = WLabel(context).apply {
        setStyle(14f)
        text = try {
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionName = packageInfo.versionName ?: ""
            val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo).toString()
            LocaleController.getFormattedString(
                "MyTonWallet Air v%1$@ (%2$@)",
                listOf(versionName, versionCode)
            )
        } catch (e: PackageManager.NameNotFoundException) {
            ""
        }
        setOnClickListener {
            multiTapDetector.registerTap()
        }
        setOnLongClickListener {
            presentDebugMenu()
            return@setOnLongClickListener true
        }
    }

    init {
        super.setupViews()

        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, HEIGHT.dp)
        addView(lbl, LayoutParams(WRAP_CONTENT, HEIGHT.dp))
        setConstraints {
            allEdges(lbl)
        }

        updateTheme()
    }

    override fun updateTheme() {
        lbl.setTextColor(WColor.SecondaryText.color)
    }

    private fun presentDebugMenu() {
        DebugMenuHelpers.present(window, lbl)
    }
}
