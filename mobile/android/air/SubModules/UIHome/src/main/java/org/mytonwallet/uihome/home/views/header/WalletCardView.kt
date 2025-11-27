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
import androidx.core.view.children
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.RadialGradientView
import org.mytonwallet.app_air.uicomponents.commonViews.WalletTypeView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.NftGradientHelpers
import org.mytonwallet.app_air.uicomponents.helpers.TiltSensorManager
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WGradientMaskView
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
import org.mytonwallet.app_air.uicomponents.widgets.menu.WPopupWindow
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.MTW_CARDS_COLLECTION
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.setBaseCurrency
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardTextType
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.uihome.home.views.UpdateStatusView
import java.math.BigInteger
import kotlin.math.absoluteValue
import kotlin.math.roundToInt
import kotlin.math.sqrt

@SuppressLint("ViewConstructor")
class WalletCardView(
    val window: WWindow
) : WView(window), WThemedView, TiltSensorManager.TiltObserver {

    companion object {
        const val EXPANDED_RADIUS = 24
        const val COLLAPSED_RADIUS = 3
        private const val RATIO = 208 / 358f
    }

    var isInGoneState = false
        set(value) {
            field = value
            isGone = value || account == null
        }

    // PRIVATE VARIABLES ///////////////////////////////////////////////////////////////////////////
    var account: MAccount? = null
        private set
    private var cardNft: ApiNft? = null
    private var balanceAmount: BigInteger? = null
    private var isShowingSkeletons = false

    private var statusViewState: UpdateStatusView.State = UpdateStatusView.State.Updated

    // Tilt Effect
    private var isSensorListening = false
    private var currentTiltX = 0f
    private var currentTiltY = 0f
    override fun onTilt(x: Float, y: Float) {
        if (shiningView.visibility != VISIBLE) return

        currentTiltX = x
        currentTiltY = y

        shiningView.background =
            NftGradientHelpers(cardNft).gradient(
                window.window.decorView.width.toFloat() / 3,
                currentTiltX,
                currentTiltY
            )
    }

    // CHILDREN ////////////////////////////////////////////////////////////////////////////////////
    private val img = WImageView(context)

    private val miniPlaceholders: WView by lazy {
        WView(context, LayoutParams(34.dp, WRAP_CONTENT)).apply {
            alpha = 0f
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
                toTop(v1, 6f)
                toCenterX(v1)
                topToTop(v2, v1, 2.5f)
                toCenterX(v2)
                topToTop(v3, v2, 7.5f)
                toCenterX(v3)
            }
        }
    }

    private lateinit var balanceView: WBalanceView
    private lateinit var balanceViewMaskWrapper: WGradientMaskView
    private lateinit var arrowImageView: AppCompatImageView
    private val arrowDownDrawable = ContextCompat.getDrawable(
        context,
        org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_rounded
    )
    private val balanceViewContainer: WSensitiveDataContainer<AutoScaleContainerView> by lazy {
        val linearLayout = LinearLayout(context).apply {
            clipChildren = false
            clipToPadding = false
            layoutDirection = LAYOUT_DIRECTION_LTR
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        balanceView = WBalanceView(context).apply {
            clipChildren = false
            clipToPadding = false
            primaryColor = WColor.White.color
            secondaryColor = WColor.White.color
            decimalsAlpha = 191
            typeface = WFont.NunitoExtraBold.typeface
        }
        balanceViewMaskWrapper = WGradientMaskView(balanceView)
        linearLayout.addView(balanceViewMaskWrapper, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        arrowImageView = AppCompatImageView(context).apply {
            setImageDrawable(arrowDownDrawable)
        }
        linearLayout.addView(arrowImageView, LayoutParams(18.dp, 18.dp).apply {
            leftMargin = 2.dp
            topMargin = 5.dp
            rightMargin = 2.dp
        })
        linearLayout.setOnClickListener {
            balanceViewContainerTapped()
        }
        WSensitiveDataContainer(
            AutoScaleContainerView(linearLayout).apply {
                clipChildren = false
                clipToPadding = false
                maxAllowedWidth = window.windowView.width - 34.dp
                minPadding = 11.dp
            },
            WSensitiveDataContainer.MaskConfig(
                9, 4, Gravity.CENTER,
                skin = SensitiveDataMaskView.Skin.DARK_THEME,
                cellSize = 14.dp,
                protectContentLayoutSize = false
            )
        ).apply {
            clipChildren = false
            clipToPadding = false
        }
    }

    private val balanceChangeLabel: WSensitiveDataContainer<WLabel> by lazy {
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

    private val balanceSkeletonView = WView(context).apply {
        visibility = GONE
    }
    private val balanceChangeSkeletonView = WView(context).apply {
        visibility = GONE
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

    private val walletTypeView = WalletTypeView(context)

    private val addressLabelContainer = WView(context).apply {
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

    private val exploreDrawable =
        ContextCompat.getDrawable(context, org.mytonwallet.app_air.icons.R.drawable.ic_world)
    private val exploreButton = AppCompatImageView(context).apply {
        id = generateViewId()
        setImageDrawable(exploreDrawable)
        setOnClickListener {
            val byChain = account?.byChain
            val chain = byChain?.keys?.firstOrNull() ?: return@setOnClickListener
            val blockchain = MBlockchain.valueOf(chain)
            val address = byChain[chain]?.address
            address?.let {
                val walletEvent =
                    WalletEvent.OpenUrl(
                        blockchain.explorerUrl(address)
                    )
                WalletCore.notifyEvent(walletEvent)
            }
        }
        translationX = (-1f).dp
    }

    private val bottomViewContainer = WView(context).apply {
        addView(walletTypeView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(addressLabelContainer, LayoutParams(WRAP_CONTENT, MATCH_PARENT))
        addView(exploreButton, LayoutParams(17.dp, 17.dp))
        setConstraints {
            toStart(walletTypeView)
            startToEnd(addressLabelContainer, walletTypeView)
            startToEnd(exploreButton, addressLabelContainer)
            toEnd(exploreButton)
            toCenterY(walletTypeView)
            toCenterY(addressLabelContainer)
            toTop(exploreButton, 1f)
            toBottom(exploreButton)
        }
    }

    private val mintIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.CENTER
        setOnClickListener {
            val url =
                "https://getgems.io/collection/$MTW_CARDS_COLLECTION"
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
        val v = WView(context).apply {
            clipChildren = false
            clipToPadding = false
        }
        v.addView(shiningView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        v.addView(img, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        v.addView(radialGradientView, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        v.addView(miniPlaceholders)
        v.addView(balanceViewContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(balanceChangeLabel, LayoutParams(WRAP_CONTENT, 28.dp))
        v.addView(balanceSkeletonView, LayoutParams(134.dp, 56.dp))
        v.addView(balanceChangeSkeletonView, LayoutParams(134.dp, 28.dp))
        v.addView(bottomViewContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        v.addView(mintIcon, LayoutParams(40.dp, 40.dp))

        v.setConstraints {
            allEdges(img)
            allEdges(radialGradientView, 1f)
            toCenterX(miniPlaceholders)
            toTop(miniPlaceholders)
            toTop(balanceViewContainer)
            toCenterX(balanceViewContainer)
            toTop(balanceChangeLabel)
            toCenterX(balanceChangeLabel)
            toCenterX(bottomViewContainer)
            edgeToEdge(balanceSkeletonView, balanceViewContainer)
            edgeToEdge(balanceChangeSkeletonView, balanceChangeLabel)
            toEnd(mintIcon, 4f)
        }

        v.post {
            val topOffset = (((parent as View).width - 32.dp) * RATIO - 40.dp).roundToInt()
            v.setConstraints {
                toTopPx(bottomViewContainer, topOffset)
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

        balanceView.onTotalWidthChanged = { width ->
            balanceViewMaskWrapper.setupLayout(
                width = width,
                height = 56.dp,
                parentWidth = (this@WalletCardView.parent as HomeHeaderView).width
            )
        }
        addressLabelContainer.setOnClickListener {
            addressLabelTapped()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startSensorListening()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopSensorListening()
    }

    override fun updateTheme() {
        if (ThemeManager.isDark)
            startSensorListening()
        else
            stopSensorListening()
        cardNft?.let {
            startSensorListening()
            shiningView.background =
                NftGradientHelpers(cardNft).gradient(
                    window.window.decorView.width.toFloat() / 3,
                    currentTiltX,
                    currentTiltY
                )
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second)
            return
        } ?: run {
            stopSensorListening()
            shiningView.background = null
        }
        setLabelColors(Color.WHITE, Color.WHITE)

        balanceChangeLabel.contentView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            14f.dp
        )
        if (isShowingSkeletons) {
            updateSkeletonViewColors()
        }
    }

    fun onDestroy() {
        stopSensorListening()
        balanceView.onTotalWidthChanged = null
        balanceViewMaskWrapper.onDestroy()
    }

    fun startSensorListening() {
        if (isSensorListening ||
            cardNft == null ||
            !ThemeManager.isDark ||
            !isAttachedToWindow ||
            headerMode != HomeHeaderView.Mode.Expanded
        ) return
        isSensorListening = true
        TiltSensorManager.addObserver(this)
    }

    fun stopSensorListening() {
        if (!isSensorListening) return
        TiltSensorManager.removeObserver(this)
        isSensorListening = false
    }

    // PUBLIC METHODS //////////////////////////////////////////////////////////////////////////////
    fun setupLayout(parentWidth: Int) {
        balanceViewMaskWrapper.setupLayout(parentWidth = parentWidth)
    }

    fun updatePositions(balanceY: Float, expandProgress: Float) {
        miniPlaceholders.scaleX = 1 + sqrt(expandProgress)
        miniPlaceholders.scaleY = miniPlaceholders.scaleX

        balanceViewContainer.y = balanceY
        balanceSkeletonView.y = balanceY
        balanceChangeLabel.y = balanceY + 64.dp
        balanceChangeSkeletonView.y = balanceY + 64.dp

        val scale2 = (30f + 8f * expandProgress) / 38f
        balanceView.setScale(
            (36f + 16f * expandProgress) / 52f,
            scale2,
            (-2.5f).dp + 1f.dp * expandProgress
        )
        balanceView.translationX = 11f.dp * (1 - expandProgress)
        balanceViewContainer.contentView.updateScale()
    }

    fun updateBalanceChange(balance: Double?, balance24h: Double?, animated: Boolean) {
        var balanceChangeString: String? = null
        balance?.let {
            balance24h?.let {
                if (balance > 0) {
                    val changeValue = balance - balance24h
                    if (changeValue.isFinite()) {
                        val balanceChangeValueString = (changeValue.absoluteValue).toString(
                            WalletCore.baseCurrency.decimalsCount,
                            WalletCore.baseCurrency.sign,
                            WalletCore.baseCurrency.decimalsCount,
                            true
                        )
                        val balanceChangePercentString =
                            if (balance24h == 0.0) "" else "${if (balance - balance24h >= 0) "+" else ""}${((balance - balance24h) / balance24h * 10000).roundToInt() / 100f}% · "
                        balanceChangeString =
                            "$balanceChangePercentString$balanceChangeValueString"
                    }
                }
            }
        }
        updateBalanceChange(balanceChangeString, animated)
    }

    fun updateBalanceChange(balanceChangeString: String?, animated: Boolean) {
        if (balanceChangeLabel.contentView.text.isEmpty() && animated) {
            balanceChangeLabel.alpha = 0f
            balanceChangeLabel.fadeIn()
        }
        balanceChangeLabel.contentView.text = balanceChangeString
        balanceChangeLabel.visibility =
            if (balanceChangeLabel.contentView.text.isNullOrEmpty()) INVISIBLE else VISIBLE
    }

    fun animateBalance(animateConfig: WBalanceView.AnimateConfig) {
        if (balanceAmount == null && animateConfig.amount != null) {
            if (animateConfig.animated)
                fadeInBalanceContainer()
            showBalanceArrow(animateConfig.animated)
            hideSkeletons()
        } else if (animateConfig.amount == null) {
            showSkeletons()
        }
        balanceAmount = animateConfig.amount
        balanceView.animateText(animateConfig)
    }

    fun showSkeletons() {
        if (isShowingSkeletons)
            return
        isShowingSkeletons = true
        balanceSkeletonView.visibility = VISIBLE
        balanceSkeletonView.alpha = 1f
        val showBalanceChangePlace = account?.isNew != true && balanceAmount != BigInteger.ZERO
        balanceChangeSkeletonView.isVisible = showBalanceChangePlace
        balanceChangeSkeletonView.alpha = 1f
        arrowImageView.visibility = INVISIBLE
        updateSkeletonViewColors()
    }

    fun hideSkeletons() {
        if (!isShowingSkeletons)
            return
        isShowingSkeletons = false
        balanceSkeletonView.fadeOut(onCompletion = {
            if (!isShowingSkeletons) {
                balanceSkeletonView.visibility = GONE
                balanceChangeSkeletonView.visibility = GONE
            }
        })
        if (balanceChangeSkeletonView.isVisible)
            balanceChangeSkeletonView.fadeOut()
    }

    fun getSkeletonViews(): List<View> {
        return listOf(
            balanceSkeletonView,
            balanceChangeSkeletonView
        )
    }

    fun setStatusViewState(value: UpdateStatusView.State, animated: Boolean) {
        if (statusViewState == value) return
        statusViewState = value
        updateContentAlpha(animated)
        balanceViewMaskWrapper.isLoading = value == UpdateStatusView.State.Updating
    }

    // Called to update account
    fun updateAccountData(account: MAccount?) {
        if (this.account?.accountId == account?.accountId) {
            return
        }
        this.account = account
        if (account == null) {
            isGone = true
            return
        } else {
            isGone = isInGoneState
        }
        val isMultiChain = account.isMultichain
        addressChain.layoutParams.width = if (isMultiChain) 26.dp else 16.dp
        updateAddressLabel()
        updateCardImage()
        val drawableRes = when {
            isMultiChain -> org.mytonwallet.app_air.icons.R.drawable.ic_multichain
            account.byChain.containsKey(MBlockchain.ton.name) ->
                org.mytonwallet.app_air.icons.R.drawable.ic_blockchain_ton_128

            account.byChain.containsKey(MBlockchain.tron.name) ->
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
        walletTypeView.configure(account)
        bottomViewContainer.setConstraints {
            startToEnd(
                addressLabelContainer,
                walletTypeView,
                if (walletTypeView.isGone) 0f else 6f
            )
        }
        exploreButton.isGone = account.isMultichain == true
        bottomViewContainer.translationX = if (exploreButton.isGone) 0f else (-0.5f).dp
        balanceAmount = null
        animateBalance(
            WBalanceView.AnimateConfig(
                null,
                0,
                "",
                animated = false,
                forceCurrencyToRight = false
            )
        )
        updateBalanceChange(null, false)
    }

    fun updateCardImage() {
        cardNft =
            account?.accountId?.let { accountId ->
                WGlobalStorage.getCardBackgroundNft(accountId)
                    ?.let { ApiNft.fromJson(it) }
            }
        updateTheme()

        if (cardNft == null) {
            img.setImageDrawable(
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uicomponents.R.drawable.img_card
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
                org.mytonwallet.app_air.uicomponents.R.drawable.img_card
            )
        )
        img.loadUrl(cardNft?.metadata?.cardImageUrl(false) ?: "")
        contentView.setConstraints {
            allEdges(img, 1f)
        }
    }

    var headerMode = HomeHeaderView.DEFAULT_MODE
        set(value) {
            field = value
            if (value == HomeHeaderView.Mode.Expanded)
                startSensorListening()
            else
                stopSensorListening()
        }
    var mode = HomeHeaderView.DEFAULT_MODE
    fun expand(animated: Boolean) {
        if (mode == HomeHeaderView.Mode.Expanded)
            return
        mode = HomeHeaderView.Mode.Expanded
        updateContentAlpha(animated)
        if (animated) {
            miniPlaceholders.fadeOut(AnimationConstants.SUPER_QUICK_ANIMATION)
            shiningView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            miniPlaceholders.alpha = 0f
            shiningView.alpha = 1f
        }
        startSensorListening()
    }

    fun collapse(animated: Boolean) {
        if (mode == HomeHeaderView.Mode.Collapsed)
            return
        stopSensorListening()
        mode = HomeHeaderView.Mode.Collapsed
        updateContentAlpha(animated)
        if (animated) {
            miniPlaceholders.alpha = 0f
            miniPlaceholders.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
            shiningView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            miniPlaceholders.alpha = 1f
            shiningView.alpha = 0f
        }
    }

    var currentRadius = -1f
    fun setRoundingParam(radius: Float) {
        if (this.currentRadius == radius)
            return
        this.currentRadius = radius
        setBackgroundColor(Color.TRANSPARENT, radius, true)
        img.setBackgroundColor(Color.TRANSPARENT, radius, true)
        radialGradientView.cornerRadius = radius
    }

    fun updateMintIconVisibility() {
        mintIcon.isGone =
            WGlobalStorage.getCardsInfo(account?.accountId ?: "") == null &&
                !WGlobalStorage.isCardMinting(account?.accountId ?: "")
    }

    fun updateActionsAlpha(actionsAlpha: Float) {
        addressLabelContainer.alpha = actionsAlpha
        mintIcon.alpha = actionsAlpha
        walletTypeView.alpha = actionsAlpha
        exploreButton.alpha = actionsAlpha
    }

    fun viewWillDisappear() {
        balanceView.interruptAnimation()
    }

    // PRIVATE METHODS /////////////////////////////////////////////////////////////////////////////
    private fun updateAddressLabel() {
        val txt =
            if (account?.isMultichain == true) LocaleController.getString("Multichain") else account?.firstAddress?.formatStartEndAddress(
                6,
                6
            ) ?: ""
        val ss = SpannableStringBuilder(txt)
        if (account?.isMultichain != true)
            ss.updateDotsTypeface()
        ContextCompat.getDrawable(
            context,
            if (account?.isMultichain == true) org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24 else org.mytonwallet.app_air.icons.R.drawable.ic_copy
        )?.let { drawable ->
            drawable.mutate()
            drawable.setTint(addressLabel.currentTextColor)
            val width = 18.dp
            val height = 18.dp
            drawable.setBounds(1.dp, 1.dp - FontManager.activeFont.textOffset, width + 1.dp, height)
            val imageSpan = VerticalImageSpan(drawable)
            ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        addressLabel.text = ss
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
        balanceViewMaskWrapper.setupColors(
            intArrayOf(
                primaryColor.colorWithAlpha(191),
                primaryColor,
                primaryColor.colorWithAlpha(191)
            )
        )
        balanceView.updateColors(primaryColor, secondaryColor.colorWithAlpha(191))
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
        walletTypeView.setColor(secondaryColor.colorWithAlpha(191))
        exploreDrawable?.setTint(secondaryColor.colorWithAlpha(191))
        addressLabelContainer.background = null
        addressLabelContainer.addRippleEffect(
            Color.WHITE.colorWithAlpha(25),
            20f.dp
        )
        exploreButton.background = null
        exploreButton.addRippleEffect(
            Color.WHITE.colorWithAlpha(25),
            20f.dp
        )
    }

    private fun updateSkeletonViewColors() {
        balanceSkeletonView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            8f.dp
        )
        balanceChangeSkeletonView.setBackgroundColor(
            Color.WHITE.colorWithAlpha(25),
            14f.dp
        )
    }

    private fun fadeInBalanceContainer() {
        balanceViewContainer.alpha = 0f
        balanceViewContainer.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
    }

    fun showBalanceArrow(animated: Boolean) {
        if (arrowImageView.isInvisible) {
            arrowImageView.visibility = VISIBLE
            if (animated)
                arrowImageView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
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
                    contentView.fadeIn()
                } else {
                    contentView.alpha = 1f
                }
            }
        }
    }

    private fun balanceViewContainerTapped() {
        val location = IntArray(2)
        balanceViewContainer.contentView.getLocationOnScreen(location)
        WMenuPopup.present(
            balanceViewContainer.contentView,
            listOf(
                MBaseCurrency.USD,
                MBaseCurrency.EUR,
                MBaseCurrency.RUB,
                MBaseCurrency.CNY,
                MBaseCurrency.BTC,
                MBaseCurrency.TON
            ).map {
                val totalBalance =
                    BalanceStore.calcTotalBalanceInBaseCurrency(account!!.accountId, it)
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.SelectableItem(
                        title = it.currencyName,
                        subtitle = totalBalance?.toString(
                            decimals = 9,
                            currency = it.sign,
                            currencyDecimals = 9,
                            smartDecimals = true,
                            roundUp = false
                        ),
                        isSelected = WalletCore.baseCurrency.currencySymbol == it.currencySymbol
                    ),
                    false,
                ) {
                    WalletCore.setBaseCurrency(newBaseCurrency = it.currencyCode) { _, _ -> }
                    WidgetsConfigurations.reloadWidgets(context)
                }
            },
            offset = (-location[0] + (window.navigationControllers.last().width / 2) - 112.5f.dp).toInt(),
            verticalOffset = (-8).dp,
            popupWidth = 225.dp,
            aboveView = false
        )
    }

    private fun addressLabelTapped() {
        if (account?.isMultichain != true) {
            val clipboard =
                context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip =
                ClipData.newPlainText("", account?.firstAddress)
            clipboard.setPrimaryClip(clip)
            Toast.makeText(
                context,
                LocaleController.getString("Your address was copied!"),
                Toast.LENGTH_SHORT
            ).show()
            return
        }

        val location = IntArray(2)
        addressLabelContainer.getLocationInWindow(location)

        lateinit var popupWindow: WPopupWindow
        val menuWidth = 272.dp
        val items =
            listOf(MBlockchain.ton, MBlockchain.tron).mapNotNull { chain ->
                val fullAddress = account?.addressByChain[chain.name]
                val shortAddress =
                    fullAddress?.formatStartEndAddress(4, 4) ?: return@mapNotNull null
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
