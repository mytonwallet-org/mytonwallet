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
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
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

    private val titleLabel = HeaderCell(context).apply {
        configure(LocaleController.getString("Palette and Card"), titleColor = WColor.Tint, HeaderCell.TopRounding.NORMAL)
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
        WRippleDrawable.create(0f, 0f, ViewConstants.BLOCK_RADIUS.dp, ViewConstants.BLOCK_RADIUS.dp)
            .apply {
                rippleColor = WColor.BackgroundRipple.color
            }

    private val customizeButton: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            background = rippleBackground
            addView(customizeIconView, FrameLayout.LayoutParams(40.dp, 35.dp).apply {
                marginStart = 20.dp
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            })
            addView(customizeLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                marginStart = 64.dp
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
        addView(customizeButton, LayoutParams(MATCH_PARENT, 50.dp))

        setConstraints {
            toTop(titleLabel)
            toCenterX(titleLabel)
            topToBottom(customizeButton, titleLabel)
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
            ViewConstants.BLOCK_RADIUS.dp
        )
        circleDrawable?.setTint(WColor.Tint.color)
        rippleBackground.rippleColor = WColor.BackgroundRipple.color
    }

}
