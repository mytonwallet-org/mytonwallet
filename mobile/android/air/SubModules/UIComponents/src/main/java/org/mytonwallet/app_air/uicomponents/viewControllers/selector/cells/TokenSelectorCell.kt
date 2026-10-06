package org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import java.math.BigInteger
import kotlin.math.abs
import org.mytonwallet.app_air.uicomponents.commonViews.FiatCurrencyIconView
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.TokenNameHelper
import org.mytonwallet.app_air.uicomponents.helpers.TokenTagHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class TokenSelectorCell(context: Context) :
    WCell(context),
    WThemedView {

    private companion object {
        const val FIAT_RATE_PRECISION = 9
        const val DISABLED_ALPHA = 0.4f
    }

    enum class SecondaryAmountMode {
        BALANCE_VALUE,
        BALANCE_VALUE_OR_PRICE,
        TOKEN_PRICE
    }

    private val tagHelper = TokenTagHelper(context)

    private val iconView: IconView by lazy {
        val iv = IconView(context, 44.dp)
        iv
    }

    private val topLeftLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize(), WFont.Medium)
        lbl.setSingleLine()
        lbl.ellipsize = TextUtils.TruncateAt.END
        lbl.isHorizontalFadingEdgeEnabled = true
        lbl
    }

    private val bottomLeftLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    private val topRightLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(adaptiveFontSize())
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(0, 2, Gravity.END or Gravity.CENTER_VERTICAL)
        )
    }

    private val bottomRightLabel = WLabel(context).apply {
        setStyle(13f)
    }

    private val rightContainer: WView by lazy {
        WView(context).apply {
            id = generateViewId()
            addView(topRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            addView(bottomRightLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
            setConstraints {
                toTop(topRightLabel, 8f)
                toEnd(topRightLabel)
                toBottom(bottomRightLabel, 11f)
                toEnd(bottomRightLabel)
            }
        }
    }

    private val fiatIconView = FiatCurrencyIconView(context).apply {
        visibility = GONE
    }

    var onTap: ((tokenBalance: MTokenBalance) -> Unit)? = null
    var onFiatTap: ((currency: MBaseCurrency) -> Unit)? = null
    private var currency: MBaseCurrency? = null

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(iconView, LayoutParams(46.dp, 46.dp))
        addView(fiatIconView, LayoutParams(44.dp, 44.dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(tagHelper.tagLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(bottomLeftLabel)
        addView(rightContainer, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints {
            toTop(iconView, 8f)
            toBottom(iconView, 8f)
            toStart(iconView, 12f)
            toTop(fiatIconView, 8f)
            toBottom(fiatIconView, 8f)
            toStart(fiatIconView, 12f)
            toTop(topLeftLabel, 8f)
            toStart(topLeftLabel, 68f)
            startToEnd(tagHelper.tagLabel, topLeftLabel, 3f)
            centerYToCenterY(tagHelper.tagLabel, topLeftLabel)
            endToStart(tagHelper.tagLabel, rightContainer, 4f)
            toEnd(rightContainer, 16f)
            constrainedWidth(topLeftLabel.id, true)
            setHorizontalBias(topLeftLabel.id, 0f)
            setHorizontalBias(tagHelper.tagLabel.id, 0f)
            toBottom(bottomLeftLabel, 11f)
            toStart(bottomLeftLabel, 68f)
            endToStart(bottomLeftLabel, rightContainer, 4f)
            setHorizontalBias(bottomLeftLabel.id, 0f)
        }
        setOnClickListener {
            currency?.let {
                onFiatTap?.invoke(it)
                return@setOnClickListener
            }
            tokenBalance?.let {
                onTap?.invoke(it)
            }
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        tagHelper.onThemeChanged()
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        bottomRightLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var tokenBalance: MTokenBalance? = null
    private var isFirst = false
    private var isLast = false

    @SuppressLint("SetTextI18n")
    fun configure(
        tokenBalance: MTokenBalance,
        showChain: Boolean,
        isLast: Boolean,
        isFirst: Boolean = false,
        accountId: String? = null,
        showBalance: Boolean = true,
        secondaryAmountMode: SecondaryAmountMode = SecondaryAmountMode.BALANCE_VALUE,
        isSelectable: Boolean = true
    ) {
        this.tokenBalance = tokenBalance
        this.currency = null
        this.isFirst = isFirst
        this.isLast = isLast
        setSelectable(isSelectable)
        topLeftLabel.translationY = 0f
        topRightLabel.translationY = 0f
        updateTheme()
        iconView.visibility = VISIBLE
        fiatIconView.visibility = GONE
        topRightLabel.isSensitiveData = true

        val token = TokenStore.getToken(tokenBalance.token)

        iconView.config(token, showChain = showChain)

        topLeftLabel.text = token?.let { TokenNameHelper.getTokenName(it, tokenBalance) } ?: ""

        if (showBalance) {
            topRightLabel.visibility = VISIBLE

            val amountCols = 4 + abs(tokenBalance.token.hashCode() % 8)
            topRightLabel.setMaskCols(amountCols)
            topRightLabel.updateProtectedView(false)

            topRightLabel.contentView.setAmount(
                tokenBalance.amountValue,
                token?.decimals ?: 9,
                token?.symbol ?: "",
                token?.decimals ?: 9,
                smartDecimals = true,
                forceCurrencyToRight = true
            )

            val showsPrice = secondaryAmountMode == SecondaryAmountMode.BALANCE_VALUE_OR_PRICE &&
                tokenBalance.amountValue <= BigInteger.ZERO
            bottomRightLabel.text = if (showsPrice) {
                if ((token?.price ?: 0.0) > 0.0) {
                    "${LocaleController.getString("Price")}: ${tokenPriceText(token)}"
                } else {
                    tokenPriceText(token)
                }
            } else {
                "\u202D" + when (secondaryAmountMode) {
                    SecondaryAmountMode.TOKEN_PRICE -> tokenPriceText(token)

                    SecondaryAmountMode.BALANCE_VALUE, SecondaryAmountMode.BALANCE_VALUE_OR_PRICE ->
                        tokenBalance.toBaseCurrency?.toString(
                            token?.decimals ?: 9,
                            WalletCore.baseCurrency.sign,
                            WalletCore.baseCurrency.decimalsCount,
                            smartDecimals = true
                        ) ?: ""
                }
            }
        } else {
            topRightLabel.visibility = GONE

            bottomRightLabel.text = tokenPriceText(token)
            if (bottomRightLabel.textSize != topRightLabel.contentView.textSize) {
                bottomRightLabel.textSize = adaptiveFontSize()
            }
        }

        bottomLeftLabel.text = token?.mBlockchain?.displayName
            ?: token?.chain?.replaceFirstChar {
                if (it.isLowerCase()) it.titlecase() else it.toString()
            } ?: ""

        tagHelper.configure(this, topLeftLabel, rightContainer, accountId, token, tokenBalance)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        // Fiat rows have no second line, so their title and rate sit on the row's center line.
        val isFiat = currency != null
        topLeftLabel.translationY =
            if (isFiat) (height - topLeftLabel.height) / 2f - topLeftLabel.top else 0f
        topRightLabel.translationY =
            if (isFiat) (height - topRightLabel.height) / 2f - topRightLabel.top else 0f
    }

    fun configure(currency: MBaseCurrency, isLast: Boolean) {
        this.tokenBalance = null
        this.currency = currency
        this.isFirst = false
        this.isLast = isLast
        setSelectable(true)
        updateTheme()
        iconView.visibility = INVISIBLE
        fiatIconView.visibility = VISIBLE
        fiatIconView.configure(currency)
        topLeftLabel.text = if (currency == MBaseCurrency.RUB) {
            LocaleController.getString("Ruble")
        } else {
            currency.currencyName
        }
        bottomLeftLabel.text = ""
        requestLayout()
        val baseCurrency = WalletCore.baseCurrency
        val rate = TokenStore.currencyRates?.get(currency.currencyCode) ?: 0.0
        val baseRate = TokenStore.currencyRates?.get(baseCurrency.currencyCode) ?: 0.0
        topRightLabel.visibility = VISIBLE
        topRightLabel.isSensitiveData = false
        topRightLabel.updateProtectedView(false)
        topRightLabel.contentView.text = if (rate > 0) {
            (baseRate / rate).toString(
                FIAT_RATE_PRECISION,
                baseCurrency.sign,
                baseCurrency.decimalsCount,
                smartDecimals = true
            ) ?: ""
        } else {
            ""
        }
        bottomRightLabel.text = ""
        tagHelper.configure(this, topLeftLabel, rightContainer, null, null, null)
    }

    private fun setSelectable(isSelectable: Boolean) {
        isEnabled = isSelectable
        val alpha = if (isSelectable) 1f else DISABLED_ALPHA
        iconView.alpha = alpha
        topLeftLabel.alpha = alpha
        tagHelper.tagLabel.alpha = alpha
        bottomLeftLabel.alpha = alpha
        rightContainer.alpha = alpha
    }

    private fun tokenPriceText(token: MToken?): String = when (val tokenPrice = token?.price) {
        null -> ""

        0.0 -> LocaleController.getString("No Price")

        else -> tokenPrice.toString(
            token.decimals,
            WalletCore.baseCurrency.sign,
            WalletCore.baseCurrency.decimalsCount,
            smartDecimals = true
        ) ?: ""
    }
}
