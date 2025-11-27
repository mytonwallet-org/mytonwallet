package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class AppearancePaletteAndCardView(
    context: Context,
) : WView(context), WThemedView {
    var onCustomizePressed: (() -> Unit)? = null

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("Palette and Card")
        lbl.setStyle(16f, WFont.Medium)
        lbl
    }

    private val customizeImageView by lazy {
        AppCompatImageView(context).apply {
            setImageDrawable(
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.img_customize
                )
            )
        }
    }

    private val customizeLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setTextColor(WColor.PrimaryText)
            text = LocaleController.getString("Customize Wallet")
        }
    }

    private val customizeButton: FrameLayout by lazy {
        FrameLayout(context).apply {
            id = generateViewId()
            addView(customizeImageView, FrameLayout.LayoutParams(32.dp, 32.dp).apply {
                marginStart = 20.dp
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            })
            addView(customizeLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginStart = 72.dp
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            })
            setOnClickListener {
                onCustomizePressed?.invoke()
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(customizeButton, LayoutParams(MATCH_PARENT, 56.dp))

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            topToBottom(customizeButton, titleLabel, 17f)
            toCenterX(customizeButton)
            toBottom(customizeButton)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp
        )
        titleLabel.setTextColor(WColor.Tint.color)
        customizeButton.background = null
        customizeButton.addRippleEffect(
            WColor.BackgroundRipple.color,
            ViewConstants.BIG_RADIUS.dp
        )
    }

}
