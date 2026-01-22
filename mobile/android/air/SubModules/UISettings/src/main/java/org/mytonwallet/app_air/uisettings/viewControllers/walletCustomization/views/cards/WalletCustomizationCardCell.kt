package org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.views.cards

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Shader
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
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
        containerWidth = cellWidth
    }

    private val balanceContainerView = WSensitiveDataContainer(
        AutoScaleContainerView(balanceView).apply {
            clipChildren = false
            clipToPadding = false
            minPadding = 16.dp
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

    private val addressLabel: WMultichainAddressLabel by lazy {
        WMultichainAddressLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setPaddingDpLocalized(3, 0, 1, 1)
            gravity = Gravity.CENTER
            containerWidth = cellWidth
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(imageView, LayoutParams(0, 0))
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(balanceContainerView, LayoutParams(0, MATCH_PARENT))
        addView(addressLabel, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))

        setConstraints {
            allEdges(imageView)
            toTop(titleLabel, 16f)
            toCenterX(balanceContainerView)
            toTop(balanceContainerView, -4f)
            toBottom(balanceContainerView, 4f)
            toCenterX(addressLabel, 16f)
            toBottom(addressLabel, 16f)
        }
    }

    override fun updateTheme() {
        setBackgroundColor(Color.TRANSPARENT, 20f.dp, true)
        cardNft?.let {
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second, drawGradient = true)
            return
        }
        setLabelColors(Color.WHITE, Color.WHITE.colorWithAlpha(191), drawGradient = false)
    }

    private var account: MAccount? = null
    private var cardNft: ApiNft? = null

    fun configure(account: MAccount) {
        this.account = account
        titleLabel.text = account.name

        updateCardImage()
        updateBalance()
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
            return
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

    private fun setLabelColors(primaryColor: Int, secondaryColor: Int, drawGradient: Boolean) {
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
        balanceView.updateColors(primaryColor, secondaryColor, drawGradient)
        addressLabel.setTextColor(primaryColor, secondaryColor, drawGradient)
        if (textShader == null) {
            addressLabel.paint.shader = null
        } else {
            addressLabel.paint.shader = textShader
            addressLabel.invalidate()
        }
        val style = when (account?.accountType) {
            MAccount.AccountType.VIEW -> WMultichainAddressLabel.walletCustomizationViewStyle
            MAccount.AccountType.HARDWARE -> WMultichainAddressLabel.walletCustomizationHardwareStyle
            else -> WMultichainAddressLabel.walletCustomizationStyle
        }
        addressLabel.displayAddresses(account, style)
    }

    private fun updateBalance() {
        val accountId = account?.accountId ?: return
        val balance = BalanceStore.totalBalanceInBaseCurrency(accountId)
        balanceView.animateText(
            WBalanceView.AnimateConfig(
                amount = balance?.toBigInteger(WalletCore.baseCurrency.decimalsCount),
                decimals = WalletCore.baseCurrency.decimalsCount,
                currency = WalletCore.baseCurrency.sign,
                animated = false,
                setInstantly = true,
                forceCurrencyToRight = LocaleController.isRTL
            )
        )
    }
}
