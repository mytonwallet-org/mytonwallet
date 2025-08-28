package org.mytonwallet.app_air.uicomponents.extensions

import android.content.ClipboardManager
import android.content.Context

fun Context.getTextFromClipboard(): String? {
    try {
        val clipboard = this.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clipData = clipboard.primaryClip
        return if (clipData != null && clipData.itemCount > 0) {
            clipData.getItemAt(0).text?.toString()
        } else {
            null
        }
    } catch (t: Throwable) {
        return null
    }
}
