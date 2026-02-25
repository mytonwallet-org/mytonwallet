package org.mytonwallet.app_air.uicomponents.adapter.implementation.holders

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.adapter.BaseListHolder
import org.mytonwallet.app_air.uicomponents.adapter.implementation.Item
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import java.math.BigInteger
import kotlin.math.abs
import kotlin.math.roundToInt

class ListIconDualLineCell(context: Context) : FrameLayout(context), WThemedView {
    companion object {
        const val HEIGHT = 60
    }

    private val separatorDrawable = SeparatorBackgroundDrawable()
    private val ripple = WRippleDrawable.create(separatorDrawable)

    private val tokenImage = WCustomImageView(context).apply {
        layoutParams = LayoutParams(
            ApplicationContextHolder.adaptiveIconSize.dp,
            ApplicationContextHolder.adaptiveIconSize.dp,
            Gravity.START or Gravity.CENTER_VERTICAL
        ).apply {
            marginStart = 12.dp
        }
    }

    private val tokenTitle = WLabel(context).apply {
        layoutParams = LayoutParams(
            LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT
        ).apply {
            marginStart = ApplicationContextHolder.adaptiveContentStart.dp.roundToInt()
            topMargin = 9.dp
        }
        ellipsize = TextUtils.TruncateAt.END
        isSingleLine = true

        setStyle(ApplicationContextHolder.adaptiveFontSize, WFont.DemiBold)
        setTextColor(WColor.PrimaryText)
    }

    private val tokenSubtitle = WSensitiveDataContainer(
        WLabel(context).apply {
            ellipsize = TextUtils.TruncateAt.END
            isSingleLine = true

            setStyle(13f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
        },
        WSensitiveDataContainer.MaskConfig(
            4 + abs(tokenTitle.hashCode()) % 8,
            2,
            Gravity.START or Gravity.CENTER_VERTICAL
        )
    )

    init {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, HEIGHT.dp)
        background = ripple

        addView(tokenImage)
        addView(tokenTitle)
        addView(
            tokenSubtitle, LayoutParams(
                LayoutParams.WRAP_CONTENT,
                LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.START or Gravity.BOTTOM
                marginStart = ApplicationContextHolder.adaptiveContentStart.dp.roundToInt()
                bottomMargin = 10.dp
            })

        updateTheme()
    }

    fun configure(
        image: Content?,
        title: CharSequence?,
        subtitle: CharSequence?,
        isSensitiveData: Boolean,
        imageRounding: Float? = null,
    ) {
        if (imageRounding != null)
            tokenImage.defaultRounding = Content.Rounding.Radius(imageRounding)

        image?.let {
            tokenImage.set(image)
        } ?: run {
            tokenImage.clear()
        }

        val margin =
            (if (image != null) ApplicationContextHolder.adaptiveContentStart else 20f).dp.roundToInt()
        listOf(tokenTitle, tokenSubtitle).forEach { view ->
            (view.layoutParams as? MarginLayoutParams)?.apply {
                marginStart = margin
                view.layoutParams = this
            }
        }
        tokenTitle.text = title
        tokenSubtitle.contentView.text = subtitle
        tokenSubtitle.isSensitiveData = isSensitiveData
        updateTheme()
    }

    fun allowSeparator(separator: Boolean) {
        separatorDrawable.forceSeparator = separator
        separatorDrawable.allowSeparator = separator
    }

    fun configure(asset: MApiSwapAsset, balance: BigInteger, separator: Boolean) {
        tokenImage.set(Content.of(asset, showChain = false))
        tokenTitle.text = asset.name ?: asset.symbol

        if (balance > BigInteger.ZERO) {
            tokenSubtitle.contentView.setAmount(
                balance,
                asset.decimals,
                asset.symbol ?: "",
                asset.decimals,
                true
            )
        } else {
            tokenSubtitle.contentView.text = asset.symbol
        }

        separatorDrawable.forceSeparator = separator
        updateTheme()
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.BackgroundRipple.color
        separatorDrawable.invalidateSelf()
    }


    class Holder(parent: ViewGroup) :
        BaseListHolder<Item.IconDualLine>(ListIconDualLineCell(parent.context)) {
        private val view: ListIconDualLineCell = itemView as ListIconDualLineCell
        override fun onBind(item: Item.IconDualLine) {
            view.allowSeparator(item.allowSeparator)
            view.configure(item.image, item.title, item.subtitle, item.isSensitiveData)
        }
    }
}
