package org.mytonwallet.app_air.uicomponents.helpers

import android.text.Editable
import android.text.TextWatcher
import android.text.style.RelativeSizeSpan
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils

class AmountTextWatcher(proportion: Float = 16f / 22f) : TextWatcher {
    private val span = RelativeSizeSpan(proportion)
    var decimals: Int? = null

    override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {

    }

    override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {

    }

    override fun afterTextChanged(s: Editable?) {
        val text = s ?: return

        for (i in text.indices) {
            if (text[i] == ',') {
                text.replace(i, i + 1, ".")
            }
        }

        val newText = text.toString().replaceFirst("^0+(?!$|\\.)".toRegex(), "")
        if (newText != text.toString()) {
            s.replace(0, s.length, newText)
        }

        CoinUtils.setSpanToFractionalPart(text, span)

        val decimal = decimals ?: return
        val index = text.lastIndexOf('.')
        if (index == -1 || text.length <= (index + decimal + 1)) {
            return
        }

        text.delete(index + decimal + 1, text.length)
    }
}
