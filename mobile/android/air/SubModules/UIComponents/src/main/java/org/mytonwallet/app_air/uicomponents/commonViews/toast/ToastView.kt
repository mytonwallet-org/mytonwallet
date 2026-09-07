package org.mytonwallet.app_air.uicomponents.commonViews.toast

import android.content.Context
import android.graphics.Color
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

class ToastView(context: Context) :
    WView(context),
    WThemedView {

    companion object {
        const val HEIGHT_DP = 56
        private const val CORNER_RADIUS_DP = HEIGHT_DP / 2f
        private const val ICON_SIZE_DP = 24
    }

    private val iconView = ImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }

    private val textLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(WColor.PrimaryText)
        gravity = Gravity.CENTER_VERTICAL
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
        useCustomEmoji = true
    }

    private val actionRipple = WRippleDrawable.create(16f.dp)

    private val actionLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        setTextColor(WColor.Tint)
        gravity = Gravity.CENTER
        setPaddingDp(8)
        background = actionRipple
    }

    private var glassView: WGlassView? = null
    private var blurRootView: ViewGroup? = null
    private var actionListener: (() -> Unit)? = null

    init {
        isClickable = true
        isFocusable = true
        setOnClickListener {}

        addView(iconView, LayoutParams(ICON_SIZE_DP.dp, ICON_SIZE_DP.dp))
        addView(
            actionLabel,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        )
        addView(
            textLabel,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.MATCH_CONSTRAINT)
        )

        setConstraints {
            toCenterY(iconView)
            toStart(iconView, 16f)

            toCenterY(actionLabel)
            toEnd(actionLabel, 10f)

            toCenterY(textLabel)
            startToEnd(textLabel, iconView, 16f)
            endToStart(textLabel, actionLabel)
        }

        actionLabel.setOnClickListener {
            actionListener?.invoke()
        }

        updateTheme()
    }

    fun configure(toast: ToastManager.Toast, onAction: (() -> Unit)?) {
        with(iconView) {
            isVisible = toast.iconResId != null
            setImageDrawable(
                toast.iconResId?.let { context.getDrawableCompat(it)?.mutate() }
            )
        }
        textLabel.text = toast.text
        with(actionLabel) {
            isVisible = toast.actionTitle != null
            text = toast.actionTitle
        }
        actionListener = onAction
        updateTheme()
    }

    fun attachBlurRoot(blurRootView: ViewGroup?) {
        if (this.blurRootView === blurRootView) {
            return
        }
        this.blurRootView = blurRootView
        glassView?.setupWith(blurRootView)
        updateTheme()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (glassView == null) {
            glassView = WGlassView.attachTo(
                this,
                CORNER_RADIUS_DP.dp,
                GlassProviders.legacy(WColor.SearchFieldBackground, shadow = true),
                blurRootView,
                flavor = GlassFlavor.FROSTED
            ).apply {
                liquidGlass = false
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
    }

    override fun updateTheme() {
        iconView.drawable?.setTint(WColor.PrimaryText.color)
        textLabel.updateTheme()
        actionLabel.updateTheme()
        actionRipple.rippleColor = WColor.TintRipple.color

        setBackgroundColor(Color.TRANSPARENT, CORNER_RADIUS_DP.dp, clipToBounds = true)
        glassView?.updateTheme()
    }
}
