package org.mytonwallet.app_air.uicomponents.widgets

import android.content.Context
import java.math.BigInteger

class WAmountInput(
    context: Context,
    var maximumFractionDigits: Int,
) : WEditText(context, multilinePaste = false) {

    var maxLength: Int = 10
    private val onChange: () -> Unit

    init {
        onChange = { }
        inputType =
            android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
    }

    fun amountValue(): BigInteger {
        val parts = text.toString().replace(" ", "").split(".")
        val integerPart = parts[0]
        val fractionPart = (parts.getOrNull(1) ?: "").padEnd(maximumFractionDigits, '0')
            .take(maximumFractionDigits)
        return BigInteger(integerPart + fractionPart)
    }
}
