package org.mytonwallet.app_air.uicomponents.commonViews.cells.activity

import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.moshi.ApiSwapStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import java.math.BigInteger
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.max

class ActivityAmountView(context: Context) : WFrameLayout(context), WThemedView, WProtectedView {

    private val amountLabel = WSensitiveDataContainer(
        WLabel(context).apply {
            setStyle(ApplicationContextHolder.adaptiveFontSize)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.MARQUEE
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
            applyFontOffsetFix = true
        },
        WSensitiveDataContainer.MaskConfig(
            0,
            2,
            (if (LocaleController.isRTL) Gravity.LEFT else Gravity.RIGHT) or Gravity.CENTER_VERTICAL
        )
    )

    private val mainIconView = WCustomImageView(context)
    private val borderView = View(context)
    private val secondIconView = WCustomImageView(context)

    init {
        addView(amountLabel)
        addView(mainIconView)
        addView(borderView)
        addView(secondIconView)
    }

    private fun updateViewOrder() {
        if (secondIconView.isVisible) {
            removeView(mainIconView)
            removeView(borderView)
            removeView(secondIconView)

            addView(mainIconView)
            addView(borderView)
            addView(secondIconView)
        }
    }

    fun configure(transaction: MApiTransaction.Transaction) {
        val amountCols =
            if (transaction.isNft || transaction.noAmountTransaction) 0 else 4 + abs(
                transaction.id.hashCode() % 8
            )
        amountLabel.setMaskCols(amountCols)

        val token = transaction.token
        if (token == null || transaction.isNft || transaction.noAmountTransaction) {
            amountLabel.contentView.text = ""
            mainIconView.clear()
            secondIconView.clear()
            return
        }

        val isStake = transaction.type == ApiTransactionType.STAKE
        amountLabel.contentView.setAmount(
            if (isStake) transaction.amount.abs() else transaction.amount,
            token.decimals,
            token.symbol,
            token.decimals,
            true,
            !isStake,
            forceCurrencyToRight = true,
        )
        amountLabel.maskView.skin =
            if (transaction.type == null && transaction.isIncoming) SensitiveDataMaskView.Skin.GREEN else null
        amountLabel.contentView.setTextColor(
            when {
                transaction.status == ApiTransactionStatus.FAILED -> WColor.Red.color
                transaction.type == ApiTransactionType.STAKE -> WColor.Purple.color
                transaction.type == ApiTransactionType.BURN -> WColor.Red.color
                (transaction.amount > BigInteger.ZERO) -> WColor.Green.color
                else -> WColor.PrimaryText.color
            }
        )
        mainIconView.set(Content.of(token, showChain = false))
        secondIconView.visibility = GONE
        borderView.visibility = GONE

        requestLayout()
    }

    fun configure(swap: MApiTransaction.Swap) {
        amountLabel.setMaskCols(4 + abs(swap.id.hashCode() % 8))
        amountLabel.maskView.skin = null

        val fromToken = swap.fromToken
        val toToken = swap.toToken
        if (fromToken == null || toToken == null) {
            amountLabel.contentView.text = ""
            mainIconView.clear()
            secondIconView.clear()
            return
        }
        val isFailed = swap.status == ApiSwapStatus.EXPIRED || swap.status == ApiSwapStatus.FAILED

        mainIconView.set(Content.of(fromToken, showChain = false))
        borderView.visibility = VISIBLE
        secondIconView.visibility = VISIBLE
        secondIconView.set(Content.of(toToken, showChain = false))
        updateViewOrder()

        val builder = SpannableStringBuilder()

        if (LocaleController.isRTL) {
            builder.append(
                swap.toAmount.toString(
                    decimals = toToken.decimals,
                    currency = toToken.symbol,
                    currencyDecimals = toToken.decimals,
                    smartDecimals = true,
                    forceCurrencyToRight = true
                )
            )
        } else {
            builder.append(
                swap.fromAmount.absoluteValue.toString(
                    decimals = fromToken.decimals,
                    currency = fromToken.symbol,
                    currencyDecimals = fromToken.decimals,
                    smartDecimals = true,
                    forceCurrencyToRight = true
                )
            )
        }

        ContextCompat.getDrawable(
            context,
            org.mytonwallet.app_air.walletcontext.R.drawable.ic_act_swap_done
        )?.let { drawable ->
            drawable.mutate()
            if (isFailed) {
                drawable.setTint(WColor.Red.color)
            }
            val width = 16.dp
            val height = 16.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable, LocaleController.isRTL)
            builder.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }

        val swapToStart = builder.length

        if (LocaleController.isRTL) {
            builder.append(
                swap.fromAmount.absoluteValue.toString(
                    decimals = fromToken.decimals,
                    currency = fromToken.symbol,
                    currencyDecimals = fromToken.decimals,
                    smartDecimals = true,
                    forceCurrencyToRight = true
                )
            )
        } else {
            builder.append(
                swap.toAmount.toString(
                    decimals = toToken.decimals,
                    currency = toToken.symbol,
                    currencyDecimals = toToken.decimals,
                    smartDecimals = true,
                    forceCurrencyToRight = true
                )
            )
        }
        if (isFailed) {
            builder.setSpan(
                ForegroundColorSpan(WColor.Red.color),
                0,
                builder.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        } else {
            builder.setSpan(
                ForegroundColorSpan(WColor.PrimaryLightText.color),
                0,
                builder.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            if (LocaleController.isRTL) {
                builder.setSpan(
                    ForegroundColorSpan(WColor.Green.color),
                    0,
                    swapToStart,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            } else {
                builder.setSpan(
                    ForegroundColorSpan(WColor.Green.color),
                    swapToStart,
                    builder.length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
        }
        amountLabel.contentView.text = builder

        requestLayout()
        updateTheme()
    }

    override fun updateTheme() {
        borderView.setBackgroundColor(WColor.Background.color, 20f.dp)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val totalAvailableWidth = MeasureSpec.getSize(widthMeasureSpec)
        val iconWidth = 18.dp
        val spacingBetweenViews = 4.dp
        val secondIconOffset = if (secondIconView.isVisible) 12.dp else 0
        val reservedWidth =
            paddingLeft + iconWidth + spacingBetweenViews + paddingRight + secondIconOffset

        val maxAmountLabelWidth = totalAvailableWidth - reservedWidth

        amountLabel.measure(maxAmountLabelWidth.atMost, 0.unspecified)
        mainIconView.measure(iconWidth.exactly, iconWidth.exactly)
        secondIconView.measure(iconWidth.exactly, iconWidth.exactly)

        val totalWidth = paddingLeft + amountLabel.measuredWidth + spacingBetweenViews +
            mainIconView.measuredWidth + paddingRight + secondIconOffset

        setMeasuredDimension(
            resolveSize(totalWidth, widthMeasureSpec),
            resolveSize(24.dp, heightMeasureSpec)
        )
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)

        if (LocaleController.isRTL) {
            val mainIconLeft = paddingLeft
            val mainIconRight = mainIconLeft + mainIconView.measuredWidth

            mainIconView.layout(
                mainIconLeft,
                (height - mainIconView.measuredHeight) / 2,
                mainIconRight,
                (height - mainIconView.measuredHeight) / 2 + mainIconView.measuredHeight
            )

            if (secondIconView.isVisible) {
                val secondIconLeft = mainIconLeft
                val secondIconRight = secondIconLeft + secondIconView.measuredWidth
                val secondIconTop = (height - secondIconView.measuredHeight) / 2

                secondIconView.layout(
                    secondIconLeft,
                    secondIconTop,
                    secondIconRight,
                    secondIconTop + secondIconView.measuredHeight
                )

                borderView.layout(
                    secondIconLeft - 1.dp,
                    secondIconTop - 1.dp,
                    secondIconRight + 1.dp,
                    secondIconTop + secondIconView.measuredHeight + 1.dp
                )

                val mainIconOverlapLeft = secondIconRight - 6.dp
                mainIconView.layout(
                    mainIconOverlapLeft,
                    (height - mainIconView.measuredHeight) / 2,
                    mainIconOverlapLeft + mainIconView.measuredWidth,
                    (height - mainIconView.measuredHeight) / 2 + mainIconView.measuredHeight
                )
            }

            val amountLabelLeft = if (secondIconView.isVisible) {
                mainIconView.right + 4.dp
            } else {
                mainIconRight + 4.dp
            }
            val amountLabelRight = width - paddingRight
            amountLabel.layout(
                amountLabelLeft,
                (height - amountLabel.measuredHeight) / 2 - 1.dp,
                amountLabelRight,
                (height - amountLabel.measuredHeight) / 2 + amountLabel.measuredHeight - 1.dp
            )
        } else {
            val amountLabelRight =
                max(
                    paddingLeft + amountLabel.measuredWidth,
                    width - paddingRight - mainIconView.measuredWidth - (if (secondIconView.isVisible) 16.dp else 4.dp)
                )
            amountLabel.layout(
                paddingLeft,
                (height - amountLabel.measuredHeight) / 2 - 1.dp,
                amountLabelRight,
                (height - amountLabel.measuredHeight) / 2 + amountLabel.measuredHeight - 1.dp
            )

            val mainIconLeft = amountLabelRight + 4.dp
            mainIconView.layout(
                mainIconLeft,
                (height - mainIconView.measuredHeight) / 2,
                mainIconLeft + mainIconView.measuredWidth,
                (height - mainIconView.measuredHeight) / 2 + mainIconView.measuredHeight
            )

            if (secondIconView.isVisible) {
                val secondIconLeft = mainIconView.right - 6.dp
                val secondIconTop = mainIconView.top
                borderView.layout(
                    secondIconLeft - 1.dp,
                    secondIconTop - 1.dp,
                    secondIconLeft + secondIconView.measuredWidth + 1.dp,
                    secondIconTop + secondIconView.measuredHeight + 1.dp
                )
                secondIconView.layout(
                    secondIconLeft,
                    secondIconTop,
                    secondIconLeft + secondIconView.measuredWidth,
                    secondIconTop + secondIconView.measuredHeight
                )
            }
        }
    }

    override fun updateProtectedView() {
        amountLabel.updateProtectedView()
    }

}
