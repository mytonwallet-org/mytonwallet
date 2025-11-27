package org.mytonwallet.uihome.wallets

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.commonViews.RadialGradientView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class MiniCardView(context: Context) : WView(context), WThemedView {

    private var cardNft: ApiNft? = null

    private val imageView = WImageView(context, 12.dp).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
    }
    private val radialGradientView = RadialGradientView(context).apply {
        cornerRadius = 12f.dp
    }

    private val balanceView = WBalanceView(context).apply {
        currencySize = 16f
        primarySize = 18f
        decimalsSize = 13f
        typeface = WFont.NunitoExtraBold.typeface
    }

    private val balanceContainerView = WSensitiveDataContainer(
        AutoScaleContainerView(balanceView).apply {
            clipChildren = false
            clipToPadding = false
            minPadding = 12.dp
        },
        WSensitiveDataContainer.MaskConfig(
            6,
            2,
            Gravity.CENTER,
            skin = SensitiveDataMaskView.Skin.DARK_THEME,
            protectContentLayoutSize = false
        )
    ).apply {
        clipChildren = false
        clipToPadding = false
    }

    private val addressLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(11f, WFont.Medium)
            paint.letterSpacing = 0.031f
        }
    }

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f.dp
    }

    private val containerView by lazy {
        WView(context).apply {
            addView(imageView, LayoutParams(0, 0))
            addView(radialGradientView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(balanceContainerView, LayoutParams(0, MATCH_PARENT))
            addView(addressLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

            setConstraints {
                allEdges(imageView)
                toCenterX(balanceContainerView)
                toTop(balanceContainerView, -4f)
                toBottom(balanceContainerView, 4f)
                toCenterX(addressLabel)
                toBottom(addressLabel, 6f)
            }

            setBackgroundColor(Color.TRANSPARENT, 12f.dp, clipToBounds = true)
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(containerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        updateTheme()
    }

    override fun updateTheme() {
        borderPaint.color = WColor.Tint.color
        cardNft?.let {
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second)
            return
        }
        setLabelColors(Color.WHITE, Color.WHITE)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)

        balanceContainerView.contentView.maxAllowedWidth = w - 8.dp
    }

    private var account: MAccount? = null
    fun configure(account: MAccount) {
        this.account = account
        updateCardImage()
        val balance = BalanceStore.totalBalanceInBaseCurrency(account.accountId)
        balanceView.animateText(
            WBalanceView.AnimateConfig(
                balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                false,
                LocaleController.isRTL
            )
        )
        setPadding(if (account.accountId == AccountStore.activeAccountId) 3.dp else 1.dp)
    }

    fun notifyBalanceChange() {
        val accountId = account?.accountId ?: return
        val baseCurrency = WalletCore.baseCurrency
        val balance = BalanceStore.totalBalanceInBaseCurrency(accountId)
        balanceView.animateText(
            WBalanceView.AnimateConfig(
                balance?.toBigInteger(baseCurrency.decimalsCount),
                baseCurrency.decimalsCount,
                baseCurrency.sign,
                true,
                LocaleController.isRTL
            )
        )
    }

    fun updateCardImage() {
        cardNft =
            account?.accountId?.let { activeAccountId ->
                WGlobalStorage.getCardBackgroundNft(activeAccountId)
                    ?.let { ApiNft.fromJson(it) }
            }
        updateTheme()

        if (cardNft == null) {
            imageView.loadRes(org.mytonwallet.app_air.uicomponents.R.drawable.img_card)
            radialGradientView.visibility = GONE
            return
        }
        if (cardNft?.metadata?.mtwCardType == ApiMtwCardType.STANDARD) {
            radialGradientView.isTextLight =
                cardNft?.metadata?.mtwCardTextType == ApiMtwCardTextType.LIGHT
            radialGradientView.visibility = VISIBLE
        } else {
            radialGradientView.visibility = GONE
        }
        imageView.hierarchy.setPlaceholderImage(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uicomponents.R.drawable.img_card
            )
        )
        imageView.loadUrl(cardNft?.metadata?.cardImageUrl(false) ?: "")
    }

    private fun setLabelColors(primaryColor: Int, secondaryColor: Int) {
        var textShader: LinearGradient?
        cardNft?.let {
            balanceView.alpha = 0.95f
            textShader = LinearGradient(
                0f, 0f,
                width.toFloat(), 0f,
                intArrayOf(
                    secondaryColor,
                    primaryColor,
                    secondaryColor,
                ),
                null, Shader.TileMode.CLAMP
            )
        } ?: run {
            balanceView.alpha = 1f
            textShader = null
        }
        balanceView.updateColors(primaryColor, secondaryColor.colorWithAlpha(191))
        addressLabel.setTextColor(secondaryColor.colorWithAlpha(204))
        if (textShader == null) {
            addressLabel.paint.shader = null
        } else {
            addressLabel.paint.shader = textShader
            addressLabel.invalidate()
        }
        updateAddressLabel()
    }

    private fun updateAddressLabel() {
        val addressSpannableString = SpannableStringBuilder()
        val isMultichain = account?.isMultichain == true
        if (account?.isViewOnly == true || account?.isHardware == true) {
            val drawable = ContextCompat.getDrawable(
                context,
                if (account?.isHardware == true)
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger
                else
                    org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye
            )!!
            drawable.mutate()
            drawable.setTint(addressLabel.currentTextColor)
            val width = 12.dp
            val height = 12.dp
            drawable.setBounds(0, 0, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            addressSpannableString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            addressSpannableString.append(
                " ",
                WSpacingSpan(4.dp),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        account?.byChain?.entries?.forEachIndexed { i, addressChain ->
            if (i > 0) {
                addressSpannableString.append(", ")
            }
            val blockchain = MBlockchain.valueOf(addressChain.key)
            blockchain.symbolIcon?.let {
                val drawable = ContextCompat.getDrawable(context, it)!!
                drawable.mutate()
                drawable.setTint(addressLabel.currentTextColor)
                val iconWidth = 8.66f.dp.roundToInt()
                val iconHeight = 8.66f.dp.roundToInt()
                drawable.setBounds(0, 0, iconWidth, iconHeight)
                val imageSpan = VerticalImageSpan(drawable)
                addressSpannableString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                addressSpannableString.append(
                    " ",
                    WSpacingSpan(1.66f.dp.roundToInt()),
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            val ss =
                SpannableStringBuilder(
                    addressChain.value.address.formatStartEndAddress(
                        prefix = if (isMultichain) 0 else 4,
                        suffix = if (isMultichain) 3 else 4
                    )
                ).apply {
                    updateDotsTypeface()
                }
            addressSpannableString.append(ss)
        }
        addressLabel.text = addressSpannableString
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)

        if (account?.accountId == AccountStore.activeAccountId)
            drawSelectedBorder(canvas)
    }

    private fun drawSelectedBorder(canvas: Canvas) {
        val padding = 0f
        val halfStroke = borderPaint.strokeWidth / 2
        val left = padding + halfStroke
        val top = padding + halfStroke
        val right = width - padding - halfStroke
        val bottom = height - padding - halfStroke

        val cornerRadius = 13.5f.dp
        canvas.drawRoundRect(
            left,
            top,
            right,
            bottom,
            cornerRadius,
            cornerRadius,
            borderPaint
        )
    }
}
