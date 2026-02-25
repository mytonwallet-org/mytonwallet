package org.mytonwallet.app_air.uicomponents.widgets

import android.annotation.SuppressLint
import android.content.Context
import android.text.InputType
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import androidx.core.widget.doOnTextChanged
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WEditText.Delegate
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.constants.PossibleWords
import org.mytonwallet.app_air.walletcore.helpers.PrivateKeyHelper

@SuppressLint("SetTextI18n", "ViewConstructor")
class WWordInput(
    context: Context,
    number: Int,
    val delegate: Delegate,
) : WView(context, LayoutParams(0, 50.dp)), WThemedView {

    private val numberLabel: WLabel by lazy {
        val label = WLabel(context)
        label.text = "$number "
        label.textAlignment = TEXT_ALIGNMENT_TEXT_END
        label.setStyle(17F)
        label
    }

    private var textFieldIsLocked = false
    val textField: WEditText by lazy {
        val textField = WEditText(context, delegate = delegate, multilinePaste = true)
        textField.setStyle(17F)
        textField.setSingleLine(true)
        textField.setMaxLines(1)
        textField.setImeOptions(EditorInfo.IME_ACTION_NEXT)
        textField.inputType =
            InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
        textField.doOnTextChanged { _, _, _, _ ->
            if (textFieldIsLocked)
                return@doOnTextChanged
            val currentSelection = textField.selectionStart
            textFieldIsLocked = true
            textField.setText(textField.text.toString().lowercase())
            textField.setSelection(currentSelection)
            textFieldIsLocked = false
        }
        textField
    }

    override fun setupViews() {
        super.setupViews()

        addView(numberLabel)
        numberLabel.minWidth = 24.dp

        addView(textField, LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            toStart(numberLabel, 8f)
            toCenterY(numberLabel)
            startToEnd(textField, numberLabel)
            toEnd(textField, 8f)
            toCenterY(textField)
        }

        setOnClickListener {
            textField.requestFocus()
            textField.showKeyboard()
        }

        updateTheme()
    }

    override fun updateTheme() {
        numberLabel.setTextColor(WColor.SecondaryText.color)
        setBackgroundColor(WColor.Background.color, 10f.dp)
    }

    fun checkValue() {
        val inputValue = textField.text.toString().trim().lowercase()
        if (PrivateKeyHelper.isValidPrivateKeyHex(inputValue)) {
            textField.textIsAcceptable = true
            return
        }
        if (inputValue.isNotEmpty() &&
            !PossibleWords.All.contains(
                inputValue
            )
        ) {
            val suggestion = if (inputValue.isNotEmpty()) PossibleWords.All.firstOrNull {
                it.startsWith(inputValue)
            } else null
            if (suggestion != null) {
                textField.setText(suggestion)
                textField.textIsAcceptable = true
            } else {
                textField.textIsAcceptable = false
            }
        } else {
            textField.textIsAcceptable = true
        }
    }
}
