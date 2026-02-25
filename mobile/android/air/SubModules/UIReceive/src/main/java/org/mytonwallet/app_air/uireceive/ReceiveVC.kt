package org.mytonwallet.app_air.uireceive

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.constraintlayout.widget.ConstraintLayout.generateViewId
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.CustomTabsBrowser
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ReceiveVC(
    context: Context,
    private val defaultChain: MBlockchain = MBlockchain.ton,
    private var openBuyWithCardInstantly: Boolean = false,
) : WViewControllerWithModelStore(context) {
    override val TAG = "Receive"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    override val shouldDisplayBottomBar: Boolean
        get() = navigationController?.tabBarController == null

    companion object {
        const val OPTION_ROW_HEIGHT = 50
    }

    private val receiveViewModel by lazy { ViewModelProvider(this)[ReceiveViewModel::class.java] }

    private val addressByChain = AccountStore.activeAccount?.addressByChain ?: emptyMap()

    val availableChains: List<MBlockchain> =
        MBlockchain.supportedChains.filter { addressByChain.containsKey(it.name) }

    val qrCodeVCs: Map<MBlockchain, QRCodeVC> =
        availableChains.associateWith { QRCodeVC(context, it) }

    private val defaultChainIndex = availableChains.indexOf(defaultChain).coerceAtLeast(0)

    private val gradientColorViews: List<View> =
        availableChains.mapIndexed { i, _ ->
            View(context).apply {
                id = generateViewId()
                alpha = if (i == defaultChainIndex) 1f else 0f
            }
        }

    private val currentChain: MBlockchain
        get() = availableChains.getOrElse(qrSegmentView.currentOffset.roundToInt()) { availableChains.first() }

    private val qrSegmentView: WSegmentedController by lazy {
        val defaultIndex = availableChains.indexOf(defaultChain).coerceAtLeast(0)
        val segmentedController = WSegmentedController(
            navigationController!!,
            availableChains.map { chain ->
                WSegmentedControllerItem(qrCodeVCs[chain]!!, null)
            } as ArrayList<WSegmentedControllerItem>,
            isTransparent = true,
            applySideGutters = false,
            defaultSelectedIndex = defaultIndex,
            onOffsetChange = { _, currentOffset ->
                val chainCount = availableChains.size
                for (i in gradientColorViews.indices) {
                    gradientColorViews[i].alpha = when {
                        chainCount == 1 -> 1f
                        i == 0 -> (1f - currentOffset.coerceIn(0f, 1f))
                        i == chainCount - 1 -> (currentOffset - (i - 1)).coerceIn(0f, 1f)
                        else -> {
                            val dist = (currentOffset - i).let { kotlin.math.abs(it) }
                            (1f - dist).coerceIn(0f, 1f)
                        }
                    }
                }

                for ((i, chain) in availableChains.withIndex()) {
                    val vc = qrCodeVCs[chain] ?: continue
                    val progress = (currentOffset - i).let { kotlin.math.abs(it) }.coerceIn(0f, 1f)
                    val direction = if (currentOffset > i) -1 else 1
                    animateQrView(vc.qrCodeView, vc.ornamentView, direction, progress)
                }

                if (chainCount > 1) {
                    val floorIdx = currentOffset.toInt().coerceIn(0, chainCount - 2)
                    val frac = currentOffset - floorIdx
                    val vcA = qrCodeVCs[availableChains[floorIdx]]!!
                    val vcB = qrCodeVCs[availableChains[floorIdx + 1]]!!
                    val height = ((1 - frac) * qrCodeHeight(vcA)) + (frac * qrCodeHeight(vcB))
                    val layoutParams = qrSegmentView.layoutParams
                    layoutParams.height = height.toInt()
                    qrSegmentView.layoutParams = layoutParams
                }

                updateOptionsForOffset(currentOffset)
            },
            forceCenterTabs = true
        )
        segmentedController.addCloseButton()
        segmentedController
    }

    val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(22F, WFont.SemiBold)
        lbl.gravity = Gravity.CENTER
        lbl.text =
            LocaleController.getString("Add Crypto")
        lbl
    }

    private val backgroundColorView = WView(context).apply {
        setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BLOCK_RADIUS.dp)
    }

    private val currentQRCode: QRCodeVC
        get() {
            return (qrSegmentView.currentItem as QRCodeVC)
        }

    private val copyAddressLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Copy Address")
        lbl
    }
    private val copyAddressSeparator: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }
    private val copyAddressView: WView by lazy {
        val v = WView(context)
        v.addView(copyAddressLabel)
        v.setConstraints {
            toStart(copyAddressLabel, 20f)
            toCenterY(copyAddressLabel)
            toStart(copyAddressSeparator, 20f)
            toEnd(copyAddressSeparator, 16f)
            toBottom(copyAddressSeparator)
        }
        v.setOnClickListener {

            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Wallet Address", currentQRCode.walletAddress)
            clipboard.setPrimaryClip(clip)
            Haptics.play(v, HapticType.LIGHT_TAP)
            Toast.makeText(
                context,
                LocaleController.getString("%chain% Address Copied")
                    .replace("%chain%", currentQRCode.chain.displayName),
                Toast.LENGTH_SHORT
            )
                .show()
        }
        v
    }

    private val shareQRCodeLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Share QR Code")
        lbl
    }

    private val optionsSeparatorView: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }

    private val buyWithCardLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Buy with Card")
        lbl
    }

    private val buyWithCardView: WView by lazy {
        val v = WView(context)
        v.isGone = AccountStore.activeAccount?.supportsBuyWithCard != true
        if (v.isVisible) {
            v.addView(buyWithCardLabel)
            v.setConstraints {
                toStart(buyWithCardLabel, 20f)
                toTop(buyWithCardLabel, 14f)
            }
            v.setOnClickListener {
                openBuyWithCard(currentQRCode.chain.name)
            }
        }
        v
    }

    private val buyWithCryptoLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Buy with Crypto")
        lbl
    }

    private val buyWithCryptoView: WView by lazy {
        val v = WView(context)
        v.isGone = AccountStore.activeAccount?.supportsBuyWithCrypto != true
        if (v.isVisible) {
            v.addView(buyWithCryptoLabel)
            v.setConstraints {
                toStart(buyWithCryptoLabel, 20f)
                toCenterY(buyWithCryptoLabel)
            }
            v.setOnClickListener {
                TokenStore.getToken(currentQRCode.chain.nativeSlug)?.let {
                    val sendingToken = when (currentQRCode.chain) {
                        MBlockchain.ton -> {
                            TokenStore.getToken(TRON_USDT_SLUG)
                        }

                        else -> {
                            TokenStore.getToken(TONCOIN_SLUG)
                        }
                    }
                    if (sendingToken != null) {
                        val swapVC = SwapVC(
                            context,
                            defaultSendingToken = MApiSwapAsset.from(sendingToken),
                            defaultReceivingToken = MApiSwapAsset.from(it)
                        )
                        navigationController?.push(swapVC)
                    }
                }
            }
        }
        v
    }

    private val invoiceLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.text =
            LocaleController.getString("Create Deposit Link")
        lbl
    }
    private val invoiceView: WView by lazy {
        val v = WView(context)
        v.addView(invoiceLabel)
        v.setConstraints {
            toStart(invoiceLabel, 20f)
            toTop(invoiceLabel, 14f)
        }
        v.setOnClickListener {
            val invoiceVC = InvoiceVC(context)
            navigationController?.push(invoiceVC)
        }
        v
    }

    private val optionsContainerView: WView by lazy {
        val v = WView(context)
        v.addView(buyWithCardView, LayoutParams(MATCH_PARENT, OPTION_ROW_HEIGHT.dp))
        v.addView(buyWithCryptoView, LayoutParams(MATCH_PARENT, OPTION_ROW_HEIGHT.dp))
        v.addView(invoiceView, LayoutParams(MATCH_PARENT, OPTION_ROW_HEIGHT.dp))
        v.setConstraints {
            toTop(buyWithCardView)
            toCenterX(buyWithCardView)
            topToBottom(buyWithCryptoView, buyWithCardView)
            toCenterX(buyWithCryptoView)
            topToBottom(invoiceView, buyWithCryptoView)
            toCenterX(invoiceView)
            toBottom(invoiceView)
        }
        v.clipToOutline = true
        v.clipChildren = false
        v
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)

        for (colorView in gradientColorViews) {
            v.addView(
                colorView,
                LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.WRAP_CONTENT)
            )
        }
        v.addView(
            backgroundColorView,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.MATCH_CONSTRAINT)
        )
        v.addView(
            qrSegmentView,
            LayoutParams(MATCH_PARENT, qrHeight)
        )
        if (qrSegmentView.items.size == 1) v.addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WNavigationBar.DEFAULT_HEIGHT.dp)
        )
        v.addView(optionsSeparatorView, LayoutParams(MATCH_PARENT, 16.dp))
        v.addView(optionsContainerView, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
        v
    }

    private val scrollView: WScrollView by lazy {
        val sv = WScrollView(WeakReference(this))
        sv.addView(scrollingContentView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        sv
    }

    override fun setupViews() {
        super.setupViews()

        val layerPaint = Paint().apply {
            isAntiAlias = true
        }
        qrCodeVCs.values.forEach { vc ->
            vc.qrCodeView.setLayerType(View.LAYER_TYPE_HARDWARE, layerPaint)
        }

        view.addView(scrollView, LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }
        scrollingContentView.setConstraints {
            toTopPx(titleLabel, navigationController?.getSystemBars()?.top ?: 0)
            toCenterX(titleLabel)
            toTop(qrSegmentView)
            toCenterX(qrSegmentView)
            for (colorView in gradientColorViews) {
                topToTop(colorView, qrSegmentView)
                startToStart(colorView, qrSegmentView)
                endToEnd(colorView, qrSegmentView)
            }
            topToBottom(backgroundColorView, gradientColorViews.first())
            bottomToBottom(backgroundColorView, qrSegmentView)
            toCenterX(backgroundColorView)
            topToBottom(optionsSeparatorView, qrSegmentView)
            topToBottom(optionsContainerView, optionsSeparatorView)
            toBottom(optionsContainerView)
            toCenterX(optionsContainerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }

        updateTheme()
        updateOptionsForOffset(defaultChainIndex.toFloat())

        val firstVC = qrCodeVCs.values.first()
        gradientColorViews.forEach { colorView ->
            val layoutParams = colorView.layoutParams
            layoutParams.height = qrTransparentHeight(firstVC)
            colorView.layoutParams = layoutParams
        }
        val defaultVC = qrCodeVCs[defaultChain] ?: firstVC
        defaultVC.addressView.viewTreeObserver.addOnPreDrawListener(viewTreeObserver)
    }

    override val isTinted = true
    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        titleLabel.setTextColor(Color.WHITE)
        copyAddressView.setBackgroundColor(WColor.Background.color)
        copyAddressView.addRippleEffect(WColor.SecondaryBackground.color)
        copyAddressLabel.setTextColor(WColor.Tint.color)
        copyAddressSeparator.setBackgroundColor(WColor.Separator.color)
        shareQRCodeLabel.setTextColor(WColor.Tint.color)
        optionsSeparatorView.setBackgroundColor(WColor.SecondaryBackground.color)
        optionsContainerView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        buyWithCardView.setBackgroundColor(WColor.Background.color)
        buyWithCardView.addRippleEffect(WColor.SecondaryBackground.color)
        buyWithCardLabel.setTextColor(WColor.Tint.color)
        buyWithCryptoView.setBackgroundColor(WColor.Background.color)
        buyWithCryptoView.addRippleEffect(WColor.SecondaryBackground.color)
        buyWithCryptoLabel.setTextColor(WColor.Tint.color)
        invoiceView.setBackgroundColor(WColor.Background.color)
        invoiceView.addRippleEffect(WColor.SecondaryBackground.color)
        invoiceLabel.setTextColor(WColor.Tint.color)
        qrSegmentView.layoutParams.height = qrHeight

        val cacheWidth = ApplicationContextHolder.screenWidth
        val cacheHeight = (navigationController?.getSystemBars()?.top ?: 0) + 307.dp + 64.dp
        for ((i, chain) in availableChains.withIndex()) {
            val targetView = gradientColorViews[i]
            ReceiveBackgroundCache.render(chain, cacheWidth, cacheHeight) { drawable ->
                drawable?.let {
                    targetView.post { targetView.background = it }
                }
            }
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toCenterX(optionsContainerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }
    }

    private fun openBuyWithCard(chain: String, anchorView: View? = null) {
        val baseCurrencies = listOfNotNull(
            MBaseCurrency.USD,
            MBaseCurrency.EUR,
            if (chain == MBlockchain.ton.name) MBaseCurrency.RUB else null
        )
        val preferredBaseCurrency = if (ConfigStore.countryCode == "RU")
            MBaseCurrency.RUB
        else
            WalletCore.baseCurrency
        val baseCurrency =
            if (baseCurrencies.contains(preferredBaseCurrency))
                preferredBaseCurrency
            else
                MBaseCurrency.USD
        if (anchorView != null && baseCurrencies.size > 1) {
            WMenuPopup.present(
                anchorView,
                baseCurrencies.map { currency ->
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = null,
                            title = currency.currencyName,
                            subtitle = currency.currencyCode,
                        ),
                        onTap = {
                            openBuyWithCardUrl(chain, currency)
                        }
                    )
                },
                positioning = WMenuPopup.Positioning.ALIGNED,
                windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                    view = anchorView,
                    roundRadius = 16f.dp,
                    horizontalOffset = 8.dp,
                    verticalOffset = 0
                )
            )
            return
        }

        openBuyWithCardUrl(chain, baseCurrency)
    }

    private fun openBuyWithCardUrl(chain: String, baseCurrency: MBaseCurrency) {
        buyWithCardView.isClickable = false
        receiveViewModel.buyWithCardUrl(chain, baseCurrency) { url ->
            buyWithCardView.isClickable = true
            url?.let {
                CustomTabsBrowser.open(context, it)
            } ?: run {
                if (!WalletCore.isConnected())
                    showError(MBridgeError.SERVER_ERROR)
            }
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        if (navigationController?.isSwipingBack == true)
            return
        window!!.forceStatusBarLight = true
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        window!!.forceStatusBarLight = true

        if (openBuyWithCardInstantly) {
            openBuyWithCardInstantly = false
            openBuyWithCard(defaultChain.name)
        }
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        window!!.forceStatusBarLight = null
    }

    private val activeVC: QRCodeVC
        get() {
            val offset = qrSegmentView.currentOffset
            val idx = offset.toInt().coerceIn(0, availableChains.size - 1)
            return qrCodeVCs[availableChains[idx]]!!
        }

    private val qrHeight: Int
        get() {
            return qrCodeHeight(activeVC)
        }

    private var viewTreeObserver: ViewTreeObserver.OnPreDrawListener? =
        object : ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                val layoutParams = qrSegmentView.layoutParams
                layoutParams.height = qrHeight
                qrSegmentView.layoutParams = layoutParams
                val defaultVC = qrCodeVCs[defaultChain] ?: qrCodeVCs.values.first()
                defaultVC.addressView.viewTreeObserver.removeOnPreDrawListener(this)
                return true
            }
        }

    private fun qrCodeHeight(vc: QRCodeVC): Int {
        return vc.getHeight()
    }

    private fun qrTransparentHeight(vc: QRCodeVC): Int {
        return vc.getTransparentHeight() + qrSegmentView.navHeight +
            (navigationController?.getSystemBars()?.top ?: 0)
    }

    private fun animateQrView(
        qrCodeView: View,
        ornamentView: View,
        direction: Int,
        progress: Float
    ) {
        val rotation = -10 * progress * direction
        qrCodeView.rotationY = rotation
        ornamentView.rotationY = rotation

        val scale = 1f - (0.5f * progress)
        qrCodeView.scaleX = scale
        qrCodeView.scaleY = scale
        ornamentView.scaleX = scale
        ornamentView.scaleY = scale

        val alpha = 1f - (0.75f * progress)
        qrCodeView.alpha = alpha

        val translation = progress * 100.dp * -direction
        qrCodeView.translationX = translation
        ornamentView.translationX = translation
    }

    override fun onDestroy() {
        super.onDestroy()
        qrSegmentView.onDestroy()
        copyAddressView.setOnClickListener(null)
        buyWithCardView.setOnClickListener(null)
        buyWithCryptoView.setOnClickListener(null)
        val defaultVC = qrCodeVCs[defaultChain] ?: qrCodeVCs.values.firstOrNull()
        defaultVC?.addressView?.viewTreeObserver?.removeOnPreDrawListener(viewTreeObserver)
        viewTreeObserver = null
    }

    private fun updateOptionsForOffset(offset: Float) {
        val tonIndex = availableChains.indexOf(MBlockchain.ton)
        val tonFraction = if (tonIndex >= 0)
            (1f - kotlin.math.abs(offset - tonIndex)).coerceIn(0f, 1f)
        else 0f
        invoiceView.layoutParams?.height = (OPTION_ROW_HEIGHT.dp * tonFraction).toInt()
        invoiceView.requestLayout()
        invoiceView.isClickable = tonFraction == 1f

        if (AccountStore.activeAccount?.supportsBuyWithCard == true) {
            val floorIdx = offset.toInt().coerceIn(0, availableChains.size - 1)
            val ceilIdx = (floorIdx + 1).coerceAtMost(availableChains.size - 1)
            val fracA = if (availableChains[floorIdx].canBuyWithCard) 1f else 0f
            val fracB = if (availableChains[ceilIdx].canBuyWithCard) 1f else 0f
            val buyWithCardFraction = fracA + (fracB - fracA) * (offset - floorIdx)
            val buyWithCardHeight = (OPTION_ROW_HEIGHT.dp * buyWithCardFraction).toInt()
            buyWithCardView.layoutParams?.height = buyWithCardHeight
            buyWithCardView.isGone = buyWithCardHeight == 0
            buyWithCardView.translationY = buyWithCardHeight.toFloat() - OPTION_ROW_HEIGHT.dp
            buyWithCardView.requestLayout()
            buyWithCardView.isClickable = buyWithCardFraction == 1f
        }
    }

}
