package org.mytonwallet.app_air.uireceive

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
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
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItem
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TRON_USDT_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference

// TODO:: Refactor required. The current implementation is too tightly coupled with Ton and Tron.
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

    private val receiveViewModel by lazy { ViewModelProvider(this)[ReceiveViewModel::class.java] }

    private val walletAddressTon = AccountStore.activeAccount?.tonAddress
    private val walletAddressTron = AccountStore.activeAccount?.tronAddress

    val qrCodeVcTon = if (walletAddressTon != null) QRCodeVC(context, MBlockchain.ton) else null
    val qrCodeVcTron = if (walletAddressTron != null) QRCodeVC(context, MBlockchain.tron) else null
    private var isShowingTon = true
        set(value) {
            if (field == value)
                return
            field = value
            if (!value) {
                hideInvoiceView()
            } else {
                showInvoiceView()
            }
        }

    private val qrSegmentView: WSegmentedController by lazy {
        val segmentedController = WSegmentedController(
            navigationController!!,
            arrayListOf<WSegmentedControllerItem>().apply {
                if (qrCodeVcTon != null) {
                    add(WSegmentedControllerItem(qrCodeVcTon, null))
                }
                if (qrCodeVcTron != null) {
                    add(WSegmentedControllerItem(qrCodeVcTron, null))
                }
            },
            isTransparent = true,
            applySideGutters = false,
            defaultSelectedIndex = if (defaultChain == MBlockchain.tron && walletAddressTon != null) 1 else 0,
            onOffsetChange = { position, currentOffset ->
                if (walletAddressTon == null) {
                    blueColorView.alpha = 0f
                    redColorView.alpha = 1f
                } else {
                    blueColorView.alpha = 1f - currentOffset.coerceIn(0f, 1f)
                    redColorView.alpha = currentOffset
                }

                if (qrCodeVcTon != null)
                    animateQrView(
                        qrCodeVcTon.qrCodeView,
                        qrCodeVcTon.ornamentView,
                        -1,
                        currentOffset
                    )
                if (qrCodeVcTron != null) {
                    animateQrView(
                        qrCodeVcTron.qrCodeView,
                        qrCodeVcTron.ornamentView,
                        1,
                        if (qrCodeVcTon == null)
                            currentOffset
                        else
                            1f - currentOffset.coerceIn(
                                0f,
                                1f
                            )
                    )

                    val height =
                        if (qrCodeVcTon != null) {
                            ((1 - currentOffset) * qrCodeHeight(qrCodeVcTon)) + (currentOffset * qrCodeHeight(
                                qrCodeVcTron
                            ))
                        } else {
                            qrCodeHeight(qrCodeVcTron)
                        }
                    val layoutParams = qrSegmentView.layoutParams
                    layoutParams.height = height.toInt()
                    qrSegmentView.layoutParams = layoutParams
                }

                isShowingTon = blueColorView.alpha > redColorView.alpha
            }
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

    private val blueColorView = View(context).apply {
        id = generateViewId()
        alpha = 1f
    }

    private val redColorView = View(context).apply {
        id = generateViewId()
        alpha = 0f
    }

    private val backgroundColorView = WView(context).apply {
        setBackgroundColor(WColor.Background.color, 0f, ViewConstants.BIG_RADIUS.dp)
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
                LocaleController.getString("Your address was copied!"),
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
    private val buyWithCardSeparator: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }
    private val buyWithCardView: WView by lazy {
        val v = WView(context)
        v.isGone = AccountStore.activeAccount?.supportsBuyWithCard != true
        if (v.isVisible) {
            v.addView(buyWithCardLabel)
            v.setConstraints {
                toStart(buyWithCardLabel, 20f)
                toCenterY(buyWithCardLabel)
                toStart(buyWithCardSeparator, 20f)
                toEnd(buyWithCardSeparator)
                toBottom(buyWithCardSeparator)
            }
            v.setOnClickListener {

                val tokenSymbol: String = when (currentQRCode.chain) {
                    MBlockchain.ton -> {
                        "ton"
                    }

                    MBlockchain.tron -> {
                        "tron"
                    }

                    else -> {
                        return@setOnClickListener
                    }
                }
                openBuyWithCard(tokenSymbol)
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
    private val buyWithCryptoSeparator: WBaseView by lazy {
        val v = WBaseView(context)
        v
    }
    private val buyWithCryptoView: WView by lazy {
        val v = WView(context)
        v.isGone = AccountStore.activeAccount?.supportsBuyWithCrypto != true
        if (v.isVisible) {
            v.addView(buyWithCryptoLabel)
            v.setConstraints {
                toStart(buyWithCryptoLabel, 20f)
                toCenterY(buyWithCryptoLabel)
                toStart(buyWithCryptoSeparator, 20f)
                toEnd(buyWithCryptoSeparator)
                toBottom(buyWithCryptoSeparator)
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
            toCenterY(invoiceLabel)
        }
        v.setOnClickListener {
            val invoiceVC = InvoiceVC(context)
            navigationController?.push(invoiceVC)
        }
        v
    }

    private val scrollingContentView: WView by lazy {
        val v = WView(context)

        v.addView(
            redColorView,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.WRAP_CONTENT)
        )
        v.addView(
            blueColorView,
            LayoutParams(LayoutParams.MATCH_CONSTRAINT, LayoutParams.WRAP_CONTENT)
        )
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
        v.addView(buyWithCardView, LayoutParams(MATCH_PARENT, 50.dp))
        v.addView(buyWithCryptoView, LayoutParams(MATCH_PARENT, 50.dp))
        v.addView(invoiceView, LayoutParams(MATCH_PARENT, 50.dp))
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
        qrCodeVcTon?.qrCodeView?.setLayerType(View.LAYER_TYPE_HARDWARE, layerPaint)
        qrCodeVcTron?.qrCodeView?.setLayerType(View.LAYER_TYPE_HARDWARE, layerPaint)

        view.addView(scrollView, LayoutParams(0, 0))
        view.setConstraints {
            allEdges(scrollView)
        }
        scrollingContentView.setConstraints {
            toTopPx(titleLabel, navigationController?.getSystemBars()?.top ?: 0)
            toCenterX(titleLabel)
            toTop(qrSegmentView)
            toCenterX(qrSegmentView)
            topToTop(redColorView, qrSegmentView)
            startToStart(redColorView, qrSegmentView)
            endToEnd(redColorView, qrSegmentView)
            topToTop(blueColorView, qrSegmentView)
            startToStart(blueColorView, qrSegmentView)
            endToEnd(blueColorView, qrSegmentView)
            topToBottom(backgroundColorView, blueColorView)
            bottomToBottom(backgroundColorView, qrSegmentView)
            toCenterX(backgroundColorView)
            topToBottom(optionsSeparatorView, qrSegmentView)
            topToBottom(buyWithCardView, optionsSeparatorView)
            topToBottom(buyWithCryptoView, buyWithCardView)
            topToBottom(invoiceView, buyWithCryptoView)
            toBottom(invoiceView)
            toCenterX(buyWithCardView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toCenterX(buyWithCryptoView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toCenterX(invoiceView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }

        updateTheme()

        arrayListOf(redColorView, blueColorView).forEach { colorView ->
            val layoutParams = colorView.layoutParams
            layoutParams.height = qrTransparentHeight(qrCodeVcTon ?: qrCodeVcTron!!)
            colorView.layoutParams = layoutParams
        }
        (if (defaultChain == MBlockchain.tron && qrCodeVcTron != null)
            qrCodeVcTron
        else
            qrCodeVcTon!!).addressView.viewTreeObserver.addOnPreDrawListener(viewTreeObserver)
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
        buyWithCardView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            0f
        )
        buyWithCardView.addRippleEffect(WColor.SecondaryBackground.color)
        buyWithCardLabel.setTextColor(WColor.Tint.color)
        buyWithCardSeparator.setBackgroundColor(WColor.Separator.color)
        buyWithCryptoView.setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isShowingTon) 0f else ViewConstants.BIG_RADIUS.dp,
        )
        buyWithCryptoView.addRippleEffect(WColor.SecondaryBackground.color)
        buyWithCryptoLabel.setTextColor(WColor.Tint.color)
        buyWithCryptoSeparator.setBackgroundColor(WColor.Separator.color)
        invoiceView.setBackgroundColor(
            WColor.Background.color,
            if (AccountStore.activeAccount?.supportsBuyWithCrypto == true ||
                AccountStore.activeAccount?.supportsBuyWithCard == true
            )
                0f
            else ViewConstants.BIG_RADIUS.dp,
            ViewConstants.BIG_RADIUS.dp,
        )
        invoiceView.addRippleEffect(WColor.SecondaryBackground.color)
        invoiceLabel.setTextColor(WColor.Tint.color)
        qrSegmentView.layoutParams.height = qrHeight

        val tonGradient = GradientDrawable().apply {
            colors = MBlockchain.ton.gradientColors
            orientation = GradientDrawable.Orientation.TL_BR
            gradientType = GradientDrawable.LINEAR_GRADIENT
            shape = GradientDrawable.RECTANGLE
        }
        blueColorView.background = tonGradient
        val tronGradient = GradientDrawable().apply {
            colors = MBlockchain.tron.gradientColors
            orientation = GradientDrawable.Orientation.TL_BR
            gradientType = GradientDrawable.LINEAR_GRADIENT
            shape = GradientDrawable.RECTANGLE
        }
        redColorView.background = tronGradient
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toCenterX(buyWithCardView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toCenterX(buyWithCryptoView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toCenterX(invoiceView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }
    }

    private fun openBuyWithCard(chain: String) {
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
        receiveViewModel.buyWithCardUrl(chain, baseCurrency) { url ->
            url?.let {
                openBuyWithCardWebView(
                    chain,
                    baseCurrencies,
                    url,
                    baseCurrency
                )
            } ?: run {
                if (!WalletCore.isConnected())
                    showError(MBridgeError.SERVER_ERROR)
            }
        }
    }

    private fun openBuyWithCardWebView(
        chain: String,
        baseCurrencies: List<MBaseCurrency>,
        url: String,
        defaultCurrency: MBaseCurrency
    ) {
        val nav = WNavigationController(window!!)
        nav.setRoot(
            InAppBrowserVC(
                context,
                null,
                InAppBrowserConfig(
                    url,
                    title = LocaleController.getString("Buy with Card"),
                    injectTonConnectBridge = false,
                    forceCloseOnBack = true,
                    options = baseCurrencies.map { baseCurrency ->
                        InAppBrowserConfig.Option(
                            identifier = baseCurrency.currencyCode,
                            title = baseCurrency.currencyName,
                            onClick = { vc ->
                                receiveViewModel.buyWithCardUrl(chain, baseCurrency, { url ->
                                    url?.let {
                                        (vc.get() as? InAppBrowserVC)?.navigate(url)
                                    }
                                })
                            }
                        )
                    },
                    selectedOption = defaultCurrency.currencyCode
                )
            )
        )
        window?.present(nav)
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
            return if (qrCodeVcTon == null || (qrSegmentView.currentOffset > 0 && qrCodeVcTron != null))
                qrCodeVcTron!!
            else
                qrCodeVcTon
        }

    private val qrHeight: Int
        get() {
            return qrCodeHeight(activeVC)
        }

    private var viewTreeObserver: ViewTreeObserver.OnPreDrawListener? =
        object : ViewTreeObserver.OnPreDrawListener {
            var segmentViewHeight: Int? = null
            override fun onPreDraw(): Boolean {
                val layoutParams = qrSegmentView.layoutParams
                layoutParams.height = qrHeight
                qrSegmentView.layoutParams = layoutParams
                if (segmentViewHeight != null && layoutParams.height > segmentViewHeight!!)
                    qrCodeVcTon?.addressView?.viewTreeObserver?.removeOnPreDrawListener(this)
                segmentViewHeight = layoutParams.height
                return true
            }
        }

    private fun qrCodeHeight(vc: QRCodeVC): Int {
        return vc.getHeight()
    }

    private fun qrTransparentHeight(vc: QRCodeVC): Int {
        return vc.getTransparentHeight() + qrSegmentView.navHeight + (navigationController?.getSystemBars()?.top
            ?: 0)
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
        qrCodeVcTon?.addressView?.viewTreeObserver?.removeOnPreDrawListener(viewTreeObserver)
        viewTreeObserver = null
    }

    private fun hideInvoiceView() {
        ValueAnimator.ofFloat(0f, ViewConstants.BIG_RADIUS.dp).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            addUpdateListener {
                buyWithCryptoView.setBackgroundColor(
                    WColor.Background.color,
                    0f,
                    animatedValue as Float,
                )
            }
            start()
        }
        buyWithCryptoSeparator.fadeOut()
        invoiceView.fadeOut()
        invoiceView.isClickable = false
    }

    private fun showInvoiceView() {
        ValueAnimator.ofFloat(ViewConstants.BIG_RADIUS.dp, 0f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            addUpdateListener {
                buyWithCryptoView.setBackgroundColor(
                    WColor.Background.color,
                    0f,
                    animatedValue as Float,
                )
            }
            start()
        }
        buyWithCryptoSeparator.fadeIn()
        invoiceView.fadeIn()
        invoiceView.isClickable = true
    }
}
