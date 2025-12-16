package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.WalletContextManager
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TemporaryAccountItemView(
    context: Context,
    title: CharSequence?,
    blockchain: MBlockchain,
    address: String,
    private val hasSeparator: Boolean,
) : FrameLayout(context), WThemedView {

    private val iconView: AccountIconView by lazy {
        AccountIconView(context, AccountIconView.Usage.VIEW_ITEM)
    }

    private val label = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(13f)
        applyFontOffsetFix = true
    }

    private val arrowView = AppCompatImageView(context)

    private val separatorView = if (hasSeparator) View(context) else null

    private val backgroundDrawable = WRippleDrawable.create(0f).apply {
        rippleColor = WColor.BackgroundRipple.color
    }

    init {
        background = backgroundDrawable
        addView(iconView, LayoutParams(36.dp, 36.dp).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            marginStart = 10f.dp.roundToInt()
            bottomMargin = if (hasSeparator) 1.5f.dp.roundToInt() else 0
        })
        addView(arrowView, LayoutParams(30.dp, 30.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            marginEnd = 8.dp
            bottomMargin = if (hasSeparator) 1.5f.dp.roundToInt() else 0
        })
        if (hasSeparator)
            addView(separatorView, LayoutParams(MATCH_PARENT, 7.dp).apply {
                gravity = Gravity.BOTTOM
            })
        title?.let {
            addView(label, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START
                topMargin = 9.dp
                bottomMargin = if (hasSeparator) 3.5f.dp.roundToInt() else 0
                marginStart = 58.dp
                marginEnd = 42.dp
            })
            addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START
                topMargin = 33.dp
                bottomMargin = if (hasSeparator) 3.5f.dp.roundToInt() else 0
                marginStart = 58.dp
                marginEnd = 42.dp
            })
            label.text = title
            subtitleLabel.text = buildSpannedString {
                append(address.formatStartEndAddress())
                updateDotsTypeface()
            }
        } ?: run {
            addView(label, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = 58.dp
                marginEnd = 42.dp
                bottomMargin = if (hasSeparator) 3.5f.dp.roundToInt() else 0
            })
            label.text = buildSpannedString {
                append(address.formatStartEndAddress(6, 6))
                updateDotsTypeface()
            }
        }
        iconView.config(title, address)
        updateTheme()
        setOnClickListener {
            WalletContextManager.delegate?.openASingleWallet(
                mapOf(blockchain.name to address),
                title?.toString()
            )
        }
    }

    override fun updateTheme() {
        backgroundDrawable.rippleColor = WColor.BackgroundRipple.color
        val drawable =
            ContextCompat.getDrawable(context, R.drawable.ic_menu_arrow_right)?.apply {
                setTint(WColor.PrimaryLightText.color)
            }
        arrowView.setImageDrawable(drawable)
        separatorView?.setBackgroundColor(WColor.SecondaryBackground.color)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec((56 + if (hasSeparator) 7 else 0).dp, MeasureSpec.EXACTLY)
        )
    }
}
