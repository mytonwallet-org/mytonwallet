package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.text.TextUtils
import android.util.AttributeSet
import android.util.TypedValue
import android.view.ViewGroup
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.view.isVisible
import me.vkryl.android.AnimatorUtils
import me.vkryl.android.animatorx.BoolAnimator
import me.vkryl.core.fromTo
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ListExpandableTextCell @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : ViewGroup(context, attrs, defStyle), WThemedView {
    private val PADDING_HORIZONTAL = 6

    private val isExpanded = BoolAnimator(
        280L,
        AnimatorUtils.DECELERATE_INTERPOLATOR,
        false
    ) { state, value, changed, _ ->
        textViewFull.alpha = value
        textViewHidden.alpha = 1f - value
        moreButtonView.alpha = 1f - value
        if (changed) {
            moreButtonView.isEnabled = state != BoolAnimator.State.FALSE
            moreButtonView.isVisible = state != BoolAnimator.State.TRUE
            textViewHidden.isVisible = state != BoolAnimator.State.TRUE
            textViewFull.isVisible = state != BoolAnimator.State.FALSE
        }
        requestLayout()
    }

    private val ripple = WRippleDrawable.create(4f.dp)
    private val moreButtonView = AppCompatTextView(context).apply {
        setPaddingDp(PADDING_HORIZONTAL, 0, PADDING_HORIZONTAL, 0)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Regular.typeface
        text = LocaleController.getString("More")
        layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        background = ripple
    }

    private val textViewFull = CopyTextView(context).apply {
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Regular.typeface
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        isVisible = false
    }

    private val textViewHidden = AppCompatTextView(context).apply {
        setPaddingDp(
            CopyTextView.PADDING_HORIZONTAL,
            CopyTextView.PADDING_VERTICAL,
            CopyTextView.PADDING_HORIZONTAL,
            CopyTextView.PADDING_VERTICAL
        )
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = WFont.Regular.typeface
        ellipsize = TextUtils.TruncateAt.END
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        isSingleLine = true
        maxLines = 1
    }


    init {
        moreButtonView.setOnClickListener { isExpanded.animatedValue = !isExpanded.value }

        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        setPaddingDp(
            20 - CopyTextView.PADDING_HORIZONTAL,
            8 - CopyTextView.PADDING_VERTICAL,
            20 - CopyTextView.PADDING_HORIZONTAL,
            20 - CopyTextView.PADDING_VERTICAL
        )
        addView(textViewFull)
        addView(textViewHidden)
        addView(moreButtonView)
        updateTheme()
    }

    private var mLastKey: CharSequence? = null

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)

        val textWidth = width - paddingLeft - paddingRight

        moreButtonView.measure(0, 0)
        textViewFull.measure(textWidth.exactly, 0)

        /*if (textViewFull.text != mLastKey) {
            mLastKey = textViewFull.text
            mLastKey?.let { t ->
                textViewHidden.text = TextUtils.ellipsize(t, textViewFull.paint, textViewFull.measuredWidth - moreButtonView.measuredWidth - 8f.dp, TextUtils.TruncateAt.END)
            }
        }*/
        textViewHidden.measure((textWidth - moreButtonView.measuredWidth - 8.dp).exactly, 0)

        val currentHeight = fromTo(
            textViewHidden.measuredHeight,
            textViewFull.measuredHeight,
            isExpanded.floatValue
        )
        setMeasuredDimension(width, currentHeight + paddingTop + paddingBottom)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        textViewFull.layout(
            paddingLeft,
            paddingTop,
            paddingLeft + textViewFull.measuredWidth,
            paddingTop + textViewFull.measuredHeight
        )
        textViewHidden.layout(
            paddingLeft,
            paddingTop,
            paddingLeft + textViewHidden.measuredWidth,
            paddingTop + textViewHidden.measuredHeight
        )
        moreButtonView.layout(
            measuredWidth - paddingRight - moreButtonView.measuredWidth + CopyTextView.PADDING_HORIZONTAL.dp,
            paddingTop + CopyTextView.PADDING_VERTICAL.dp,
            measuredWidth - paddingRight + CopyTextView.PADDING_HORIZONTAL.dp,
            paddingTop + moreButtonView.measuredHeight + CopyTextView.PADDING_VERTICAL.dp
        )
    }

    override val isTinted = true
    override fun updateTheme() {
        textViewFull.setTextColor(WColor.PrimaryText.color)
        textViewHidden.setTextColor(WColor.PrimaryText.color)
        moreButtonView.setTextColor(WColor.Tint.color)

        ripple.rippleColor = WColor.TintRipple.color
    }

    fun setText(text: CharSequence) {
        textViewFull.text = text
        textViewHidden.text = text
    }

    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.ExpandableText>(ListExpandableTextCell(parent.context)) {
        private val view = itemView as ListExpandableTextCell

        override fun onBind(item: Item.ExpandableText) {
            view.isExpanded.forcedValue = false
            view.setText(item.text)
        }
    }
}
