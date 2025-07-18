package org.mytonwallet.app_air.uiassets.viewControllers.assets

import WNavigationController
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams
import androidx.core.content.ContextCompat
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiassets.viewControllers.assets.cells.AssetCell
import org.mytonwallet.app_air.uiassets.viewControllers.assets.views.EmptyCollectionsView
import org.mytonwallet.app_air.uiassets.viewControllers.assetsTab.AssetsTabVC
import org.mytonwallet.app_air.uiassets.viewControllers.nft.NftVC
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerView
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.ShowAllView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.SpacesItemDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.NftCollection
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class AssetsVC(
    context: Context,
    private val mode: Mode,
    private var injectedWindow: WWindow? = null,
    val collectionMode: CollectionMode? = null,
    private val allowReordering: Boolean = true,
    private val onHeightChanged: (() -> Unit)? = null,
    private val onScroll: ((rv: RecyclerView) -> Unit)? = null,
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource, AssetsVM.Delegate {

    enum class Mode {
        THUMB,
        COMPLETE
    }

    sealed class CollectionMode {
        data object TelegramGifts : CollectionMode()
        data class SingleCollection(val collection: NftCollection) : CollectionMode()
    }

    companion object {
        val ASSET_CELL = WCell.Type(1)
    }

    override var title: String?
        get() {
            return when (collectionMode) {
                is CollectionMode.TelegramGifts -> {
                    LocaleController.getString(org.mytonwallet.app_air.walletcontext.R.string.Assets_TelegramGifts)
                }

                is CollectionMode.SingleCollection -> {
                    collectionMode.collection.name
                }

                else -> {
                    LocaleController.getString(org.mytonwallet.app_air.walletcontext.R.string.Assets_Title)
                }
            }
        }
        set(_) {
        }

    private val isShowingCollection = collectionMode != null

    override val isSwipeBackAllowed = mode == Mode.COMPLETE && isShowingCollection

    override val shouldDisplayTopBar = mode == Mode.COMPLETE && isShowingCollection

    private val assetsVM by lazy {
        AssetsVM(collectionMode, this)
    }

    private val thereAreMoreToShow: Boolean
        get() {
            return (assetsVM.nfts?.size ?: 0) > 6
        }

    var currentHeight: Int? = null
    private val finalHeight: Int
        get() {
            return if (assetsVM.nfts.isNullOrEmpty()) 224.dp else
                (if ((assetsVM.nfts?.size
                        ?: 0) > 3
                ) 2 else 1) * (recyclerView.width - 32
                    .dp) / 3 + 4.dp + (if (thereAreMoreToShow) 56 else 4).dp
        }

    private val rvAdapter =
        WRecyclerViewAdapter(WeakReference(this), arrayOf(ASSET_CELL))

    private var emptyView: WView? = null
    var isDragging = false
        private set

    private val itemTouchHelper by lazy {
        val callback = object : ItemTouchHelper.SimpleCallback(
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

                assetsVM.moveItem(fromPosition, toPosition)
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
        ItemTouchHelper(callback)
    }

    private val scrollListener = object : RecyclerView.OnScrollListener() {
        override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
            super.onScrolled(recyclerView, dx, dy)
            if (dx == 0 && dy == 0)
                return
            reversedCornerViewAboveRecyclerView.translationY =
                -recyclerView.computeVerticalScrollOffset().toFloat()
            updateBlurViews(recyclerView)
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

    private val recyclerView: WRecyclerView by lazy {
        val rv = WRecyclerView(this)
        rv.adapter = rvAdapter
        val cols = calculateNoOfColumns()
        val layoutManager = GridLayoutManager(context, cols)
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

        if (allowReordering) {
            itemTouchHelper.attachToRecyclerView(rv)
        }

        rv
    }

    private val showAllView: ShowAllView by lazy {
        val v = ShowAllView(context)
        v.titleLabel.text =
            LocaleController.getString(org.mytonwallet.app_air.walletcontext.R.string.Assets_ShowAll)
        v.onTap = {
            val window = injectedWindow ?: this.window!!
            val navVC = WNavigationController(window)
            collectionMode?.let {
                navVC.setRoot(
                    AssetsVC(
                        context,
                        Mode.COMPLETE,
                        window,
                        collectionMode,
                        allowReordering = allowReordering
                    )
                )
            } ?: run {
                navVC.setRoot(AssetsTabVC(context, defaultSelectedIndex = 1))
            }
            window.present(navVC)
        }
        v.visibility = View.GONE
        v
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPadding(8.dp)
        btn.setOnClickListener {
            val homeNftCollections =
                WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId!!)
            val homeCollectionAddress = when (collectionMode) {
                is CollectionMode.SingleCollection -> {
                    collectionMode.collection.address
                }

                CollectionMode.TelegramGifts -> {
                    NftCollection.TELEGRAM_GIFTS_SUPER_COLLECTION
                }

                null -> throw Exception()
            }
            val isInHomeTabs = homeNftCollections.contains(homeCollectionAddress)
            WMenuPopup.present(
                btn,
                listOf(
                    WMenuPopup.Item(
                        null,
                        LocaleController.getString(
                            if (isInHomeTabs)
                                org.mytonwallet.app_air.walletcontext.R.string.Assets_RemoveTab
                            else
                                org.mytonwallet.app_air.walletcontext.R.string.Assets_AddTab
                        ),
                        false,
                    ) {
                        val homeNftCollections =
                            WGlobalStorage.getHomeNftCollections(AccountStore.activeAccountId!!)
                        if (isInHomeTabs) {
                            homeNftCollections.remove(homeCollectionAddress)
                        } else {
                            if (!homeNftCollections.contains(homeCollectionAddress))
                                homeNftCollections.add(homeCollectionAddress)
                        }
                        WGlobalStorage.setHomeNftCollections(
                            AccountStore.activeAccountId!!,
                            homeNftCollections
                        )
                        WalletCore.notifyEvent(WalletCore.Event.HomeNftCollectionsUpdated)
                    }),
                offset = (-140).dp,
                popupWidth = 180.dp,
                aboveView = true
            )
        }
        btn
    }

    // We can't use the usual trick of setting top and bottom rounding to cells for grid cells here,
    //  So, we add a reversed corner view to simulate that without ui issues and keep blur as expected.
    val reversedCornerViewAboveRecyclerView = ReversedCornerView(
        context, initialConfig = ReversedCornerView.Config(
            overrideBackgroundColor = WColor.SecondaryBackground
        )
    )

    override fun setupViews() {
        super.setupViews()

        setNavTitle(title!!)
        if (mode == Mode.COMPLETE && isShowingCollection) {
            setupNavBar(true)
            navigationBar?.addTrailingView(moreButton, LayoutParams(40.dp, 40.dp))
        }
        view.addView(recyclerView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (mode == Mode.COMPLETE) {
            view.addView(
                reversedCornerViewAboveRecyclerView,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    recyclerView.paddingTop + ViewConstants.BAR_ROUNDS.dp.roundToInt()
                )
            )
        }
        if (mode == Mode.THUMB) {
            view.addView(showAllView, LayoutParams(MATCH_PARENT, 56.dp))
        }
        view.setConstraints {
            toTop(reversedCornerViewAboveRecyclerView)
            toCenterX(
                reversedCornerViewAboveRecyclerView,
                if (mode == Mode.COMPLETE) -ViewConstants.HORIZONTAL_PADDINGS.toFloat() else 0f
            )
            if (mode == Mode.THUMB) {
                toCenterX(showAllView)
            }
            if (mode == Mode.COMPLETE && (navigationController?.viewControllers?.size ?: 1) > 1)
                toCenterX(
                    recyclerView,
                    ViewConstants.HORIZONTAL_PADDINGS.toFloat()
                )
        }

        assetsVM.delegateIsReady()

        updateTheme()

        view.post {
            updateEmptyView()
            nftsUpdated()
        }
    }

    override fun updateTheme() {
        super.updateTheme()

        if (mode == Mode.THUMB) {
            view.background = null
        } else {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
            recyclerView.setBackgroundColor(WColor.Background.color)
        }
        rvAdapter.reloadData()
        if (mode == Mode.COMPLETE && isShowingCollection) {
            val moreDrawable =
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.icons.R.drawable.ic_more
                )?.apply {
                    setTint(WColor.SecondaryText.color)
                }
            moreButton.setImageDrawable(moreDrawable)
            moreButton.addRippleEffect(WColor.BackgroundRipple.color, 20f.dp)
        }
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
            reversedCornerViewAboveRecyclerView.updateLayoutParams {
                height = recyclerView.paddingTop + ViewConstants.BAR_ROUNDS.dp.roundToInt()
            }
        }
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    private fun onNftTap(nft: ApiNft) {
        val assetVC = NftVC(context, nft, assetsVM.nfts!!)
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
        cell.configure(assetsVM.nfts!![indexPath.row])
    }

    override fun updateEmptyView() {
        if (assetsVM.nfts == null) {
            if ((emptyView?.alpha ?: 0f) > 0)
                emptyView?.fadeOut(onCompletion = {
                    if (assetsVM.nfts == null)
                        emptyView?.visibility == View.GONE
                })
        } else if (assetsVM.nfts.isNullOrEmpty()) {
            if (emptyView == null) {
                emptyView =
                    when (mode) {
                        Mode.COMPLETE -> {
                            WEmptyIconView(
                                context,
                                R.raw.animation_empty,
                                LocaleController.getString(org.mytonwallet.app_air.walletcontext.R.string.Assets_NoAssetsFound)
                            )
                        }

                        Mode.THUMB -> {
                            EmptyCollectionsView(injectedWindow ?: window!!)
                        }
                    }
                view.addView(emptyView!!, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
                view.constraintSet().apply {
                    toCenterX(emptyView!!)
                    if (mode == Mode.COMPLETE)
                        toCenterY(emptyView!!)
                    else
                        toTop(emptyView!!, 85f)
                }.layout()
            } else if ((emptyView?.alpha ?: 0f) < 1) {
                if ((emptyView as? WEmptyIconView)?.startedAnimation != false) {
                    emptyView?.visibility = View.VISIBLE
                    emptyView?.fadeIn()
                }
            }
        } else if (assetsVM.nfts?.isNotEmpty() == true) {
            if ((emptyView?.alpha ?: 0f) > 0)
                emptyView?.fadeOut(onCompletion = {
                    if (assetsVM.nfts?.isNotEmpty() == true)
                        emptyView?.visibility == View.GONE
                })
        }
    }

    override fun nftsUpdated() {
        rvAdapter.reloadData()
        showAllView.visibility = if (thereAreMoreToShow) View.VISIBLE else View.GONE

        if (mode == Mode.THUMB) {
            view.setConstraints {
                toTopPx(showAllView, finalHeight - 56.dp)
            }

            animateHeight()
        }
    }

    private fun animateHeight() {
        currentHeight?.let {
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
        } ?: run {
            currentHeight = finalHeight
            onHeightChanged?.invoke()
        }
    }

    private fun calculateNoOfColumns(): Int {
        return if (mode == Mode.THUMB) 3 else max(
            2,
            (view.width - 16.dp) / 182.dp
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        recyclerView.removeOnScrollListener(scrollListener)
        itemTouchHelper.attachToRecyclerView(null)
        recyclerView.adapter = null
        recyclerView.removeAllViews()
    }
}
