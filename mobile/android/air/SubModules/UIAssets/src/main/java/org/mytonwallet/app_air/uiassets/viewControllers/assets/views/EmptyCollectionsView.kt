package org.mytonwallet.app_air.uiassets.viewControllers.assets.views

import WNavigationController
import android.annotation.SuppressLint
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

@SuppressLint("ViewConstructor")
class EmptyCollectionsView(window: WWindow) : WView(window), WThemedView {

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.text = LocaleController.getString("No NFTs yet")
        lbl.setStyle(17f, WFont.Medium)
        lbl
    }

    private val exploreButton: WLabel by lazy {
        val btn = WLabel(context)
        btn.textAlignment = TEXT_ALIGNMENT_CENTER
        btn.setStyle(14f)
        btn.setPadding(16.dp, 0, 16.dp, 0)

        btn.setOnClickListener {
            val navVC = WNavigationController(window)
            val browserVC = InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(
                    "https://getgems.io/",
                    title = "GetGems",
                    injectTonConnectBridge = true
                )
            )
            navVC.setRoot(browserVC)
            window.present(navVC)
        }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        addView(titleLabel)
        addView(exploreButton, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            toTop(titleLabel)
            toCenterX(titleLabel)
            topToBottom(exploreButton, titleLabel, 8f)
            toCenterX(exploreButton)
            toBottom(exploreButton)
        }

        updateTheme()
    }

    override fun updateTheme() {
        setExploreText()
        titleLabel.setTextColor(WColor.PrimaryText.color)
        exploreButton.setTextColor(WColor.Tint.color)
        exploreButton.addRippleEffect(WColor.TintRipple.color, 16f.dp)
    }

    private fun setExploreText() {
        val attr = SpannableStringBuilder()
        attr.append(SpannableString("${LocaleController.getString("\$nft_explore_offer")} ").apply {
            setSpan(
                WFont.Regular,
                0,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        })
        val drawable = ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_thin_24
        )!!
        drawable.mutate()
        drawable.setTint(WColor.Tint.color)
        val width = 16.dp
        val height = 24.dp
        drawable.setBounds(0, 0, width, height)
        val imageSpan = VerticalImageSpan(drawable, LocaleController.isRTL)
        attr.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        exploreButton.text = attr
    }

}
