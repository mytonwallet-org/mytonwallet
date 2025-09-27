package org.mytonwallet.app_air.uisend.send.lauouts

import android.content.Context
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setConstraints
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ConfirmAmountView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0
) : ConstraintLayout(context, attrs, defStyle), WThemedView {

    private val tokenIconView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(32.dp, 32.dp)
        chainSize = 12.dp
        chainSizeGap = 1f.dp
    }

    private val tokenAmountTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        typeface = WFont.Medium.typeface
        ellipsize = TextUtils.TruncateAt.END
        isSingleLine = true
        maxLines = 1
    }

    private val tokenFiatAmountTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        typeface = WFont.Regular.typeface
        ellipsize = TextUtils.TruncateAt.END
        isSingleLine = true
        maxLines = 1
    }

    private val feeAmountTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        typeface = WFont.Regular.typeface
        ellipsize = TextUtils.TruncateAt.END
        isSingleLine = true
        maxLines = 1
    }

    init {
        id = generateViewId()
        layoutDirection = LAYOUT_DIRECTION_LTR

        addView(tokenIconView)
        addView(tokenAmountTextView)
        addView(tokenFiatAmountTextView)
        addView(feeAmountTextView)

        setConstraints {
            toStart(tokenIconView, 20f)
            toTop(tokenIconView, 8f)

            centerYToCenterY(tokenAmountTextView, tokenIconView)
            startToEnd(tokenAmountTextView, tokenIconView, 8f)
            toEnd(tokenAmountTextView, 20f)

            topToBottom(tokenFiatAmountTextView, tokenIconView, 16f)
            toStart(tokenFiatAmountTextView, 20f)
            endToStart(tokenFiatAmountTextView, feeAmountTextView, 8f)
            toBottom(tokenFiatAmountTextView, 16f)

            topToBottom(feeAmountTextView, tokenIconView, 16f)
            toEnd(feeAmountTextView, 20f)
            toBottom(feeAmountTextView, 16f)
        }

        updateTheme()
    }

    fun set(
        token: Content,
        amount: CharSequence?,
        currency: CharSequence?,
        fee: CharSequence?
    ) {
        tokenIconView.set(token)
        tokenAmountTextView.text = amount
        tokenFiatAmountTextView.text = currency
        feeAmountTextView.text = fee
    }

    override fun updateTheme() {
        tokenAmountTextView.setTextColor(WColor.PrimaryText.color)
        tokenFiatAmountTextView.setTextColor(WColor.SecondaryText.color)
        feeAmountTextView.setTextColor(WColor.SecondaryText.color)
    }
}
