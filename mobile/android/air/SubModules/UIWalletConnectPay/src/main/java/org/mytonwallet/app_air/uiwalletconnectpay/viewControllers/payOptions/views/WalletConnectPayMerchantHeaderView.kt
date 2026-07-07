package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.views

import android.annotation.SuppressLint
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.WcPayMerchant
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletConnectPayMerchantHeaderView(
    private val navigationController: WNavigationController,
) : WView(navigationController.context), WThemedView {

    companion object {
        private const val NAV_SIZE_OFFSET_DP = 8
        const val NAV_DEFAULT_HEIGHT_DP = WNavigationBar.DEFAULT_HEIGHT - NAV_SIZE_OFFSET_DP
        val navDefaultHeight = NAV_DEFAULT_HEIGHT_DP.dp
    }

    val contentHeight = 128.dp

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val iconView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(20f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Background)
    }

    private val nameLabel = WLabel(context).apply {
        setStyle(22f, WFont.Medium)
        gravity = Gravity.CENTER
    }

    private val domainLabel = WLabel(context).apply {
        setStyle(16f, WFont.Regular)
        gravity = Gravity.CENTER
    }

    override fun setupViews() {
        super.setupViews()

        addView(iconView, LayoutParams(80.dp, 80.dp))
        addView(nameLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            toTop(iconView)
            toCenterX(iconView)
            toTop(nameLabel)
            toCenterX(nameLabel)
        }

        updateTheme()
        updateScroll(0)
    }

    override fun updateTheme() {
        nameLabel.setTextColor(WColor.PrimaryText.color)
        domainLabel.setTextColor(WColor.Tint.color)
    }

    fun configure(merchant: WcPayMerchant) {
        iconView.set(Content.ofUrl(merchant.iconUrl ?: ""))
        nameLabel.text = merchant.name
    }

    private val calculatedMinHeight: Int
        get() = navigationController.getSystemBars().top + navDefaultHeight

    fun updateScroll(dy: Int) {
        layoutParams.height = calculatedMinHeight + max(0, contentHeight - dy)

        val collapseProgress = max(0f, min(1f, dy.toFloat() / contentHeight.toFloat()))
        val statusBarTop = navigationController.getSystemBars().top

        iconView.translationY = statusBarTop + 28.dp - dy.toFloat()
        iconView.alpha = 1 - collapseProgress
        domainLabel.alpha = 1 - collapseProgress

        nameLabel.translationY = statusBarTop +
            lerp(
                131f.dp,
                (navDefaultHeight - nameLabel.height) / 2f,
                collapseProgress
            )
        nameLabel.scaleX = lerp(1f, 16f / 22f, collapseProgress)
        nameLabel.scaleY = nameLabel.scaleX
    }
}
