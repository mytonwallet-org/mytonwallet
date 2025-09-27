package org.mytonwallet.app_air.uiswap.screens.cex.receiveAddressInput.views

import android.content.Context
import android.os.Build
import android.util.TypedValue
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatEditText
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SwapInputView(context: Context) : FrameLayout(context), WThemedView {

    val editText = AppCompatEditText(context).apply {
        background = null
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        }

        typeface = WFont.Regular.typeface
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        setPaddingDp(20, 8, 20, 0)
    }

    init {
        minimumHeight = 52.dp

        addView(editText)
        updateTheme()
    }

    override fun updateTheme() {
        editText.setHintTextColor(WColor.SecondaryText.color)
        editText.setTextColor(WColor.PrimaryText.color)
    }
}
