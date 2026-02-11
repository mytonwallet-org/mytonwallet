package org.mytonwallet.uihome.wallets

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.Guideline
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.RecyclerView.NO_POSITION
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HighlightOverlayView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.AccountDialogHelpers
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.frameAsRectF
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.WalletCustomizationVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.LogMessage
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.models.MWalletSettingsViewMode
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.uihome.wallets.cells.IWalletCardCell
import org.mytonwallet.uihome.wallets.cells.WalletCardCell
import org.mytonwallet.uihome.wallets.cells.WalletCardRowCell
import org.mytonwallet.uihome.walletsTabs.WalletsTabsVC
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

class WalletsVC(
    context: Context,
    val walletCategory: WalletsTabsVC.WalletCategory,
    private val totalWidth: Int,
    private val topInset: Int,
    private val bottomInset: Int,
) : WViewController(context), WRecyclerViewAdapter.WRecyclerViewDataSource {
    override val TAG = "Wallets"

    override val isSwipeBackAllowed = false
    override val shouldDisplayTopBar = true
    val guideline = Guideline(context).apply {
        id = View.generateViewId()
    }
    override val topBlurViewGuideline = guideline
    var parentTopReversedCornerView: WeakReference<ReversedCornerView>? = null
    var parentBottomReversedCornerView: WeakReference<ReversedCornerViewUpsideDown>? = null
    var isModalExpanded = false

    companion object {
        val ACCOUNT_GRID_CELL = WCell.Type(1)
        val ACCOUNT_ROW_CELL = WCell.Type(2)
    }

    var accounts: List<MAccount> = emptyList()
        private set
    var checkedAccounts: MutableSet<MAccount> = mutableSetOf()

    override var title: String? = walletCategory.localized

    var viewMode = MWalletSettingsViewMode.GRID
        set(value) {
            if (field != value) {
                field = value
                if (!didSetup)
                    return
                updateRecyclerViewInsets()
                if (recyclerView.computeVerticalScrollOffset() > 0)
                    recyclerView.scrollTo(0, 0)
                if (!recyclerView.isNestedScrollingEnabled)
                    recyclerView.isNestedScrollingEnabled = true
            }
        }
    var isReordering = false

    var onAccountsReordered: ((List<MAccount>) -> Unit)? = null
    var onToggleReorderTapped: (() -> Unit)? = null
    var onCheckChanged: (() -> Unit)? = null
    var onSwitchAccountInProgress: (() -> Unit)? = null

    private val itemTouchHelper by lazy {
        val callback = object : ItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN,
            0
        ) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                val fromPosition = viewHolder.adapterPosition
                val toPosition = target.adapterPosition

                if (fromPosition < accounts.size && toPosition < accounts.size) {
                    val mutableAccounts = accounts.toMutableList()
                    val movedAccount = mutableAccounts.removeAt(fromPosition)
                    mutableAccounts.add(toPosition, movedAccount)
                    accounts = mutableAccounts

                    rvAdapter.notifyItemMoved(fromPosition, toPosition)
                    onAccountsReordered?.invoke(accounts)
                }

                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
                // Not used
            }

            override fun isLongPressDragEnabled(): Boolean {
                return isReordering
            }

            override fun onSelectedChanged(viewHolder: RecyclerView.ViewHolder?, actionState: Int) {
                super.onSelectedChanged(viewHolder, actionState)
                if (actionState == ItemTouchHelper.ACTION_STATE_DRAG) {
                    viewHolder?.itemView?.alpha = 0.7f
                }
            }

            override fun clearView(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ) {
                super.clearView(recyclerView, viewHolder)
                viewHolder.itemView.alpha = 1.0f
            }
        }
        ItemTouchHelper(callback)
    }

    private fun calculateNoOfColumns(): Int {
        return max(
            2,
            (totalWidth - 16.dp) / 104.dp
        )
    }

    // TODO: Workaround for RecyclerView jump glitch. we temporarily scroll to the top before applying changes.
    //       Find a proper fix for the glitch and remove this workaround.
    var animatingReorderingTo = false
    var animatingReorderChange = false
        set(value) {
            field = value
            if (!animatingReorderChange) {
                isReordering = animatingReorderingTo
                for (i in 0 until recyclerView.childCount) {
                    val child = recyclerView.getChildAt(i)
                    val viewHolder = recyclerView.getChildViewHolder(child)
                    (viewHolder.itemView as WalletCardRowCell).toggleReordering(isReordering, true)
                }
                Handler(Looper.getMainLooper()).postDelayed({
                    rvAdapter.reloadData()
                }, AnimationConstants.QUICK_ANIMATION)
            }
        }

    private val cellWidth: Int
        get() {
            val cols = calculateNoOfColumns()
            return (totalWidth - 16.dp) / cols
        }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(ACCOUNT_GRID_CELL, ACCOUNT_ROW_CELL)
        ).apply {
            setHasStableIds(true)
        }
    private var scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            val offset = recyclerView.computeVerticalScrollOffset()
            val isNestedScrollingEnabled = !isModalExpanded || offset == 0
            if (recyclerView.isNestedScrollingEnabled != isNestedScrollingEnabled)
                recyclerView.isNestedScrollingEnabled = isNestedScrollingEnabled
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                if (animatingReorderChange)
                    animatingReorderChange = false
            }
        }
    }
    private var touchingItem: WView? = null
    private val recyclerView by lazy {
        object : WRecyclerView(this) {

            private var initialX = 0f
            private var initialY = 0f
            private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
            private var isHorizontalScroll: Boolean? = null

            override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
                return super.onInterceptTouchEvent(e)
            }

            @SuppressLint("ClickableViewAccessibility")
            override fun onTouchEvent(ev: MotionEvent?): Boolean {
                // Pass touches to recycler view items, to handle touch events.
                touchingItem?.onTouchEvent(ev)

                when (ev?.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        isHorizontalScroll = null
                    }

                    MotionEvent.ACTION_UP -> {
                        touchingItem = null
                    }
                }

                if (isHorizontalScroll != null || isReordering)
                    return if (isHorizontalScroll == true) false else super.onTouchEvent(ev)

                when (ev?.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = ev.x
                        initialY = ev.y
                        requestDisallowInterceptTouchEvent(true)
                    }

                    MotionEvent.ACTION_MOVE -> {
                        val deltaX = abs(ev.x - initialX)
                        val deltaY = abs(ev.y - initialY)

                        if (deltaX > touchSlop || deltaY > touchSlop) {
                            if (deltaX > deltaY) {
                                isHorizontalScroll = true
                                requestDisallowInterceptTouchEvent(false)
                                return false
                            } else {
                                isHorizontalScroll = false
                            }
                        }
                    }
                }

                return super.onTouchEvent(ev)
            }

            override fun onMeasure(widthSpec: Int, heightSpec: Int) {
                setMeasuredDimension(
                    view.width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp,
                    view.height - topInset - bottomInset + 48.dp
                )
            }
        }.apply {
            val spanSize = totalWidth - 16.dp
            val layoutManager = GridLayoutManager(context, spanSize)
            layoutManager.isSmoothScrollbarEnabled = true
            layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
                override fun getSpanSize(position: Int): Int {
                    return if (viewMode == MWalletSettingsViewMode.GRID) cellWidth else spanSize
                }
            }
            this.layoutManager = layoutManager
            adapter = rvAdapter
            clipToPadding = false
            clipChildren = false
            addOnScrollListener(scrollListener)
            disallowInterceptOnOverscroll()
        }
    }

    private var highlightOverlayView: HighlightOverlayView? = null

    private var emptyView: WEmptyIconTitleSubtitleView? = null

    val bottomReversedCornerViewUpsideDown by lazy {
        ReversedCornerViewUpsideDown(context, recyclerView).apply {
            isClickable = true
            isFocusable = true
            setOnTouchListener { _, _ -> true }
        }
    }

    private var didSetup = false
    override fun setupViews() {
        super.setupViews()

        view.addView(
            guideline, ConstraintLayout.LayoutParams(
                WRAP_CONTENT,
                WRAP_CONTENT
            ).apply {
                orientation = ConstraintLayout.LayoutParams.HORIZONTAL
                guideBegin = (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT_THICK.dp +
                    33.dp
            })
        view.addView(recyclerView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            FrameLayout.LayoutParams(MATCH_PARENT, MATCH_CONSTRAINT)
        )
        view.setConstraints {
            toBottom(bottomReversedCornerViewUpsideDown)
        }

        itemTouchHelper.attachToRecyclerView(recyclerView)

        updateTheme()
        updateEmptyView()
        didSetup = true
        updateBottomViewsYPosition()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        insetsUpdated()
        bottomReversedCornerViewUpsideDown.updateLayoutParams {
            height = ViewConstants.TOOLBAR_RADIUS.dp.roundToInt() +
                ViewConstants.GAP.dp +
                50.dp +
                16.dp +
                (navigationController?.getSystemBars()?.bottom ?: 0)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        recyclerView.setBackgroundColor(WColor.Background.color)
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.scrollToPosition(0)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()

        updateRecyclerViewInsets()
    }

    private fun updateRecyclerViewInsets() {
        when (viewMode) {
            MWalletSettingsViewMode.LIST -> {
                topReversedCornerView?.isGone = false
                bottomReversedCornerViewUpsideDown.isGone = false
                recyclerView.setPadding(
                    0,
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT_THICK.dp +
                        44.dp -
                        ViewConstants.BLOCK_RADIUS.dp.roundToInt() +
                        22.dp,
                    0,
                    90.dp + bottomInset
                )
                view.setConstraints {
                    toCenterY(recyclerView)
                    toCenterX(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
                }
            }

            MWalletSettingsViewMode.GRID -> {
                topReversedCornerView?.isGone = true
                bottomReversedCornerViewUpsideDown.isGone = true
                recyclerView.setPadding(
                    10.dp,
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT_THICK.dp +
                        44.dp -
                        ViewConstants.BLOCK_RADIUS.dp.roundToInt() +
                        22.dp,
                    6.dp,
                    90.dp + bottomInset
                )
                view.setConstraints {
                    toCenterY(recyclerView)
                    toCenterX(recyclerView, 0f)
                }
            }
        }
    }

    fun setAccounts(accounts: List<MAccount>) {
        this.accounts = accounts
        checkedAccounts = checkedAccounts.filter { checkedAccount ->
            accounts.find { it.accountId == checkedAccount.accountId } != null
        }.toMutableSet()
        if (!didSetup)
            return
        rvAdapter.reloadData()
        updateEmptyView()
    }

    fun reloadData() {
        rvAdapter.reloadData()
    }

    private fun updateEmptyView() {
        emptyView?.animate()?.cancel()
        if (accounts.isEmpty()) {
            emptyView?.isGone = false
            if (emptyView == null) {
                emptyView =
                    WEmptyIconTitleSubtitleView(
                        context,
                        R.raw.animation_empty,
                        LocaleController.getString(
                            when (walletCategory) {
                                WalletsTabsVC.WalletCategory.MY,
                                WalletsTabsVC.WalletCategory.ALL -> "You don’t have any wallets yet"

                                WalletsTabsVC.WalletCategory.LEDGER -> "No Ledger wallets yet"
                                WalletsTabsVC.WalletCategory.VIEW -> "No view wallets yet"
                            }
                        ),
                        LocaleController.getString(
                            when (walletCategory) {
                                WalletsTabsVC.WalletCategory.VIEW -> "Add the first one to track balances and activity for any address."
                                else -> "Add your first one to begin."
                            }
                        ),
                    )
                view.addView(
                    emptyView!!,
                    ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
                )
                bottomReversedCornerViewUpsideDown.bringToFront()
                view.setConstraints {
                    toCenterX(emptyView!!, 16f)
                    setVerticalBias(emptyView!!.id, 0f)
                    toTopPx(
                        emptyView!!,
                        topInset + 120.dp
                    )
                }
            } else if ((emptyView?.alpha ?: 0f) < 1) {
                if (emptyView?.startedAnimation == true)
                    emptyView?.fadeIn()
            }
        } else {
            if ((emptyView?.alpha ?: 0f) > 0f) {
                emptyView?.fadeOut {
                    emptyView?.isGone = true
                }
            }
        }
    }

    private fun updateBottomViewsYPosition() {
        val modalExpandOffset = modalExpandOffset ?: 0
        bottomReversedCornerViewUpsideDown.translationY =
            WalletsTabsVC.DEFAULT_HEIGHT.toFloat().dp -
                (window?.windowView?.height ?: 0) +
                bottomInset +
                modalExpandOffset
        emptyView?.translationY = (modalExpandOffset / 2f).coerceAtLeast(0f)
    }

    fun notifyBalanceChange(async: Boolean) {
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i)
            val position = recyclerView.getChildAdapterPosition(child)
            if (position != NO_POSITION) {
                val viewHolder = recyclerView.getChildViewHolder(child) as WCell.Holder
                (viewHolder.cell as? IWalletCardCell)?.notifyBalanceChange()
            }
        }
    }

    private fun switchAccountTo(newAccount: MAccount) {
        window?.dismissLastNav { }
        onSwitchAccountInProgress?.invoke()
        WalletCore.activateAccount(
            newAccount.accountId,
            notifySDK = true,
            willPopTemporaryPushedWallets = true
        ) { res, err ->
            if (res == null || err != null) {
                // Should not happen!
                Logger.e(
                    Logger.LogTag.ACCOUNT,
                    LogMessage.Builder()
                        .append(
                            "activateAccount: Failed on switch account err=$err",
                            LogMessage.MessagePartPrivacy.PUBLIC
                        ).build()
                )
            } else {
                WalletCore.notifyEvent(
                    WalletEvent.AccountChangedInApp(
                        persistedAccountsModified = false
                    )
                )
            }
        }
    }

    private fun showMenu(cell: IWalletCardCell, cellView: WView, account: MAccount) {
        recyclerView.cancelActiveGesture()
        val rect = cellView.frameAsRectF(4f)
        val isGridMode = cell is WalletCardCell
        if (isGridMode) {
            val width = rect.width()
            val height = rect.height()
            val dx = (width * 1.05f - width) / 2f
            val dy = (height * 1.05f - height) / 2f
            rect.inset(-dx, -dy)
        }
        highlightOverlayView =
            HighlightOverlayView(
                context,
                rect,
                if (cell is WalletCardCell) 16f.dp else 24f.dp,
                if (topReversedCornerView?.isVisible == true)
                    topReversedCornerView
                else
                    parentTopReversedCornerView?.get(),
                if (bottomReversedCornerViewUpsideDown.isVisible)
                    bottomReversedCornerViewUpsideDown
                else
                    parentBottomReversedCornerView?.get()
            ).apply {
                alpha = 0f
                fadeIn()
            }
        window?.windowView?.addView(
            highlightOverlayView,
            FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        WMenuPopup.present(
            cellView,
            listOf(
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.uihome.R.drawable.ic_reorder,
                            tintColor = WColor.SecondaryText
                        ),
                        title = LocaleController.getString("Reorder")
                    ),
                    hasSeparator = false,
                    onTap = {
                        onToggleReorderTapped?.invoke()
                    }),
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.uihome.R.drawable.ic_pen,
                            tintColor = WColor.SecondaryText
                        ),
                        title = LocaleController.getString("Rename")
                    ),
                    hasSeparator = false,
                    onTap = {
                        AccountDialogHelpers.presentRename(this, account)
                    }),
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.uihome.R.drawable.ic_customize,
                            tintColor = WColor.SecondaryText
                        ),
                        title = LocaleController.getString("Customize")
                    ),
                    hasSeparator = false,
                    onTap = {
                        val navVC = WNavigationController(window!!)
                        val walletCustomizationVC =
                            WalletCustomizationVC(context, account.accountId)
                        navVC.setRoot(walletCustomizationVC)
                        window?.present(navVC)
                    }),
                WMenuPopup.Item(
                    config = WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            org.mytonwallet.uihome.R.drawable.ic_remove,
                            tintColor = WColor.Red
                        ),
                        title = LocaleController.getString("Remove"),
                        titleColor = WColor.Red.color
                    ),
                    hasSeparator = false,
                    onTap = {
                        window?.let {
                            AccountDialogHelpers.presentSignOut(it, account)
                        }
                    })
            ),
            xOffset = if (isGridMode) (-8).dp else 72.dp,
            yOffset = if (isGridMode) 1 else (-20).dp,
            positioning = WMenuPopup.Positioning.BELOW,
            centerHorizontally = true,
            onWillDismiss = {
                cell.isShowingPopup = false
                highlightOverlayView?.let { highlightOverlayView ->
                    highlightOverlayView.fadeOut {
                        window?.windowView?.removeView(highlightOverlayView)
                    }
                }
            }
        )
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(
        rv: RecyclerView,
        section: Int
    ): Int {
        return accounts.size
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return if (viewMode == MWalletSettingsViewMode.GRID) ACCOUNT_GRID_CELL else ACCOUNT_ROW_CELL
    }

    override fun recyclerViewCellView(
        rv: RecyclerView,
        cellType: WCell.Type
    ): WCell {
        return when (cellType) {
            ACCOUNT_GRID_CELL -> {
                WalletCardCell(
                    window!!,
                    cellWidth,
                    onTouchStart = { v ->
                        touchingItem = v
                    }, onClick = { newAccount ->
                        switchAccountTo(newAccount)
                    }, onLongClick = { cell, view, account ->
                        showMenu(cell, view, account)
                    })
            }

            ACCOUNT_ROW_CELL -> {
                WalletCardRowCell(
                    window!!,
                    reordering = isReordering,
                    onTouchStart = { v ->
                        touchingItem = v
                    }, onClick = { newAccount ->
                        switchAccountTo(newAccount)
                    }, onLongClick = { cell, view, account ->
                        showMenu(cell, view, account)
                    }, onCheckChanged = { account, isChecked ->
                        if (isChecked)
                            checkedAccounts.add(account)
                        else
                            checkedAccounts.remove(account)
                        onCheckChanged?.invoke()
                    })
            }

            else -> {
                throw Error()
            }
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when {
            cellHolder.cell is WalletCardCell -> {
                (cellHolder.cell as WalletCardCell).configure(accounts[indexPath.row])
            }

            cellHolder.cell is WalletCardRowCell -> {
                val account = accounts[indexPath.row]
                (cellHolder.cell as WalletCardRowCell).configure(
                    account = account,
                    isFirst = indexPath.row == 0,
                    isLast = indexPath.row == accounts.size - 1,
                    isChecked = checkedAccounts.contains(account),
                    reordering = isReordering
                )
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return accounts[indexPath.row].accountId
    }

    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        super.onModalSlide(expandOffset, expandProgress)
        if (!didSetup)
            return
        updateBottomViewsYPosition()
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.removeOnScrollListener(scrollListener)
    }

    fun toggleReorder(reordering: Boolean, animated: Boolean) {
        // Update all visible cells
        if (animated) {
            animatingReorderingTo = reordering
            if (recyclerView.computeVerticalScrollOffset() > 0) {
                animatingReorderChange = true
                recyclerView.smoothScrollToPosition(0)
            } else {
                animatingReorderChange = false
            }
        } else {
            isReordering = reordering
            rvAdapter.reloadData()
        }
    }
}
