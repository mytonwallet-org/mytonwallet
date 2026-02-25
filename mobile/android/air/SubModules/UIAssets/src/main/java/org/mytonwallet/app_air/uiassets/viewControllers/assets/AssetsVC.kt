package org.mytonwallet.app_air.uiassets.viewControllers.assets

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.SingleCollection
import org.mytonwallet.app_air.uiassets.viewControllers.assets.AssetsVC.CollectionMode.TelegramGifts
import org.mytonwallet.app_air.uiassets.viewControllers.assets.cells.AssetCell
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.ISortableView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
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
import org.mytonwallet.app_air.uicomponents.helpers.SpacesItemDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.recyclerView.CustomItemTouchHelper
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
import org.mytonwallet.app_air.walletcore.models.MCollectionTabToShow
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AssetsVC(
    context: Context,
    defaultAccountId: String,
    private val mode: Mode,
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

    enum class Mode {
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
        val ASSET_CELL = WCell.Type(1)
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
        if (mode == Mode.COMPLETE && !isShowingSingleCollection) ReversedCornerView(
            context,
            ReversedCornerView.Config(
                shouldBlur = false,
            )
        ).apply {
            setHorizontalPadding(0f)
        } else null
    }

    private val assetsVM by lazy {
        AssetsVM(collectionMode, defaultAccountId, this)
    }

    private val thereAreMoreToShow: Boolean
        get() {
            return (assetsVM.nfts?.size ?: 0) > 6
        }

    var currentHeight: Int? = null
    private var emptyDataViewHeight = 0
    private val finalHeight: Int
        get() {
            return if (assetsVM.nfts.isNullOrEmpty()) {
                getEmptyThumbHeight().takeIf { it > 0 } ?: 192.dp
            } else {
                val rows = if ((assetsVM.nfts?.size ?: 0) > 3) 2 else 1
                rows * (recyclerView.width - 32.dp) / 3 +
                    4.dp +
                    (if (thereAreMoreToShow) 64 else 8).dp
            }
        }

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(ASSET_CELL))

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
            return mode == Mode.COMPLETE
        }

    private var animationsPaused: Boolean? = null

    private val itemTouchHelper by lazy {
        val callback = object : CustomItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN or ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT,
            0
        ) {

            override fun isLongPressDragEnabled(): Boolean {
                return allowReordering
            }

            override fun isItemViewSwipeEnabled(): Boolean {
                return false
            }

            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                val fromPosition = viewHolder.adapterPosition
                val toPosition = target.adapterPosition

                if (mode == Mode.THUMB) {
                    val maxPosition = min(6, assetsVM.nfts?.size ?: 0) - 1
                    if (toPosition > maxPosition) return false
                }

                assetsVM.moveItem(fromPosition, toPosition, shouldSave = saveOnDrag)
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
                return if (allowReordering) {
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

    private val recyclerViewTouchListener = object : RecyclerView.OnItemTouchListener {
        private var startedDrag = false
        private var touchDownX = 0f
        private var touchDownY = 0f
        private val mSwipeSlop = ViewConfiguration.get(context).scaledTouchSlop

        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    val child = rv.findChildViewUnder(e.x, e.y)

                    if (assetsVM.isInDragMode) {
                        val touchDownViewHolder = child?.let { rv.getChildViewHolder(child) }
                        if (touchDownViewHolder != null) {
                            itemTouchHelper.startDrag(touchDownViewHolder)
                            startedDrag = true
                        }
                        return false
                    }

                    startedDrag = false
                    touchDownX = e.x
                    touchDownY = e.y
                }

                MotionEvent.ACTION_MOVE -> {
                    if (startedDrag) {
                        return false
                    }

                    val dx = abs(e.x - touchDownX)
                    val dy = abs(e.y - touchDownY)
                    if (!startedDrag) {
                        if (dx > mSwipeSlop || dy > mSwipeSlop) {
                            startedDrag = true
                        }
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                }
            }

            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {
            itemTouchHelper.injectTouchEvent(e)
        }

        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
    }

    private val layoutManager = GridLayoutManager(context, calculateNoOfColumns())
    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        layoutManager.isSmoothScrollbarEnabled = true
        rv.layoutManager = layoutManager
        rv.setLayoutManager(layoutManager)
        rv.clipToPadding = false
        when (mode) {
            Mode.THUMB -> {
                rv.setPadding(12.dp, 4.dp, 12.dp, 4.dp)
                rv.addItemDecoration(
                    SpacesItemDecoration(
                        0,
                        0
                    )
                )
            }

            Mode.COMPLETE -> {
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

        if (mode == Mode.COMPLETE && !isShowingSingleCollection)
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
            val window = injectedWindow ?: this.window!!
            val navVC = WNavigationController(window)
            navVC.setRoot(
                AssetsTabVC(
                    context,
                    assetsVM.showingAccountId,
                    defaultSelectedIdentifier = collectionMode?.collectionAddress
                        ?: AssetsTabVC.TAB_COLLECTIBLES
                )
            )
            window.present(navVC)
        }
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
                                        icon = WMenuPopup.Item.Config.Icon(
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
                                    openLink(url)
                                }
                            )
                            items.add(
                                WMenuPopup.Item(
                                    WMenuPopup.Item.Config.Item(
                                        icon = WMenuPopup.Item.Config.Icon(
                                            icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_tonscan,
                                            tintColor = null,
                                            iconSize = 28.dp
                                        ),
                                        title = "Tonscan",
                                    ),
                                    false,
                                ) {
                                    openLink("https://tonscan.org/nft/$collectionAddress")
                                }
                            )
                        }
                    }

                    TelegramGifts -> {
                        items.add(
                            WMenuPopup.Item(
                                WMenuPopup.Item.Config.Item(
                                    icon = WMenuPopup.Item.Config.Icon(
                                        icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_fragment,
                                        tintColor = null,
                                        iconSize = 28.dp
                                    ),
                                    title = "Fragment",
                                ),
                                false,
                            ) {
                                openLink("https://fragment.com/gifts")
                            }
                        )

                        items.add(
                            WMenuPopup.Item(
                                WMenuPopup.Item.Config.Item(
                                    icon = WMenuPopup.Item.Config.Icon(
                                        icon = org.mytonwallet.app_air.uiassets.R.drawable.ic_getgems,
                                        tintColor = null,
                                        iconSize = 28.dp
                                    ),
                                    title = "Getgems",
                                ),
                                false,
                            ) {
                                openLink("https://getgems.io/top-gifts")
                            }
                        )
                    }

                    null -> return@setOnClickListener
                }

                WMenuPopup.present(
                    this,
                    items,
                    popupWidth = WRAP_CONTENT,
                    positioning = WMenuPopup.Positioning.ALIGNED
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

    override fun setupViews() {
        super.setupViews()

        setNavTitle(title!!)
        if (isShowingSingleCollection) {
            setupNavBar(true)
            navigationBar?.addTrailingView(navTrailingView, LayoutParams(WRAP_CONTENT, 40.dp))
        }
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (mode == Mode.THUMB) {
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
            if (mode == Mode.THUMB) {
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

        assetsVM.delegateIsReady()

        if (onReorderingRequested != null) {
            itemTouchHelper.setBeforeLongPressListener {
                if (isShowingEmptyView)
                    return@setBeforeLongPressListener
                assetsVM.isInDragMode = true
                onReorderingRequested.invoke()
                rvAdapter.updateVisibleCells()
            }
        }

        updateTheme()
        insetsUpdated()

        view.post {
            updateEmptyView()
            nftsUpdated()
        }
    }

    fun configure(accountId: String) {
        if (assetsVM.showingAccountId == accountId)
            return
        emptyDataView.isGone = true
        isShowingEmptyView = false
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

        if (mode == Mode.THUMB) {
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
        if (mode == Mode.THUMB) {
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

    private fun getEmptyThumbHeight(): Int {
        val targetWidth = view.width
        if (targetWidth > 0 && emptyDataView.width != targetWidth) {
            emptyDataView.measure(targetWidth.exactly, 0.unspecified)
            emptyDataViewHeight = emptyDataView.measuredHeight
        }
        return emptyDataViewHeight
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
        if (mode == Mode.COMPLETE) {
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
        if (animationsPaused == paused)
            return
        animationsPaused = paused
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
        layoutManager?.let {
            val firstVisible = it.findFirstVisibleItemPosition()
            val lastVisible = it.findLastVisibleItemPosition()

            for (i in firstVisible..lastVisible) {
                val holder = recyclerView.findViewHolderForAdapterPosition(i)
                if (holder != null) {
                    (holder.itemView as AssetCell).apply {
                        if (paused)
                            pauseAnimation()
                        else
                            resumeAnimation()
                    }
                }
            }
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun onNftTap(nft: ApiNft) {
        if (assetsVM.isInDragMode)
            return
        val assetVC = NftVC(
            context,
            assetsVM.showingAccountId,
            nft,
            assetsVM.nfts!!
        )
        val window = injectedWindow ?: window!!
        val tabNav = window.navigationControllers.last().tabBarController?.navigationController
        if (tabNav != null)
            tabNav.push(assetVC)
        else
            window.navigationControllers.last().push(assetVC)
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int {
        return 1
    }

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return when (mode) {
            Mode.COMPLETE -> assetsVM.nfts?.size ?: 0
            Mode.THUMB -> min(6, assetsVM.nfts?.size ?: 0)
        }
    }

    override fun recyclerViewCellType(
        rv: RecyclerView,
        indexPath: IndexPath
    ): WCell.Type {
        return ASSET_CELL
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        val cell = AssetCell(context, mode)
        cell.onTap = { nft ->
            onNftTap(nft)
        }
        return cell
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        if (mode == Mode.THUMB)
            return assetsVM.nfts!![indexPath.row].image
        return null
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val cell = cellHolder.cell as AssetCell
        cell.configure(
            assetsVM.nfts!![indexPath.row],
            assetsVM.isInDragMode,
            animationsPaused == false
        )
    }

    var isShowingEmptyView = false
    override fun updateEmptyView() {
        val nfts = assetsVM.nfts
        val isEmpty = nfts?.isEmpty() == true
        if (isEmpty != isEmptyStateVisible) {
            isEmptyStateVisible = isEmpty
            if (mode == Mode.THUMB) {
                onHeightChanged?.invoke()
            }
        }
        if (mode == Mode.THUMB) {
            recyclerView.isGone = isEmpty
            if (isEmpty) {
                showAllView.isGone = true
            }
        }
        if (nfts == null) {
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
            if (mode == Mode.COMPLETE) {
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

    private var prevShowAllViewToTop = 0
    override fun nftsUpdated() {
        assetsVM.nfts?.size?.let { nftsCount ->
            setNavSubtitle(
                LocaleController.getStringWithKeyValues(
                    "%amount% NFTs",
                    listOf(
                        Pair("%amount%", nftsCount.toString())
                    )
                )
            )
        }
        layoutManager.spanCount = calculateNoOfColumns()
        rvAdapter.reloadData()
        if (mode == Mode.THUMB) {
            updateRecyclerViewPaddingForCentering()
        }
        showAllView.isGone = !thereAreMoreToShow

        updateShowAllPosition()
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
        return if (mode == Mode.THUMB) {
            (assetsVM.nfts?.size ?: 0).coerceIn(1, 3)
        } else {
            max(2, (view.width - 16.dp) / 182.dp)
        }
    }

    private fun updateRecyclerViewPaddingForCentering() {
        val itemCount = assetsVM.nfts?.size ?: 0

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
        } else if (mode == Mode.THUMB) {
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

    private fun openLink(url: String) {
        WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
    }

    override fun startSorting() {
        if (assetsVM.isInDragMode)
            return
        assetsVM.isInDragMode = true
        rvAdapter.reloadData()
    }

    override fun endSorting() {
        assetsVM.isInDragMode = false
        rvAdapter.reloadData()
    }

    fun saveList() {
        assetsVM.saveList()
    }

    fun reloadList() {
        assetsVM.loadCachedNftsAsync(keepOrder = false, onFinished = {
            rvAdapter.reloadData()
        })
        /*if (hasChanged) {
            recyclerView.fadeOut(AnimationConstants.VERY_QUICK_ANIMATION) {
                rvAdapter.reloadData()
                recyclerView.fadeIn(AnimationConstants.VERY_QUICK_ANIMATION)
            }
        }*/
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
