package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.resize
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

@SuppressLint("ViewConstructor")
class ExploreLargeConnectedItemCell(
    context: Context,
    cellWidth: Int,
    private val onDAppTap: (site: ApiDapp?) -> Unit,
) :
    WCell(context, LayoutParams(cellWidth, WRAP_CONTENT)),
    WThemedView {

    private val ripple = WRippleDrawable.create(16f.dp)

    init {
        background = ripple
    }

    private val imagePadding = 4

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(16f.dp)
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(12f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
    }

    private val imageWidth = cellWidth - 12.dp

    override fun setupViews() {
        super.setupViews()

        addView(imageView, LayoutParams(imageWidth, imageWidth))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toCenterX(imageView, imagePadding.toFloat())
            toTop(imageView, imagePadding.toFloat())
            topToBottom(titleLabel, imageView, 6f)
            toBottom(titleLabel, 6f)
            toCenterX(titleLabel, 1f)
        }

        setOnClickListener {
            onDAppTap(dApp)
        }
    }

    private var dApp: ApiDapp? = null
    fun configure(dApp: ApiDapp?) {
        this.dApp = dApp
        dApp?.let {
            imageView.background = null
            dApp.iconUrl?.let { iconUrl ->
                imageView.set(Content.ofUrl(iconUrl))
            } ?: run {
                imageView.clear()
            }
            titleLabel.text = dApp.name
        } ?: run {
            imageView.setBackgroundColor(WColor.Background.color, 16f.dp)
            imageView.scaleType = ImageView.ScaleType.CENTER_INSIDE
            val drawable = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_details
            )!!
            imageView.setImageDrawable(
                drawable.resize(context, 30.dp, 30.dp, WColor.SecondaryText.color)
            )
            titleLabel.text = LocaleController.getString("Settings")
        }
        updateTheme()
    }

    override fun updateTheme() {
        ripple.backgroundColor = Color.TRANSPARENT
        ripple.rippleColor = WColor.BackgroundRipple.color
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }
}
