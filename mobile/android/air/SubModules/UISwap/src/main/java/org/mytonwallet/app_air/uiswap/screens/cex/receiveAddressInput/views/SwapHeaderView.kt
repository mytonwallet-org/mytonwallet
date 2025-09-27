package org.mytonwallet.app_air.uiswap.screens.cex.receiveAddressInput.views

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class SwapHeaderView(context: Context) : AppCompatTextView(context), WThemedView {
    init {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setPaddingDp(20, 16, 20, 8)
        typeface = WFont.Medium.typeface
        isSingleLine = true
        ellipsize = TextUtils.TruncateAt.END

        updateTheme()
    }

    override fun updateTheme() {
        setTextColor(WColor.PrimaryText.color)
    }
}
