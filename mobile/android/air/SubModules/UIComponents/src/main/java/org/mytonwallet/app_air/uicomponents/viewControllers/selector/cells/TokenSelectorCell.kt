package org.mytonwallet.app_air.uicomponents.viewControllers.selector.cells

import android.annotation.SuppressLint
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import android.content.Context
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.core.view.marginBottom
import org.mytonwallet.app_air.uicomponents.commonViews.IconView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.TokenTagHelper
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MTokenBalance
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import kotlin.math.abs
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TokenSelectorCell(context: Context) : WCell(context), WThemedView {

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

    private val bottomRightLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            layoutDirection = LAYOUT_DIRECTION_LTR
        }
    }

    private val rightContainer: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.END
            addView(topRightLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                topMargin = (-2.5f).dp.roundToInt()
                bottomMargin = 1.dp
            })
            addView(bottomRightLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
    }

    var onTap: ((tokenBalance: MTokenBalance) -> Unit)? = null

    init {
        layoutParams.apply {
            height = 60.dp
        }
        addView(iconView, LayoutParams(46.dp, 46.dp))
        addView(topLeftLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(tagHelper.tagLabel, LayoutParams(WRAP_CONTENT, 16.dp))
        addView(bottomLeftLabel)
        addView(rightContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(iconView, 8f)
            toBottom(iconView, 8f)
            toStart(iconView, 12f)
            toTop(topLeftLabel, 8f)
            toStart(topLeftLabel, 68f)
            startToEnd(tagHelper.tagLabel, topLeftLabel, 3f)
            centerYToCenterY(tagHelper.tagLabel, topLeftLabel)
            endToStart(tagHelper.tagLabel, rightContainer, 4f)
            toCenterY(rightContainer)
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
            tokenBalance?.let {
                onTap?.invoke(it)
            }
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.SecondaryBackground.color,
            0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        topLeftLabel.setTextColor(WColor.PrimaryText.color)
        tagHelper.onThemeChanged()
        topRightLabel.contentView.setTextColor(WColor.PrimaryText.color)
        bottomLeftLabel.setTextColor(WColor.SecondaryText.color)
        bottomRightLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var tokenBalance: MTokenBalance? = null
    private var isLast = false

    fun configure(
        tokenBalance: MTokenBalance,
        showChain: Boolean,
        isLast: Boolean,
        accountId: String? = null,
        showBalance: Boolean = true,
    ) {
        this.tokenBalance = tokenBalance
        this.isLast = isLast
        updateTheme()

        val token = TokenStore.getToken(tokenBalance.token)

        iconView.config(token, showChain = showChain)

        topLeftLabel.text = token?.name ?: ""

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

            bottomRightLabel.text = tokenBalance.toBaseCurrency?.toString(
                token?.decimals ?: 9,
                WalletCore.baseCurrency.sign,
                WalletCore.baseCurrency.decimalsCount,
                smartDecimals = true
            ) ?: ""
        } else {
            topRightLabel.visibility = GONE

            val priceText = when (val tokenPrice = token?.price) {
                null -> ""
                0.0 -> LocaleController.getString("No Price")
                else -> tokenPrice.toString(
                    token.decimals,
                    WalletCore.baseCurrency.sign,
                    WalletCore.baseCurrency.decimalsCount,
                    smartDecimals = true
                )
            }
            bottomRightLabel.text = priceText
            if (bottomRightLabel.textSize != topRightLabel.contentView.textSize)
                bottomRightLabel.textSize = adaptiveFontSize()
        }

        bottomLeftLabel.text = token?.mBlockchain?.displayName
            ?: token?.chain?.replaceFirstChar {
                if (it.isLowerCase()) it.titlecase() else it.toString()
            } ?: ""

        tagHelper.configure(this, topLeftLabel, topRightLabel, accountId, token, tokenBalance)
    }
}
