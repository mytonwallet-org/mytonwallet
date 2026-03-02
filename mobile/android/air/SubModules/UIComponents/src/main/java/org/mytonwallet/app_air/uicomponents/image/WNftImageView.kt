package org.mytonwallet.app_air.uicomponents.image

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.appcompat.widget.AppCompatTextView
import androidx.core.view.isVisible
import androidx.core.widget.TextViewCompat
import com.facebook.drawee.generic.RoundingParams
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
@SuppressLint("ViewConstructor")
class WNftImageView(
    context: Context,
    private var noImageSize: Int,
    private var noImageLabelSpacing: Int,
    private var cornerRadius: Float = 12f.dp,
) : WFrameLayout(context), WThemedView {

    val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(cornerRadius)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
        layoutParams = LayoutParams(MATCH_PARENT, MATCH_PARENT)
    }

    private val placeholderViewDelegate = lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            layoutParams = LayoutParams(
                MATCH_PARENT,
                MATCH_PARENT
            )
            addView(placeholderIconView)
            addView(placeholderLabelView)
        }
    }
    private val placeholderView: LinearLayout by placeholderViewDelegate

    private val placeholderIconView: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            layoutParams = LinearLayout.LayoutParams(noImageSize, noImageSize)
        }
    }

    private val placeholderLabelView: AppCompatTextView by lazy {
        AppCompatTextView(context).apply {
            text = LocaleController.getString("No Image")
            typeface = WFont.NunitoExtraBold.typeface
            gravity = Gravity.CENTER

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)

            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            TextViewCompat.setAutoSizeTextTypeWithDefaults(
                this,
                TextViewCompat.AUTO_SIZE_TEXT_TYPE_UNIFORM
            )
            TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                this,
                5,
                9,
                1,
                TypedValue.COMPLEX_UNIT_SP
            )

            layoutParams = LinearLayout.LayoutParams(
                WRAP_CONTENT,
                WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = noImageLabelSpacing
                leftMargin = 2.dp
                rightMargin = 2.dp
            }
        }
    }

    init {
        addView(imageView)
        setRoundedOutline(cornerRadius)
    }

    fun setNftImage(imageUrl: String?, thumbnailUrl: String? = null) {
        val hasImage = !imageUrl.isNullOrEmpty()
        imageView.isVisible = hasImage
        if (hasImage) {
            imageView.set(Content.ofUrl(imageUrl), thumbnailUrl)
            if (placeholderViewDelegate.isInitialized()) placeholderView.isVisible = false
        } else {
            imageView.clear()
            val placeholder = placeholderView
            if (placeholder.parent == null) addView(placeholder)
            placeholder.isVisible = true
        }
    }

    fun setCornerRadius(radius: Float) {
        cornerRadius = radius
        setRoundedOutline(radius)
        imageView.hierarchy?.roundingParams = RoundingParams.fromCornersRadius(radius)
    }

    override fun updateTheme() {
        if (!placeholderViewDelegate.isInitialized()) return
        placeholderView.setBackgroundColor(WColor.SecondaryBackground.color)
        placeholderIconView.setImageResource(
            if (ThemeManager.isDark) org.mytonwallet.app_air.icons.R.drawable.img_nft_no_image_dark
            else org.mytonwallet.app_air.icons.R.drawable.img_nft_no_image_light
        )
        placeholderLabelView.setTextColor(WColor.SecondaryText.color)
    }
}

