package org.mytonwallet.app_air.uistake.earn

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.DecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.contains
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.core.widget.TextViewCompat
import androidx.lifecycle.ViewModelProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter.WRecyclerViewDataSource
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.LinearLayoutManagerAccurateOffset
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WAnimationView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WCounterLabel
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uistake.earn.cells.EarnItemCell
import org.mytonwallet.app_air.uistake.earn.cells.EarnSpaceCell
import org.mytonwallet.app_air.uistake.earn.models.EarnItem
import org.mytonwallet.app_air.uistake.earn.views.EarnHeaderView
import org.mytonwallet.app_air.uistake.helpers.ClaimRewardsHelper
import org.mytonwallet.app_air.uistake.helpers.StakingMessageHelpers
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.USDE_SLUG
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger

@SuppressLint("ClickableViewAccessibility")
class EarnVC(
    context: Context,
    val tokenSlug: String,
    private var onScroll: ((rv: RecyclerView) -> Unit)?
) : WViewControllerWithModelStore(context), WRecyclerViewDataSource {
    override val TAG = "Earn"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = true

    companion object {
        val HEADER_CELL = WCell.Type(1)
        val ITEMS_CELL = WCell.Type(2)

        val SKELETON_HEADER_CELL = WCell.Type(3)
        val SKELETON_CELL = WCell.Type(4)
    }

    private val viewModelFactory = EarnViewModelFactory(tokenSlug)
    private val earnViewModel by lazy {
        ViewModelProvider(
            window!!,
            viewModelFactory
        )[EarnViewModel.alias(tokenSlug), EarnViewModel::class.java]
    }

    override var title: String?
        get() = when (tokenSlug) {
            TONCOIN_SLUG -> "TON"
            MYCOIN_SLUG -> "MY"
            USDE_SLUG -> "USDe"
            else -> ""
        }
        set(value) {}

    override val isSwipeBackAllowed: Boolean = false

    private var skeletonDataSource: WRecyclerViewDataSource? = object : WRecyclerViewDataSource {
        override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
            return 2
        }

        override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
            return if (section == 0) 1 else 100
        }

        override fun recyclerViewCellType(
            rv: RecyclerView,
            indexPath: IndexPath
        ): WCell.Type {
            return when (indexPath.section) {
                0 -> {
                    HEADER_CELL
                }

                else -> {
                    return if (indexPath.row == 0) SKELETON_HEADER_CELL else SKELETON_CELL
                }
            }
        }

        override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
            return when (cellType) {
                HEADER_CELL -> {
                    EarnSpaceCell(context, isTransparent = true)
                }

                SKELETON_HEADER_CELL -> {
                    SkeletonHeaderCell(context, 48.dp)
                }

                else -> {
                    SkeletonCell(context)
                }
            }
        }

        override fun recyclerViewConfigureCell(
            rv: RecyclerView,
            cellHolder: WCell.Holder,
            indexPath: IndexPath
        ) {
            when (cellHolder.cell) {
                is EarnSpaceCell -> {
                    configureHeaderCell(cellHolder)
                }

                is SkeletonHeaderCell -> {
                    (cellHolder.cell as SkeletonHeaderCell).updateTheme()
                }

                is SkeletonCell -> {
                    (cellHolder.cell as SkeletonCell).apply {
                        configure(indexPath.row, isFirst = false, isLast = false)
                        updateTheme()
                    }
                }
            }
        }
    }

    private val rvSkeletonAdapter =
        WRecyclerViewAdapter(
            WeakReference(skeletonDataSource),
            arrayOf(HEADER_CELL, SKELETON_HEADER_CELL, SKELETON_CELL)
        )

    private val skeletonRecyclerView: WRecyclerView by lazy {
        val rv = object : WRecyclerView(this) {
            override fun onTouchEvent(event: MotionEvent): Boolean {
                return false
            }
        }
        rv.adapter = rvSkeletonAdapter
        rv.setLayoutManager(LinearLayoutManager(context))
        rv.setItemAnimator(null)
        rv.alpha = 0f
        rv.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        rv
    }

    private val skeletonView = SkeletonView(context)

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(HEADER_CELL, ITEMS_CELL)).apply {
            setHasStableIds(true)
        }

    private val noItemView: WView by lazy {
        val wView = WView(context)
        wView.visibility = View.GONE
        wView.apply {
            addView(
                animationView,
                ConstraintLayout.LayoutParams(124.dp, 124.dp)
            )
            addView(
                noItemLabel,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
            )
            addView(
                notItemButton,
                ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 50.dp)
            )

            setConstraints {
                toCenterX(animationView)
                topToBottom(noItemLabel, animationView, 12f)
                toCenterX(noItemLabel, 40f)

                topToBottom(notItemButton, noItemLabel, 8f)
                toCenterX(notItemButton, 40f)
            }
        }
        wView.post {
            wView.setConstraints {
                toTopPx(
                    animationView,
                    (view.height - headerView.measuredHeight -
                        (navigationController?.getSystemBars()?.bottom ?: 0) - 250.dp) / 2
                )
            }
        }
        wView
    }

    private val animationView: WAnimationView by lazy {
        val v = WAnimationView(context)
        v.alpha = 0f
        v
    }

    private val noItemLabel: WLabel by lazy {
        val label = WLabel(context)
        label.setStyle(16f, WFont.Medium)
        label.textAlignment = View.TEXT_ALIGNMENT_CENTER
        label.text =
            LocaleController.getString("Earn up to %1$@ per year from your tokens")
        label
    }

    private val notItemButton: WButton by lazy {
        val label = WButton(context, WButton.Type.SECONDARY)
        label.textAlignment = View.TEXT_ALIGNMENT_CENTER
        label.text =
            LocaleController.getString("How does it work?")
        label.setOnClickListener { onNoItemButtonClicked() }
        label
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            updateBlurViews(recyclerView)
            onScroll?.invoke(recyclerView)

            val firstVisibleItem =
                (recyclerView.layoutManager as LinearLayoutManagerAccurateOffset).findFirstVisibleItemPosition() == 0
            if (dy > 3 && !firstVisibleItem) {
                hideRewards()
            } else if (dy < -3 || firstVisibleItem) {
                showRewards()
            }
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
                onScroll?.invoke(recyclerView)
            }
        }
    }

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val layoutManager = LinearLayoutManagerAccurateOffset(context)
        layoutManager.isSmoothScrollbarEnabled = true
        rv.setLayoutManager(layoutManager)
        rv.setItemAnimator(null)
        rv.clipToPadding = false
        rv.addOnScrollListener(scrollListener)
        var initialY = 0f
        rv.setOnTouchListener { _: View?, event: MotionEvent ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialY = event.y
                }
            }
            if (event.action == MotionEvent.ACTION_MOVE) {
                if (!rv.canScrollVertically(-1) && (event.y - initialY) > 10) {
                    rv.requestDisallowInterceptTouchEvent(true)
                } else if (!rv.canScrollVertically(1) && (event.y - initialY) < -10) {
                    rv.requestDisallowInterceptTouchEvent(true)
                }
            }
            false
        }
        rv
    }

    private var headerCell: EarnSpaceCell? = null

    private val headerView: EarnHeaderView by lazy {
        val v = EarnHeaderView(
            WeakReference(this),
            onAddStakeClick = {
                val nav = navigationController
                nav?.push(
                    StakingVC(
                        context,
                        tokenSlug,
                        StakingViewModel.Mode.STAKE
                    )
                )
            },
            onUnstakeClick = {
                val stakingState = AccountStore.stakingData?.stakingState(tokenSlug)
                if (stakingState?.isUnstakeRequestAmountUnlocked == true) {
                    claimRewardsPressed()
                } else {
                    navigationController?.push(
                        StakingVC(
                            context,
                            tokenSlug,
                            StakingViewModel.Mode.UNSTAKE
                        )
                    )
                }
            }
        )
        v.gravity = Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
        v
    }

    private val headerHeight: Int
        get() {
            return 298.dp + (navigationController?.getSystemBars()?.top ?: 0)
        }

    private val rewardLabel: WSensitiveDataContainer<WCounterLabel> by lazy {
        WSensitiveDataContainer(
            WCounterLabel(context).apply {
                id = View.generateViewId()
                setStyle(16f)
                setGradientColor(
                    arrayOf(
                        WColor.EarnGradientLeft,
                        WColor.EarnGradientRight
                    )
                )
            },
            maskConfig = WSensitiveDataContainer.MaskConfig(
                10,
                2,
                Gravity.START or Gravity.CENTER_VERTICAL
            )
        )
    }
    val claimButton = WLabel(context).apply {
        text =
            LocaleController.getString("Claim")
        setOnClickListener {
            claimRewardsPressed()
        }
        isGone = AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW
        setTextColor(WColor.Tint)
        isTinted = true
        setPadding(12.dp, 0, 12.dp, 0)
        gravity = Gravity.CENTER
    }
    private val claimRewardView: WView by lazy {
        WView(context).apply {
            elevation = 4f.dp
            val titleLabel = WLabel(context).apply {
                text =
                    LocaleController.getString("Accumulated Rewards")
                setStyle(16f, WFont.Medium)
                setTextColor(WColor.PrimaryText)
                setSingleLine()
                TextViewCompat.setAutoSizeTextTypeUniformWithConfiguration(
                    this,
                    12,
                    16,
                    3,
                    TypedValue.COMPLEX_UNIT_SP
                )
            }
            addView(titleLabel, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
            addView(rewardLabel)
            addView(claimButton, ConstraintLayout.LayoutParams(WRAP_CONTENT, 30.dp))
            setConstraints {
                toTop(titleLabel, 8f)
                toStart(titleLabel, 20f)
                endToStart(titleLabel, claimButton, 8f)
                topToBottom(rewardLabel, titleLabel, 8f)
                toStart(rewardLabel, 20f)
                toBottom(rewardLabel, 8f)
                toEnd(claimButton, 12f)
                toCenterY(claimButton)
            }
        }
    }

    override fun setupViews() {
        super.setupViews()

        view.addView(
            recyclerView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
        )

        view.addView(
            skeletonRecyclerView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
        )

        view.addView(skeletonView)

        view.addView(
            noItemView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
        )
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.bottom ?: 0)
        )
        view.addView(claimRewardView, ConstraintLayout.LayoutParams(0, 58.dp))
        view.setConstraints {
            allEdges(recyclerView)
            allEdges(skeletonRecyclerView)
            allEdges(skeletonView)

            toTopPx(noItemView, headerHeight)
            toCenterX(noItemView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottom(noItemView)

            toBottomPx(
                claimRewardView,
                16.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
            toCenterX(claimRewardView, 2 * ViewConstants.HORIZONTAL_PADDINGS + 12f)
        }
        navigationBar?.bringToFront()

        updateView(earnViewModel.viewStateValue())

        updateTheme()

        setupObservers()

        earnViewModel.loadOrRefreshStakingData()
    }

    private var lastListState: HistoryListState? = null
    private var previousHistoryItems: List<EarnItem> = emptyList()
    private fun updateItems(newItems: List<EarnItem>) {
        val previousHistoryItems = previousHistoryItems
        this.previousHistoryItems = newItems.toList()
        rvAdapter.applyChanges(
            previousHistoryItems,
            newItems,
            1,
            true
        )
    }

    private fun updateView(viewState: EarnViewState) {
        // balance
        headerView.apply {
            setStakingBalance(
                viewState.stakingBalance ?: "0",
                earnViewModel.token?.symbol ?: "",
                viewState.stakingBalanceIsLarge,
            )
            setSubtitle(AccountStore.stakingData?.stakingState(tokenSlug))
            changeAddStakeButtonEnable(viewState.enableAddStakeButton)
            changeUnstakeButtonVisibility(viewState.showUnstakeButton)
        }

        // list
        when (viewState.historyListState) {
            is HistoryListState.InitialState -> {
                if (viewState.stakingBalance == null) {
                    headerView.hideInnerViews()
                } else {
                    headerView.showInnerViews(
                        viewState.showAddStakeButton,
                        viewState.showUnstakeButton,
                        viewState.showBiggerUnstakeButton
                    )
                }
                recyclerView.overScrollMode = RecyclerView.OVER_SCROLL_NEVER
                noItemView.visibility = View.GONE
                showSkeletonViews(viewState.stakingBalance == null)

                rvAdapter.reloadData()
            }

            is HistoryListState.NoItem -> {
                headerView.showInnerViews(
                    viewState.showAddStakeButton,
                    viewState.showUnstakeButton, viewState.showBiggerUnstakeButton
                )
                recyclerView.overScrollMode = RecyclerView.OVER_SCROLL_NEVER
                noItemView.visibility = View.VISIBLE
                updateSkeletonState()

                noItemLabel.text = LocaleController.getFormattedString(
                    "Earn up to %1$@ per year from your tokens",
                    listOf("${earnViewModel.apy.toString()}%")
                )

                animationView.play(R.raw.animation_gem, false, onStart = {
                    startedNow()
                })
                Handler(Looper.getMainLooper()).postDelayed({
                    startedNow()
                }, 3000)

                rvAdapter.reloadData()
            }

            is HistoryListState.HasItem -> {
                headerView.showInnerViews(
                    viewState.showAddStakeButton,
                    viewState.showUnstakeButton,
                    viewState.showBiggerUnstakeButton
                )
                recyclerView.overScrollMode = RecyclerView.OVER_SCROLL_ALWAYS
                noItemView.visibility = View.GONE
                updateSkeletonState()
                updateItems(viewState.historyListState.historyItems)

            }
        }
        lastListState = viewState.historyListState

        val shouldShowUnclaimedReward =
            tokenSlug != USDE_SLUG &&
                viewState.unclaimedReward != null &&
                viewState.unclaimedReward > BigInteger.ZERO
        if (shouldShowUnclaimedReward) {
            if (!claimRewardView.isVisible) {
                claimRewardView.visibility = View.VISIBLE
                claimRewardView.fadeIn()
            }
            rewardLabel.contentView.setAmount(TokenStore.getToken(tokenSlug)?.let { token ->
                viewState.unclaimedReward.toString(
                    decimals = token.decimals,
                    currency = token.symbol,
                    currencyDecimals = token.decimals,
                    showPositiveSign = false,
                    forceCurrencyToRight = true,
                    roundUp = false
                )
            } ?: "")
            recyclerView.setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                86.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        } else {
            claimRewardView.visibility = View.GONE
            recyclerView.setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                (navigationController?.getSystemBars()?.bottom ?: 0)
            )
        }
    }

    var startedAnimation = false
        private set

    private fun startedNow() {
        if (startedAnimation)
            return
        startedAnimation = true
        animationView.fadeIn()
    }

    override fun updateTheme() {
        super.updateTheme()

        recyclerView.setBackgroundColor(WColor.SecondaryBackground.color)

        noItemView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        noItemLabel.setTextColor(WColor.PrimaryText.color)

        rvAdapter.reloadData()

        claimRewardView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        claimButton.setBackgroundColor(WColor.Tint.color.colorWithAlpha(25), 15f.dp)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            recyclerView.paddingBottom
        )
        (headerView.parent as? WCell)?.setConstraints {
            toCenterX(headerView)
        }
        view.setConstraints {
            toCenterX(claimRewardView, 2 * ViewConstants.HORIZONTAL_PADDINGS + 12f)
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return listOf(
            HEADER_CELL,
            ITEMS_CELL
        ).size
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            0 -> 1
            else -> earnViewModel.getHistoryItems().size
        }
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (indexPath.section) {
            0 -> HEADER_CELL
            else -> ITEMS_CELL
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            HEADER_CELL -> {
                getHeaderCell()
            }

            ITEMS_CELL -> {
                EarnItemCell(context)
            }

            else -> {
                throw Error()
            }
        }
    }

    private fun getHeaderCell(): EarnSpaceCell {
        if (headerCell == null || headerCell?.contains(headerView) == false) {
            headerCell = EarnSpaceCell(context)
            headerCell?.addView(
                headerView,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    headerHeight
                )
            )
            headerCell?.setConstraints {
                toCenterX(headerView, -ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
        }
        return headerCell!!
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            0 -> {
                configureHeaderCell(cellHolder)

                return
            }

            else -> {
                val item = earnViewModel.getHistoryItems()[indexPath.row]
                val cell = (cellHolder.cell as EarnItemCell)
                cell.configure(
                    item,
                    earnViewModel.token?.symbol ?: "",
                    earnViewModel.getTotalProfitFormatted(),
                    indexPath.row == 0,
                    indexPath.row == earnViewModel.getHistoryItems().size - 1
                ) { }

                checkShouldLoadMoreItems(item.timestamp)

                return
            }
        }

    }

    private fun configureHeaderCell(cellHolder: WCell.Holder) {
        val cellLayoutParams = RecyclerView.LayoutParams(MATCH_PARENT, 0)
        (cellHolder.cell as EarnSpaceCell).updateTheme()

        val newHeight = headerHeight
        cellLayoutParams.height = newHeight
        cellHolder.cell.layoutParams = cellLayoutParams
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        when (indexPath.section) {
            0 -> {}

            else -> {
                val item = earnViewModel.getHistoryItems()[indexPath.row]
                return item.id
            }
        }
        return super.recyclerViewCellItemId(rv, indexPath)
    }

    private fun checkShouldLoadMoreItems(timestampOfShowingItem: Long) {
        with(earnViewModel) {
            if (lastStakingHistoryItem?.let { timestampOfShowingItem <= it.timestamp } == true) {
                loadMoreStakingHistoryItems()
            }
            if (lastStakedActivityTimestamp?.let { timestampOfShowingItem <= it } == true) {
                loadMoreStakeActivityItems()
            }
            if (lastUnstakedActivityTimestamp?.let { timestampOfShowingItem <= it } == true) {
                loadMoreUnstakeActivityItem()
            }
        }
    }

    private fun setupObservers() {
        collectFlow(earnViewModel.viewState) { viewState ->
            updateView(viewState)
        }
    }

    private fun onNoItemButtonClicked() {
        window?.topViewController?.showAlert(
            title = LocaleController.getString(
                "How does it work?"
            ),
            text = StakingMessageHelpers.whyStakingIsSafeDescription(earnViewModel.tokenSlug)
                ?: return,
            button = LocaleController.getString(
                "OK"
            ),
            preferPrimary = false,
            allowLinkInText = true
        )
    }

    private fun updateSkeletonViews(showHeaderSkeleton: Boolean) {
        val skeletonViews = mutableListOf<View>()
        val skeletonViewsRadius = hashMapOf<Int, Float>()
        for (i in 1 until skeletonRecyclerView.childCount) {
            val child = skeletonRecyclerView.getChildAt(i)
            if (child is SkeletonContainer) {
                child.getChildViewMap().forEach {
                    skeletonViews.add(it.key)
                    skeletonViewsRadius[skeletonViews.lastIndex] = it.value
                }
            }
        }
        if (showHeaderSkeleton) {
            headerView.getChildViewMap().forEach {
                skeletonViews.add(it.key)
                skeletonViewsRadius[skeletonViews.lastIndex] = it.value
            }
        }
        skeletonView.applyMask(skeletonViews, skeletonViewsRadius)
    }

    private fun showSkeletonViews(showHeaderSkeleton: Boolean) {
        rvSkeletonAdapter.reloadData()
        view.post {
            updateSkeletonViews(showHeaderSkeleton)
            skeletonAlpha = 1f
            skeletonRecyclerView.alpha = 1f
            skeletonView.startAnimating()
        }
    }

    private var skeletonAlpha = 0f
    private fun updateSkeletonState() {
        if (skeletonAlpha > 0f) {
            skeletonAlpha = 0f
            skeletonRecyclerView.fadeOut {
                skeletonView.stopAnimating()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        onScroll = null
        recyclerView.adapter = null
        skeletonRecyclerView.adapter = null
        recyclerView.removeAllViews()
        skeletonRecyclerView.removeAllViews()
        recyclerView.setOnTouchListener(null)
        recyclerView.removeOnScrollListener(scrollListener)
        headerView.onDestroy()
        notItemButton.setOnClickListener(null)
    }

    private var visibilityFraction = 1f
    private var visibilityTarget = 1f
    private var activeVisibilityValueAnimator: ValueAnimator? = null

    private fun showRewards() {
        if (visibilityTarget == 1f)
            return
        activeVisibilityValueAnimator?.cancel()
        activeVisibilityValueAnimator = ValueAnimator.ofFloat(visibilityFraction, 1f).apply {
            duration =
                (AnimationConstants.VERY_QUICK_ANIMATION * (1f - visibilityFraction)).toLong()
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                visibilityFraction = animatedValue as Float
                claimRewardView.alpha = visibilityFraction
                claimRewardView.translationY = 16.dp * (1 - visibilityFraction)
            }
            visibilityTarget = 1f
            start()
        }
    }

    private fun hideRewards() {
        if (visibilityTarget == 0f)
            return
        activeVisibilityValueAnimator?.cancel()
        activeVisibilityValueAnimator = ValueAnimator.ofFloat(visibilityFraction, 0f).apply {
            duration =
                (AnimationConstants.VERY_QUICK_ANIMATION * visibilityFraction).toLong()
            interpolator = DecelerateInterpolator()
            addUpdateListener {
                visibilityFraction = animatedValue as Float
                claimRewardView.alpha = visibilityFraction
                claimRewardView.translationY = 16.dp * (1 - visibilityFraction)
            }
            visibilityTarget = 0f
            start()
        }
    }

    private fun claimRewardsPressed() {
        Logger.d(Logger.LogTag.STAKING, "claimRewardsPressed: tokenSlug=$tokenSlug")
        val stakingState = AccountStore.stakingData?.stakingState(tokenSlug) ?: return
        val isEthena = stakingState is StakingState.Ethena
        ClaimRewardsHelper.presentClaimRewards(
            viewController = this,
            tokenSlug = tokenSlug,
            stakingState = stakingState,
            amountToClaim = earnViewModel.amountToClaim ?: stakingState.amountToClaim,
            onClaimed = {
                if (!isEthena) {
                    claimRewardView.visibility = View.GONE
                }
            },
            onError = { error ->
                showError(error)
            }
        )
    }
}
