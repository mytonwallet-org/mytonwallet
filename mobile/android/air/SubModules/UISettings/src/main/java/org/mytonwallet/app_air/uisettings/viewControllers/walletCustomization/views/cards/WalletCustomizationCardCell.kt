package org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.views.cards

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Shader
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.commonViews.RadialGradientView
import org.mytonwallet.app_air.uicomponents.commonViews.WalletTypeView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
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
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletCustomizationCardCell(context: Context, val cellWidth: Int) :
    WCell(context, LayoutParams(cellWidth, (cellWidth / RATIO).roundToInt())), WThemedView {

    companion object {
        const val RATIO = 274 / 176f
    }

    private val cellHeight by lazy {
        cellWidth / RATIO
    }

    init {
        pivotY = cellHeight / 2
    }

    private val imageView = WImageView(context, 20.dp).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
    }
    private val radialGradientView = RadialGradientView(context).apply {
        cornerRadius = 20f.dp
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_DIP, 22f)
        gravity = Gravity.CENTER
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val balanceView = WBalanceView(context).apply {
        currencySize = 38f
        primarySize = 42f
        decimalsSize = 32f
        typeface = WFont.NunitoExtraBold.typeface
    }

    private val balanceContainerView = WSensitiveDataContainer(
        AutoScaleContainerView(balanceView).apply {
            clipChildren = false
            clipToPadding = false
            minPadding = 12.dp
            maxAllowedWidth = cellWidth
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

    private val addressChain = AppCompatImageView(context).apply {
        id = generateViewId()
    }

    private val addressLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl.paint.letterSpacing = 0.031f
        lbl
    }

    val walletTypeView = WalletTypeView(context)

    val addressLabelContainer = WView(context).apply {
        setPaddingDpLocalized(4, 0, 1, 0)
        addView(addressChain, LayoutParams(16.dp, 16.dp))
        addView(addressLabel, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints {
            toStart(addressChain)
            toCenterY(addressChain)
            startToEnd(addressLabel, addressChain, 6f)
            toEnd(addressLabel)
            toCenterY(addressLabel)
        }
    }

    val bottomViewContainer = WView(context).apply {
        addView(walletTypeView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(addressLabelContainer, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        setConstraints {
            toStart(walletTypeView)
            startToEnd(addressLabelContainer, walletTypeView)
            toEnd(addressLabelContainer)
            toCenterY(walletTypeView)
            toCenterY(addressLabelContainer)
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(imageView, LayoutParams(0, 0))
        addView(radialGradientView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(balanceContainerView, LayoutParams(0, MATCH_PARENT))
        addView(bottomViewContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            allEdges(imageView)
            toTop(titleLabel, 16f)
            toCenterX(balanceContainerView)
            toTop(balanceContainerView, -4f)
            toBottom(balanceContainerView, 4f)
            toCenterX(bottomViewContainer)
            toBottom(bottomViewContainer, 16f)
        }
    }

    override fun updateTheme() {
        setBackgroundColor(Color.TRANSPARENT, 20f.dp, true)
        cardNft?.let {
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second)
            return
        }
        setLabelColors(Color.WHITE, Color.WHITE)
    }

    private var account: MAccount? = null
    private var cardNft: ApiNft? = null

    fun configure(account: MAccount) {
        this.account = account
        titleLabel.text = account.name

        updateCardImage()
        updateBalance()

        val isMultiChain = account.isMultichain
        addressChain.layoutParams.width = if (isMultiChain) 26.dp else 16.dp
        val drawableRes = when {
            isMultiChain -> R.drawable.ic_multichain
            account.byChain.containsKey(MBlockchain.ton.name) ->
                R.drawable.ic_blockchain_ton_128

            account.byChain.containsKey(MBlockchain.tron.name) ->
                R.drawable.ic_blockchain_tron_40

            else -> null
        }
        addressChain.setImageDrawable(drawableRes?.let {
            ContextCompat.getDrawable(
                context,
                drawableRes
            )
        })
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
            setConstraints {
                allEdges(imageView)
            }
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
        setConstraints {
            allEdges(imageView)
        }
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
        titleLabel.setTextColor(primaryColor)
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
        val txt =
            if (isMultichain) LocaleController.getString("Multichain") else account?.firstAddress?.formatStartEndAddress(
                6,
                6
            ) ?: ""
        addressSpannableString.append(
            SpannableStringBuilder(txt).apply {
                if (!isMultichain)
                    updateDotsTypeface()
            }
        )
        addressLabel.text = addressSpannableString
    }

    private fun updateBalance() {
        val accountId = account?.accountId ?: return
        val balance = BalanceStore.totalBalanceInBaseCurrency(accountId)
        balanceView.animateText(
            WBalanceView.AnimateConfig(
                balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                WalletCore.baseCurrency.decimalsCount,
                WalletCore.baseCurrency.sign,
                false,
                LocaleController.isRTL
            )
        )
    }
}
