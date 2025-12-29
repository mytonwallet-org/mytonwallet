package org.mytonwallet.app_air.uisettings.viewControllers.appearance.views.palette

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.commonViews.CardThumbnailView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MAccount
import kotlin.math.roundToInt

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

    private val cardThumbnailView = CardThumbnailView(context).apply {
        clipChildren = false
        clipToPadding = false
        rotation = -10f
        showBorder = true
    }

    private val circleDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.uicomponents.R.drawable.ic_customize_card
    )

    private val customizeIconView by lazy {
        FrameLayout(context).apply {
            addView(AppCompatImageView(context).apply {
                setImageDrawable(circleDrawable)
                scaleType = ImageView.ScaleType.FIT_XY
            }, LayoutParams(35.dp, 35.dp))
            addView(cardThumbnailView, LayoutParams(24.dp, 16.dp).apply {
                topMargin = 8.5f.dp.roundToInt()
                leftMargin = 10.dp
            })
        }
    }

    private val customizeLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setTextColor(WColor.PrimaryText)
            text = LocaleController.getString("Customize Wallet")
        }
    }

    private val rippleBackground =
        WRippleDrawable.create(0f, 0f, ViewConstants.BIG_RADIUS.dp, ViewConstants.BIG_RADIUS.dp)
            .apply {
                rippleColor = WColor.BackgroundRipple.color
            }

    private val customizeButton: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            background = rippleBackground
            addView(customizeIconView, FrameLayout.LayoutParams(40.dp, 35.dp).apply {
                marginStart = 18.dp
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

        clipChildren = false
        clipToPadding = false
        addView(titleLabel)
        addView(customizeButton, LayoutParams(MATCH_PARENT, 56.dp))

        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            topToBottom(customizeButton, titleLabel, 9f)
            toCenterX(customizeButton)
            toBottom(customizeButton)
        }

        updateTheme()
    }

    fun configure(account: MAccount?) {
        cardThumbnailView.configure(account, showDefaultCard = true)
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp
        )
        titleLabel.setTextColor(WColor.Tint.color)
        circleDrawable?.setTint(WColor.Tint.color)
        rippleBackground.rippleColor = WColor.BackgroundRipple.color
    }

}
