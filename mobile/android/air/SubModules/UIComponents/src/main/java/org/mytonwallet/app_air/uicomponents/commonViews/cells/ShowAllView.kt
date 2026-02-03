package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class ShowAllView(
    context: Context,
) : WFrameLayout(context), WThemedView {

    private val ripple = WRippleDrawable.create(0f)

    var onTap: (() -> Unit)? = null

    private var iconDrawable: Drawable? = null

    private val iconView = AppCompatImageView(context)

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setTextColor(WColor.PrimaryText)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    init {
        background = ripple
        addView(iconView, LayoutParams(28.dp, 28.dp).apply {
            marginStart = 20.dp
            gravity = Gravity.CENTER_VERTICAL
        })
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
            marginStart = 68.dp
            marginEnd = 20.dp
            gravity = Gravity.CENTER_VERTICAL
        })

        setOnClickListener {
            onTap?.invoke()
        }

        updateTheme()
    }

    fun configure(icon: Int, text: String) {
        iconDrawable = ContextCompat.getDrawable(context, icon)?.apply {
            setTint(WColor.SecondaryText.color)
        }
        iconView.setImageDrawable(iconDrawable)
        titleLabel.text = text
    }

    override fun updateTheme() {
        ripple.rippleColor = WColor.BackgroundRipple.color
        iconDrawable?.setTint(WColor.SecondaryText.color)
    }

}
