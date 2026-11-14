package org.mytonwallet.app_air.uiassets.viewControllers.token.views

import android.annotation.SuppressLint
import android.net.Uri
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isInvisible
import androidx.core.view.setPadding
import java.math.BigInteger
import java.math.RoundingMode
import java.net.URI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.diamond.WBlueDiamondView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView.AnimateConfig
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.ShareHelpers
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.MApiTokenDetails
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenHeaderView(
    val navigationController: WNavigationController,
    private val navigationBar: WNavigationBar,
    private val accountId: String,
    var token: MToken,
    private val tokenInfoProvider: () -> MApiTokenDetails.TokenInfo? = { null }
) : WView(navigationController.context),
    WThemedView {

    companion object {
        const val NAV_DEFAULT_HEIGHT_DP = WNavigationBar.DEFAULT_HEIGHT
        val navDefaultHeight = NAV_DEFAULT_HEIGHT_DP.dp
        val navContentMarginTop = 2.dp
        private const val FULL_BALANCE_MORPH_DURATION = AnimationConstants.SUPER_QUICK_ANIMATION
        private const val DIAMOND_SIZE = 126
        private const val DIAMOND_MAX_GROW = 1.5f
        const val REVEAL_OFFSET = 10

        // Starts once the growing area fully uncovers the view.
        fun revealFraction(
            revealedBottom: Int,
            viewBottom: Int,
            fullBottom: Int,
            progress: Float
        ): Float {
            val start = viewBottom + REVEAL_OFFSET.dp
            if (start >= fullBottom) return progress
            return ((revealedBottom - start).toFloat() / (fullBottom - start)).coerceIn(0f, 1f)
        }
    }

    private val fullContentHeight = 244.dp

    val contentHeight: Int
        get() = (fullContentHeight * contentProgress).roundToInt()

    var contentProgress = 1f
        set(value) {
            if (field == value) return
            field = value
            updateContentAlpha()
        }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        updateContentAlpha()
    }

    private var scrollDy = 0

    private fun updateContentAlpha() {
        val revealedBottom = calculatedMinHeight + max(0, contentHeight - scrollDy)
        val fullBottom = calculatedMinHeight + max(0, fullContentHeight - scrollDy)
        reveal(iconView, revealedBottom, fullBottom, hidesUnderNav = true)
        reveal(balanceView, revealedBottom, fullBottom)
        reveal(equivalentLabel, revealedBottom, fullBottom)
        diamondView?.apply {
            alpha = iconView.alpha
            translationY = iconView.translationY
            isRenderingEnabled = alpha > 0.01f && iconView.bottom > 0
        }
    }

    private fun reveal(
        view: View,
        revealedBottom: Int,
        fullBottom: Int,
        hidesUnderNav: Boolean = false
    ) {
        val fraction = when {
            contentProgress >= 1f -> 1f
            contentProgress <= 0f || view.height <= 0 -> 0f
            view.top < calculatedMinHeight -> if (hidesUnderNav) 0f else contentProgress
            else -> revealFraction(revealedBottom, view.bottom, fullBottom, contentProgress)
        }
        view.alpha = fraction
        view.translationY = (1f - fraction) * REVEAL_OFFSET.dp
    }

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.id = UIComponentsR.id.token_more_button
        btn.setPadding(8.dp)
        btn.setOnMenuClickListener {
            val items = buildMoreMenuItems()
            if (items.isEmpty()) {
                return@setOnMenuClickListener
            }
            WMenuPopup.present(
                btn,
                items,
                positioning = WMenuPopup.Positioning.ALIGNED,
                backdropStyle = WMenuPopup.BackdropStyle.Transparent
            )
        }
        btn
    }

    init {
        navigationBar.addTrailingView(moreButton, LayoutParams(40.dp, 40.dp))
    }

    private fun buildMoreMenuItems(): List<WMenuPopup.Item> {
        val tokenInfo = tokenInfoProvider()
        val groups = mutableListOf<List<WMenuPopup.Item>>()
        val aggregatorItems = tokenInfo?.aggregatorLinks
            ?.mapNotNull { link ->
                link.url.validTokenMenuUrlOrNull()?.let { url ->
                    WMenuPopup.Item(null, link.name) { open(url) }
                }
            }
            .orEmpty()
        if (aggregatorItems.isNotEmpty()) {
            groups.add(aggregatorItems)
        }

        val tokenInfoItems = mutableListOf<WMenuPopup.Item>()
        tokenInfo?.docsUrl.validTokenMenuUrlOrNull()?.let { url ->
            tokenInfoItems.add(
                WMenuPopup.Item(null, LocaleController.getString("Documentation")) { open(url) }
            )
        }
        tokenInfo?.sourceCodeUrl.validTokenMenuUrlOrNull()?.let { url ->
            tokenInfoItems.add(
                WMenuPopup.Item(null, LocaleController.getString("Source Code")) { open(url) }
            )
        }
        if (tokenInfoItems.isNotEmpty()) {
            groups.add(tokenInfoItems)
        }

        val lastGroupItems = mutableListOf<WMenuPopup.Item>()
        token.explorerUrl(MBlockchainNetwork.ofAccountId(accountId))
            .validTokenMenuUrlOrNull()
            ?.let { url ->
                lastGroupItems.add(
                    WMenuPopup.Item(
                        R.drawable.ic_world,
                        LocaleController.getString("Open in Explorer")
                    ) {
                        open(url)
                    }
                )
            }
        lastGroupItems.add(
            WMenuPopup.Item(R.drawable.ic_share, LocaleController.getString("Share")) {
                shareLink()
            }
        )
        groups.add(lastGroupItems)

        return groups.flatMapIndexed { index, group ->
            if (index < groups.lastIndex) {
                group.last().hasSeparator = true
            }
            group
        }
    }

    private fun shareLink() {
        val uriBuilder = Uri.Builder()
            .scheme("https")
            .authority(ApplicationContextHolder.universalShortUrlHost)
            .appendPath("token")
        val chain = token.chain
        val tokenAddress = token.tokenAddress
        if (chain.isNotEmpty() && !tokenAddress.isNullOrEmpty()) {
            uriBuilder.appendPath(chain).appendPath(tokenAddress)
        } else {
            uriBuilder.appendPath(token.slug)
        }
        ShareHelpers.shareText(
            context,
            uriBuilder.build().toString(),
            LocaleController.getString("Share")
        )
    }

    private fun String?.validTokenMenuUrlOrNull(): String? {
        val value = this?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val uri = runCatching { URI(value) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase()
        return value.takeIf {
            (scheme == "http" || scheme == "https") && !uri.host.isNullOrBlank()
        }
    }

    private val iconView = WCustomImageView(context).apply {
        chainSize = 30.dp
        chainSizeGap = 2f.dp
    }

    private val diamondView = if (ApplicationContextHolder.isGramApp &&
        token.slug == TONCOIN_SLUG
    ) {
        WBlueDiamondView(context, DIAMOND_MAX_GROW)
    } else {
        null
    }

    private val balanceContentView = WBalanceView(context).apply {
        primarySize = 36f
        decimalsSize = 30f
        typeface = WFont.Balance.typeface
        clipChildren = false
        clipToPadding = false
        smartDecimalsColor = true
        setOnClickListener {
            showsFullBalance = !showsFullBalance
            reloadData(fastBalanceMorph = true)
        }
    }
    private val balanceView = WSensitiveDataContainer(
        AutoScaleContainerView(balanceContentView).apply {
            clipChildren = false
            clipToPadding = false
            maxAllowedWidth = navigationController.window.windowView.width - 34.dp
        },
        WSensitiveDataContainer.MaskConfig(
            16,
            4,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(144f, 36f, softwareSnapshot = true)
        )
    ).apply {
        clipChildren = false
        clipToPadding = false
    }

    private var showsFullBalance = false

    private val equivalentLabel = WSensitiveDataContainer(
        WLabel(context).apply {
            layoutDirection = LAYOUT_DIRECTION_LTR
            setStyle(22f, WFont.Medium)
        },
        WSensitiveDataContainer.MaskConfig(
            8,
            3,
            Gravity.CENTER,
            protectContentLayoutSize = false,
            hero = WSensitiveDataContainer.HeroConfig(182f, 26f, softwareSnapshot = true)
        )
    )

    override fun setupViews() {
        super.setupViews()

        addView(iconView, LayoutParams(80.dp, 80.dp))
        diamondView?.let {
            val canvasSize = (DIAMOND_SIZE * DIAMOND_MAX_GROW).dp.toInt()
            addView(it, LayoutParams(canvasSize, canvasSize))
            iconView.isInvisible = true
        }
        addView(balanceView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(equivalentLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        iconView.set(Content.of(token = token, showChain = true))

        setConstraints {
            toTopPx(iconView, navDefaultHeight + 24.dp)
            toCenterX(iconView)
            diamondView?.let { centerToCenter(it, iconView) }
            toTopPx(balanceView, navDefaultHeight + 125.dp)
            toCenterX(balanceView, 16f)
            constrainedWidth(balanceView.id, true)
            topToBottom(equivalentLabel, balanceView)
            toCenterX(equivalentLabel)
        }
        navigationBar.setTitle(token.displayName ?: token.name, false)
        if (token.localizedName != null) {
            navigationBar.titleLabel.setOnClickListener {
                WGlobalStorage.setUseLocalizedTokenNames(
                    !WGlobalStorage.getUseLocalizedTokenNames()
                )
                navigationBar.setTitle(token.displayName ?: token.name, true)
                WalletCore.notifyEvent(WalletEvent.TokensChanged)
            }
        }

        updateTheme()

        reloadData()
        updateScroll(0)
    }

    override fun updateTheme() {
        diamondView?.updatePlayback()
        balanceContentView.updateTheme()
        balanceContentView.apply {
            typeface = WFont.Balance.typeface
        }
        equivalentLabel.contentView.setTextColor(WColor.SubtitleText.color)
        val moreDrawable =
            context.getDrawableCompat(R.drawable.ic_more)?.apply {
                setTint(WColor.SecondaryText.color)
            }
        moreButton.setImageDrawable(moreDrawable)
        moreButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)
    }

    private val calculatedMinHeight: Int
        get() = navigationController.getSystemBars().top +
            navDefaultHeight

    fun updateScroll(dy: Int) {
        scrollDy = dy
        val iconViewLayoutParams = iconView.layoutParams as LayoutParams
        iconViewLayoutParams.topMargin = calculatedMinHeight + 24.dp - dy
        iconView.layoutParams = iconViewLayoutParams
        layoutParams.height = calculatedMinHeight + max(0, contentHeight - dy)

        updateTitle(dy)
        val scrollCollapseProgress = max(0f, min(1f, dy.toFloat() / 232.dp))
        // While the title crossfades, keep the balance in the nav so both move alike.
        val collapseProgress = if (isTitleCrossfading) {
            val fullHeaderWeight =
                contentProgress * contentProgress * contentProgress * contentProgress
            1f - (1f - scrollCollapseProgress) * fullHeaderWeight
        } else {
            scrollCollapseProgress
        }
        val balanceLayoutParams = balanceView.layoutParams as LayoutParams
        balanceLayoutParams.topMargin = calculatedMinHeight +
            if (dy < 0) {
                124.dp - dy
            } else {
                ((-74.5f).dp + (1 - collapseProgress) * 198.5f.dp).roundToInt()
            }
        balanceView.layoutParams = balanceLayoutParams
        balanceContentView.setScale(
            (18 + 18 * (1 - collapseProgress)) / 36f,
            (18 + 12 * (1 - collapseProgress)) / 30f,
            (-1.5f).dp * collapseProgress
        )
        balanceView.setMaskPivotYPercent(1f)
        balanceView.setMaskScale(0.5f + (1 - collapseProgress) / 2f)
        val equivalentLabelLayoutParams = equivalentLabel.layoutParams as LayoutParams
        equivalentLabelLayoutParams.topMargin =
            ((-2.5f).dp + (collapseProgress * (-14.5f).dp)).roundToInt()
        equivalentLabel.scaleX = (14 + 8 * (1 - collapseProgress)) / 22f
        equivalentLabel.scaleY = equivalentLabel.scaleX
        equivalentLabel.setMaskPivotYPercent(0f)
        equivalentLabel.setMaskScale(0.5f + (1 - collapseProgress) / 2f)
    }

    private var isTitleCrossfading = false

    private fun updateTitle(dy: Int) {
        val titleLabel = navigationBar.titleLabel
        val scrolledOffset = min(0f, -dy.toFloat())
        // A scrolled-away title crossfades instead of sliding through its clip.
        if (contentProgress < 1f && titleLabel.height > 0 && -scrolledOffset >= titleLabel.bottom) {
            isTitleCrossfading = true
            titleLabel.alpha = 1f - contentProgress
            titleLabel.translationY = -contentProgress * REVEAL_OFFSET.dp
            return
        }
        if (isTitleCrossfading) {
            isTitleCrossfading = false
            titleLabel.alpha = 1f
        }
        titleLabel.translationY = scrolledOffset * contentProgress
    }

    private var prevBalance: BigInteger? = null
    fun reloadData(fastBalanceMorph: Boolean = false) {
        token = TokenStore.getToken(token.slug) ?: token
        val balance =
            BalanceStore.getBalances(accountId)?.get(token.slug)
                ?: BigInteger.ZERO
        balanceContentView.animateText(
            AnimateConfig(
                balance,
                token.decimals,
                token.symbol,
                prevBalance != null,
                setInstantly = false,
                forceCurrencyToRight = true,
                decimalsCount = if (showsFullBalance) {
                    token.decimals
                } else {
                    balance.smartDecimalsCount(token.decimals, token.amountPrecision)
                },
                morphingDurationOverride =
                    if (fastBalanceMorph) FULL_BALANCE_MORPH_DURATION.toInt() else null,
                rounding = RoundingMode.DOWN
            )
        )
        prevBalance = balance
        val fallbackToUsd = token.symbol == WalletCore.baseCurrency.currencyCode
        val tokenPrice = if (fallbackToUsd) {
            token.priceUsd
        } else {
            token.price
        }
        val balanceInBaseCurrency =
            balance?.let { balance ->
                tokenPrice?.let { tokenPrice ->
                    balance.doubleAbsRepresentation(token.decimals) * tokenPrice
                }
            }
        val equivalentCurrency = if (fallbackToUsd) {
            MBaseCurrency.USD
        } else {
            WalletCore.baseCurrency
        }
        equivalentLabel.contentView.text = balanceInBaseCurrency?.toString(
            9,
            equivalentCurrency.sign,
            equivalentCurrency.decimalsCount,
            true
        )
    }

    private fun open(url: String) {
        val nav = WNavigationController(navigationController.window)
        nav.setRoot(
            InAppBrowserVC(
                context,
                InAppBrowserConfig(url, injectDappConnect = true)
            )
        )
        navigationController.window.present(nav)
    }
}
