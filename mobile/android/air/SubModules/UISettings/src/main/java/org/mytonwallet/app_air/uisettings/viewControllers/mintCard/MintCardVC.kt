package org.mytonwallet.app_air.uisettings.viewControllers.mintCard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.widget.NestedScrollView
import androidx.recyclerview.widget.RecyclerView
import androidx.viewpager2.widget.ViewPager2
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setupSpringFling
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.viewControllers.MfaActionConfirmVC
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardDotsView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardPosterView
import org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views.MintCardProsView
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcore.MINT_CARD_ADDRESS
import org.mytonwallet.app_air.walletcore.MINT_CARD_COMMENT
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcontext.utils.lerpColor
import org.mytonwallet.app_air.walletcore.models.MCardInfo
import org.mytonwallet.app_air.walletcore.moshi.ApiMtwCardType
import org.mytonwallet.app_air.walletcore.moshi.ApiTransferPayload
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.pow
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class MintCardVC(context: Context) : WViewController(context) {
    override val TAG = "MintCard"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false
    override val isSwipeBackAllowed = false

    override val isExpandable = false

    private var calculatedHeight: Int? = null

    override fun getModalHalfExpandedHeight(): Int? {
        if (pagerHost.parent == null || contentContainer.parent == null) {
            return calculatedHeight ?: super.getModalHalfExpandedHeight()
        }
        val width = (scrollView.width.takeIf { it > 0 }
            ?: view.width.takeIf { it > 0 }
            ?: window?.windowView?.width?.takeIf { it > 0 })
            ?: return calculatedHeight ?: super.getModalHalfExpandedHeight()

        contentContainer.measure(
            View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        val contentH = contentContainer.measuredHeight

        val bottomInset = navigationController?.bottomInset ?: 0
        val topInset = navigationController?.getSystemBars()?.top ?: 0
        val footerH = BUTTON_GAP_DP.dp + BUTTON_HEIGHT_DP.dp + BUTTON_GAP_DP.dp + bottomInset

        val maxSheet = ((window?.windowView?.height ?: 0) - topInset)
            .takeIf { it > 0 } ?: (contentH + footerH)
        return minOf(contentH + footerH, maxSheet)
    }

    private fun recalculateModalHeight() {
        if (upgradeButton.parent == null || scrollView.layoutParams == null) return
        val sheetH = getModalHalfExpandedHeight() ?: return
        if (sheetH != calculatedHeight && sheetH > 0) {
            calculatedHeight = sheetH
            navigationController?.onBottomSheetHeightChanged()
        }
    }

    private val orderedTypes = MintCardTypeInfo.ordered
    private var currentIndex = 0

    private val cardsInfo by lazy {
        MintCardHelpers.cardsInfo(displayedAccount.accountId ?: "")
    }

    private val viewPager = ViewPager2(context).apply {
        id = View.generateViewId()
    }

    private fun freeViewPagerVerticalDrags() {
        (viewPager.getChildAt(0) as? RecyclerView)?.apply {
            isNestedScrollingEnabled = false
            addOnItemTouchListener(
                object : RecyclerView.OnItemTouchListener {
                    override fun onInterceptTouchEvent(
                        rv: RecyclerView,
                        e: android.view.MotionEvent
                    ) = false

                    override fun onTouchEvent(rv: RecyclerView, e: android.view.MotionEvent) {}
                    override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
                }
            )
        }
    }

    private val dotsView = MintCardDotsView(context, orderedTypes.size).apply {
        id = View.generateViewId()
    }

    private val pagerHost: android.widget.FrameLayout =
        object : android.widget.FrameLayout(context) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val w = MeasureSpec.getSize(widthMeasureSpec)
                super.onMeasure(
                    widthMeasureSpec,
                    MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY)
                )
            }
        }.apply {
            id = View.generateViewId()
            addView(viewPager, android.widget.FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            addView(
                dotsView,
                android.widget.FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
                    bottomMargin = 92.dp
                }
            )
        }

    private val contentContainer = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    private val prosView = MintCardProsView(context).apply {
        id = View.generateViewId()
    }

    private val upgradeButton = WButton(context).apply {
        id = View.generateViewId()
        setOnClickListener {
            val info = orderedTypes[boundButtonIndex]
            onUpgradePressed(info.type, cardsInfo?.get(info.type))
        }
    }

    private val bottomSection = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    // Routes gestures at dispatch level (which reliably receives every event). A horizontal drag —
    // anywhere in the sheet — is forwarded as a native touch stream to the pager's RecyclerView, so
    // the pager handles it with its own drag + spring-fling physics. Vertical drags fall through to
    // the scroll view / bottom-sheet.
    @SuppressLint("ClickableViewAccessibility")
    private val scrollView: NestedScrollView = object : NestedScrollView(context) {
        private val touchSlop = android.view.ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var forwarding = false
        private var decided = false

        private fun forwardToPager(ev: android.view.MotionEvent, action: Int) {
            val rv = pagerRecyclerView ?: return
            val copy = android.view.MotionEvent.obtain(ev)
            copy.action = action
            // Map from scrollView coords to the pager RecyclerView's coords (x only matters for paging).
            copy.offsetLocation(
                (pagerHost.left - scrollX).toFloat(),
                (pagerHost.top - scrollY).toFloat()
            )
            rv.dispatchTouchEvent(copy)
            copy.recycle()
        }

        override fun dispatchTouchEvent(ev: android.view.MotionEvent): Boolean {
            when (ev.actionMasked) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    downX = ev.x; downY = ev.y
                    forwarding = false; decided = false
                }

                android.view.MotionEvent.ACTION_MOVE -> {
                    if (!decided) {
                        val dx = kotlin.math.abs(ev.x - downX)
                        val dy = kotlin.math.abs(ev.y - downY)
                        if (dx > touchSlop || dy > touchSlop) {
                            decided = true
                            forwarding = dx > dy
                            if (forwarding) {
                                // Cancel whoever started handling this gesture in the scroll tree.
                                val cancel = android.view.MotionEvent.obtain(ev)
                                cancel.action = android.view.MotionEvent.ACTION_CANCEL
                                super.dispatchTouchEvent(cancel)
                                cancel.recycle()
                                // Start a fresh native gesture on the pager.
                                forwardToPager(ev, android.view.MotionEvent.ACTION_DOWN)
                            }
                        }
                    }
                    if (forwarding) {
                        forwardToPager(ev, android.view.MotionEvent.ACTION_MOVE)
                        return true
                    }
                }

                android.view.MotionEvent.ACTION_UP,
                android.view.MotionEvent.ACTION_CANCEL -> {
                    if (forwarding) {
                        forwardToPager(ev, ev.actionMasked)
                        forwarding = false; decided = false
                        return true
                    }
                    decided = false
                }
            }
            return super.dispatchTouchEvent(ev)
        }
    }.apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = NestedScrollView.OVER_SCROLL_NEVER
    }

    private val bottomReversedCorner = ReversedCornerViewUpsideDown(context, scrollView)

    private val closeButton = WImageButton(context).apply {
        id = View.generateViewId()
        setImageDrawable(context.getDrawableCompat(R.drawable.ic_close))
        updateColors(WColor.White, WColor.BackgroundRipple)
        setPaddingDp(8, 8, 8, 8)
        setOnClickListener { window?.dismissLastNav() }
    }

    private val slideAdapter = SlideAdapter()

    override fun setupViews() {
        super.setupViews()

        viewPager.adapter = slideAdapter
        viewPager.offscreenPageLimit = 5
        freeViewPagerVerticalDrags()
        viewPager.setupSpringFling { target ->
            target.coerceIn(currentIndex - 1, currentIndex + 1)
                .coerceIn(0, orderedTypes.size - 1)
        }
        viewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageScrolled(
                position: Int,
                positionOffset: Float,
                positionOffsetPixels: Int
            ) {
                applyScrollProgress(position, positionOffset)
                dotsView.setPosition(position + positionOffset)
                updateVideoPlaybackForVisibility()
            }

            override fun onPageSelected(position: Int) {
                currentIndex = position
                bindFixedContent(position)
                updateVideoPlaybackForVisibility()
            }
        })

        bottomSection.addView(
            prosView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 20.dp
                bottomMargin = 20.dp
                leftMargin = 24.dp
                rightMargin = 24.dp
            }
        )

        contentContainer.addView(
            pagerHost,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        contentContainer.addView(
            bottomSection,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        scrollView.clipToPadding = false
        scrollView.addView(contentContainer, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.addView(
            bottomReversedCorner,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
        )
        view.addView(upgradeButton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 50.dp))
        view.addView(closeButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))

        view.setConstraints {
            toTop(scrollView)
            toCenterX(scrollView)

            toStart(upgradeButton, 16f)
            toEnd(upgradeButton, 16f)

            topToTop(
                bottomReversedCorner,
                upgradeButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCorner)
        }

        bindFixedContent(0)
        updateTheme()

        // Prefetch every card's video so all tabs play instantly (and offline).
        MintCardVideoCache.precache(context, orderedTypes.map { it.type })

        view.doOnPreDraw { recalculateModalHeight() }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottom = navigationController?.bottomInset ?: 0
        view.setConstraints {
            toBottomPx(upgradeButton, BUTTON_GAP_DP.dp + bottom)
            toTopPx(closeButton, 8.dp)
            toEnd(closeButton, 8f)
        }
        scrollView.setPadding(
            0,
            0,
            0,
            BUTTON_GAP_DP.dp + BUTTON_HEIGHT_DP.dp + BUTTON_GAP_DP.dp + bottom
        )
        recalculateModalHeight()
    }

    override fun onDestroy() {
        super.onDestroy()
        releaseAllVideos()
    }

    private fun releaseAllVideos() {
        val rv = pagerRecyclerView ?: return
        for (i in 0 until rv.childCount) {
            ((rv.getChildAt(i)) as? MintCardPosterView)?.releaseVideo()
        }
    }

    private var boundButtonIndex = 0
    private fun applyScrollProgress(position: Int, offset: Float) {
        val fromType = orderedTypes.getOrNull(position)?.type ?: return
        val toType = orderedTypes.getOrNull(position + 1)?.type ?: fromType

        val accent = lerpColor(
            MintCardTypeInfo.accentColor(fromType),
            MintCardTypeInfo.accentColor(toType),
            offset
        )
        prosView.setAccentColor(accent)
        upgradeButton.customTint = accent
        upgradeButton.customTextColor = lerpColor(
            buttonTextColor(fromType),
            buttonTextColor(toType),
            offset
        )

        val bottomColor = lerpColor(
            bottomSectionBaseColor(fromType),
            bottomSectionBaseColor(toType),
            offset
        )
        applyBaseColor(bottomColor)

        prosView.setBlackProgress(
            lerpFloat(blackProgress(fromType), blackProgress(toType), offset)
        )

        val targetIndex = if (offset > 0.5f) position + 1 else position
        if (targetIndex != boundButtonIndex && targetIndex in orderedTypes.indices) {
            boundButtonIndex = targetIndex
            bindButton(targetIndex)
        }
    }

    private fun bottomSectionBaseColor(type: ApiMtwCardType): Int {
        return if (type == ApiMtwCardType.BLACK) Color.BLACK else WColor.Background.color
    }

    private fun buttonTextColor(type: ApiMtwCardType): Int {
        return if (type == ApiMtwCardType.BLACK) Color.BLACK else WColor.TextOnTint.color
    }

    private fun applyBaseColor(color: Int) {
        view.setBackgroundColor(color)
        bottomSection.setBackgroundColor(color)
        bottomReversedCorner.setBlurOverlayColor(color)
    }

    private fun blackProgress(type: ApiMtwCardType): Float {
        return if (type == ApiMtwCardType.BLACK) 1f else 0f
    }

    private fun lerpFloat(a: Float, b: Float, t: Float): Float = a + (b - a) * t

    private fun bindFixedContent(position: Int) {
        val info = orderedTypes[position]
        val accent = MintCardTypeInfo.accentColor(info.type)
        prosView.setAccentColor(accent)
        upgradeButton.customTint = accent
        upgradeButton.customTextColor = buttonTextColor(info.type)
        applyBaseColor(bottomSectionBaseColor(info.type))
        prosView.setBlackProgress(blackProgress(info.type))
        boundButtonIndex = position
        bindButton(position)
    }

    private fun bindButton(position: Int) {
        val info = orderedTypes[position]
        val cardInfo = cardsInfo?.get(info.type)
        val accountId = displayedAccount.accountId
        val price = cardInfo?.price
        val mycoin = MintCardHelpers.mycoin
        if (price != null && price > 0.0) {
            upgradeButton.isGone = false
            upgradeButton.setText(
                LocaleController.getString("Upgrade for %amount% %currency%")
                    .replace("%amount%", formatPrice(price))
                    .replace("%currency%", mycoin?.symbol ?: "MY")
            )
            upgradeButton.isEnabled =
                accountId != null && cardInfo.isAvailable && mycoin != null
        } else {
            upgradeButton.isGone = true
        }
    }

    private fun formatPrice(price: Double): String {
        val format = java.text.NumberFormat.getNumberInstance().apply {
            maximumFractionDigits = 2
            minimumFractionDigits = 0
        }
        return format.format(price)
    }

    private val pagerRecyclerView: RecyclerView?
        get() = viewPager.getChildAt(0) as? RecyclerView

    private fun updateVideoPlaybackForVisibility() {
        val rv = pagerRecyclerView ?: return
        val pagerWidth = rv.width
        if (pagerWidth <= 0) return
        for (i in 0 until rv.childCount) {
            val poster = rv.getChildAt(i) as? MintCardPosterView ?: continue
            val fullyOffscreen = poster.right <= 0 || poster.left >= pagerWidth
            if (fullyOffscreen) {
                poster.stopVideo()
                poster.prepareVideo()
            } else {
                poster.playVideo()
            }
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.clipToOutline = true
        view.outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(v: View, outline: android.graphics.Outline) {
                val r = ViewConstants.TOOLBAR_RADIUS.dp
                outline.setRoundRect(0, 0, v.width, v.height + r.toInt(), r)
            }
        }
        applyScrollProgress(currentIndex, 0f)
    }

    private inner class SlideAdapter :
        RecyclerView.Adapter<SlideAdapter.SlideHolder>() {

        inner class SlideHolder(val poster: MintCardPosterView) :
            RecyclerView.ViewHolder(poster)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): SlideHolder {
            val poster = MintCardPosterView(parent.context).apply {
                layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            }
            return SlideHolder(poster)
        }

        override fun onBindViewHolder(holder: SlideHolder, position: Int) {
            val info = orderedTypes[position]
            holder.poster.configure(
                info.type,
                LocaleController.getString(info.displayNameKey),
                cardsInfo?.get(info.type)
            )
        }

        override fun onViewAttachedToWindow(holder: SlideHolder) {
            if (holder.bindingAdapterPosition == currentIndex) {
                holder.poster.playVideo()
            } else {
                holder.poster.prepareVideo()
            }
        }

        override fun onViewDetachedFromWindow(holder: SlideHolder) {
            holder.poster.stopVideo()
        }

        override fun onViewRecycled(holder: SlideHolder) {
            holder.poster.releaseVideo()
        }

        override fun getItemCount(): Int = orderedTypes.size
    }

    private fun onUpgradePressed(type: ApiMtwCardType, cardInfo: MCardInfo?) {
        val accountId = displayedAccount.accountId ?: return
        val mycoin = MintCardHelpers.mycoin ?: return
        cardInfo ?: return

        val enoughMycoin = MintCardHelpers.isEnoughMycoin(accountId, cardInfo, mycoin)
        val enoughToncoin = MintCardHelpers.isEnoughToncoin(accountId)

        if (enoughMycoin && enoughToncoin) {
            startMinting(type, cardInfo)
            return
        }

        if (!enoughMycoin) {
            startSwapForShortfall(cardInfo, mycoin)
            return
        }

        val tonSymbol = TokenStore.getToken(TONCOIN_SLUG)?.symbol ?: "TON"
        showAlert(
            LocaleController.getString("Insufficient Fee"),
            LocaleController.getString("Please top up your %token% balance.")
                .replace("%token%", tonSymbol)
        )
    }

    private fun startSwapForShortfall(
        cardInfo: MCardInfo,
        mycoin: org.mytonwallet.app_air.walletcore.models.MToken
    ) {
        val requiredAmount = MintCardHelpers.priceAmount(cardInfo, mycoin) ?: return
        val currentBalance = MintCardHelpers.mycoinBalance(displayedAccount.accountId ?: "")
        val missing = (requiredAmount - currentBalance).max(BigInteger.ZERO)
        // Add 5% reserve to cover swap slippage, mirroring web SWAP_AMOUNT_RESERVE_MULTIPLIER.
        val missingWithReserve = missing * BigInteger.valueOf(105) / BigInteger.valueOf(100)
        val amountOut = missingWithReserve.toDouble() / 10.0.pow(mycoin.decimals.toDouble())

        val tonToken = TokenStore.getToken(TONCOIN_SLUG)
        val sendingAsset = tonToken?.let { MApiSwapAsset.from(it) }
        val receivingAsset = MApiSwapAsset.from(mycoin)

        val win = window ?: return
        win.dismissLastNav {
            val nav = WNavigationController(win)
            nav.setRoot(
                SwapVC(
                    context,
                    defaultSendingToken = sendingAsset,
                    defaultReceivingToken = receivingAsset,
                    amountIn = if (amountOut > 0) amountOut else null
                )
            )
            win.present(nav)
        }
    }

    private val headerView: View
        get() {
            val info = orderedTypes[currentIndex]
            return PasscodeHeaderSendView(
                WeakReference(this),
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content(image = Content.Image.Empty),
                    LocaleController.getString("Confirm Upgrading"),
                    LocaleController.getString(info.displayNameKey),
                    Content.Rounding.Radius(12f.dp)
                )
            }
        }

    private fun buildTransferOptions(
        cardInfo: MCardInfo,
        passcode: String
    ): MApiSubmitTransferOptions? {
        val accountId = displayedAccount.accountId ?: return null
        val mycoin = MintCardHelpers.mycoin ?: return null
        val amount = MintCardHelpers.priceAmount(cardInfo, mycoin) ?: return null
        return MApiSubmitTransferOptions(
            accountId = accountId,
            toAddress = MINT_CARD_ADDRESS,
            payload = ApiTransferPayload.Comment(MINT_CARD_COMMENT),
            tokenAddress = mycoin.tokenAddress,
            password = passcode,
            amount = amount
        )
    }

    private var flowNav: WNavigationController? = null

    private fun presentFlow(rootVC: WViewController) {
        val win = window ?: return
        val nav = WNavigationController(win)
        nav.setRoot(rootVC)
        flowNav = nav
        win.present(nav)
    }

    private fun startMinting(type: ApiMtwCardType, cardInfo: MCardInfo) {
        if (AccountStore.activeAccount?.isHardware == true) {
            mintWithHardware(cardInfo)
        } else {
            mintWithPassword(cardInfo)
        }
    }

    private fun mintWithPassword(cardInfo: MCardInfo) {
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                headerView,
                LocaleController.getString("Confirm Upgrading"),
                showNavbarTitle = false
            ),
            task = { passcode ->
                val options = buildTransferOptions(cardInfo, passcode)
                if (options == null) {
                    showError(null)
                    return@PasscodeConfirmVC
                }
                submitMint(options)
            }
        )
        presentFlow(passcodeConfirmVC)
    }

    private fun mintWithHardware(cardInfo: MCardInfo) {
        val account = AccountStore.activeAccount ?: return
        val mycoin = MintCardHelpers.mycoin ?: return
        val options = buildTransferOptions(cardInfo, "") ?: run {
            showError(null)
            return
        }
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignTransfer(
                    accountId = account.accountId,
                    transferOptions = options,
                    slug = mycoin.slug
                ),
                onDone = {
                    onMintSucceeded()
                }),
            headerView = headerView
        )
        presentFlow(ledgerConnectVC)
    }

    private fun submitMint(options: MApiSubmitTransferOptions) {
        WalletCore.call(
            ApiMethod.Transfer.SubmitTransfer(MBlockchain.ton, options)
        ) { res, err ->
            if (isDestroyed)
                return@call
            if (err != null) {
                showError(err.parsed)
                return@call
            }
            val mfaHash = res?.mfaRequestHash
            if (mfaHash != null) {
                val mfaVC = MfaActionConfirmVC(
                    context,
                    requestHash = mfaHash,
                    onFinishOverride = {
                        onMintSucceeded()
                    }
                )
                flowNav?.push(mfaVC, onCompletion = {
                    flowNav?.removePrevViewControllerOnly()
                })
                return@call
            }
            onMintSucceeded()
        }
    }

    private fun onMintSucceeded() {
        displayedAccount.accountId?.let { NftStore.setCardMinting(it, true) }
        val doneVC = MintCardDoneVC(context)
        flowNav?.push(doneVC, onCompletion = {
            flowNav?.removePrevViewControllerOnly()
            window?.dismissNav(navigationController)
        })
    }

    companion object {
        private const val BUTTON_HEIGHT_DP = 50
        private const val BUTTON_GAP_DP = 16 // gap above and below the pinned button

        fun present(navigationController: WNavigationController) {
            val nav = object : WNavigationController(
                navigationController.window,
                PresentationConfig(style = PresentationStyle.BottomSheet)
            ) {
                override val isCenteredWindow: Boolean
                    get() = window.isWideLayout

                override val centeredWindowWidth: Int = 300.dp
            }
            nav.setRoot(MintCardVC(navigationController.context))
            navigationController.window.present(nav)
        }
    }
}
