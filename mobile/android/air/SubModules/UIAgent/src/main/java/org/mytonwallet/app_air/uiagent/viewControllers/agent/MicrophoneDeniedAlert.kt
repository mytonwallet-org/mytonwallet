package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

/** Dictation needs the microphone, which only the app's page in the device settings gives back once denied */
internal fun WViewController.showMicrophoneDeniedAlert() {
    showAlert(
        title = null,
        text = LocaleController.getString("\$agent_dictation_microphone_denied_device"),
        button = LocaleController.getString("Open Settings"),
        buttonPressed = { openAppSettings() },
        secondaryButton = LocaleController.getString("Cancel")
    )
}

private fun WViewController.openAppSettings() {
    val currentWindow = window ?: return
    try {
        currentWindow.startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", context.packageName, null)
            )
        )
    } catch (_: ActivityNotFoundException) {
        try {
            currentWindow.startActivity(Intent(Settings.ACTION_SETTINGS))
        } catch (_: ActivityNotFoundException) {
        }
    }
}
