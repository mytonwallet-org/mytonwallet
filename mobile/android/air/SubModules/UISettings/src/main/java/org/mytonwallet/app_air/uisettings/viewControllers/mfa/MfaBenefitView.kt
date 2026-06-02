package org.mytonwallet.app_air.uisettings.viewControllers.mfa

import android.annotation.SuppressLint
import android.content.Context
import android.util.TypedValue
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.toProcessedSpannableStringBuilder

@SuppressLint("ViewConstructor")
class MfaBenefitView(
    context: Context,
    iconResId: Int?,
    markdownText: String,
) : WView(context), WThemedView {

    private val iconView = AppCompatImageView(context).apply {
        id = generateViewId()
        if (iconResId != null) {
            setImageDrawable(context.getDrawableCompat(iconResId))
        }
    }

    private val textLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(adaptiveFontSize())
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        text = markdownText.toProcessedSpannableStringBuilder()
    }

    init {
        addView(iconView, LayoutParams(32.dp, 32.dp))
        addView(textLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(iconView, 16f)
            toCenterY(iconView, 12f)
            startToEnd(textLabel, iconView, 16f)
            toTop(textLabel, 12f)
            toBottom(textLabel, 12f)
            toEnd(textLabel, 16f)
        }
        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        textLabel.setTextColor(WColor.PrimaryText.color)
    }
}
