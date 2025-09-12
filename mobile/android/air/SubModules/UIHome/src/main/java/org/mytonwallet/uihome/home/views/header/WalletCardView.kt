package org.mytonwallet.uihome.home.views.header

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Shader
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.Toast
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.graphics.toColorInt
import androidx.core.view.children
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.setBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.views.UpdateStatusView
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletCardView(
    val window: WWindow
) : WView(window), WThemedView {

    companion object {
        const val EXPANDED_RADIUS = 16
        const val COLLAPSED_RADIUS = 3
    }

    private var cardNft: ApiNft? = null
    var isShowingSkeleton = true

    var statusViewState: UpdateStatusView.State = UpdateStatusView.State.Updated
        set(value) {
            // Check if the state has changed
            if (field == value) return
            field = value
            updateContentAlpha()
            balanceView.isLoading = value == UpdateStatusView.State.Updating
        }
    val ratio = 208 / 358f

    private val img = WImageView(context)

    val miniPlaceholders: WView by lazy {
        WView(context, LayoutParams(34.dp, WRAP_CONTENT)).apply {
            pivotY = 0f
            pivotX = 17f.dp
            val v1 = WView(context, LayoutParams(16.dp, 1.5f.dp.toInt()))
            addView(v1)
            val v2 =
                WView(context, LayoutParams(5f.dp.toInt(), 1.5f.dp.toInt()))
            v2.alpha = 0.6f
            addView(v2)
            val v3 = WView(context, LayoutParams(8.dp, 1.5f.dp.toInt()))
            v3.alpha = 0.6f
            addView(v3)
            setConstraints {
                toTop(v1, 4f)
                toCenterX(v1)
                topToTop(v2, v1, 2.5f)
                toCenterX(v2)
                topToTop(v3, v2, 4.5f)
                toCenterX(v3)
            }
        }
    }

    lateinit var balanceView: WBalanceView
    lateinit var arrowImageView: AppCompatImageView
    private val arrowDownDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_rounded
    )
    val balanceViewContainer: WSensitiveDataContainer<AutoScaleContainerView> by lazy {
        val linearLayout = LinearLayout(context)
        linearLayout.layoutDirection = LAYOUT_DIRECTION_LTR
        linearLayout.orientation = LinearLayout.HORIZONTAL
        linearLayout.gravity = Gravity.CENTER
        balanceView = WBalanceView(context, false)
        balanceView.setStyle(52f, 38f, WFont.NunitoExtraBold)
        balanceView.decimalsAlpha = 0.75f
        linearLayout.addView(balanceView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        arrowImageView = AppCompatImageView(context)
        arrowImageView.setImageDrawable(arrowDownDrawable)
        linearLayout.addView(arrowImageView, LayoutParams(18.dp, 18.dp).apply {
            leftMargin = 2.dp
            topMargin = 7.dp
            rightMargin = 2.dp
        })
        linearLayout.setOnClickListener {
            val location = IntArray(2)
            linearLayout.getLocationOnScreen(location)
            WMenuPopup.present(
                linearLayout,
                listOf(
                    MBaseCurrency.USD,
                    MBaseCurrency.EUR,
                    MBaseCurrency.RUB,
                    MBaseCurrency.CNY,
                    MBaseCurrency.BTC,
                    MBaseCurrency.TON
                ).map {
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.SelectableItem(
                            title = it.currencyName,
                            subtitle = null,
                            isSelected = WalletCore.baseCurrency?.currencySymbol == it.currencySymbol
                        ),
                        false,
                    ) {
                        WalletCore.setBaseCurrency(newBaseCurrency = it.currencyCode) { _, _ -> }
                    }
                },
                offset = (-location[0] + (window.navigationControllers.last().width / 2) - 112.5f.dp).toInt(),
                verticalOffset = (-8).dp,
                popupWidth = 225.dp,
                aboveView = false
            )
        }
        WSensitiveDataContainer(
            AutoScaleContainerView(linearLayout),
            WSensitiveDataContainer.MaskConfig(
                9, 4, Gravity.CENTER,
                skin = SensitiveDataMaskView.Skin.DARK_THEME,
                cellSize = 14.dp,
                protectContentLayoutSize = false
            )
        )
    }

    val balanceChangeLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setBackgroundColor(Color.WHITE.colorWithAlpha(128), 13f.dp)
        lbl.setPadding(8.dp, 3.dp, 8.dp, 3.dp)
        lbl.setStyle(16f, WFont.NunitoSemiBold)
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(
                16,
                3,
                Gravity.CENTER,
                16.dp,
                cellSize = 10.dp,
                skin = SensitiveDataMaskView.Skin.DARK_THEME,
                protectContentLayoutSize = false
            )
        )
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

    val addressLabelContainer = WView(context).apply {
        setPaddingDp(4, 0, 4, 0)
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

    val mintIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.CENTER
        setOnClickListener {
            val url =
                "https://getgems.io/collection/EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM"
            WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
        }
    }

    private val shiningView = WBaseView(context).apply {
        visibility = GONE
    }
    private val radialGradientView = RadialGradientView(context).apply {
        visibility = GONE
    }

    private val contentView: WView by lazy {
        val v = WView(context)
        v.addView(shiningView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        v.addView(img, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        v.addView(radialGradientView, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        v.addView(miniPlaceholders)
        v.addView(balanceViewContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(balanceChangeLabel, LayoutParams(WRAP_CONTENT, 28.dp))
        v.addView(addressLabelContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(mintIcon, LayoutParams(40.dp, 40.dp))

        v.setConstraints {
            allEdges(img)
            allEdges(radialGradientView, 1f)
            toCenterX(miniPlaceholders)
            toTop(miniPlaceholders, -4f)
            toBottom(miniPlaceholders, 4f)
            toTop(balanceViewContainer)
            toCenterX(balanceViewContainer)
            toTop(balanceChangeLabel)
            toCenterX(balanceChangeLabel)
            toCenterX(addressLabelContainer)
            toEnd(mintIcon, 4f)
        }

        v.post {
            val topOffset = (((parent as View).width - 32.dp) * ratio - 40.dp).roundToInt()
            v.setConstraints {
                toTopPx(addressLabelContainer, topOffset)
                toTopPx(mintIcon, topOffset - 8)
                constrainMaxWidth(balanceViewContainer.id, (parent as View).width - 34.dp)
            }
        }

        v
    }

    override fun setupViews() {
        super.setupViews()

        addView(contentView)

        setConstraints {
            allEdges(contentView)
        }

        WalletCore.doOnBridgeReady {
            updateAccountData()
        }

        addressLabelContainer.setOnClickListener {
            if (!WalletCore.isMultichain) {
                val clipboard =
                    context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip =
                    ClipData.newPlainText("", AccountStore.activeAccount?.firstAddress)
                clipboard.setPrimaryClip(clip)
                Toast.makeText(
                    context,
                    LocaleController.getString("Your address was copied!"),
                    Toast.LENGTH_SHORT
                ).show()
                return@setOnClickListener
            }

            val location = IntArray(2)
            addressLabelContainer.getLocationInWindow(location)

            lateinit var popupWindow: PopupWindow
            val menuWidth = 272.dp
            val items =
                listOf(MBlockchain.ton, MBlockchain.tron).mapNotNull { chain ->
                    val fullAddress = AccountStore.activeAccount?.addressByChain[chain.name]
                    val shortAddress =
                        fullAddress?.formatStartEndAddress(6, 6) ?: return@mapNotNull null
                    val ss = SpannableStringBuilder()

                    ContextCompat.getDrawable(
                        context,
                        org.mytonwallet.app_air.icons.R.drawable.ic_copy
                    )?.let { drawable ->
                        drawable.mutate()
                        drawable.setTint(WColor.SecondaryText.color)
                        val width = 16.dp
                        val height = 16.dp
                        drawable.setBounds(0, -FontManager.activeFont.textOffset, width, height)
                        val imageSpan = VerticalImageSpan(drawable)

                        if (LocaleController.isRTL) {
                            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                            ss.append(" $shortAddress")
                        } else {
                            ss.append("$shortAddress ")
                            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        }
                    }

                    ss.updateDotsTypeface()

                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = Icon(chain.icon, tintColor = null),
                            title = ss,
                            subtitle = chain.name.uppercase(),
                            trailingView = object : AppCompatImageView(contentView.context),
                                WThemedView {
                                init {
                                    updateTheme()
                                    setOnClickListener {
                                        val walletEvent =
                                            WalletEvent.OpenUrl(
                                                chain.explorerUrl(fullAddress)
                                            )
                                        WalletCore.notifyEvent(walletEvent)
                                        popupWindow.dismiss()
                                    }
                                }

                                override fun updateTheme() {
                                    val drw = ContextCompat.getDrawable(
                                        context,
                                        org.mytonwallet.app_air.icons.R.drawable.ic_world
                                    )
                                    drw?.setTint(WColor.Tint.color)
                                    setImageDrawable(drw)
                                    addRippleEffect(WColor.SecondaryBackground.color)
                                }
                            },
                        ),
                        false,
                    ) {
                        val clipboard =
                            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip =
                            ClipData.newPlainText("", fullAddress)
                        clipboard.setPrimaryClip(clip)
                        Toast.makeText(
                            context,
                            LocaleController.getString("Your address was copied!"),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }

            popupWindow = WMenuPopup.present(
                addressLabelContainer,
                items,
                popupWidth = menuWidth,
                offset = -location[0] + ((parent as View).width / 2) - menuWidth / 2,
                aboveView = false
            )
        }
    }

    fun updateAccountData() {
        val account = AccountStore.activeAccount
        val isMultiChain = account?.isMultichain == true
        addressChain.layoutParams.width = if (isMultiChain) 26.dp else 16.dp
        updateAddressLabel()
        updateCardImage()
        val drawableRes = when {
            isMultiChain -> org.mytonwallet.app_air.icons.R.drawable.ic_multichain
            account?.byChain?.containsKey(MBlockchain.ton.name) == true ->
                org.mytonwallet.app_air.icons.R.drawable.ic_blockchain_ton_128

            account?.byChain?.containsKey(MBlockchain.tron.name) == true ->
                org.mytonwallet.app_air.icons.R.drawable.ic_blockchain_tron_40

            else -> null
        }
        addressChain.setImageDrawable(drawableRes?.let {
            ContextCompat.getDrawable(
                context,
                drawableRes
            )
        })
        addressLabelContainer.addRippleEffect(
            Color.WHITE.colorWithAlpha(25),
            20f.dp
        )
    }

    private fun updateAddressLabel() {
        val txt =
            if (AccountStore.activeAccount?.isMultichain == true) LocaleController.getString("Multichain") else AccountStore.activeAccount?.firstAddress?.formatStartEndAddress(
                6,
                6
            ) ?: ""
        val ss = SpannableStringBuilder(txt)
        if (AccountStore.activeAccount?.isMultichain != true)
            ss.updateDotsTypeface()
        ContextCompat.getDrawable(
            context,
            if (WalletCore.isMultichain) org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24 else org.mytonwallet.app_air.icons.R.drawable.ic_copy
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(addressLabel.currentTextColor)
            val width = 16.dp
            val height = 16.dp
            drawable.setBounds(0, 1.dp - FontManager.activeFont.textOffset, width, height)
            val imageSpan = VerticalImageSpan(drawable)
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        addressLabel.text = ss
    }

    fun updateCardImage() {
        cardNft =
            AccountStore.activeAccountId?.let { activeAccountId ->
                WGlobalStorage.getCardBackgroundNft(activeAccountId)
                    ?.let { ApiNft.fromJson(it) }
            }
        updateTheme()

        if (cardNft == null) {
            img.setImageDrawable(
                ContextCompat.getDrawable(
                    context,
                    R.drawable.img_card
                )
            )
            contentView.setConstraints {
                allEdges(img)
            }
            shiningView.visibility = GONE
            radialGradientView.visibility = GONE
            return
        }
        shiningView.visibility = VISIBLE
        if (cardNft?.metadata?.mtwCardType == ApiMtwCardType.STANDARD) {
            radialGradientView.isTextLight =
                cardNft?.metadata?.mtwCardTextType == ApiMtwCardTextType.LIGHT
            radialGradientView.visibility = VISIBLE
        } else {
            radialGradientView.visibility = GONE
        }
        img.hierarchy.setPlaceholderImage(
            ContextCompat.getDrawable(
                context,
                R.drawable.img_card
            )
        )
        img.loadUrl(cardNft?.metadata?.cardImageUrl ?: "")
        contentView.setConstraints {
            allEdges(img, 1f)
        }
    }

    var mode = HomeHeaderView.DEFAULT_MODE
    fun expand(animated: Boolean) {
        mode = HomeHeaderView.Mode.Expanded
        updateContentAlpha(animated)
        if (animated) {
            miniPlaceholders.fadeOut(AnimationConstants.SUPER_QUICK_ANIMATION)
            shiningView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            miniPlaceholders.alpha = 0f
            shiningView.alpha = 1f
        }
    }

    fun collapse() {
        mode = HomeHeaderView.Mode.Collapsed
        updateContentAlpha()
        miniPlaceholders.alpha = 0f
        miniPlaceholders.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        shiningView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
    }

    override fun updateTheme() {
        cardNft?.let {
            shiningView.background =
                cardNft?.metadata?.gradient(window.window.decorView.width.toFloat() / 3)
            when (cardNft?.metadata?.mtwCardType) {
                ApiMtwCardType.SILVER -> {
                    setLabelColors(
                        "#272727".toColorInt(),
                        "#272727".toColorInt()
                    )
                }

                ApiMtwCardType.GOLD -> {
                    setLabelColors(
                        "#34270A".toColorInt(),
                        "#272727".toColorInt()
                    )
                }

                ApiMtwCardType.PLATINUM -> {
                    setLabelColors(Color.WHITE, Color.WHITE)
                }

                ApiMtwCardType.BLACK -> {
                    setLabelColors(Color.WHITE, Color.WHITE)
                }

                else -> {
                    if (cardNft?.metadata?.mtwCardTextType == ApiMtwCardTextType.LIGHT) {
                        setLabelColors(Color.WHITE, Color.WHITE)
                    } else {
                        setLabelColors(Color.BLACK, Color.BLACK)
                    }
                }
            }
            return
        } ?: run {
            shiningView.background = null
        }
        setLabelColors(Color.WHITE, Color.WHITE)
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
        balanceView.setTextColor(primaryColor, secondaryColor, secondaryColor.colorWithAlpha(191))
        arrowDownDrawable?.setTint(secondaryColor)
        addressLabel.setTextColor(secondaryColor.colorWithAlpha(204))
        if (textShader == null) {
            balanceChangeLabel.contentView.paint.shader = null
            addressLabel.paint.shader = null
            balanceChangeLabel.contentView.setTextColor(primaryColor.colorWithAlpha(191))
        } else {
            balanceChangeLabel.contentView.paint.shader = textShader
            balanceChangeLabel.contentView.invalidate()
            addressLabel.paint.shader = textShader
            addressLabel.invalidate()
        }
        updateAddressLabel()
        for (child in miniPlaceholders.children)
            child.setBackgroundColor(primaryColor, 1f.dp)
        mintIcon.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_mint
            )!!.apply {
                setTint(secondaryColor.colorWithAlpha(191))
            }
        )
        mintIcon.addRippleEffect(
            Color.WHITE.colorWithAlpha(25),
            20f.dp
        )
    }

    val miniPlaceholdersMaxBottom = 28f.dp
    fun updatePositions(balanceY: Float) {
        balanceViewContainer.y = balanceY
        balanceChangeLabel.y = balanceY + 74.dp

        val currentBottom = miniPlaceholders.top + miniPlaceholders.height
        if (currentBottom > miniPlaceholdersMaxBottom) {
            val offsetNeeded = currentBottom - miniPlaceholdersMaxBottom
            miniPlaceholders.translationY = -offsetNeeded
        } else {
            miniPlaceholders.translationY = 0f
        }
    }

    private var currentAlpha = 1f
    private fun updateContentAlpha(animated: Boolean = true) {
        if (mode == HomeHeaderView.Mode.Collapsed) {
            // Card view may be above stateView, so hide it if required
            when (statusViewState) {
                UpdateStatusView.State.WaitingForNetwork, UpdateStatusView.State.Updating -> {
                    if (currentAlpha > 0f) {
                        currentAlpha = 0f
                        if (animated) {
                            contentView.fadeOut()
                        } else {
                            contentView.alpha = 0f
                        }
                    }
                }

                else ->
                    if (currentAlpha < 1f) {
                        currentAlpha = 1f
                        if (animated) {
                            contentView.alpha = 0f
                            contentView.fadeIn()
                        } else {
                            contentView.alpha = 1f
                        }
                    }
            }
        } else {
            if (currentAlpha < 1f) {
                currentAlpha = 1f
                if (animated) {
                    contentView.alpha = 0f
                    contentView.fadeIn()
                } else {
                    contentView.alpha = 1f
                }
            }
        }
    }

    fun setRoundingParam(radius: Float) {
        setBackgroundColor(Color.TRANSPARENT, radius, true)
        img.setBackgroundColor(Color.TRANSPARENT, radius, true)
        radialGradientView.cornerRadius = radius
    }

    fun updateMintIconVisibility() {
        mintIcon.isGone =
            WGlobalStorage.getCardsInfo(AccountStore.activeAccountId ?: "") == null &&
                !WGlobalStorage.isCardMinting(AccountStore.activeAccountId ?: "")
    }
}
