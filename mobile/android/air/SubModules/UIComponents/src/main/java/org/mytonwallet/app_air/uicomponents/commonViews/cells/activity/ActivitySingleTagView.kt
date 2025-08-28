package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.moshi.ApiNft

class ActivitySingleTagView(context: Context) : FrameLayout(context) {

    val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(12f.dp)
    }
    val titleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }
    val subtitleLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    init {
        id = generateViewId()

        addView(imageView, LayoutParams(56.dp, 56.dp))
        addView(titleLabel, LayoutParams(WRAP_CONTENT, 24.dp).apply {
            marginStart = 66.dp
            marginEnd = 12.dp
            topMargin = 8.dp
            gravity = Gravity.TOP or Gravity.START
        })
        addView(subtitleLabel, LayoutParams(WRAP_CONTENT, 24.dp).apply {
            marginStart = 66.dp
            marginEnd = 12.dp
            topMargin = 28.dp
            gravity = Gravity.TOP or Gravity.START
        })
    }

    fun configure(nft: ApiNft) {
        nft.image?.let {
            imageView.set(Content.ofUrl(it))
        } ?: run {
            imageView.clear()
        }
        titleLabel.text = nft.name
        subtitleLabel.text = nft.collectionName
        setBackgroundColor(
            WColor.TrinaryBackground.color,
            12f.dp,
            true
        )
        if (ThemeManager.isDark) {
            titleLabel.setTextColor(WColor.PrimaryText.color)
            subtitleLabel.setTextColor(WColor.PrimaryText.color.colorWithAlpha(179))
        } else {
            titleLabel.setTextColor(WColor.PrimaryDarkText.color)
            subtitleLabel.setTextColor(WColor.PrimaryDarkText.color)
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(56.dp, MeasureSpec.EXACTLY))
    }

}
