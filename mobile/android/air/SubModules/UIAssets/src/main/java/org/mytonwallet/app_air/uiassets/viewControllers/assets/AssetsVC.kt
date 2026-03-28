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
import androidx.core.content.ContextCompat
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
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.SingleCollection
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.TelegramGifts
import org.mytonwallet.app_air.uiassets.viewControllers.assets.cells.AssetCell
import org.mytonwallet.app_air.uiassets.viewControllers.assets.cells.DomainExpirationBannerCell
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uiassets.viewControllers.renew.RenewVC
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
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
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
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.NftStore
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.time.Duration.Companion.days

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

                null -> AssetsTabVC.TAB_COLLECTIBLES
            }
        }

    enum class ViewMode {
        THUMB,
        COMPLETE
    }

    sealed class CollectionMode {
        data object TelegramGifts : CollectionMode()
        data class SingleCollection(val collection: MCollectionTabToShow) : CollectionMode()

        val collectionAddress: String
            get() {
                return when (this) {
                    is SingleCollection -> {
                        collection.address
                    }

                    TelegramGifts -> {
                        NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                    }
                }
            }

        fun matches(comparing: CollectionMode): Boolean {
            return when (this) {
                is SingleCollection -> {
                    comparing is SingleCollection && comparing.collection.address == collection.address
                }

                TelegramGifts -> {
                    comparing is TelegramGifts
                }
            }
        }
    }

    companion object {
        const val EXPIRE_WARNING_SECTION = 0
        const val NFTS_SECTION = 1
        val ASSET_CELL = WCell.Type(1)
        val EXPIRATION_BANNER_CELL = WCell.Type(2)
    }

    override val shouldDisplayBottomBar = isShowingSingleCollection

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
    private val bannerHeight: Int get() = DomainExpirationBannerCell.CELL_HEIGHT_DP.dp

    private val finalHeight: Int
        get() {
            return if (!assetsVM.hasLoadedNfts || assetsVM.isEmpty) {
                getEmptyThumbHeight().takeIf { it > 0 } ?: 192.dp
            } else {
                val rows = if (assetsVM.nftsCount > 3) 2 else 1
                val nftGridHeight = rows * (recyclerView.width - 32.dp) / 3 +
                    4.dp +
                    (if (thereAreMoreToShow) 64 else 8).dp
                nftGridHeight + (if (shouldShowWarningBanner == true) bannerHeight else 0)
            }
        }

    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(ASSET_CELL, EXPIRATION_BANNER_CELL)
        ).apply {
            setHasStableIds(true)
        }
    private var displayedAssetRows: List<AssetRow> = emptyList()

    private val emptyDataView: WEmptyIconTitleSubtitleActionView by lazy {
        WEmptyIconTitleSubtitleActionView(context).apply {
            configure(
                titleText = LocaleController.getString("No collectibles yet"),
                subtitleText = LocaleController.getString(
                    "Explore a marketplace to discover existing NFT collections."
                ),
                actionText = LocaleController.getString("Open Getgems"),
                animation = R.raw.animation_happy
            ) {
                openGetgems()
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
    private val topCellsCount: Int
        get() = if (shouldShowWarningBanner == true || warningBannerAnimator.floatValue > 0f) 1 else 0

    // Expiring domains warning
    private var cachedExpiringDomains: List<ApiNft>? = null
    private val shouldShowWarningBanner: Boolean?
        get() = cachedExpiringDomains?.isNotEmpty()
    private var isShowingWarningBanner = false
    private var warningBannerCell: WCell? = null
    private val warningBannerAnimator = BoolAnimator(
        duration = AnimationConstants.VERY_QUICK_ANIMATION,
        interpolator = CubicBezierInterpolator.EASE_BOTH,
        onAnimationsFinished = { finalState, _ ->
            if (isShowingWarningBanner && finalState == BoolAnimator.State.FALSE) {
                isShowingWarningBanner = false
                nftViewTranslationY = 0f
                rvAdapter.reloadData()
            }
        }
    ) { _, floatValue, _, _ ->
        bannerAnimationUpdate(floatValue)
    }
    private var bannerViewAlpha = 0f
    private var nftViewTranslationY = 0f

    private fun bannerAnimationUpdate(floatValue: Float) {
        bannerViewAlpha = (floatValue - 0.5f).coerceAtLeast(0f) * 2
        nftViewTranslationY = if (isShowingWarningBanner) -bannerHeight * (1 - floatValue) else 0f
        warningBannerCell?.also { banner ->
            banner.alpha = bannerViewAlpha
        }
        updateItemsTranslationY()
        updateShowAllTranslationY()
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

                if (fromPosition < topCellsCount || toPosition < topCellsCount) return false
                val offset = if (isShowingWarningBanner) 1 else 0

                val adjustedFrom = fromPosition - offset
                val adjustedTo = toPosition - offset

                if (viewMode == ViewMode.THUMB) {
                    val maxPosition = min(6, assetsVM.nftsCount) - 1
                    if (adjustedTo > maxPosition) return false
                }

                assetsVM.moveItem(adjustedFrom, adjustedTo, shouldSave = saveOnDrag)
                displayedAssetRows = assetsVM.assetRows
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
                if (viewHolder.adapterPosition < topCellsCount) return 0
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
                        val isBanner = (viewHolder?.adapterPosition ?: 0) < topCellsCount
                        if (viewHolder != null && !isBanner) {
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

    private val layoutManager = GridLayoutManager(context, calculateNoOfColumns())
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
                rv.setPadding(12.dp, 4.dp, 12.dp, 4.dp)
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
        rv.addOnItemTouchListener(recyclerViewTouchListener)

        if (allowReordering) {
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
            val navVC = WNavigationController(window)
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

                null -> throw Exception()
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
                                    WMenuPopup.Item.Config.Item(
                                        icon = Icon(
                                            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_getgems,
                                            tintColor = null,
                                            iconSize = 28.dp
                                        ),
                                        title = "Getgems",
                                    ),
                                    false,
                                ) {
                                    val baseUrl = ExplorerHelpers.getgemsUrl(network)
                                    val url = "${baseUrl}collection/$collectionAddress"
                                    CollectionsMenuHelpers.openLink(url)
                                }
                            )
                            items.add(
                                WMenuPopup.Item(
                                    WMenuPopup.Item.Config.Item(
                                        icon = Icon(
                                            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_tonscan,
                                            tintColor = null,
                                            iconSize = 28.dp
                                        ),
                                        title = "Tonscan",
                                    ),
                                    false,
                                ) {
                                    CollectionsMenuHelpers.openLink("https://tonscan.org/nft/$collectionAddress")
                                }
                            )
                        }
                    }

                    TelegramGifts -> {
                        items.add(
                            WMenuPopup.Item(
                                WMenuPopup.Item.Config.Item(
                                    icon = Icon(
                                        icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_fragment,
                                        tintColor = null,
                                        iconSize = 28.dp
                                    ),
                                    title = "Fragment",
                                ),
                                false,
                            ) {
                                CollectionsMenuHelpers.openLink("https://fragment.com/gifts")
                            }
                        )

                        items.add(
                            WMenuPopup.Item(
                                WMenuPopup.Item.Config.Item(
                                    icon = Icon(
                                        icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_getgems,
                                        tintColor = null,
                                        iconSize = 28.dp
                                    ),
                                    title = "Getgems",
                                ),
                                false,
                            ) {
                                CollectionsMenuHelpers.openLink("https://getgems.io/top-gifts")
                            }
                        )
                    }

                    null -> return@setOnClickListener
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
                    backdropStyle = WMenuPopup.BackdropStyle.Transparent
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
    var onSelectionChanged: ((selectedCount: Int, animationMode: TitleAnimationMode?, isInSelectionMode: Boolean) -> Unit)? =
        null

    private fun syncAssetRows(forceReload: Boolean = false) {
        val prevRows = displayedAssetRows
        val newRows = assetsVM.assetRows
        displayedAssetRows = newRows
        if (forceReload) {
            rvAdapter.reloadData()
            return
        }
        rvAdapter.applyChanges(prevRows, newRows, NFTS_SECTION, false)
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(title!!)
        if (isShowingSingleCollection) {
            setupNavBar(true)
            setupActionBar()
            navigationBar?.addTrailingView(navTrailingView, LayoutParams(WRAP_CONTENT, 40.dp))
        }
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (viewMode == ViewMode.THUMB) {
            view.addView(showAllView, LayoutParams(MATCH_PARENT, 56.dp))
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
                toCenterX(showAllView)
            }
            if (isShowingSingleCollection)
                toCenterX(
                    recyclerView,
                    ViewConstants.HORIZONTAL_PADDINGS.toFloat()
                )
            underSegmentedControlReversedCornerView?.let {
                toTop(it)
            }
        }

        layoutManager.spanSizeLookup = object : GridLayoutManager.SpanSizeLookup() {
            override fun getSpanSize(position: Int): Int {
                return if (position < topCellsCount) layoutManager.spanCount else 1
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
        displayedAssetRows = emptyList()
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
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
            recyclerView.setBackgroundColor(WColor.Background.color)
        }
        rvAdapter.reloadData()
        if (isShowingSingleCollection) {
            val moreDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.icons.R.drawable.ic_more
                )?.apply {
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
        val pinDrawable = ContextCompat.getDrawable(
            context,
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
            val newShowAllViewToTop = finalHeight - 56.dp
            if (prevShowAllViewToTop != newShowAllViewToTop) {
                prevShowAllViewToTop = newShowAllViewToTop
                view.setConstraints {
                    toTopPx(showAllView, newShowAllViewToTop)
                }
            }

            animateHeight()
        }
    }

    private fun updateItemsTranslationY() {
        for (i in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(i) ?: continue
            if (recyclerView.getChildAdapterPosition(child) != 0) {
                child.translationY = nftViewTranslationY
            }
        }
    }

    private fun updateShowAllTranslationY() {
        if (viewMode == ViewMode.THUMB) {
            val offset =
                if (shouldShowWarningBanner == true) -bannerHeight * (1f - warningBannerAnimator.floatValue) else bannerHeight * warningBannerAnimator.floatValue
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

    private fun refreshExpiringDomains() {
        val expirationByAddress = NftStore.nftData?.expirationByAddress
        if (assetsVM.isViewOnlyAccount || expirationByAddress == null) {
            cachedExpiringDomains = emptyList()
            return
        }
        val thresholdMs = System.currentTimeMillis() +
            DomainExpirationBannerCell.DAYS_THRESHOLD * 24L * 60 * 60 * 1000
        cachedExpiringDomains = (assetsVM.nfts ?: emptyList()).filter { nft ->
            val expMs = expirationByAddress[nft.address] ?: return@filter false
            expMs <= thresholdMs && nft.address !in NftStore.getIgnoredExpiringAddresses(assetsVM.showingAccountId)
        }
    }

    private fun minDaysUntilExpiration(): Int {
        val ignoredAddresses = NftStore.getIgnoredExpiringAddresses(assetsVM.showingAccountId)
        return assetsVM.assetRows
            .filter { row -> row.nft.address !in ignoredAddresses }
            .mapNotNull { it.daysUntilExpiration }
            .minOrNull() ?: 0
    }

    private fun openRenewForExpiringDomains() {
        val nft = cachedExpiringDomains?.firstOrNull() ?: return
        val activeWindow = injectedWindow ?: window ?: return
        val navVC = WNavigationController(
            activeWindow, PresentationConfig(
                overFullScreen = false,
                isBottomSheet = true
            )
        )
        navVC.setRoot(RenewVC(context, nft))
        activeWindow.present(navVC)
    }

    private fun openGetgems() {
        val activeWindow = injectedWindow ?: window ?: return
        val activeNetwork = AccountStore.activeAccount?.network ?: return
        val navVC = WNavigationController(activeWindow)
        val browserVC = InAppBrowserVC(
            context,
            null,
            InAppBrowserConfig(
                url = ExplorerHelpers.getgemsUrl(activeNetwork),
                title = "Getgems",
                injectDappConnect = true
            )
        )
        navVC.setRoot(browserVC)
        activeWindow.present(navVC)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        if (viewMode == ViewMode.COMPLETE) {
            recyclerView.setPadding(
                0,
                (navigationController?.getSystemBars()?.top ?: 0) +
                    WNavigationBar.DEFAULT_HEIGHT.dp,
                0,
                navigationController?.getSystemBars()?.bottom ?: 0
            )
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
        val tabNav = window.navigationControllers.last().tabBarController?.navigationController
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
        return 2
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (section) {
            EXPIRE_WARNING_SECTION -> if (isShowingWarningBanner) 1 else 0
            NFTS_SECTION -> displayedAssetRows.size
            else -> throw IllegalStateException()
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return when (indexPath.section) {
            EXPIRE_WARNING_SECTION -> EXPIRATION_BANNER_CELL
            NFTS_SECTION -> ASSET_CELL
            else -> throw IllegalStateException()
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        if (cellType == EXPIRATION_BANNER_CELL) {
            if (warningBannerCell == null)
                warningBannerCell = DomainExpirationBannerCell(context)
            return warningBannerCell!!
        }
        return AssetCell(context, viewMode).apply {
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
            EXPIRE_WARNING_SECTION -> null
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
            EXPIRE_WARNING_SECTION -> {
                val cell = cellHolder.cell as DomainExpirationBannerCell
                cell.configure(
                    iconNfts = cachedExpiringDomains?.take(3) ?: emptyList(),
                    count = cachedExpiringDomains?.size ?: 0,
                    minDays = minDaysUntilExpiration()
                )
                cell.onTap = { openRenewForExpiringDomains() }
                cell.onClose = {
                    onReorderingRequested?.invoke()
                    NftStore.addIgnoredExpiringAddresses(
                        assetsVM.showingAccountId,
                        cachedExpiringDomains?.map { it.address } ?: emptyList())
                }
                cell.alpha = bannerViewAlpha
            }

            NFTS_SECTION -> {
                val cell = cellHolder.cell as AssetCell
                val row = displayedAssetRows[indexPath.row]
                cell.configure(
                    nft = row.nft,
                    interactionMode = row.interactionMode,
                    animationsPaused = row.animationsPaused,
                    isSelected = row.isSelected,
                    daysUntilExpiration = row.daysUntilExpiration
                )
                cell.translationY = nftViewTranslationY
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
        if (viewMode == ViewMode.COMPLETE)
            return false

        val wasBannerShown = shouldShowWarningBanner
        refreshExpiringDomains()
        val badgeCount = cachedExpiringDomains?.size?.takeIf { it > 0 }
        segmentedController?.setBadge(identifier, badgeCount?.toString())

        val holder = recyclerView.findViewHolderForAdapterPosition(0)
        (holder?.itemView as? DomainExpirationBannerCell)?.configure(
            iconNfts = cachedExpiringDomains?.take(3) ?: emptyList(),
            count = cachedExpiringDomains?.size ?: 0,
            minDays = minDaysUntilExpiration()
        )

        val bannerStateChanged = wasBannerShown != shouldShowWarningBanner
        if (!bannerStateChanged)
            return false

        if (!isShowingWarningBanner) {
            isShowingWarningBanner = true
            rvAdapter.reloadData()
            if (animated)
                recyclerView.doOnPreDraw {
                    bannerAnimationUpdate(warningBannerAnimator.floatValue)
                }
        }
        warningBannerAnimator.changeValue(shouldShowWarningBanner ?: false, animated = animated)
        updateShowAllPosition()
        if (animated)
            updateShowAllTranslationY()
        return true
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

    private fun updateRecyclerViewPaddingForCentering() {
        val itemCount = assetsVM.nftsCount

        if (itemCount in 1..2) {
            val itemWidth = (recyclerView.width - 32.dp) / 3
            val totalItemsWidth = itemCount * itemWidth
            val availableWidth = recyclerView.width - 24.dp
            val horizontalPadding = if (totalItemsWidth < availableWidth) {
                (availableWidth - totalItemsWidth) / 2 + 12.dp
            } else {
                12.dp
            }

            recyclerView.setPadding(horizontalPadding, 4.dp, horizontalPadding, 4.dp)
        } else if (viewMode == ViewMode.THUMB) {
            recyclerView.setPadding(12.dp, 4.dp, 12.dp, 4.dp)
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

            else -> {
                LocaleController.getString("Collectibles")
            }
        }
    }
