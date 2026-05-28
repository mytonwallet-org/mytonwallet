package org.mytonwallet.app_air.uicomponents.widgets

import android.R
import android.annotation.SuppressLint
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Rect
import android.util.TypedValue
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputConnectionWrapper
import androidx.appcompat.widget.AppCompatEditText
import org.mytonwallet.app_air.uicomponents.helpers.EditTextTint
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
open class WEditText(
    context: Context,
    delegate: Delegate? = null,
    private val multilinePaste: Boolean,
) : AppCompatEditText(context), WThemedView {
    init {
        id = generateViewId()
        background = null
    }

    var nextFocusView: WeakReference<WEditText>? = null

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? {
        val ic = super.onCreateInputConnection(outAttrs)
        return if (multilinePaste)
            PasteInterceptingInputConnection(ic, true)
        else
            ic
    }

    interface Delegate {
        fun pastedMultipleLines()
    }

    val delegate: WeakReference<Delegate> = WeakReference(delegate)

    fun setStyle(size: Float, font: WFont? = null) {
        typeface = (font ?: WFont.Regular).typeface
        setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
    }

    override val isTinted = true
    override fun updateTheme() {
        setTextColor(if (textIsAcceptable) WColor.PrimaryText.color else WColor.Error.color)
        highlightColor = WColor.Tint.color.colorWithAlpha(51)
        EditTextTint.applyColor(this, WColor.Tint.color)
    }

    override fun onFocusChanged(focused: Boolean, direction: Int, previouslyFocusedRect: Rect?) {
        super.onFocusChanged(focused, direction, previouslyFocusedRect)
        if (focused)
            textIsAcceptable = true
    }

    var textIsAcceptable = true
        set(value) {
            field = value
            updateTheme()
        }

    override fun onTextContextMenuItem(id: Int): Boolean {
        if (multilinePaste && (id == R.id.paste || id == R.id.pasteAsPlainText)) {
            val clipboard: ClipboardManager =
                context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            if (clipboard != null && clipboard.hasText()) {
                val pasteData = clipboard.getText().toString();
                if (pasteData.contains("\n") || pasteData.contains(" ")) {
                    handlePaste(pasteData)
                    return true;
                }
            }
        }
        return super.onTextContextMenuItem(id)
    }

    fun handlePaste(pasteData: String) {
        val lines = pasteData.split("[\n ]".toRegex()).filter { it.isNotEmpty() }
            .toTypedArray()
        var currentEditText: WEditText = this
        for (line in lines) {
            currentEditText.setText(line)
            try {
                if (currentEditText.nextFocusView?.get() != null) {
                    currentEditText = currentEditText.nextFocusView?.get()!!

                } else {
                    break
                }
            } catch (e: Exception) {
                break
            }
        }
        if (lines.count() > 1) {
            hideKeyboard()
            delegate.get()?.pastedMultipleLines()
        }
    }

    private inner class PasteInterceptingInputConnection(
        target: InputConnection?,
        mutable: Boolean
    ) : InputConnectionWrapper(target, mutable) {

        override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
            if (multilinePaste && text != null && text.length > 5 &&
                (text.contains("\n") || text.contains(" "))
            ) {
                post {
                    handlePaste(text.toString())
                }
                return true
            }
            return super.commitText(text, newCursorPosition)
        }
    }
}
