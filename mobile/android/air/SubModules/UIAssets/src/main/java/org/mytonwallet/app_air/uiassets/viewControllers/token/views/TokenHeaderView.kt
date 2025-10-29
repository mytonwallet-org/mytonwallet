package org.mytonwallet.app_air.uiassets.viewControllers.token.views

import android.annotation.SuppressLint
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
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
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TokenHeaderView(
    val navigationController: WNavigationController,
    private val navigationBar: WNavigationBar,
    var token: MToken
) :
    WView(navigationController.context), WThemedView {

    companion object {
        private const val NAV_SIZE_OFFSET_DP = 8
        const val NAV_DEFAULT_HEIGHT_DP = WNavigationBar.DEFAULT_HEIGHT - NAV_SIZE_OFFSET_DP
        val navDefaultHeight = NAV_DEFAULT_HEIGHT_DP.dp
    }

    val contentHeight = 244.dp

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPadding(8.dp)
        btn.setOnClickListener {
            WMenuPopup.present(
                btn,
                listOfNotNull(
                    if (token.tokenAddress?.isNotEmpty() == true || token.cmcSlug != null)
                        WMenuPopup.Item(
                            R.drawable.ic_world,
                            LocaleController.getString("View on Explorer"),
                            true,
                        ) {
                            token.explorerUrl?.let {
                                open(it)
                            }
                        } else null,
                    token.cmcSlug?.let {
                        WMenuPopup.Item(
                            null,
                            "CoinMarketCap",
                            false,
                        ) {
                            open("https://coinmarketcap.com/currencies/${token.cmcSlug}")
                        }
                    },
                    WMenuPopup.Item(
                        null,
                        "CoinGecko",
                        false,
                    ) {
                        open("https://www.coingecko.com/coins/${token.name.lowercase()}")
                    },
                    WMenuPopup.Item(
                        null,
                        "GeckoTerminal",
                        false,
                    ) {
                        open("https://www.geckoterminal.com/?q=${token.symbol.lowercase()}")
                    },
                    WMenuPopup.Item(
                        null,
                        "DEX Screener",
                        false,
                    ) {
                        open("https://dexscreener.com/search?q=${token.name.lowercase()}")
                    }),
                aboveView = true
            )
        }
        btn
    }

    private val iconView = WCustomImageView(context).apply {
        chainSize = 30.dp
        chainSizeGap = 2f.dp
    }

    private val balanceContentView = WBalanceView(context).apply {
        primarySize = 36f
        decimalsSize = 30f
        typeface = WFont.NunitoExtraBold.typeface
        clipChildren = false
        clipToPadding = false
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
            protectContentLayoutSize = false
        )
    ).apply {
        clipChildren = false
        clipToPadding = false
    }

    private val equivalentLabel = WSensitiveDataContainer(WLabel(context).apply {
        layoutDirection = LAYOUT_DIRECTION_LTR
        setStyle(22f, WFont.Medium)
    }, WSensitiveDataContainer.MaskConfig(8, 3, Gravity.CENTER, protectContentLayoutSize = false))

    override fun setupViews() {
        super.setupViews()

        addView(iconView, LayoutParams(80.dp, 80.dp))
        addView(balanceView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(equivalentLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        iconView.set(Content.of(token = token, alwaysShowChain = true))

        setConstraints {
            toTopPx(iconView, navDefaultHeight + 24.dp)
            toCenterX(iconView)
            toTopPx(balanceView, navDefaultHeight + 125.dp)
            toCenterX(balanceView, 16f)
            constrainedWidth(balanceView.id, true)
            topToBottom(equivalentLabel, balanceView)
            toCenterX(equivalentLabel)
        }
        navigationBar.setTitle(token.name, false)
        navigationBar.addTrailingView(moreButton, LayoutParams(40.dp, 40.dp))

        updateTheme()

        reloadData()
        updateScroll(0)
    }

    override fun updateTheme() {
        updateBackgroundColor()
        balanceContentView.apply {
            typeface = WFont.NunitoExtraBold.typeface
        }
        equivalentLabel.contentView.setTextColor(WColor.SubtitleText.color)
        val moreDrawable =
            ContextCompat.getDrawable(
                context,
                R.drawable.ic_more
            )?.apply {
                setTint(WColor.SecondaryText.color)
            }
        moreButton.setImageDrawable(moreDrawable)
        moreButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)
    }

    private val calculatedMinHeight: Int
        get() = navigationController.getSystemBars().top +
            navDefaultHeight

    fun updateScroll(dy: Int) {
        val iconViewLayoutParams = iconView.layoutParams as LayoutParams
        iconViewLayoutParams.topMargin = calculatedMinHeight + 24.dp - dy
        iconView.layoutParams = iconViewLayoutParams
        layoutParams.height = calculatedMinHeight + max(0, contentHeight - dy)

        val collapseProgress = max(0f, min(1f, dy.toFloat() / 232.dp))

        navigationBar.titleLabel.translationY =
            min(0f, -dy.toFloat())
        val balanceLayoutParams = balanceView.layoutParams as LayoutParams
        balanceLayoutParams.topMargin = calculatedMinHeight +
            if (dy < 0) 124.dp - dy else
                ((-70.5f).dp + (1 - collapseProgress) * 194.5f.dp).roundToInt()
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

        if (ThemeManager.uiMode.hasRoundedCorners)
            return
        val newAlpha = min(
            1f,
            (contentHeight - dy + 92.dp) / ViewConstants.GAP.dp.toFloat()
        )
        updateBackgroundColor(newAlpha)
    }

    private var backgroundAlpha = 1f
    private fun updateBackgroundColor(newAlpha: Float? = null) {
        backgroundAlpha = newAlpha ?: backgroundAlpha
        if (!ThemeManager.uiMode.hasRoundedCorners && backgroundAlpha > 0)
            setBackgroundColor(WColor.Background.color.colorWithAlpha((backgroundAlpha * 255).toInt()))
        else
            background = null
    }

    private var prevBalance: BigInteger? = null
    fun reloadData() {
        token = TokenStore.getToken(token.slug) ?: token
        val balance =
            BalanceStore.getBalances(AccountStore.activeAccountId!!)?.get(token.slug)
                ?: BigInteger.ZERO
        balanceContentView.animateText(
            AnimateConfig(
                balance,
                token.decimals,
                token.symbol,
                prevBalance != null,
                forceCurrencyToRight = true
            )
        )
        prevBalance = balance
        val balanceInBaseCurrency =
            balance?.let { balance ->
                token.price?.let { tokenPrice ->
                    balance.doubleAbsRepresentation(token.decimals) * tokenPrice
                }
            }
        equivalentLabel.contentView.text = balanceInBaseCurrency?.toString(
            WalletCore.baseCurrency.decimalsCount,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            true
        )
    }

    private fun open(url: String) {
        val nav = WNavigationController(navigationController.window)
        nav.setRoot(
            InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(url, injectTonConnectBridge = true)
            )
        )
        navigationController.window.present(nav)
    }
}
