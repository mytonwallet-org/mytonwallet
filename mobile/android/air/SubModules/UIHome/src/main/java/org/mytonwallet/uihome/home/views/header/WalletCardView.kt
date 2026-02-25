package org.mytonwallet.uihome.home.views.header

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.view.Gravity
import android.view.TouchDelegate
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import com.facebook.fresco.ui.common.OnFadeListener
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.WalletTypeView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.getLocationOnScreen
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.FontManager
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.NftGradientHelpers
import org.mytonwallet.app_air.uicomponents.helpers.TiltSensorManager
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WLetterSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WSpacingSpan
import org.mytonwallet.app_air.uicomponents.helpers.textOffset
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.AutoScaleContainerView
import org.mytonwallet.app_air.uicomponents.widgets.IPopup
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WGradientMaskView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLinearLayout
import org.mytonwallet.app_air.uicomponents.widgets.WMultichainAddressLabel
import org.mytonwallet.app_air.uicomponents.widgets.WShiningView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.balance.WBalanceView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.SensitiveDataMaskView
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetsConfigurations
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.signSpace
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletbasecontext.utils.trimAddress
import org.mytonwallet.app_air.walletbasecontext.utils.trimDomain
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.helpers.ShareHelpers
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.setBaseCurrency
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MAccount.AccountChain
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.uihome.home.views.UpdateStatusView
import org.mytonwallet.uihome.home.views.header.seasonal.SeasonalOverlayView
import java.math.BigInteger
import kotlin.math.absoluteValue
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class WalletCardView(
    val window: WWindow
) : WView(window), WThemedView, TiltSensorManager.TiltObserver {

    companion object {
        const val EXPANDED_RADIUS = 26
        const val COLLAPSED_RADIUS = 4.5f
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
    private var isPresentingImage = false

    var statusViewState: UpdateStatusView.State = UpdateStatusView.State.Updated("")
        private set

    private val cardFullWidth: Int
        get() {
            return window.window.decorView.width - 32.dp
        }

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
                cardFullWidth.toFloat(),
                currentTiltX,
                currentTiltY
            )
    }

    // CHILDREN ////////////////////////////////////////////////////////////////////////////////////
    private val img = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(0f)
        fadeListener = object : OnFadeListener {
            override fun onFadeStarted() {
                isPresentingImage = true
                resumeBlurringIfNeeded()
            }

            override fun onFadeFinished() {
                isPresentingImage = false
                pauseBlurring()
            }

            override fun onShownImmediately() {
                onFadeStarted()
                post {
                    onFadeFinished()
                }
            }

        }
    }

    private val miniPlaceholders: MiniPlaceholdersView by lazy {
        MiniPlaceholdersView(context).apply {
            layoutParams = LayoutParams(36.dp, WRAP_CONTENT)
            alpha = 0f
            pivotY = 0f
            pivotX = 18f.dp
        }
    }

    private var balanceView = WBalanceView(context).apply {
        clipChildren = false
        clipToPadding = false
        primaryColor = WColor.White.color
        secondaryColor = WColor.White.color
        smartDecimalsAlpha = true
        reducedDecimalsAlpha = 191
        smartDecimalsColor = true
        typeface = WFont.NunitoExtraBold.typeface
        containerWidth = window.windowView.width - 34.dp
        onAnimationStateChanged = { isAnimating ->
            if (isAnimating) {
                resumeBlurringIfNeeded()
            } else {
                pauseBlurring()
            }
        }
    }
    private lateinit var balanceViewMaskWrapper: WGradientMaskView
    private val arrowDownDrawable = ContextCompat.getDrawable(
        context, R.drawable.ic_arrows_14
    )
    private var arrowImageView = AppCompatImageView(context).apply {
        setImageDrawable(arrowDownDrawable)
        alpha = 0.5f
    }
    private val balanceViewContainer: WSensitiveDataContainer<AutoScaleContainerView> by lazy {
        val linearLayout = LinearLayout(context).apply {
            clipChildren = false
            clipToPadding = false
            layoutDirection = LAYOUT_DIRECTION_LTR
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        balanceViewMaskWrapper = WGradientMaskView(balanceView)
        linearLayout.addView(balanceViewMaskWrapper, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        linearLayout.addView(arrowImageView, LayoutParams(18.dp, 24.dp).apply {
            leftMargin = 2.dp
            topMargin = 3.dp
            rightMargin = 2.dp
        })
        linearLayout.setOnClickListener {
            if (mode == HomeHeaderView.Mode.Collapsed)
                return@setOnClickListener
            balanceViewContainerTapped()
        }
        WSensitiveDataContainer(
            AutoScaleContainerView(linearLayout).apply {
                clipChildren = false
                clipToPadding = false
                maxAllowedWidth = balanceView.containerWidth
                minPadding = 16.dp
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

    private val balanceChangeChevron = ContextCompat.getDrawable(
        context, org.mytonwallet.app_air.icons.R.drawable.ic_arrow_right_16_24
    )?.apply {
        mutate()
        setBounds(0, 0, intrinsicWidth, intrinsicHeight)
    }

    private val balanceChangeLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        lbl.setPadding(8.dp, 3.dp, 8.dp, 3.dp)
        lbl.setStyle(16f, WFont.NunitoSemiBold)
        lbl.compoundDrawablePadding = 0
        lbl.setCompoundDrawablesRelativeWithIntrinsicBounds(null, null, balanceChangeChevron, null)
        lbl.foreground = WRippleDrawable.create(14f.dp).apply {
            rippleColor = Color.WHITE.colorWithAlpha(25)
        }
        lbl.setOnClickListener {
            if (mode == HomeHeaderView.Mode.Collapsed) return@setOnClickListener
            WalletCore.notifyEvent(WalletEvent.OpenUrl("https://portfolio.mytonwallet.io"))
        }
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

    private val addressLabel: WMultichainAddressLabel by lazy {
        WMultichainAddressLabel(context).apply {
            setStyle(16f, WFont.Medium)
            setPadding(5.dp, 1.5f.dp.roundToInt(), 5.dp, 2.dp)
            containerWidth = cardFullWidth
            background = WRippleDrawable.create(20f.dp).apply {
                rippleColor = Color.WHITE.colorWithAlpha(25)
            }
        }
    }

    private var walletTypeView: WalletTypeView

    private val bottomViewContainer = WLinearLayout(context, LinearLayout.HORIZONTAL).apply {
        gravity = Gravity.CENTER
        setPadding(0, 4.dp, 0, 4.dp)
        clipToPadding = false
        walletTypeView = object : WalletTypeView(context, true) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                addressLabel.gradientOffset = -w
            }
        }
        addView(walletTypeView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            marginStart = 2.dp
            marginEnd = 1.dp
        })
        addView(addressLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    private val mintIconRipple = WRippleDrawable.create(20f.dp).apply {
        rippleColor = Color.WHITE.colorWithAlpha(25)
    }
    private val mintIcon = AppCompatImageView(context).apply {
        id = generateViewId()
        scaleType = ImageView.ScaleType.CENTER
        setOnClickListener {
            if (mode == HomeHeaderView.Mode.Collapsed)
                return@setOnClickListener
            val url = ExplorerHelpers.getMtwCardsUrl(
                AccountStore.activeAccount?.network ?: MBlockchainNetwork.MAINNET
            )
            WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
        }
        background = mintIconRipple
        isGone = true
    }

    private val shiningView = WShiningView(context).apply {
        visibility = GONE
    }

    private val balanceChangeBlurView: WBlurryBackgroundView? =
        if (DevicePerformanceClassifier.isHighClass)
            WBlurryBackgroundView(
                context,
                fadeSide = null
            ).apply {
                setOverlayColor(WColor.Transparent)
                setBackgroundColor(Color.TRANSPARENT, 14f.dp, clipToBounds = true)
            }
        else
            null

    private val seasonalOverlayView = SeasonalOverlayView(context).apply {
        id = generateViewId()
    }

    private val contentView: WView by lazy {
        val v = WView(context).apply {
            clipChildren = false
            clipToPadding = false
        }
        val maxBottomContainerWidth = max(240.dp, window.windowView.width - (34 + 96).dp)
        v.addView(img, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        v.addView(shiningView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        v.addView(seasonalOverlayView, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))
        v.addView(miniPlaceholders)
        v.addView(balanceViewContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        balanceChangeBlurView?.let { balanceChangeBlurView ->
            v.addView(balanceChangeBlurView, LayoutParams(MATCH_CONSTRAINT, 28.dp))
            balanceChangeBlurView.setupWith(v)
        }
        v.addView(balanceChangeLabel, LayoutParams(WRAP_CONTENT, 28.dp))
        v.addView(balanceSkeletonView, LayoutParams(134.dp, 56.dp))
        v.addView(balanceChangeSkeletonView, LayoutParams(134.dp, 28.dp))
        v.addView(bottomViewContainer, LayoutParams(maxBottomContainerWidth, WRAP_CONTENT))
        v.addView(mintIcon, LayoutParams(40.dp, 40.dp))

        v.setConstraints {
            allEdges(img)
            allEdges(seasonalOverlayView)
            toCenterX(miniPlaceholders)
            toTop(miniPlaceholders)
            toTop(balanceViewContainer)
            toCenterX(balanceViewContainer)
            balanceChangeBlurView?.let {
                topToTop(balanceChangeBlurView, balanceChangeLabel)
                centerXToCenterX(balanceChangeBlurView, balanceChangeLabel)
            }
            toTop(balanceChangeLabel)
            toCenterX(balanceChangeLabel)
            toCenterX(bottomViewContainer)
            toBottom(bottomViewContainer, 10f)
            topToTop(balanceSkeletonView, balanceViewContainer)
            centerXToCenterX(balanceSkeletonView, balanceViewContainer)
            edgeToEdge(balanceChangeSkeletonView, balanceChangeLabel)
            toEnd(mintIcon, 4f)
        }

        v.post {
            val topOffset = (((parent as View).width - 32.dp) * RATIO - 40.dp).roundToInt()
            v.setConstraints {
                toBottom(mintIcon, 5f)
                constrainMaxWidth(balanceViewContainer.id, (parent as View).width - 34.dp)
            }
        }

        walletTypeView.setupBlurWith(v)
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
        addressLabel.setOnClickListener {
            if (mode == HomeHeaderView.Mode.Collapsed)
                return@setOnClickListener
            openAddressMenu()
        }

        addressLabel.onLongPressChain = { chainName, _, _ ->
            if (mode != HomeHeaderView.Mode.Collapsed) {
                val chain = MBlockchain.supportedChains.find { it.name == chainName }
                if (chain != null) {
                    account?.byChain?.get(chainName)?.let { accountChain ->
                        copyAccountToClipboard(accountChain, chain)
                    }
                }
            }
        }

        addressLabel.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            val rect = Rect()
            addressLabel.getHitRect(rect)
            rect.inset(-5.dp, -4.dp)
            bottomViewContainer.touchDelegate = TouchDelegate(rect, addressLabel)
        }

        updateSeasonalTheme()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startSensorListening()
        resumeBlurringIfNeeded()
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
                    cardFullWidth.toFloat(),
                    currentTiltX,
                    currentTiltY
                )
            val colors = cardNft?.metadata?.mtwCardColors ?: return@let
            setLabelColors(colors.first, colors.second, drawGradient = true)
            return
        } ?: run {
            stopSensorListening()
            shiningView.background = null
        }
        setLabelColors(Color.WHITE, Color.WHITE.colorWithAlpha(191), drawGradient = false)

        if (balanceChangeBlurView == null)
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
        // Scale placeholders proportionally to the card's actual size
        val cardWidth = this.layoutParams?.width ?: 36.dp
        val placeholderScale = if (cardWidth > 0) cardWidth / 36f.dp else 1f
        miniPlaceholders.scaleX = placeholderScale
        miniPlaceholders.scaleY = placeholderScale

        balanceViewContainer.y = balanceY
        balanceSkeletonView.y = balanceY
        balanceChangeLabel.y = balanceY + 64.dp
        balanceChangeBlurView?.y = balanceChangeLabel.y
        balanceChangeSkeletonView.y = balanceChangeLabel.y

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
                            if (balance24h == 0.0) "" else "${if (balance - balance24h >= 0) "+$signSpace" else "-$signSpace"}${
                                kotlin.math.abs(
                                    ((balance - balance24h) / balance24h * 10000).roundToInt() / 100f
                                )
                            }% · "
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
            balanceChangeBlurView?.alpha = 0f
            balanceChangeBlurView?.fadeIn()
            balanceChangeLabel.alpha = 0f
            balanceChangeLabel.fadeIn()
        }
        balanceChangeLabel.contentView.text = balanceChangeString
        balanceChangeLabel.visibility =
            if (balanceChangeLabel.contentView.text.isNullOrEmpty()) INVISIBLE else VISIBLE
        balanceChangeBlurView?.visibility = balanceChangeLabel.visibility
    }

    fun animateBalance(animateConfig: WBalanceView.AnimateConfig) {
        if (balanceAmount == null && animateConfig.amount != null) {
            fadeInBalanceContainer()
            showBalanceArrow(animateConfig.animated)
            hideSkeletons()
        } else if (animateConfig.amount == null) {
            showSkeletons()
        }
        balanceAmount = animateConfig.amount
        balanceView.animateText(animateConfig)
        updateAddressLabel()
    }

    fun showSkeletons() {
        if (isShowingSkeletons)
            return
        isShowingSkeletons = true
        balanceViewContainer.visibility = INVISIBLE
        balanceSkeletonView.visibility = VISIBLE
        balanceSkeletonView.alpha = 1f
        val showBalanceChangePlace = account?.isNew != true && balanceAmount != BigInteger.ZERO
        balanceChangeSkeletonView.isGone = !showBalanceChangePlace
        balanceChangeSkeletonView.alpha = 1f
        arrowImageView.visibility = INVISIBLE
        updateSkeletonViewColors()
    }

    fun hideSkeletons() {
        if (!isShowingSkeletons)
            return
        isShowingSkeletons = false
        balanceViewContainer.visibility = VISIBLE
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
        if (::balanceViewMaskWrapper.isInitialized)
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
        updateAddressLabel()
        updateCardImage()
        walletTypeView.configure(account)
        balanceAmount = null
        animateBalance(
            WBalanceView.AnimateConfig(
                null,
                0,
                "",
                animated = false,
                setInstantly = mode == HomeHeaderView.Mode.Collapsed,
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
            img.set(Content(Content.Image.Res(org.mytonwallet.app_air.uicomponents.R.drawable.img_card)))
            contentView.setConstraints {
                allEdges(img)
            }
            shiningView.visibility = GONE
            return
        }
        shiningView.visibility = VISIBLE
        img.hierarchy.setPlaceholderImage(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uicomponents.R.drawable.img_card
            )
        )
        img.set(Content.ofUrl(cardNft?.metadata?.cardImageUrl(false) ?: ""))
    }

    fun updateAddressLabel() {
        addressLabel.displayAddresses(account, WMultichainAddressLabel.walletExpandStyle)
    }

    fun updateSeasonalTheme() {
        seasonalOverlayView.updateSeasonalTheme()
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
            miniPlaceholders.fadeOut(AnimationConstants.INSTANT_ANIMATION)
            shiningView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            seasonalOverlayView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            miniPlaceholders.alpha = 0f
            shiningView.alpha = 1f
            seasonalOverlayView.alpha = 1f
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
            miniPlaceholders.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            shiningView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
            seasonalOverlayView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION)
        } else {
            miniPlaceholders.alpha = 1f
            shiningView.alpha = 0f
            seasonalOverlayView.alpha = 0f
        }
    }

    var currentRadius = -1f
    fun setRoundingParam(radius: Float) {
        if (this.currentRadius == radius)
            return
        this.currentRadius = radius
        setBackgroundColor(Color.TRANSPARENT, radius, true)
        img.setBackgroundColor(Color.TRANSPARENT, radius, true)
        shiningView.radius = radius
    }

    fun updateMintIconVisibility() {
        mintIcon.isGone =
            WGlobalStorage.getCardsInfo(account?.accountId ?: "") == null &&
                !WGlobalStorage.isCardMinting(account?.accountId ?: "")
    }

    fun viewWillDisappear() {
        balanceView.interruptAnimation()
    }

    fun updateActionsTransformProgress(progress: Float) {
        updateActionsAlpha(progress)
    }

    // PRIVATE METHODS /////////////////////////////////////////////////////////////////////////////
    private fun updateActionsAlpha(actionsAlpha: Float) {
        addressLabel.alpha = actionsAlpha
        mintIcon.alpha = actionsAlpha
        walletTypeView.alpha = actionsAlpha
    }

    private var _primaryColor: Int? = null
    private var _secondaryColor: Int? = null
    private var _drawGradient: Boolean? = null
    private fun setLabelColors(primaryColor: Int, secondaryColor: Int, drawGradient: Boolean) {
        if (_primaryColor == primaryColor &&
            _secondaryColor == secondaryColor &&
            _drawGradient == drawGradient
        )
            return
        _primaryColor = primaryColor
        _secondaryColor = secondaryColor
        _drawGradient = drawGradient
        if (::balanceViewMaskWrapper.isInitialized)
            balanceViewMaskWrapper.setupColors(
                intArrayOf(
                    primaryColor.colorWithAlpha(191),
                    primaryColor,
                    primaryColor.colorWithAlpha(191)
                )
            )
        balanceView.alpha = 1f
        balanceView.updateColors(primaryColor, secondaryColor, drawGradient)
        arrowDownDrawable?.setTint(secondaryColor)
        addressLabel.setTextColor(primaryColor, secondaryColor, drawGradient)
        updateAddressLabel()
        miniPlaceholders.setColor(primaryColor)
        mintIcon.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.walletcontext.R.drawable.ic_mint
            )!!.apply {
                setTint(secondaryColor.colorWithAlpha(191))
            }
        )
        cardNft?.metadata?.overlayLabelBackground?.let { it ->
            walletTypeView.setColor(
                it.colorWithAlpha(25),
                it.colorWithAlpha(204)
            )
            balanceChangeLabel.contentView.setTextColor(it.colorWithAlpha(204))
            balanceChangeChevron?.setTint(it.colorWithAlpha(204))
            if (balanceChangeBlurView == null)
                balanceChangeLabel.contentView.setBackgroundColor(it.colorWithAlpha(25), 13f.dp)
        } ?: run {
            walletTypeView.setColor(
                secondaryColor.colorWithAlpha(41),
                secondaryColor.colorWithAlpha(191)
            )
            balanceChangeLabel.contentView.setTextColor(secondaryColor.colorWithAlpha(191))
            balanceChangeChevron?.setTint(secondaryColor.colorWithAlpha(191))
            if (balanceChangeBlurView == null)
                balanceChangeLabel.contentView.setBackgroundColor(
                    secondaryColor.colorWithAlpha(41),
                    13f.dp
                )
        }
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
        contentView.animate().cancel()
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
        val location = balanceViewContainer.contentView.getLocationOnScreen()
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
                    BalanceStore.calcTotalBalanceInBaseCurrency(account!!.accountId, it)?.total
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
            xOffset = (-location.x + (window.navigationControllers.last().width / 2) - 112.5f.dp).toInt(),
            yOffset = (-6).dp,
            popupWidth = 225.dp,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                this@WalletCardView,
                roundRadius = EXPANDED_RADIUS.dp.toFloat(),
                verticalOffset = (-0.5f).dp.roundToInt()
            )
        )
    }

    fun copyFirstAddress() {
        account?.sortedChains()?.firstOrNull()?.let {
            copyAccountToClipboard(it.value, MBlockchain.valueOf(it.key))
        }
    }

    private fun copyAccountToClipboard(account: AccountChain, chain: MBlockchain) {
        val clipboard =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("", account.domain ?: account.address)
        clipboard.setPrimaryClip(clip)
        val text = if (account.domain != null) {
            LocaleController.getString("%chain% Domain Copied")
                .replace("%chain%", chain.displayName)
        } else {
            LocaleController.getString("%chain% Address Copied")
                .replace("%chain%", chain.displayName)
        }
        Haptics.play(this, HapticType.LIGHT_TAP)
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }

    fun openAddressMenu(anchorView: View? = null) {
        val anchor = anchorView ?: addressLabel
        val location = anchor.getLocationInWindow()

        lateinit var popup: IPopup
        val menuWidth = 276.dp
        val copyDrawable = ContextCompat.getDrawable(
            context,
            R.drawable.ic_copy
        )?.apply {
            mutate()
            setTint(WColor.SecondaryText.color)
            val width = 16.dp
            val height = 16.dp
            setBounds(0, -FontManager.activeFont.textOffset, width, height)
        }
        val items =
            account?.sortedChains()?.map { accountChain ->
                val chain = MBlockchain.valueOf(accountChain.key)
                val accountChainValue = accountChain.value
                val fullAddress = accountChainValue.address
                val domain = accountChainValue.domain?.trimDomain(16)
                val shortAddress = fullAddress.trimAddress(12)
                val titleText = domain ?: buildSpannedString {
                    inSpans(WLetterSpacingSpan(0.014f)) {
                        append(shortAddress)
                    }
                }
                val title: CharSequence = buildSpannedString {
                    val imageSpan = copyDrawable?.let { VerticalImageSpan(it) }
                    if (LocaleController.isRTL) {
                        imageSpan?.let {
                            inSpans(WSpacingSpan(2.dp)) { append(" ") }
                            inSpans(it) { append(" ") }
                            inSpans(WSpacingSpan(2.dp)) { append(" ") }
                        }
                        append(titleText)
                    } else {
                        append(titleText)
                        imageSpan?.let {
                            inSpans(WSpacingSpan(2.dp)) { append(" ") }
                            inSpans(it) { append(" ") }
                            inSpans(WSpacingSpan(2.dp)) { append(" ") }
                        }
                    }
                    styleDots()
                }
                val subtitle: CharSequence = if (domain != null) {
                    buildSpannedString {
                        inSpans(WLetterSpacingSpan(0.034f)) {
                            append(shortAddress)
                            append(" · ")
                            append(chain.displayName)
                        }
                        styleDots()
                    }
                } else {
                    buildSpannedString {
                        inSpans(WLetterSpacingSpan(0.034f)) {
                            append(chain.displayName)
                        }
                    }
                }

                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            chain.icon,
                            tintColor = null,
                            iconSize = 36.dp,
                            iconMargin = 10.dp
                        ),
                        title = title,
                        subtitle = subtitle,
                        trailingView = object : AppCompatImageView(contentView.context),
                            WThemedView {
                            init {
                                updateTheme()
                                setOnClickListener {
                                    val network = account?.network ?: return@setOnClickListener
                                    val config = ExplorerHelpers.createAddressExplorerConfig(
                                        chain, network, fullAddress
                                    ) ?: return@setOnClickListener
                                    WalletCore.notifyEvent(WalletEvent.OpenUrlWithConfig(config))
                                    popup.dismiss()
                                }
                                translationX = 4f.dp
                            }

                            override val isTinted = true
                            override fun updateTheme() {
                                val drw = ContextCompat.getDrawable(context, R.drawable.ic_world)
                                drw?.setTint(WColor.Tint.color)
                                setImageDrawable(drw)
                                addRippleEffect(WColor.SecondaryBackground.color)
                            }

                            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                                super.onMeasure(28.dp.exactly, 28.dp.exactly)
                            }
                        },
                        textMargin = 58.dp
                    ),
                    false,
                ) {
                    account?.byChain[chain.name]?.let { accountChain ->
                        copyAccountToClipboard(accountChain, chain)
                    }
                }
            }?.toMutableList() ?: mutableListOf()
        account?.shareLink?.let { shareLink ->
            items.lastOrNull()?.also { it.hasSeparator = true }
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = Icon(
                            R.drawable.ic_share,
                            tintColor = WColor.SecondaryText,
                            iconSize = 30.dp,
                            iconMargin = 16.dp
                        ),
                        title = LocaleController.getString("Share Wallet Link"),
                        textMargin = 58.dp
                    ),
                    false,
                ) {
                    ShareHelpers.shareText(
                        context,
                        shareLink,
                        LocaleController.getString("Share Wallet Link")
                    )
                }
            )
        }

        popup = WMenuPopup.present(
            anchor,
            items,
            popupWidth = menuWidth,
            xOffset = -location.x + ((parent as View).width / 2) - menuWidth / 2,
            yOffset = 0,
            positioning = WMenuPopup.Positioning.BELOW,
            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                anchor,
                roundRadius = 16f.dp
            )
        )
    }

    val shouldRenderBlurs: Boolean
        get() {
            return isAttachedToWindow && (balanceView.isAnimating || isPresentingImage)
        }

    private fun resumeBlurringIfNeeded() {
        if (!shouldRenderBlurs) {
            return
        }
        balanceChangeBlurView?.resumeBlurring()
        walletTypeView.resumeBlurring()
    }

    private fun pauseBlurring() {
        if (shouldRenderBlurs) {
            return
        }
        balanceChangeBlurView?.pauseBlurring()
        walletTypeView.pauseBlurring()
    }
}
