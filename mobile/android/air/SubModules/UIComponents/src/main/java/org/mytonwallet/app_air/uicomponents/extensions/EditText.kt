package org.mytonwallet.app_air.uicomponents.extensions

import android.graphics.drawable.Drawable
import android.os.Build
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import org.mytonwallet.app_air.walletbasecontext.utils.getPrivateField
import java.lang.reflect.Field

fun EditText.setReadOnly() {
    isEnabled = false
    isFocusable = false
    isFocusableInTouchMode = false
    isCursorVisible = false
    setTextIsSelectable(false)
}

fun EditText.setTextIfDiffer(text: String?, selectionToEnd: Boolean = true) {
    if (this.text?.toString() == text) {
        return
    }

    this.setText(text)
    if (selectionToEnd) {
        try {
            text?.let { setSelection(it.length) }
        } catch (_: Throwable) {
        }
    }
}

// textCursorDrawableCompat specific

private fun getTextViewPrivateField(fieldName: String): Field =
    TextView::class.java.getPrivateField(fieldName)

private fun TextView.getEditorOrNull(): Any? = try {
    getTextViewPrivateField("mEditor").get(this)
} catch (_: Throwable) {
    null
}

private fun TextView.getCursorDrawableRes(): Int? = try {
    getTextViewPrivateField("mCursorDrawableRes").getInt(this)
} catch (_: Throwable) {
    null
}

private fun TextView.setCursorDrawableRes(value: Int) = runCatching {
    getTextViewPrivateField("mCursorDrawableRes").setInt(this, value)
}

var EditText.textCursorDrawableCompat: Drawable?
    set(value) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            textCursorDrawable = value
            return
        }

        val editor = getEditorOrNull() ?: return

        runCatching {
            val cursorDrawableField = editor.javaClass.getPrivateField("mCursorDrawable")
            val arr: Array<Drawable?>? = value?.let { arrayOf(it, it) }
            cursorDrawableField.set(editor, arr)
        }

        if (value != null) {
            setCursorDrawableRes(0)
        }
    }
    get() {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            textCursorDrawable
        } else {
            val editor = getEditorOrNull()
            val fromEditor = runCatching {
                val cursorDrawableField = editor?.javaClass?.getPrivateField("mCursorDrawable")
                @Suppress("UNCHECKED_CAST")
                (cursorDrawableField?.get(editor) as? Array<Drawable?>)?.firstOrNull()
            }.getOrNull()
            if (fromEditor != null) return fromEditor
            val cursorDrawableRes = getCursorDrawableRes() ?: 0
            if (cursorDrawableRes != 0) {
                AppCompatResources.getDrawable(context, cursorDrawableRes)
            } else {
                null
            }
        }
    }
