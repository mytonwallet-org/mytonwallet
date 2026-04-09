package org.mytonwallet.app_air.uicomponents.extensions

import android.content.ClipboardManager
import android.content.Context
import android.content.Intent

fun Context.getTextFromClipboard(): String? {
    try {
        val clipboard = this.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = clipboard.primaryClip
        return if (clipData != null && clipData.itemCount > 0) {
            clipData.getItemAt(0).text?.toString()
        } else {
            null
        }
    } catch (_: Throwable) {
        return null
    }
}

fun Context.startActivityCatching(intent: Intent) {
    runCatching { startActivity(intent) }
}
