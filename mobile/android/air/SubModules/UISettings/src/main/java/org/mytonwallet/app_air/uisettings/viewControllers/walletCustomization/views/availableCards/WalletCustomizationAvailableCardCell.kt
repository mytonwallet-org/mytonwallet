package org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.views.availableCards

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.ImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.commonViews.RadialGradientView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import java.math.BigInteger
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletCustomizationAvailableCardCell(context: Context, val cellWidth: Int) :
    WCell(context, LayoutParams(cellWidth, (cellWidth / RATIO).roundToInt())), WThemedView {

    var onTap: ((accountId: String, cardNft: ApiNft?) -> Unit)? = null

    var tintColor = 0

    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f.dp
        color = tintColor
    }

    companion object {
        const val RATIO = 122 / 84f
    }

    private val cellHeight by lazy {
        cellWidth / RATIO
    }

    init {
        pivotY = cellHeight / 2
    }

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
        containerWidth = cellWidth
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

    private val bottomViewContainer = View(context).apply {
        id = generateViewId()
    }

    private val cellContainerView = WView(context).apply {
        addView(imageView, LayoutParams(0, 0))
        addView(radialGradientView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(balanceContainerView, LayoutParams(0, MATCH_PARENT))
        addView(bottomViewContainer, LayoutParams(54.dp, 5.dp))

        setConstraints {
            allEdges(imageView)
            toCenterX(balanceContainerView)
            toTop(balanceContainerView, -4f)
            toBottom(balanceContainerView, 4f)
            toCenterX(bottomViewContainer)
            toBottom(bottomViewContainer, 8f)
        }

        setOnClickListener {
            val accountId = accountId ?: return@setOnClickListener
            onTap?.invoke(accountId, cardNft)
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(cellContainerView, LayoutParams(0, MATCH_PARENT))
        setConstraints {
            toTop(cellContainerView)
            toBottom(cellContainerView, 4f)
            toStart(cellContainerView)
            toEnd(cellContainerView, 4f)
        }
    }

    override fun updateTheme() {
        cellContainerView.setBackgroundColor(Color.TRANSPARENT, 12f.dp, true)
        cellContainerView.addRippleEffect(WColor.BackgroundRipple.color, 12f.dp, 12f.dp)
        borderPaint.color = tintColor
        cardNft?.let {
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second, drawGradient = true)
            return
        }
        setLabelColors(Color.WHITE, Color.WHITE.colorWithAlpha(191), drawGradient = false)
    }

    private var accountId: String? = null
    private var cardNft: ApiNft? = null
    private var isSelectedCard: Boolean = false

    fun configure(
        accountId: String,
        cardNft: ApiNft?,
        balance: BigInteger,
        isSelectedCard: Boolean
    ) {
        this.accountId = accountId
        this.cardNft = cardNft
        this.isSelectedCard = isSelectedCard

        updateCardImage()

        balanceView.animateText(
            WBalanceView.AnimateConfig(
                amount = balance,
                decimals = WalletCore.baseCurrency.decimalsCount,
                currency = WalletCore.baseCurrency.sign,
                animated = false,
                setInstantly = true,
                forceCurrencyToRight = LocaleController.isRTL
            )
        )
        setPaddingDp(if (isSelectedCard) 3.5f else 2f)
    }

    fun updateCardImage() {
        updateTheme()

        if (cardNft == null) {
            imageView.loadRes(R.drawable.img_card)
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
                R.drawable.img_card
            )
        )
        imageView.loadUrl(cardNft?.metadata?.cardImageUrl(false) ?: "")
    }

    private fun setLabelColors(primaryColor: Int, secondaryColor: Int, drawGradient: Boolean) {
        cardNft?.let {
            balanceView.alpha = 0.95f
        } ?: run {
            balanceView.alpha = 1f
        }
        balanceView.updateColors(primaryColor, secondaryColor, drawGradient)
        bottomViewContainer.setBackgroundColor(secondaryColor.colorWithAlpha(191), 2.5f.dp)
    }


    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)

        if (isSelectedCard)
            drawSelectedBorder(canvas)
    }

    private fun drawSelectedBorder(canvas: Canvas) {
        val padding = 2f
        val halfStroke = borderPaint.strokeWidth / 2
        val left = padding + halfStroke
        val top = padding + halfStroke
        val right = width - padding - halfStroke - 4.dp
        val bottom = height - padding - halfStroke - 4.dp

        val cornerRadius = 12f.dp
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
