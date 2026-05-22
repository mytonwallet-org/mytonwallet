package org.mytonwallet.app_air.uicomponents.helpers

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

object ClipboardHelpers {
    fun copyToClipboard(context: Context, clip: ClipData): Boolean {
        val clipboard =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        if (clipboard == null) {
            showErrorToast(context)
            return false
        }
        return try {
            clipboard.setPrimaryClip(clip)
            true
        } catch (_: Throwable) {
            showErrorToast(context)
            false
        }
    }

    fun copyToClipboard(context: Context, label: CharSequence, text: CharSequence?): Boolean {
        return copyToClipboard(context, ClipData.newPlainText(label, text))
    }

    private fun showErrorToast(context: Context) {
        Toast.makeText(context, LocaleController.getString("Error"), Toast.LENGTH_SHORT).show()
    }
}
