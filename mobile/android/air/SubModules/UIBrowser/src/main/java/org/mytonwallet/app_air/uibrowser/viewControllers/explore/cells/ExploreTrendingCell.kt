package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.SpringSnapHelper
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcore.models.MExploreSite

@SuppressLint("ViewConstructor")
class ExploreTrendingCell(
    context: Context,
    private val cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    companion object {
        private const val AUTO_SCROLL_INTERVAL = 5000L
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentIndex = 0
    private var itemCount = 0
    private var isAutoScrollEnabled = false
    private var isUserScrolling = false

    private val springSnap = SpringSnapHelper().apply {
        onUserDrag = { beginUserScroll() }
        onPositionSettled = { position ->
            currentIndex = position
            if (isUserScrolling) {
                isUserScrolling = false
                startAutoScroll()
            }
        }
    }

    private fun beginUserScroll() {
        if (isUserScrolling) return
        isUserScrolling = true
        stopAutoScroll()
    }

    private val recyclerView = WRecyclerView(context).apply {
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        isHorizontalScrollBarEnabled = false
        layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(
                outRect: Rect,
                view: View,
                parent: RecyclerView,
                state: RecyclerView.State
            ) {
                if (parent.getChildAdapterPosition(view) > 0) outRect.left = (-10).dp
            }
        })
    }

    private val trendingAdapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        var sites: List<MExploreSite> = emptyList()
            private set

        fun setSites(newSites: List<MExploreSite>) {
            sites = newSites
            recyclerView.recycledViewPool.clear()
            @Suppress("NotifyDataSetChanged")
            notifyDataSetChanged()
        }

        override fun getItemViewType(position: Int) = position

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder =
            object : RecyclerView.ViewHolder(
                ExploreTrendingItemCell(context, cellWidth, sites[viewType], onSiteTap)
            ) {}

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) = Unit

        override fun getItemCount() = sites.size
    }

    private val autoScrollRunnable = object : Runnable {
        override fun run() {
            if (!isAutoScrollEnabled || itemCount <= 1) return
            currentIndex = (currentIndex + 1) % itemCount
            springSnap.scrollTo(currentIndex)
            handler.postDelayed(this, AUTO_SCROLL_INTERVAL)
        }
    }

    init {
        recyclerView.adapter = trendingAdapter
        springSnap.attachTo(recyclerView)
        addView(recyclerView)
        setConstraints {
            toTop(recyclerView, 0f)
            toBottom(recyclerView)
            toCenterX(recyclerView)
        }
        updateTheme()
    }

    fun configure(sites: List<MExploreSite>?) {
        if (sites == trendingAdapter.sites)
            return

        stopAutoScroll()

        itemCount = sites?.size ?: 0
        currentIndex = 0

        trendingAdapter.setSites(sites ?: emptyList())
        recyclerView.scrollToPosition(0)

        startAutoScroll()
    }

    private fun startAutoScroll() {
        if (isAutoScrollEnabled || itemCount < 2 || !isAttachedToWindow) return
        isAutoScrollEnabled = true
        handler.postDelayed(autoScrollRunnable, AUTO_SCROLL_INTERVAL)
    }

    private fun stopAutoScroll() {
        if (!isAutoScrollEnabled) return
        isAutoScrollEnabled = false
        handler.removeCallbacks(autoScrollRunnable)
        springSnap.cancel()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        stopAutoScroll()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        startAutoScroll()
    }

    override fun updateTheme() {
    }
}
