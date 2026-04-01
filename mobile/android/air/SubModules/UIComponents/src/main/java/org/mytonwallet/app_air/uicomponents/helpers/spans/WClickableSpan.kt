package org.mytonwallet.app_air.uicomponents.helpers.spans

import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.View
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WClickableSpan(
    private val url: String,
    private val color: Int? = null,
    private val onClick: (String) -> Unit,
) : ClickableSpan() {
    override fun onClick(widget: View) {
        onClick(url)
    }

    override fun updateDrawState(ds: TextPaint) {
        super.updateDrawState(ds)
        ds.color = color ?: WColor.Tint.color
        ds.isUnderlineText = false
    }
}
