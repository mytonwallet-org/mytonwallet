package org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.animation.doOnEnd
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiassets.viewControllers.token.cells.TokenChartCell
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.SelectiveItemAnimator
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uifutures.viewControllers.futures.cells.FuturesActivityCell
import org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity.presentAllFuturesActivities
import org.mytonwallet.app_air.uifutures.viewControllers.futuresActivity.presentFuturesActivity
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesEditPositionVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesEditPositionView
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesModifyReviewVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.FuturesPositionChange
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresErrorText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOpen.FuturesOpenPositionVC
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.FuturesOperationActions
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.presentFuturesOperation
import org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation.showFuturesOperationAlert
import org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells.FuturesPositionDetailsCell
import org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells.FuturesPositionHeaderCell
import org.mytonwallet.app_air.uifutures.viewControllers.futuresPosition.cells.FuturesPositionInfoCell
import org.mytonwallet.app_air.uifutures.viewControllers.futuresWalletSelection.FuturesWalletSelectionVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsSide
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_CLOSE
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_OPEN
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

@SuppressLint("ViewConstructor")
class FuturesPositionVC(context: Context, private val coin: String) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    FuturesPositionVM.Delegate {
    @Suppress("PropertyName")
    override val TAG = "FuturesPosition"

    override val shouldDisplayBottomBar = true

    override val additionalBottomGradientHeight: Int
        get() = (BUTTON_HEIGHT + BUTTONS_BOTTOM_MARGIN).dp

    override var displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)
    private val positionVM = FuturesPositionVM(coin, displayedAccount.accountId, this)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var operationActions: FuturesOperationActions? = null

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, DETAILS_CELL, CHART_CELL, INFO_CELL, ACTIVITY_CELL)
    ).apply {
        setHasStableIds(true)
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            if (dy != 0) updateBlurViews(recyclerView)
        }
    }

    private val recyclerView by lazy {
        WRecyclerView(this).apply {
            adapter = rvAdapter
            layoutManager = LinearLayoutManager(context)
            itemAnimator = SelectiveItemAnimator().apply {
                setAll(WGlobalStorage.getAreAnimationsActive())
            }
            clipToPadding = false
            addOnScrollListener(scrollListener)
        }
    }

    private var chartCell: TokenChartCell? = null
    private var infoCell: FuturesPositionInfoCell? = null
    private var displayedRows: List<WCell.Type> = emptyList()
    private var shownMarketMode: Boolean? = null
    private var modeAnimator: ValueAnimator? = null

    private val editButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.SECONDARY_WITH_BACKGROUND
        text = LocaleController.getString("Edit Position")
        setOnClickListener {
            if (positionVM.position ==
                null
            ) {
                if (ensureTradingWallet { openNewPosition(MApiPerpsSide.LONG) }) {
                    openNewPosition(MApiPerpsSide.LONG)
                }
            } else if (ensureTradingWallet()) {
                openEditPosition()
            }
        }
    }

    private val closeButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.PRIMARY
        text = LocaleController.getString("Close Position")
        setOnClickListener {
            if (positionVM.position ==
                null
            ) {
                if (ensureTradingWallet { openNewPosition(MApiPerpsSide.SHORT) }) {
                    openNewPosition(MApiPerpsSide.SHORT)
                }
            } else if (ensureTradingWallet()) {
                openClosePosition()
            }
        }
    }

    private val noticeLabel = WLabel(context).apply {
        id = View.generateViewId()
        setStyle(14f)
        gravity = Gravity.CENTER
        setPadding(0, 0, 0, NOTICE_BOTTOM_PADDING.dp)
        isGone = true
    }

    private val buttonsView = WView(context).apply {
        addView(noticeLabel, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        addView(editButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        addView(closeButton, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(noticeLabel)
            toCenterX(noticeLabel)
            topToBottom(editButton, noticeLabel)
            toBottom(editButton)
            toStart(editButton)
            endToStart(editButton, closeButton, BUTTONS_SPACING / 2f)
            topToBottom(closeButton, noticeLabel)
            toBottom(closeButton)
            startToEnd(closeButton, editButton, BUTTONS_SPACING / 2f)
            toEnd(closeButton)
        }
    }

    override fun didSetupViews() {
        super.didSetupViews()
        buttonsView.bringToFront()
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(buttonsView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            allEdges(recyclerView)
            toCenterX(buttonsView, BUTTONS_HORIZONTAL_MARGIN)
        }
        positionVM.start()
        updateTitle()
        insetsUpdated()
        updateTheme()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        positionVM.refresh()
        positionVM.startPolling()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        positionVM.stopPolling()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        rvAdapter.updateTheme()
        noticeLabel.setTextColor(WColor.SecondaryText.color)
        updateTitle()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        view.setConstraints {
            toBottomPx(buttonsView, bottomInset + BUTTONS_BOTTOM_MARGIN.dp)
        }
        recyclerView.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            navigationBar?.calculatedMinHeight ?: 0,
            systemBarEndInset,
            bottomInset + (BUTTONS_BOTTOM_MARGIN + BUTTON_HEIGHT + BUTTONS_BOTTOM_MARGIN).dp +
                if (noticeLabel.isGone) 0 else NOTICE_HEIGHT.dp
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun onDestroy() {
        scope.cancel()
        positionVM.onDestroy()
        modeAnimator?.cancel()
        chartCell?.onDestroy()
        infoCell?.onDestroy()
        recyclerView.removeOnScrollListener(scrollListener)
        recyclerView.adapter = null
        recyclerView.layoutManager = null
        super.onDestroy()
    }

    override fun positionUpdated() {
        updateTitle()
        updateMode()
        updateAvailability()
        chartCell?.title = chartTitle
        reloadRows()
    }

    /** Moves between the market and the position layouts, like the token screen's balance mode. */
    private fun updateMode() {
        buttonsView.isInvisible = positionVM.asset == null
        val marketMode = isMarketMode
        val previousMode = shownMarketMode
        if (previousMode == marketMode) return
        shownMarketMode = marketMode
        modeAnimator?.cancel()
        val target = if (marketMode) 1f else 0f
        if (previousMode == null ||
            !view.isLaidOut ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            updateButtons()
            chartCell?.iconProgress = target
            return
        }
        val startIconProgress = chartCell?.iconProgress ?: (1f - target)
        var areButtonsSwapped = false
        modeAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                val fraction = it.animatedValue as Float
                chartCell?.iconProgress =
                    startIconProgress + (target - startIconProgress) * fraction
                buttonsView.alpha = abs(1f - fraction * 2f)
                if (fraction >= 0.5f && !areButtonsSwapped) {
                    areButtonsSwapped = true
                    updateButtons()
                }
            }
            doOnEnd {
                if (modeAnimator === it) modeAnimator = null
                buttonsView.alpha = 1f
                if (!areButtonsSwapped) updateButtons()
                chartCell?.iconProgress = if (isMarketMode) 1f else 0f
            }
            start()
        }
    }

    /**
     * Inserts and removes rows individually so the list animates when the layout changes; rows that
     * stay are updated in place, as TokenVC updates its cells, so no change animation runs.
     */
    private fun reloadRows() {
        val oldRows = displayedRows
        val newRows = rows
        displayedRows = newRows
        if (oldRows.isEmpty() || newRows.isEmpty() || !view.isLaidOut) {
            rvAdapter.reloadData()
            return
        }
        DiffUtil.calculateDiff(
            object : DiffUtil.Callback() {
                override fun getOldListSize() = oldRows.size
                override fun getNewListSize() = newRows.size
                override fun areItemsTheSame(oldPos: Int, newPos: Int) =
                    oldRows[oldPos] == newRows[newPos]

                override fun areContentsTheSame(oldPos: Int, newPos: Int) = true
            },
            false
        ).dispatchUpdatesTo(WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0))
        rvAdapter.updateVisibleCells()
    }

    /** No position is open in this market, so the screen shows the market and offers to open one. */
    private val isMarketMode: Boolean
        get() = positionVM.position == null

    private val longTitle by lazy { sideTitle(R.drawable.ic_futures_long, "Long") }
    private val shortTitle by lazy { sideTitle(R.drawable.ic_futures_short, "Short") }

    private fun sideTitle(icon: Int, title: String): CharSequence {
        val text = LocaleController.getString(title)
        val drawable = context.getDrawableCompat(icon)?.mutate() ?: return text
        drawable.setTint(WColor.TextOnTint.color)
        drawable.setBounds(0, 0, SIDE_ICON_SIZE.dp, SIDE_ICON_SIZE.dp)
        return SpannableStringBuilder()
            .append(
                " ",
                VerticalImageSpan(drawable, startPadding = 0, endPadding = 6.dp),
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            .append(text)
    }

    private fun updateButtons() {
        val sideInset = if (isMarketMode) SIDE_BUTTONS_EXTRA_INSET.dp else 0
        buttonsView.setPaddingRelative(sideInset, 0, sideInset, 0)
        if (isMarketMode) {
            editButton.type = WButton.Type.PRIMARY
            editButton.customTint = WColor.Buy.color
            editButton.text = longTitle
            closeButton.customTint = WColor.Sell.color
            closeButton.text = shortTitle
        } else {
            editButton.type = WButton.Type.SECONDARY_WITH_BACKGROUND
            editButton.customTint = null
            editButton.text = LocaleController.getString("Edit Position")
            closeButton.customTint = null
            closeButton.text = LocaleController.getString("Close Position")
        }
    }

    private fun updateAvailability() {
        val unavailable = isMarketMode && positionVM.asset?.isTradingUnavailable == true
        editButton.isEnabled = !unavailable
        closeButton.isEnabled = !unavailable
        if (unavailable) {
            noticeLabel.text = LocaleController.getString(
                positionVM.asset?.tradingAvailability?.reason ?: "PerpsTradingUnavailable"
            )
        }
        if (noticeLabel.isGone == !unavailable) return
        noticeLabel.isGone = !unavailable
        insetsUpdated()
    }

    /** An unsettled order blocks another, so its status opens in place of a new review. */
    private fun presentPendingOperation(assetId: String? = null, kind: String? = null): Boolean {
        val accountId = displayedAccount.accountId ?: return false
        val operation = PerpsStore.pendingOperation(accountId, assetId, kind) ?: return false
        if (DEBUG_MODE) {
            presentFuturesOperation(operation)
        } else {
            val actions = operationActions?.takeIf { it.accountId == accountId }
                ?: FuturesOperationActions(this, accountId, scope).also { operationActions = it }
            showFuturesOperationAlert(operation, actions)
        }
        return true
    }

    /** Returns `false` after offering a trading wallet, as the shown one can't sign orders. */
    private fun ensureTradingWallet(onSwitched: () -> Unit = {}): Boolean {
        if (PerpsStore.canTrade(AccountStore.accountById(displayedAccount.accountId))) return true
        if (displayedAccount.isPushedTemporary) {
            showAlert(
                null,
                LocaleController.getString("Action is not possible on a view-only wallet.")
            )
            return false
        }
        presentInNavigation(FuturesWalletSelectionVC(context) { switchAccount(it, onSwitched) })
        return false
    }

    private fun switchAccount(account: MAccount, onSwitched: () -> Unit) {
        val previousAccount = displayedAccount
        // Set first, so the tabs don't pop this screen on the account change
        displayedAccount = DisplayedAccount(account.accountId, isPushedTemporary = false)
        WalletCore.ensureAccountActivated(
            account.accountId,
            onFailure = { view.post { displayedAccount = previousAccount } }
        ) {
            view.post {
                positionVM.switchAccount(account.accountId)
                if (isMarketMode) onSwitched()
            }
        }
    }

    private fun openNewPosition(side: MApiPerpsSide) {
        val asset = positionVM.asset?.takeIf { it.context?.markPx != null } ?: return
        if (presentPendingOperation(asset.id, PERPS_QUOTE_OPEN)) return
        val window = window ?: return
        val navVC = marginNavigationController(window)
        navVC.setRoot(FuturesOpenPositionVC(context, asset, side, positionVM.displayName))
        window.present(navVC)
    }

    override fun priceDataUpdated() {
        configureChartCell()
    }

    private val chartTitle: String
        get() = if (isMarketMode) {
            LocaleController.getString("Price")
        } else {
            LocaleController.getStringWithKeyValues(
                "\$perps_asset_price",
                listOf("%asset%" to positionVM.displayName)
            )
        }

    private fun openEditPosition() {
        val position = positionVM.position?.takeIf { it.asset != null && it.markPrice != null }
            ?: return
        if (presentPendingOperation()) return
        val window = window ?: return
        val navVC = marginNavigationController(window)
        navVC.setRoot(FuturesEditPositionVC(context, position, positionVM.displayName))
        window.present(navVC)
    }

    private fun marginNavigationController(window: WWindow) = object : WNavigationController(
        window,
        PresentationConfig.PreferredFullScreen
    ) {
        override val centeredWindowMinHeight: Int
            get() = FuturesEditPositionView.centeredWindowMinHeight
    }

    private fun openClosePosition() {
        if (closeButton.isLoading) return
        val position = positionVM.position ?: return
        if (presentPendingOperation(position.asset?.id, PERPS_QUOTE_CLOSE)) return
        closeButton.isLoading = true
        positionVM.prepareClose { result ->
            closeButton.isLoading = false
            // Skipped if the user left this screen meanwhile
            if (isDisappeared || window?.topViewController !== this) return@prepareClose
            val quote = result.quote
            if (quote == null || FuturesPositionChange.of(quote) == null) {
                showAlert(
                    LocaleController.getString("Error"),
                    futuresErrorText(result.error.orEmpty())
                )
                return@prepareClose
            }
            val assetId = position.asset?.id ?: return@prepareClose
            val accountId = displayedAccount.accountId ?: return@prepareClose
            presentInNavigation(
                FuturesModifyReviewVC(
                    context,
                    accountId,
                    position,
                    positionVM.displayName,
                    quote,
                    positionVM.closeDraft(position, assetId)
                )
            )
        }
    }

    private fun updateTitle() {
        val position = positionVM.position ?: run {
            setNavTitle(
                LocaleController.getStringWithKeyValues(
                    "\$perps_market_title",
                    listOf("%asset%" to positionVM.displayName)
                ),
                animated = false
            )
            return
        }
        val sideText = "${position.leverage}x ${position.side.title}"
        val title = if (LocaleController.isRTL) {
            "\u200F${position.symbol} \u2068$sideText\u2069"
        } else {
            "${position.symbol} $sideText"
        }
        setNavTitle(title, animated = false)
        val sideColor = if (position.side == MApiPerpsSide.LONG) WColor.Green else WColor.Red
        val sideStart = title.lastIndexOf(sideText)
        navigationBar?.titleLabel?.text = SpannableString(title).apply {
            setSpan(
                ForegroundColorSpan(sideColor.color),
                sideStart,
                sideStart + sideText.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }

    private val rows: List<WCell.Type>
        get() {
            if (isMarketMode) {
                if (positionVM.asset == null) return emptyList()
                return listOfNotNull(
                    CHART_CELL.takeIf { positionVM.chartToken != null },
                    INFO_CELL,
                    ACTIVITY_CELL.takeIf { positionVM.activities.isNotEmpty() }
                )
            }
            return listOfNotNull(
                HEADER_CELL,
                DETAILS_CELL,
                CHART_CELL.takeIf { positionVM.chartToken != null },
                INFO_CELL.takeIf {
                    positionVM.position?.asset != null || positionVM.description != null
                },
                ACTIVITY_CELL.takeIf { positionVM.activities.isNotEmpty() }
            )
        }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = displayedRows.size

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String =
        displayedRows[indexPath.row].value.toString()

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        displayedRows[indexPath.row]

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> FuturesPositionHeaderCell(context)

            DETAILS_CELL -> FuturesPositionDetailsCell(context) { title, text ->
                showAlert(title, text)
            }

            CHART_CELL -> chartCell ?: TokenChartCell(
                recyclerView,
                activePeriod = positionVM.selectedPeriod,
                onSelectedPeriodChanged = { positionVM.selectedPeriod = it },
                onAnalyze = null,
                onHeightChange = null,
                title = chartTitle,
                isExpandedByDefault = true
            ).also {
                it.iconProgress = if (isMarketMode) 1f else 0f
                chartCell = it
            }

            INFO_CELL -> infoCell ?: FuturesPositionInfoCell(context) { title, text ->
                showAlert(title, text)
            }.also { infoCell = it }

            else -> FuturesActivityCell(context, ::presentFuturesActivity) {
                presentAllFuturesActivities(coin)
            }
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val position = positionVM.position
        when (val cell = cellHolder.cell) {
            is FuturesPositionHeaderCell -> position?.let(cell::configure)

            is FuturesPositionDetailsCell -> position?.let(cell::configure)

            is TokenChartCell -> {
                cell.insetLikeTokenScreen()
                configureChartCell()
            }

            is FuturesPositionInfoCell -> cell.configure(
                positionVM.asset,
                positionVM.description,
                isCollapsible = !isMarketMode
            )

            is FuturesActivityCell -> cell.configure(
                positionVM.activities,
                0,
                showsAll = positionVM.hasMoreActivities,
                animatesChanges = WGlobalStorage.getAreAnimationsActive()
            )
        }
    }

    /**
     * The cell sizes its chart and loading indicator from its own width, so it is inset by margins
     * as TokenVC's list insets it, not by padding inside it.
     */
    private fun TokenChartCell.insetLikeTokenScreen() {
        val inset = ViewConstants.HORIZONTAL_PADDINGS.dp
        val params = layoutParams as? ViewGroup.MarginLayoutParams ?: return
        if (params.marginStart == inset && params.marginEnd == inset) return
        params.marginStart = inset
        params.marginEnd = inset
        layoutParams = params
    }

    private fun configureChartCell() {
        val token = positionVM.chartToken ?: return
        chartCell?.configure(token, positionVM.historyData, positionVM.selectedPeriod)
    }

    private companion object {
        const val SIDE_ICON_SIZE = 20
        val HEADER_CELL = WCell.Type(1)
        val DETAILS_CELL = WCell.Type(2)
        val CHART_CELL = WCell.Type(3)
        val INFO_CELL = WCell.Type(4)
        val ACTIVITY_CELL = WCell.Type(5)

        const val BUTTON_HEIGHT = 50
        const val BUTTONS_SPACING = 12f
        const val BUTTONS_HORIZONTAL_MARGIN = 16f
        const val SIDE_BUTTONS_EXTRA_INSET = 4
        const val BUTTONS_BOTTOM_MARGIN = 16
        const val NOTICE_BOTTOM_PADDING = 12
        const val NOTICE_HEIGHT = 32
    }
}
