package org.mytonwallet.app_air.uiassets.viewControllers.assets

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.vkryl.android.animatorx.BoolAnimator
import org.mytonwallet.app_air.uiassets.models.ExpiringDomainsData
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.SingleCollection
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.TelegramGifts
import org.mytonwallet.app_air.uiassets.viewControllers.assets.cells.AssetCell
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.icons.menuIconRes
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uiassets.viewControllers.renew.RenewVC
import org.mytonwallet.app_air.uiassets.viewControllers.views.WDomainExpirationBannerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WActionBar
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WNavigationController.PresentationConfig
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleActionView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.SelectiveItemAnimator
import org.mytonwallet.app_air.uicomponents.helpers.SpacesItemDecoration
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config.Icon
import org.mytonwallet.app_air.uicomponents.widgets.recyclerView.CustomItemTouchHelper
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedController
import org.mytonwallet.app_air.uicomponents.widgets.segmentedController.WSegmentedControllerItemVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.models.MCollectionTab
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.MMarketplace
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchainExplorer
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AssetsVC(
    context: Context,
    defaultAccountId: String,
    private val viewMode: ViewMode,
    private var injectedWindow: WWindow? = null,
    val collectionMode: CollectionMode? = null,
    val isShowingSingleCollection: Boolean,
    private val allowReordering: Boolean = true,
    private val onHeightChanged: (() -> Unit)? = null,
    private val onScroll: ((rv: RecyclerView) -> Unit)? = null,
    private val onReorderingRequested: (() -> Unit)? = null,
    private val onNftsShown: (() -> Unit)? = null,
    private val shouldAnimateHeight: (() -> Boolean)? = null,
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, AssetsVM.Delegate,
    WSegmentedControllerItemVC,
    ISortableView {
    override val TAG = "Assets"

    data class SelectionSnapshot(
        val selectedAddresses: Set<String>
    )

    override var segmentedController: WSegmentedController? = null
    override var badge: String? = null

    val identifier: String
        get() {
            return when (collectionMode) {
                is SingleCollection -> {
                    collectionMode.collection.address
                }

                TelegramGifts -> {
                    NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                }

                is CollectionMode.ReadOnly -> collectionMode.collectionAddress

                null -> AssetsTabVC.TAB_COLLECTIBLES
            }
        }

    val isReadOnly: Boolean
        get() = collectionMode is CollectionMode.ReadOnly

    enum class ViewMode {
        THUMB,
        COMPLETE
    }

    sealed class CollectionMode {
        data object TelegramGifts : CollectionMode()
        data class SingleCollection(val collection: MCollectionTabToShow) : CollectionMode()
        data class ReadOnly(val name: String?, val nfts: List<ApiNft>) : CollectionMode()

        val collectionAddress: String
            get() {
                return when (this) {
                    is SingleCollection -> {
                        collection.address
                    }

                    TelegramGifts -> {
                        NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                    }

                    is ReadOnly -> {
                        // technical in-app use only address
                        "read_only"
                    }
                }
            }

        val chain: String?
            get() = when (this) {
                is SingleCollection -> collection.chain
                TelegramGifts -> MBlockchain.ton.name
                is ReadOnly -> null
            }

        val cacheKey: String
            get() = when (this) {
                is SingleCollection -> "${collection.chain}:${collection.address}"
                TelegramGifts -> "telegram_gifts"
                is ReadOnly -> "read_only"
            }

        fun matches(comparing: CollectionMode): Boolean {
            return when (this) {
                is SingleCollection -> {
                    comparing is SingleCollection &&
                        comparing.collection.chain == collection.chain &&
                        comparing.collection.address == collection.address
                }

                TelegramGifts -> {
                    comparing is TelegramGifts
                }

                is ReadOnly -> {
                    comparing is ReadOnly
                }
            }
        }
    }

    companion object {
        const val NFTS_SECTION = 0
        val ASSET_CELL = WCell.Type(1)
        private const val BANNER_ALPHA_VISIBLE_RANGE = 0.5f
        private const val BANNER_COLLAPSE_TRANSLATION_DP = 20
        private const val BANNER_COLLAPSE_MIN_SCALE = 0.8f
        private const val THUMB_BANNER_TOP_MARGIN_DP = 6
        private const val THUMB_BANNER_BOTTOM_MARGIN_DP = 11
        private const val THUMB_RECYCLER_HORIZONTAL_PADDING_DP = 12
        private const val THUMB_GRID_MAX_COLUMNS = 3
    }

    override val shouldDisplayBottomBar = isShowingSingleCollection &&
        (navigationController?.viewControllers?.size ?: 0) > 1

    override var title: String?
        get() {
            return collectionMode.title
        }
        set(_) {
        }

    override val isSwipeBackAllowed = isShowingSingleCollection

    override val shouldDisplayTopBar = isShowingSingleCollection

    val underSegmentedControlReversedCornerView: ReversedCornerView? by lazy {
        if (viewMode == ViewMode.COMPLETE && !isShowingSingleCollection) ReversedCornerView(
            context,
            ReversedCornerView.Config(
                shouldBlur = false,
                additionalTabletPadding = isSplitDetailPanel
            )
        ).apply {
            setHorizontalPadding(0f)
        } else null
    }

    private val assetsVM by lazy {
        AssetsVM(viewMode, collectionMode, defaultAccountId, this)
    }

    private val thereAreMoreToShow: Boolean
        get() {
            return assetsVM.thereAreMoreToShow
        }

    var currentHeight: Int? = null
    private var emptyDataViewHeight = 0
    var completeModeExpiringDomainsBannerHeight = WDomainExpirationBannerView.HEIGHT_DP.dp
    private val thumbBannerContainerHeight: Int by lazy {
        (WDomainExpirationBannerView.HEIGHT_DP +
            THUMB_BANNER_TOP_MARGIN_DP +
            THUMB_BANNER_BOTTOM_MARGIN_DP).dp
    }

    private val showsCellTitle: Boolean
        get() = viewMode == ViewMode.COMPLETE ||
            (viewMode == ViewMode.THUMB && window?.isWideLayout == true)

    private val cellTitleExtraHeight: Int
        get() = if (showsCellTitle) 8.dp + 24.dp + 20.dp else 0

    private val finalHeight: Int
        get() {
            return if (!assetsVM.hasLoadedNfts || assetsVM.isEmpty) {
                getEmptyThumbHeight().takeIf { it > 0 } ?: 192.dp
            } else {
                val rows = if (assetsVM.nftsCount > 3) 2 else 1
                val nftGridHeight = rows * (thumbGridItemWidth() + cellTitleExtraHeight) +
                    thumbRecyclerVerticalPadding() +
                    (if (thereAreMoreToShow) 64 else 8).dp.coerceAtLeast(
                        thumbRecyclerVerticalPadding()
                    )
                nftGridHeight +
                    (if (shouldShowWarningBanner) thumbBannerContainerHeight else 0)
            }
        }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(ASSET_CELL)
        ).apply {
            setHasStableIds(true)
        }
    private var displayedAssetRows: List<AssetRow> = emptyList()

    private val emptyDataView: WEmptyIconTitleSubtitleActionView by lazy {
        val marketplace = getMarketplaceForEmptyAssets()
        WEmptyIconTitleSubtitleActionView(context).apply {
            configure(
                titleText = LocaleController.getString("No collectibles yet"),
                subtitleText = LocaleController.getString("\$nft_explore_offer").trim(),
                actionText = LocaleController.getStringWithKeyValues(
                    "Open %nft_marketplace%",
                    listOf("%nft_marketplace%" to marketplace.title)
                ),
                animation = R.raw.animation_happy
            ) {
                openNftMarketplace(marketplace)
            }
            isGone = true
        }
    }

    private var isEmptyStateVisible = false
    var isDragging = false
        private set

    val saveOnDrag: Boolean
        get() {
            return false
        }

    private var lastTouchY = 0f

    // Expiring domains warning
    private val shouldShowWarningBanner: Boolean
        get() = !isReadOnly && assetsVM.expiringDomainsData != null
    private var isShowingWarningBanner = false
    private val thumbWarningBannerView: WDomainExpirationBannerView by lazy {
        WDomainExpirationBannerView(context).apply {
            isGone = true
        }
    }
    private val warningBannerAnimator = BoolAnimator(
        duration = AnimationConstants.VERY_QUICK_ANIMATION,
        interpolator = CubicBezierInterpolator.EASE_BOTH,
        onAnimationsFinished = { finalState, _ ->
            if (isShowingWarningBanner && finalState == BoolAnimator.State.FALSE) {
                isShowingWarningBanner = false
                if (viewMode == ViewMode.THUMB) {
                    updateThumbWarningBannerLayout()
                    bannerAnimationUpdate(0f)
                } else {
                    bannerAnimationUpdate(0f)
                }
            }
        }
    ) { _, floatValue, _, _ ->
        bannerAnimationUpdate(floatValue)
    }
    private var bannerViewAlpha = 0f
    private var completeModeBannerInset = 0

    private fun bannerVisualProgress(floatValue: Float): Float {
        val threshold = 1f - BANNER_ALPHA_VISIBLE_RANGE
        return ((floatValue - threshold) / BANNER_ALPHA_VISIBLE_RANGE).coerceIn(0f, 1f)
    }

    private fun bannerAnimationUpdate(floatValue: Float) {
        bannerViewAlpha = bannerVisualProgress(floatValue)
        if (viewMode == ViewMode.THUMB) {
            thumbWarningBannerView.alpha = bannerViewAlpha
            val collapseProgress = 1f - bannerViewAlpha
            thumbWarningBannerView.translationY =
                -BANNER_COLLAPSE_TRANSLATION_DP.dp * collapseProgress
            val scale = BANNER_COLLAPSE_MIN_SCALE +
                (1f - BANNER_COLLAPSE_MIN_SCALE) * bannerViewAlpha
            thumbWarningBannerView.scaleX = scale
            thumbWarningBannerView.scaleY = scale
            updateThumbWarningBannerLayout(floatValue)
        } else {
            updateCompleteModeBannerLayout(floatValue)
        }
        updateShowAllTranslationY()
    }

    private fun thumbRecyclerBasePadding(): Int {
        return (if (window?.isWideLayout == true) 8 else THUMB_RECYCLER_HORIZONTAL_PADDING_DP).dp
    }

    private fun thumbRecyclerVerticalPadding(): Int {
        return (if (window?.isWideLayout == true) 8 else 4).dp
    }

    private fun thumbGridItemWidth(): Int {
        val contentWidth = view.width.takeIf { it > 0 } ?: recyclerView.width
        return (contentWidth - 2 * thumbRecyclerBasePadding()) / THUMB_GRID_MAX_COLUMNS
    }

    private fun thumbRecyclerHorizontalPadding(): Int {
        val basePadding = thumbRecyclerBasePadding()
        val itemCount = assetsVM.nftsCount
        if (itemCount !in 1 until THUMB_GRID_MAX_COLUMNS || recyclerView.width == 0) {
            return basePadding
        }

        val centeredPadding = (recyclerView.width - thumbGridItemWidth() * itemCount) / 2
        return max(basePadding, centeredPadding)
    }

    private fun updateThumbWarningBannerLayout(floatValue: Float = warningBannerAnimator.floatValue) {
        if (viewMode != ViewMode.THUMB) {
            return
        }
        val collapsedTopInset = thumbRecyclerVerticalPadding()
        val expandedTopInset = thumbBannerContainerHeight
        val topInset = collapsedTopInset +
            ((expandedTopInset - collapsedTopInset) * floatValue).roundToInt()
        val horizontalPadding = thumbRecyclerHorizontalPadding()
        thumbWarningBannerView.isGone = !isShowingWarningBanner
        recyclerView.setPadding(
            horizontalPadding,
            topInset,
            horizontalPadding,
            thumbRecyclerBottomPadding()
        )
    }

    private fun thumbRecyclerBottomPadding(): Int {
        return thumbRecyclerVerticalPadding() + (if (thereAreMoreToShow) 56.dp else 0)
    }

    private fun completeModeTopInset(): Int {
        return (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
    }

    private fun updateCompleteModeBannerLayout(floatValue: Float = warningBannerAnimator.floatValue) {
        if (viewMode != ViewMode.COMPLETE) {
            return
        }

        val previousPaddingTop = recyclerView.paddingTop
        val firstVisiblePosition = layoutManager.findFirstVisibleItemPosition()
        val firstVisibleViewTop = layoutManager.findViewByPosition(firstVisiblePosition)?.top
        val wasAtTopBeforeInsetChange =
            firstVisiblePosition == 0 &&
                (firstVisibleViewTop == null || abs(firstVisibleViewTop - previousPaddingTop) <= 2.dp)

        val topInset = completeModeTopInset()
        val bottomInset = navigationController?.bottomInset ?: 0
        val bannerInset = (completeModeExpiringDomainsBannerHeight * floatValue).roundToInt()
        val bannerInsetDelta = bannerInset - completeModeBannerInset
        completeModeBannerInset = bannerInset

        recyclerView.setPadding(
            recyclerView.paddingLeft,
            topInset + bannerInset,
            recyclerView.paddingRight,
            bottomInset
        )

        if (bannerInsetDelta > 0 && wasAtTopBeforeInsetChange) {
            layoutManager.scrollToPositionWithOffset(0, recyclerView.paddingTop)
        }
    }

    private fun configureWarningBannerView(view: WDomainExpirationBannerView) {
        val content = assetsVM.expiringDomainsData ?: return
        view.configure(
            iconNfts = content.domainNfts,
            count = content.count,
            minDays = content.minDays
        )
        view.onTap = { openRenewForExpiringDomains() }
        view.onClose = { dismissExpiringDomainsBanner() }
        view.alpha = bannerViewAlpha
    }

    private fun updateExpiringDomainsBadge() {
        val badgeCount = assetsVM.expiringDomainsData?.count?.takeIf { it > 0 }
        segmentedController?.setBadge(identifier, badgeCount?.toString())
    }

    private fun updateThumbExpiringDomainsWarning(
        shouldShowBanner: Boolean,
        animated: Boolean
    ): Boolean {
        val bannerStateChanged = isShowingWarningBanner != shouldShowBanner
        if (!bannerStateChanged) {
            val syncValue = if (shouldShowBanner && !animated) {
                1f
            } else {
                warningBannerAnimator.floatValue
            }
            bannerAnimationUpdate(if (shouldShowBanner) syncValue else 0f)
            return false
        }

        if (!isShowingWarningBanner) {
            isShowingWarningBanner = true
            updateThumbWarningBannerLayout()
            if (animated) {
                bannerAnimationUpdate(0f)
            }
        }

        warningBannerAnimator.changeValue(shouldShowBanner, animated = animated)
        updateShowAllPosition()
        if (animated) {
            updateShowAllTranslationY()
        }
        return true
    }

    private fun updateCompleteExpiringDomainsWarning(
        shouldShowBanner: Boolean,
        animated: Boolean
    ): Boolean {
        val bannerStateChanged = isShowingWarningBanner != shouldShowBanner
        if (!bannerStateChanged) {
            bannerAnimationUpdate(warningBannerAnimator.floatValue)
            return false
        }

        if (!isShowingWarningBanner) {
            isShowingWarningBanner = true
        }
        bannerAnimationUpdate(warningBannerAnimator.floatValue)
        warningBannerAnimator.changeValue(shouldShowBanner, animated = animated)
        return true
    }

    private val itemAnimator: SelectiveItemAnimator = SelectiveItemAnimator().apply {
        setAll(WGlobalStorage.getAreAnimationsActive())
    }

    private val itemTouchHelper by lazy {
        val callback = object : CustomItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN or ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT,
            0
        ) {

            override fun isLongPressDragEnabled(): Boolean {
                return false
            }

            override fun isItemViewSwipeEnabled(): Boolean {
                return false
            }

            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                if (assetsVM.interactionMode != AssetsVM.InteractionMode.DRAG) {
                    return false
                }
                val fromPosition = viewHolder.adapterPosition
                val toPosition = target.adapterPosition

                if (viewMode == ViewMode.THUMB) {
                    val maxPosition = min(6, assetsVM.nftsCount) - 1
                    if (toPosition > maxPosition) return false
                }

                assetsVM.moveItem(fromPosition, toPosition, shouldSave = saveOnDrag)
                displayedAssetRows = assetsVM.assetRows.take(itemsCountToShow)
                rvAdapter.notifyItemMoved(fromPosition, toPosition)

                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            }

            override fun onSelectedChanged(viewHolder: RecyclerView.ViewHolder?, actionState: Int) {
                super.onSelectedChanged(viewHolder, actionState)

                when (actionState) {
                    ItemTouchHelper.ACTION_STATE_DRAG -> {
                        if (!isDragging) {
                            isDragging = true

                            recyclerView.parent?.requestDisallowInterceptTouchEvent(true)

                            viewHolder?.itemView?.animate()?.alpha(0.8f)?.scaleX(1.05f)
                                ?.scaleY(1.05f)
                                ?.translationZ(8.dp.toFloat())
                                ?.setDuration(AnimationConstants.QUICK_ANIMATION)
                                ?.setInterpolator(CubicBezierInterpolator.EASE_OUT)?.start()
                        }
                    }

                    ItemTouchHelper.ACTION_STATE_IDLE -> {
                        if (isDragging) {
                            isDragging = false

                            recyclerView.parent?.requestDisallowInterceptTouchEvent(false)

                            viewHolder?.itemView?.animate()?.alpha(1.0f)?.scaleX(1.0f)?.scaleY(1.0f)
                                ?.translationZ(0f)?.setDuration(AnimationConstants.QUICK_ANIMATION)
                                ?.setInterpolator(CubicBezierInterpolator.EASE_IN)?.start()
                        }
                    }
                }
            }

            override fun clearView(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ) {
                super.clearView(recyclerView, viewHolder)

                recyclerView.parent?.requestDisallowInterceptTouchEvent(false)

                viewHolder.itemView.animate()
                    .alpha(1.0f)
                    .scaleX(1.0f)
                    .scaleY(1.0f)
                    .translationZ(0f)
                    .setDuration(AnimationConstants.QUICK_ANIMATION)
                    .setInterpolator(CubicBezierInterpolator.EASE_IN)
                    .start()
            }

            override fun getMovementFlags(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ): Int {
                return if (allowReordering && assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) {
                    val dragFlags = ItemTouchHelper.UP or ItemTouchHelper.DOWN or
                        ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT
                    makeMovementFlags(dragFlags, 0)
                } else {
                    0
                }
            }
        }
        CustomItemTouchHelper(callback)
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            updateBlurViews(recyclerView)
            underSegmentedControlReversedCornerView?.translationY =
                -recyclerView.computeVerticalScrollOffset().toFloat()
            onScroll?.invoke(recyclerView)
        }

        override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
            super.onScrollStateChanged(recyclerView, newState)
            if (recyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE) {
                updateBlurViews(recyclerView)
                onScroll?.invoke(recyclerView)
            }
        }
    }

    private var activeNftMenuPopup: INavigationPopup? = null

    private val recyclerViewTouchListener = object : RecyclerView.OnItemTouchListener {
        private var startedDrag = false
        private var touchDownX = 0f
        private var touchDownY = 0f
        private val swipeSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val longPressTimeout = ViewConfiguration.getLongPressTimeout().toLong()
        private val dragFromMenuSlop = 10.dp
        private var pendingDragViewHolder: RecyclerView.ViewHolder? = null
        private val handler = Handler(Looper.getMainLooper())
        private val startDragRunnable = Runnable {
            pendingDragViewHolder?.let {
                itemTouchHelper.startDrag(it)
                startedDrag = true
            }
            pendingDragViewHolder = null
        }

        private fun cancelPendingDrag() {
            handler.removeCallbacks(startDragRunnable)
            pendingDragViewHolder = null
        }

        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    startedDrag = false
                    touchDownX = e.x
                    touchDownY = e.y
                    lastTouchY = e.y

                    if (assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) {
                        val child = rv.findChildViewUnder(e.x, e.y)
                        val viewHolder = child?.let { rv.getChildViewHolder(it) }
                        if (viewHolder != null) {
                            if (viewMode == ViewMode.THUMB) {
                                itemTouchHelper.startDrag(viewHolder)
                                startedDrag = true
                            } else {
                                pendingDragViewHolder = viewHolder
                                handler.postDelayed(startDragRunnable, longPressTimeout)
                            }
                        }
                        return false
                    }
                }

                MotionEvent.ACTION_MOVE -> {
                    if (startedDrag) return false
                    val dx = abs(e.x - touchDownX)
                    val dy = abs(e.y - touchDownY)
                    val popup = activeNftMenuPopup
                    if (popup != null) {
                        if (dx > dragFromMenuSlop || dy > dragFromMenuSlop) {
                            activeNftMenuPopup = null
                            popup.dismiss()
                            startDragFromMenu(touchDownX, touchDownY)
                            startedDrag = true
                        }
                        return false
                    }
                    if (dx > swipeSlop || dy > swipeSlop) {
                        if (assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) cancelPendingDrag()
                        startedDrag = true
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (activeNftMenuPopup != null) {
                        recyclerView.parent?.requestDisallowInterceptTouchEvent(false)
                        activeNftMenuPopup = null
                    }
                    if (assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) cancelPendingDrag()
                }
            }

            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {
            itemTouchHelper.injectTouchEvent(e)
        }

        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {
            if (assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) cancelPendingDrag()
        }
    }

    private val layoutManager =
        object : GridLayoutManager(context, calculateNoOfColumns()) {
            override fun canScrollVertically() =
                viewMode != ViewMode.THUMB && super.canScrollVertically()
        }
    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        rv.itemAnimator = itemAnimator
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.setLayoutManager(layoutManager)
        rv.clipToPadding = false
        rv.clipChildren = false
        when (viewMode) {
            ViewMode.THUMB -> {
                val thumbPadding = thumbRecyclerBasePadding()
                val thumbVerticalPadding = thumbRecyclerVerticalPadding()
                rv.setPadding(
                    thumbPadding,
                    thumbVerticalPadding,
                    thumbPadding,
                    thumbVerticalPadding
                )
                rv.addItemDecoration(
                    SpacesItemDecoration(
                        0,
                        0
                    )
                )
            }

            ViewMode.COMPLETE -> {
                rv.setPadding(
                    0,
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT.dp,
                    0,
                    0
                )
                rv.addItemDecoration(
                    SpacesItemDecoration(
                        0,
                        4.dp
                    )
                )
            }
        }

        rv.addOnScrollListener(scrollListener)
        if (!isReadOnly) {
            rv.addOnItemTouchListener(recyclerViewTouchListener)
        }

        if (!isReadOnly && allowReordering) {
            itemTouchHelper.attachToRecyclerView(rv)
        }

        if (viewMode == ViewMode.COMPLETE && !isShowingSingleCollection)
            rv.disallowInterceptOnOverscroll()

        rv
    }

    private val showAllView: ShowAllView by lazy {
        val v = ShowAllView(context)
        v.configure(
            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_show_collectibles,
            text = LocaleController.getFormattedString("Show All %1$@", listOf(title ?: ""))
        )
        v.onTap = {
            val initialSelectionSnapshot = selectionSnapshot()
            onShowAllTapped?.invoke()
            val window = injectedWindow ?: this.window!!
            val navVC = WNavigationController(
                window,
                PresentationConfig.PreferredFullScreen
            )
            navVC.setRoot(
                AssetsTabVC(
                    context,
                    assetsVM.showingAccountId,
                    defaultSelectedIdentifier = collectionMode?.collectionAddress
                        ?: AssetsTabVC.TAB_COLLECTIBLES,
                    initialSelectionSnapshot = initialSelectionSnapshot
                )
            )
            window.present(navVC)
        }
        v.setCounter(null)
        v.isGone = true
        v
    }

    private val pinButton: WImageButton by lazy {
        WImageButton(context).apply {
            setPadding(8.dp)
            setOnClickListener {
                val homeNftCollections =
                    WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId!!)
                if (isInHomeTabs) {
                    homeNftCollections.removeAll { it == homeCollectionTab }
                } else {
                    if (!homeNftCollections.any { it == homeCollectionTab })
                        homeNftCollections.add(homeCollectionTab)
                }
                WGlobalStorage.setHomeNftCollections(
                    AccountStore.activeAccountId!!,
                    homeNftCollections
                )
                WalletCore.notifyEvent(WalletEvent.HomeNftCollectionsUpdated)
                updatePinButton()
            }
        }
    }

    private val homeCollectionTab: MCollectionTab
        get() {
            return when (collectionMode) {
                is SingleCollection -> MCollectionTab(
                    collectionMode.collection.chain,
                    collectionMode.collection.address
                )

                TelegramGifts -> MCollectionTab(
                    MBlockchain.ton.name,
                    NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                )

                is CollectionMode.ReadOnly, null -> throw Exception()
            }
        }

    private val isInHomeTabs: Boolean
        get() {
            val homeNftCollections =
                WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId!!)
            return homeNftCollections.any { it == homeCollectionTab }
        }

    private val shouldShowMoreButton: Boolean
        get() {
            val isNonTonCollection = collectionMode is SingleCollection &&
                collectionMode.collection.chain != MBlockchain.ton.name
            return !isNonTonCollection
        }
    private val moreButton: WImageButton by lazy {
        WImageButton(context).apply {
            setPadding(8.dp)
            setOnClickListener {

                val items = mutableListOf<WMenuPopup.Item>()

                val network = MBlockchainNetwork.ofAccountId(assetsVM.showingAccountId)

                when (collectionMode) {

                    is SingleCollection -> {
                        val collectionAddress = collectionMode.collection.address

                        if (collectionMode.collection.chain == MBlockchain.ton.name) {
                            items.add(
                                WMenuPopup.Item(
                                    exploreMenuItemConfig(MMarketplace.Getgems),
                                    false,
                                ) {
                                    CollectionsMenuHelpers.openLink(
                                        MMarketplace.Getgems.collectionUrl(
                                            collectionAddress = collectionAddress,
                                            network = network
                                        )
                                    )
                                }
                            )
                            items.add(
                                WMenuPopup.Item(
                                    exploreMenuItemConfig(MBlockchainExplorer.TONSCAN),
                                    false,
                                ) {
                                    MBlockchainExplorer.TONSCAN.nftUrl(network, collectionAddress)
                                        ?.let { url ->
                                            CollectionsMenuHelpers.openLink(url)
                                        }

                                }
                            )
                        }
                    }

                    TelegramGifts -> {
                        items.add(
                            WMenuPopup.Item(
                                exploreMenuItemConfig(MMarketplace.Fragment),
                                false,
                            ) {
                                CollectionsMenuHelpers.openLink(MMarketplace.Fragment.giftsUrl())
                            }
                        )

                        items.add(
                            WMenuPopup.Item(
                                exploreMenuItemConfig(MMarketplace.Getgems),
                                false,
                            ) {
                                CollectionsMenuHelpers.openLink(MMarketplace.Getgems.giftsUrl())
                            }
                        )
                    }

                    is CollectionMode.ReadOnly, null -> return@setOnClickListener
                }
                items.lastOrNull()?.hasSeparator = true

                items.add(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = Icon(
                                org.mytonwallet.app_air.uiassets.R.drawable.ic_reorder,
                                WColor.PrimaryLightText
                            ),
                            title = LocaleController.getString("Reorder")
                        )
                    ) {
                        requestReordering()
                    })
                items.add(
                    WMenuPopup.Item(
                        WMenuPopup.Item.Config.Item(
                            icon = Icon(
                                org.mytonwallet.app_air.icons.R.drawable.ic_tick_30,
                                WColor.PrimaryLightText
                            ),
                            title = LocaleController.getString("Select")
                        )
                    ) {
                        openActionBar()
                    })

                WMenuPopup.present(
                    this,
                    items,
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.ALIGNED,
                    backdropStyle = WMenuPopup.BackdropStyle.Transparent,
                    usePillShadow = true
                )
            }
        }
    }

    private val navTrailingView: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = View.generateViewId()
            orientation = LinearLayout.HORIZONTAL
            addView(pinButton, LayoutParams(40.dp, 40.dp))
            if (shouldShowMoreButton) {
                addView(moreButton, LayoutParams(40.dp, 40.dp).apply {
                    marginStart = 8.dp
                })
            }
        }
    }

    private var actionBar: WActionBar? = null
    private var pendingSelectionSnapshot: SelectionSnapshot? = null
    private var prevSelectedCount = 0
    var onShowAllTapped: (() -> Unit)? = null
    var onSelectionRequested: ((nftAddressToSelect: String?) -> Unit)? = null
    var onAutoClose: (() -> Unit)? = null
    var onExpiringDomainsDataChanged: ((ExpiringDomainsData?) -> Unit)? = null
    var onSelectionChanged: ((selectedCount: Int, animationMode: TitleAnimationMode?, isInSelectionMode: Boolean) -> Unit)? =
        null

    private fun syncAssetRows(forceReload: Boolean = false) {
        val prevRows = displayedAssetRows
        val newRows = assetsVM.assetRows
        displayedAssetRows = newRows.take(itemsCountToShow)
        if (forceReload) {
            rvAdapter.reloadData()
            return
        }
        rvAdapter.applyChanges(prevRows, displayedAssetRows, NFTS_SECTION, false)
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(title!!)
        if (isShowingSingleCollection) {
            setupNavBar(true)
            if (!isReadOnly) {
                setupActionBar()
                navigationBar?.addTrailingView(navTrailingView, LayoutParams(WRAP_CONTENT, 40.dp))
            }
        }
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (viewMode == ViewMode.THUMB) {
            view.addView(
                thumbWarningBannerView,
                LayoutParams(0, WDomainExpirationBannerView.HEIGHT_DP.dp)
            )
            view.addView(showAllView, LayoutParams(MATCH_PARENT, 56.dp))
            showAllView.setupBlurBackground(recyclerView)
        }
        underSegmentedControlReversedCornerView?.let { underSegmentedControlReversedCornerView ->
            view.addView(
                underSegmentedControlReversedCornerView,
                LayoutParams(
                    MATCH_PARENT,
                    WNavigationBar.DEFAULT_HEIGHT.dp +
                        (navigationController?.getSystemBars()?.top ?: 0) +
                        underSegmentedControlReversedCornerView.cornerRadius.roundToInt()
                )
            )
        }
        view.setConstraints {
            if (viewMode == ViewMode.THUMB) {
                toTop(thumbWarningBannerView, THUMB_BANNER_TOP_MARGIN_DP.toFloat())
                toCenterX(thumbWarningBannerView, 16f)
                toCenterX(showAllView)
            }
            if (isShowingSingleCollection) {
                toStartPx(
                    recyclerView,
                    ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding
                )
                toEnd(recyclerView, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            }
            underSegmentedControlReversedCornerView?.let {
                toTop(it)
            }
        }

        assetsVM.delegateIsReady()

        updateTheme()
        insetsUpdated()

        view.post {
            updateEmptyView()
            nftsUpdated(isFirstLoad = true)
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldW: Int, oldH: Int) {
        super.onSizeChanged(w, h, oldW, oldH)
        if (w != oldW) {
            recyclerView.doOnPreDraw { relayoutForWidthIfNeeded() }
        }
    }

    private fun setupActionBar() {
        val actionBar = WActionBar(context)
        view.addView(actionBar, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        val navigationBar = this.navigationBar
        view.setConstraints {
            toCenterX(actionBar)
            if (navigationBar != null) {
                bottomToBottom(actionBar, navigationBar)
            } else {
                toTop(actionBar)
            }
        }
        actionBar.isVisible = false
        this.actionBar = actionBar
        configureSelectionActionBar()
    }

    private fun configureSelectionActionBar() {
        val actionBar = this.actionBar ?: return
        CollectionsMenuHelpers.configureSelectionActionBar(
            actionBar = actionBar,
            shouldShowTransferActions = shouldShowSelectionTransferActions(),
            onCloseTapped = { closeSelectionMode() },
            onHideTapped = { hideSelectedAssets() },
            onSelectAllTapped = { selectAllVisibleAssets() },
            onSendTapped = { sendSelectedNfts() },
            onBurnTapped = { burnSelectedNfts() }
        )
    }

    private fun configureReorderActionBar() {
        val actionBar = this.actionBar ?: return
        CollectionsMenuHelpers.configureReorderActionBar(
            actionBar = actionBar,
            onSaveTapped = { endSorting(save = true) },
            onCancelTapped = { endSorting(save = false) }
        )
    }

    private fun showActionBar() {
        val actionBar = this.actionBar ?: return
        val navigationBar = this.navigationBar ?: return
        if (actionBar.isVisible) {
            return
        }
        navigationBar.fadeOut(AnimationConstants.SUPER_QUICK_ANIMATION) {
            navigationBar.isInvisible = true
            actionBar.isVisible = true
            actionBar.alpha = 0f
            actionBar.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
    }

    private fun hideActionBar() {
        val actionBar = this.actionBar ?: return
        if (!actionBar.isVisible) {
            return
        }
        actionBar.fadeOut(AnimationConstants.SUPER_QUICK_ANIMATION) {
            actionBar.isInvisible = true
            navigationBar?.isVisible = true
            navigationBar?.alpha = 0f
            navigationBar?.fadeIn(AnimationConstants.SUPER_QUICK_ANIMATION)
        }
    }

    private fun notifySelectionChanged(animationMode: TitleAnimationMode? = null) {
        if (actionBar != null) {
            configureSelectionActionBar()
        }
        val currentCount = assetsVM.selectedCount()
        val isInSelectionMode = assetsVM.interactionMode == AssetsVM.InteractionMode.SELECTION
        if (isInSelectionMode && prevSelectedCount > 0 && currentCount == 0) {
            prevSelectedCount = 0
            onAutoClose?.invoke() ?: closeSelectionMode()
            return
        }
        prevSelectedCount = if (isInSelectionMode) currentCount else 0
        if (isInSelectionMode) {
            val title = if (currentCount == 0) {
                LocaleController.getString("\$nft_select")
            } else {
                currentCount.toString()
            }
            if (animationMode != null) {
                actionBar?.setTitle(title, true, animationMode)
            } else {
                actionBar?.setTitle(title, false)
            }
        }
        onSelectionChanged?.invoke(
            currentCount,
            animationMode,
            isInSelectionMode
        )
    }

    val isInSelectionMode: Boolean
        get() = assetsVM.interactionMode == AssetsVM.InteractionMode.SELECTION

    fun selectedCount(): Int {
        return assetsVM.selectedCount()
    }

    fun hasSelectedAssets(): Boolean {
        return assetsVM.hasSelectedAssets()
    }

    fun selectionSnapshot(): SelectionSnapshot? {
        if (assetsVM.interactionMode != AssetsVM.InteractionMode.SELECTION) {
            return null
        }
        return SelectionSnapshot(assetsVM.getSelectedAddresses())
    }

    fun shouldShowSelectionTransferActions(): Boolean {
        if (isReadOnly) return false
        if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) return false
        val nfts = assetsVM.getSelectedNfts()
        if (nfts.isEmpty()) return false
        return nfts.all { it.isOnSale || CollectionsMenuHelpers.isOwnNft(it) }
    }

    private enum class TransferBlocker { DIFFERENT_CHAINS, ON_SALE }

    private fun transferBlocker(): TransferBlocker? {
        val nfts = assetsVM.getSelectedNfts()
        if (nfts.map { it.chain ?: MBlockchain.ton }
                .distinct().size > 1) return TransferBlocker.DIFFERENT_CHAINS
        if (nfts.any { it.isOnSale }) return TransferBlocker.ON_SALE
        return null
    }

    fun openSelectionMode(nftAddressToSelect: String? = null) {
        var animationMode: TitleAnimationMode? = null
        if (assetsVM.interactionMode == AssetsVM.InteractionMode.SELECTION) {
            if (nftAddressToSelect != null && assetsVM.toggleSelection(nftAddressToSelect)) {
                animationMode = TitleAnimationMode.SLIDE_TOP_DOWN
            }
            if (animationMode != null) {
                syncAssetRows()
                notifySelectionChanged(animationMode)
            }
            if (actionBar != null) {
                showActionBar()
            }
            return
        }
        if (actionBar != null) {
            configureSelectionActionBar()
        }
        assetsVM.enterSelectionMode()
        if (nftAddressToSelect != null && assetsVM.toggleSelection(nftAddressToSelect)) {
            animationMode = TitleAnimationMode.SLIDE_TOP_DOWN
        }
        syncAssetRows()
        notifySelectionChanged(animationMode)
        if (actionBar != null) {
            showActionBar()
        }
    }

    fun restoreSelectionSnapshot(selectionSnapshot: SelectionSnapshot) {
        pendingSelectionSnapshot = selectionSnapshot
        applyPendingSelectionSnapshot()
    }

    private fun applyPendingSelectionSnapshot() {
        val selectionSnapshot = pendingSelectionSnapshot ?: return
        if (!assetsVM.hasLoadedNfts) {
            return
        }
        assetsVM.enterSelectionMode()
        assetsVM.setSelectedAddresses(selectionSnapshot.selectedAddresses)
        syncAssetRows(forceReload = true)
        notifySelectionChanged()
        if (actionBar != null) {
            showActionBar()
        }
        pendingSelectionSnapshot = null
    }

    fun closeSelectionMode() {
        if (assetsVM.interactionMode != AssetsVM.InteractionMode.SELECTION) {
            if (actionBar != null) {
                hideActionBar()
            }
            return
        }
        assetsVM.exitSelectionMode()
        syncAssetRows()
        notifySelectionChanged()
        if (actionBar != null) {
            hideActionBar()
        }
    }

    fun hideSelectedAssets() {
        if (!assetsVM.hasSelectedAssets()) {
            return
        }
        NftStore.hideNft(assetsVM.getSelectedNfts())
        closeSelectionMode()
    }

    fun selectAllVisibleAssets() {
        assetsVM.selectAllVisible()
        syncAssetRows()
        notifySelectionChanged(TitleAnimationMode.SLIDE_TOP_DOWN)
    }

    fun sendSelectedNfts(): Boolean = executeOnSelectedNfts { nav, nfts ->
        CollectionsMenuHelpers.pushSendNfts(nav, nfts)
    }

    fun burnSelectedNfts(): Boolean = executeOnSelectedNfts { nav, nfts ->
        CollectionsMenuHelpers.pushBurnNftsConfirm(nav, nfts)
    }

    private fun executeOnSelectedNfts(action: (WNavigationController, List<ApiNft>) -> Unit): Boolean {
        val nfts = assetsVM.getSelectedNfts()
        if (nfts.isEmpty()) return false
        val blocker = transferBlocker()
        if (blocker != null) {
            val key = if (blocker == TransferBlocker.DIFFERENT_CHAINS) {
                "\$nft_batch_different_chains"
            } else {
                "\$nft_batch_on_sale"
            }
            Toast.makeText(context, LocaleController.getString(key), Toast.LENGTH_SHORT).show()
            return false
        }
        val nav = (injectedWindow ?: window)?.navigationControllers?.lastOrNull() ?: return false
        closeSelectionMode()
        action(nav, nfts)
        return true
    }

    private fun openActionBar() {
        openSelectionMode()
    }

    private fun closeActionBar() {
        closeSelectionMode()
    }

    fun configure(accountId: String) {
        if (assetsVM.showingAccountId == accountId)
            return
        emptyDataView.isGone = true
        isShowingEmptyView = false
        isShowingWarningBanner = false
        completeModeBannerInset = 0
        displayedAssetRows = emptyList()
        if (viewMode == ViewMode.THUMB) {
            updateThumbWarningBannerLayout()
            bannerAnimationUpdate(0f)
        }
        rvAdapter.reloadData()
        assetsVM.configure(accountId)
        currentHeight = finalHeight
    }

    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        super.updateTheme()

        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        if (!darkModeChanged)
            return
        _isDarkThemeApplied = ThemeManager.isDark

        if (viewMode == ViewMode.THUMB) {
            view.background = null
            recyclerView.setBackgroundColor(WColor.Background.color)
            thumbWarningBannerView.updateTheme()
            showAllView.updateTheme()
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
            recyclerView.setBackgroundColor(WColor.Background.color)
        }
        rvAdapter.reloadData()
        if (isShowingSingleCollection && !isReadOnly) {
            val moreDrawable =
                context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_more)?.apply {
                    setTint(WColor.SecondaryText.color)
                }
            moreButton.setImageDrawable(moreDrawable)
            moreButton.background = null
            moreButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)

            updatePinButton()
        }
        updateEmptyView()
    }

    override fun onViewAttachedToWindow() {
        super.onViewAttachedToWindow()
        actionBar?.bringToFront()
    }

    private fun updatePinButton() {
        val pinDrawable = context.getDrawableCompat(
            if (isInHomeTabs)
                org.mytonwallet.app_air.uiassets.R.drawable.ic_collection_unpin
            else
                org.mytonwallet.app_air.uiassets.R.drawable.ic_collection_pin
        )
        pinButton.setImageDrawable(pinDrawable)
        pinButton.background = null
        pinButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)
    }

    private fun updateShowAllPosition() {
        if (viewMode == ViewMode.THUMB) {
            if (recyclerView.width == 0) {
                view.post { updateShowAllPosition() }
                return
            }
            if (window?.isWideLayout == true) {
                if (prevShowAllViewToTop != -2) {
                    prevShowAllViewToTop = -2
                    view.setConstraints {
                        clear(showAllView.id, ConstraintSet.TOP)
                        toBottom(showAllView)
                    }
                }
                animateHeight()
                return
            }
            val newShowAllViewToTop = finalHeight - 56.dp
            if (prevShowAllViewToTop != newShowAllViewToTop) {
                prevShowAllViewToTop = newShowAllViewToTop
                view.setConstraints {
                    clear(showAllView.id, ConstraintSet.BOTTOM)
                    toTopPx(showAllView, newShowAllViewToTop)
                }
            }

            animateHeight()
        }
    }

    private fun updateShowAllTranslationY() {
        if (viewMode == ViewMode.THUMB) {
            val offset =
                if (shouldShowWarningBanner) {
                    -thumbBannerContainerHeight * (1f - warningBannerAnimator.floatValue)
                } else {
                    thumbBannerContainerHeight * warningBannerAnimator.floatValue
                }
            showAllView.translationY = offset
        }
    }

    private fun getEmptyThumbHeight(): Int {
        val targetWidth = view.width
        if (targetWidth > 0 && emptyDataView.width != targetWidth) {
            emptyDataView.measure(targetWidth.exactly, 0.unspecified)
            emptyDataViewHeight = emptyDataView.measuredHeight
        }
        return emptyDataViewHeight
    }

    fun openRenewForExpiringDomains() {
        val nft = assetsVM.firstExpiringDomain() ?: return
        val activeWindow = injectedWindow ?: window ?: return
        val navVC = WNavigationController(
            activeWindow, PresentationConfig(
                style = WNavigationController.PresentationStyle.BottomSheet
            )
        )
        navVC.setRoot(RenewVC(context, nft))
        activeWindow.present(navVC)
    }

    fun dismissExpiringDomainsBanner() {
        NftStore.addIgnoredExpiringAddresses(
            assetsVM.showingAccountId,
            assetsVM.ignoredExpiringDomainAddresses()
        )
    }

    private fun getMarketplaceForEmptyAssets(): MMarketplace {
        val account =
            AccountStore.accountById(assetsVM.showingAccountId) ?: return MMarketplace.Fragment
        return ExplorerHelpers.defaultNftMarketplace(account)
    }

    private fun exploreMenuItemConfig(marketplace: MMarketplace): WMenuPopup.Item.Config.Item {
        return exploreMenuItemConfig(marketplace.menuIconRes, marketplace.title)
    }

    private fun exploreMenuItemConfig(explorer: MBlockchainExplorer): WMenuPopup.Item.Config.Item {
        return exploreMenuItemConfig(explorer.menuIconRes, explorer.title)
    }

    private fun exploreMenuItemConfig(iconResId: Int?, title: String): WMenuPopup.Item.Config.Item {
        return WMenuPopup.Item.Config.Item(
            icon = Icon(
                iconResId = iconResId,
                tintColor = null,
                iconSize = 28.dp
            ),
            title = title
        )
    }

    private fun openNftMarketplace(marketplace: MMarketplace) {
        val network = AccountStore.accountById(assetsVM.showingAccountId)?.network
            ?: AccountStore.activeAccount?.network
            ?: MBlockchainNetwork.MAINNET
        openNftMarketplace(
            url = marketplace.homeUrl(network),
            title = marketplace.title
        )
    }

    private fun openNftMarketplace(url: String, title: String) {
        WalletCore.notifyEvent(
            WalletEvent.OpenUrlWithConfig(
                InAppBrowserConfig(
                    url = url,
                    title = title,
                    injectDappConnect = true
                )
            )
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        if (viewMode == ViewMode.COMPLETE) {
            updateCompleteModeBannerLayout()
        }
        if (isShowingSingleCollection) {
            view.setConstraints {
                toStartPx(
                    recyclerView,
                    ViewConstants.HORIZONTAL_PADDINGS.dp + additionalTabletPadding + systemBarStartInset
                )
                toEndPx(
                    recyclerView,
                    ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset
                )
            }
        }
        underSegmentedControlReversedCornerView?.let {
            if (it.layoutParams != null)
                it.updateLayoutParams {
                    height = WNavigationBar.DEFAULT_HEIGHT.dp +
                        (navigationController?.getSystemBars()?.top ?: 0) +
                        underSegmentedControlReversedCornerView!!.cornerRadius.roundToInt()
                }
        }
        updateShowAllPosition()
    }

    fun setAnimations(paused: Boolean) {
        if (!assetsVM.setAnimationsPaused(paused))
            return
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
        layoutManager?.let {
            val firstVisible = it.findFirstVisibleItemPosition()
            val lastVisible = it.findLastVisibleItemPosition()

            for (i in firstVisible..lastVisible) {
                val holder = recyclerView.findViewHolderForAdapterPosition(i)
                (holder?.itemView as? AssetCell)?.apply {
                    if (paused)
                        pauseAnimation()
                    else
                        resumeAnimation()
                }
            }
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun onNftTap(nft: ApiNft) {
        if (assetsVM.interactionMode == AssetsVM.InteractionMode.DRAG) {
            return
        }
        if (assetsVM.interactionMode == AssetsVM.InteractionMode.SELECTION) {
            val animationDirection = if (assetsVM.toggleSelection(nft.address)) {
                TitleAnimationMode.SLIDE_TOP_DOWN
            } else {
                TitleAnimationMode.SLIDE_BOTTOM_UP
            }
            syncAssetRows()
            notifySelectionChanged(animationDirection)
            return
        }
        val assetVC = NftVC(
            context,
            assetsVM.showingAccountId,
            nft,
            assetsVM.getAllNfts()!!
        )
        val window = injectedWindow ?: window!!
        val tabNav = navigationController?.tabBarController?.mainNavigationController
        if (tabNav != null)
            tabNav.push(assetVC)
        else
            window.navigationControllers.last().push(assetVC)
    }

    private fun onNftLongPress(anchorView: View, nft: ApiNft) {
        if (assetsVM.interactionMode != AssetsVM.InteractionMode.NORMAL) {
            return
        }
        val navigationController = navigationController ?: return
        activeNftMenuPopup = CollectionsMenuHelpers.presentNftMenuOn(
            showingAccountId = assetsVM.showingAccountId,
            nft = nft,
            view = anchorView,
            navigationController = navigationController,
            shouldShowCollectionItem = collectionMode == null,
            roundRadius = if (viewMode == ViewMode.THUMB) {
                AssetCell.CORNER_RADIUS_THUMB
            } else {
                AssetCell.CORNER_RADIUS_COMPLETE
            }.dp,
            onReorderTapped = { requestReordering() },
            onSelectTapped = {
                onSelectionRequested?.invoke(nft.address) ?: openSelectionMode(nft.address)
            }
        )
        if (activeNftMenuPopup != null) {
            recyclerView.parent?.requestDisallowInterceptTouchEvent(true)
        }
    }

    private fun startDragFromMenu(x: Float, y: Float) {
        requestReordering()
        recyclerView.post {
            val child = recyclerView.findChildViewUnder(x, y) ?: return@post
            itemTouchHelper.startDrag(recyclerView.getChildViewHolder(child))
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    private val itemsCountToShow: Int
        get() = if (viewMode == ViewMode.THUMB && window?.isWideLayout != true) {
            val rows = if (assetsVM.nftsCount > 3) 2 else 1
            min(assetsVM.assetRows.size, rows * THUMB_GRID_MAX_COLUMNS)
        } else {
            assetsVM.assetRows.size
        }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            NFTS_SECTION -> displayedAssetRows.size
            else -> throw IllegalStateException()
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when (indexPath.section) {
            NFTS_SECTION -> ASSET_CELL
            else -> throw IllegalStateException()
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return AssetCell(context, viewMode, showsTitle = showsCellTitle).apply {
            onTap = { nft ->
                onNftTap(nft)
            }
            onLongPress = { anchorView, nft ->
                onNftLongPress(anchorView, nft)
            }
        }
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return when (indexPath.section) {
            NFTS_SECTION -> displayedAssetRows[indexPath.row].nft.address
            else -> throw IllegalStateException()
        }
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        when (indexPath.section) {
            NFTS_SECTION -> {
                val cell = cellHolder.cell as AssetCell
                val row = displayedAssetRows[indexPath.row]
                cell.configure(
                    nft = row.nft,
                    interactionMode = row.interactionMode,
                    animationsPaused = row.animationsPaused,
                    isSelected = row.isSelected,
                    isReadOnly = isReadOnly,
                    daysUntilExpiration = row.daysUntilExpiration,
                    showsTitle = showsCellTitle
                )
            }

            else -> throw IllegalStateException()
        }
    }

    var isShowingEmptyView = false
    override fun updateEmptyView() {
        val isEmpty = assetsVM.isEmpty
        if (isEmpty != isEmptyStateVisible) {
            isEmptyStateVisible = isEmpty
            if (viewMode == ViewMode.THUMB) {
                onHeightChanged?.invoke()
            }
        }
        if (viewMode == ViewMode.THUMB) {
            recyclerView.isGone = isEmpty
            if (isEmpty) {
                showAllView.isGone = true
            }
        }
        if (!assetsVM.hasLoadedNfts) {
            setEmptyDataViewVisible(visible = false, animate = false)
            return
        }
        if (isEmpty) {
            ensureEmptyDataViewAdded()
        }
        setEmptyDataViewVisible(isEmpty, animate = true)
    }

    private fun ensureEmptyDataViewAdded() {
        if (emptyDataView.parent != null) {
            return
        }
        view.addView(emptyDataView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.constraintSet().apply {
            toCenterX(emptyDataView)
            if (viewMode == ViewMode.COMPLETE) {
                toCenterY(emptyDataView)
            } else {
                toTop(emptyDataView)
            }
        }.layout()
    }

    private fun setEmptyDataViewVisible(visible: Boolean, animate: Boolean) {
        if (visible == isShowingEmptyView) {
            return
        }
        if (visible) {
            emptyDataView.isGone = false
            emptyDataView.updateTheme()
            if (animate) {
                emptyDataView.alpha = 0f
                emptyDataView.fadeIn()
            } else {
                emptyDataView.alpha = 1f
            }
        } else {
            if (animate) {
                emptyDataView.fadeOut(onCompletion = {
                    emptyDataView.isGone = true
                })
            } else {
                emptyDataView.isGone = true
            }
        }
        isShowingEmptyView = visible
    }

    override fun checkExpiringDomainsWarning(animated: Boolean): Boolean {
        syncAssetRows()

        val shouldShowBanner = shouldShowWarningBanner
        updateExpiringDomainsBadge()

        return when (viewMode) {
            ViewMode.THUMB -> {
                configureWarningBannerView(thumbWarningBannerView)
                updateThumbExpiringDomainsWarning(
                    shouldShowBanner = shouldShowBanner,
                    animated = animated
                )
            }

            ViewMode.COMPLETE -> {
                onExpiringDomainsDataChanged?.invoke(assetsVM.expiringDomainsData)
                updateCompleteExpiringDomainsWarning(
                    shouldShowBanner = shouldShowBanner,
                    animated = animated
                )
            }
        }
    }

    private var prevShowAllViewToTop = 0
    override fun nftsUpdated(isFirstLoad: Boolean) {
        showAllView.setCounter(assetsVM.nftsCount)
        if (assetsVM.hasLoadedNfts) {
            setNavSubtitle(
                LocaleController.getStringWithKeyValues(
                    "%amount% NFTs",
                    listOf(
                        Pair("%amount%", assetsVM.nftsCount.toString())
                    )
                )
            )
        }
        layoutManager.spanCount = calculateNoOfColumns()
        syncAssetRows()
        if (assetsVM.interactionMode == AssetsVM.InteractionMode.SELECTION && prevSelectedCount > 0 && assetsVM.selectedCount() == 0) {
            onAutoClose?.invoke() ?: closeSelectionMode()
        }
        if (viewMode == ViewMode.THUMB) {
            updateRecyclerViewPaddingForCentering()
        }
        showAllView.isGone = !thereAreMoreToShow
        val expiringDomainsWarningStateChanged =
            checkExpiringDomainsWarning(animated = !isFirstLoad)
        if (!expiringDomainsWarningStateChanged) {
            updateShowAllPosition()
        } // else: already handled inside checkExpiringDomainsWarning
        applyPendingSelectionSnapshot()
    }

    override fun nftsShown() {
        onNftsShown?.invoke()
    }

    private fun animateHeight() {
        if (currentHeight == finalHeight)
            return
        if (currentHeight != null && shouldAnimateHeight?.invoke() != false) {
            ValueAnimator.ofInt(currentHeight!!, finalHeight).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = CubicBezierInterpolator.EASE_BOTH

                addUpdateListener { animator ->
                    currentHeight = animator.animatedValue as Int
                    onHeightChanged?.invoke()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                    }
                })

                start()
            }
        } else {
            currentHeight = finalHeight
            onHeightChanged?.invoke()
        }
    }

    private fun calculateNoOfColumns(): Int {
        return if (viewMode == ViewMode.THUMB) {
            assetsVM.nftsCount.coerceIn(1, 3)
        } else {
            max(2, (view.width - 16.dp) / 182.dp)
        }
    }

    private var lastLayoutWidth = 0
    private fun relayoutForWidthIfNeeded() {
        val width = recyclerView.width.takeIf { it > 0 } ?: view.width
        if (width == 0 || width == lastLayoutWidth) return
        lastLayoutWidth = width
        val newSpan = calculateNoOfColumns()
        if (layoutManager.spanCount != newSpan) {
            layoutManager.spanCount = newSpan
            recyclerView.requestLayout()
        }
        if (viewMode == ViewMode.THUMB) {
            updateRecyclerViewPaddingForCentering()
        }
        updateShowAllPosition()
        animateHeight()
    }

    private var lastDisplayedNftCount = -1
    fun onLayoutModeChanged() {
        lastLayoutWidth = 0
        val apply = {
            layoutManager.spanCount = calculateNoOfColumns()
            if (viewMode == ViewMode.THUMB) {
                updateRecyclerViewPaddingForCentering()
            }
            val newDisplayedNftCount = itemsCountToShow
            if (newDisplayedNftCount != lastDisplayedNftCount) {
                displayedAssetRows = assetsVM.assetRows.take(newDisplayedNftCount)
                lastDisplayedNftCount = newDisplayedNftCount
                rvAdapter.reloadData()
            } else {
                rvAdapter.updateVisibleCells()
            }
            updateShowAllPosition()
            if (view.width > 0) {
                currentHeight = finalHeight
                onHeightChanged?.invoke()
            }
        }
        if (view.width > 0) apply() else view.post { apply() }
    }

    private fun updateRecyclerViewPaddingForCentering() {
        if (viewMode == ViewMode.THUMB) {
            updateThumbWarningBannerLayout()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        assetsVM.onDestroy()
        recyclerView.onDestroy()
        itemTouchHelper.attachToRecyclerView(null)
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }

    override fun onFullyVisible() {
        setAnimations(paused = false)
        setReversedCornerViewRadius(null)
    }

    override fun onPartiallyVisible() {
        setAnimations(paused = true)
        setReversedCornerViewRadius(0f)
    }

    private fun setReversedCornerViewRadius(radius: Float?) {
        underSegmentedControlReversedCornerView?.setRadius(radius)
        if (underSegmentedControlReversedCornerView?.layoutParams != null)
            underSegmentedControlReversedCornerView?.updateLayoutParams {
                height = WNavigationBar.DEFAULT_HEIGHT.dp +
                    (navigationController?.getSystemBars()?.top ?: 0) +
                    underSegmentedControlReversedCornerView!!.cornerRadius.roundToInt()
            }
    }

    private fun requestReordering() {
        if (isShowingEmptyView) {
            return
        }
        onReorderingRequested?.invoke() ?: startSorting()
    }

    override fun startSorting() {
        assetsVM.startSorting()
        syncAssetRows(forceReload = true)
        configureReorderActionBar()
        showActionBar()
    }

    override fun endSorting() {
        assetsVM.endSorting()
        syncAssetRows(forceReload = true)
        hideActionBar()
    }

    private fun endSorting(save: Boolean) {
        if (save) {
            saveList()
        } else {
            reloadList()
        }
        endSorting()
    }

    fun saveList() {
        assetsVM.saveList()
    }

    fun reloadList() {
        assetsVM.loadCachedNftsAsync(keepOrder = false, onFinished = {
            syncAssetRows(forceReload = true)
        })
    }
}

val AssetsVC.CollectionMode?.title: String
    get() {
        return when (this) {
            is TelegramGifts -> {
                LocaleController.getString("Telegram Gifts")
            }

            is SingleCollection -> {
                collection.name
            }

            is AssetsVC.CollectionMode.ReadOnly -> {
                name ?: LocaleController.getString("Collectibles")
            }

            else -> {
                LocaleController.getString("Collectibles")
            }
        }
    }
