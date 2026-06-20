package org.mytonwallet.app_air.uisettings.viewControllers.walletCustomization.views.cards

import android.annotation.SuppressLint
import android.content.Context
import androidx.core.view.doOnPreDraw
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.PagerSnapHelper
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.MAccount
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
open class WalletCustomizationCardsView(
    context: Context,
    private val accounts: List<MAccount>,
    private var selectedAccountId: String,
) :
    WRecyclerView(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource {

    companion object {
        val ACCOUNT_CELL = WCell.Type(1)

        private const val MAX_HEIGHT_DP = 360

        fun cellWidthFor(width: Int): Int {
            val byWidth = (width - 138.dp).coerceAtLeast(0)
            val byHeight =
                ((MAX_HEIGHT_DP.dp - 17.dp) * WalletCustomizationCardCell.RATIO).roundToInt()
            return minOf(byWidth, byHeight)
        }

        fun heightForWidth(width: Int): Int {
            val cw = cellWidthFor(width)
            return if (cw > 0) 17.dp + (cw / WalletCustomizationCardCell.RATIO).roundToInt() else 0
        }
    }

    interface OnItemChangeListener {
        fun onItemOffsetChanged(fromIndex: Int, toIndex: Int, offsetPercent: Float)
    }

    var onItemChangeListener: OnItemChangeListener? = null

    private val layoutManagerH = LinearLayoutManager(context, HORIZONTAL, false)

    val scrollListener = object : OnScrollListener() {
        override fun onScrolled(rv: RecyclerView, dx: Int, dy: Int) {
            val center = rv.width / 2

            for (i in 0 until rv.childCount) {
                val child = rv.getChildAt(i) as WalletCustomizationCardCell
                val childCenter = (child.left + child.right) / 2
                val distance = center - childCenter
                val maxDistance = center
                val scale = 1f - (abs(distance) / maxDistance.toFloat()) * 0.17f
                val rotationY = (distance / maxDistance.toFloat()) * 15f
                child.pivotX = child.cellWidth * (if (distance > 0) 0.84f else 0.16f)
                child.scaleX = scale
                child.scaleY = scale
                child.rotationY = rotationY
            }

            val lm = rv.layoutManager as LinearLayoutManager
            val first = lm.findFirstVisibleItemPosition()
            val firstView = lm.findViewByPosition(first) ?: return
            val itemWidth = firstView.width
            val scrollOffset = paddingLeft - firstView.left
            val offsetPercent = (scrollOffset / itemWidth.toFloat()).coerceIn(0f, 1f)
            val fromIndex = first
            val toIndex = (first + 1).coerceAtMost(accounts.lastIndex)
            onItemChangeListener?.onItemOffsetChanged(fromIndex, toIndex, offsetPercent)
        }
    }

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(ACCOUNT_CELL)).apply {
        setHasStableIds(true)
    }

    private var lastWidth = 0
    private var cellWidth = 0

    init {
        adapter = rvAdapter
        layoutManager = layoutManagerH
        clipChildren = false
        clipToPadding = false
        addOnScrollListener(scrollListener)
        PagerSnapHelper().attachToRecyclerView(this)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val w = width
        if (w <= 0 || w == lastWidth) return
        lastWidth = w
        val newCellWidth = cellWidthFor(w)
        if (newCellWidth != cellWidth) {
            cellWidth = newCellWidth
            rvAdapter.reloadData()
        }
        centerSelected(w)
    }

    private fun centerSelected(forWidth: Int) {
        if (width != forWidth || width <= 0) return
        val itemWidth = cellWidthFor(width)
        if (itemWidth <= 0) return
        val targetHeight = heightForWidth(width)
        if (layoutParams != null && layoutParams.height != targetHeight) {
            updateLayoutParams { height = targetHeight }
        }
        val sidePadding = (width - itemWidth) / 2
        setPadding(sidePadding, 0, sidePadding, 0)

        val index = accounts.indexOfFirst { it.accountId == selectedAccountId }
        if (index != -1) {
            layoutManagerH.scrollToPosition(index)
            doOnPreDraw {
                scrollListener.onScrolled(this@WalletCustomizationCardsView, 0, 0)
            }
        }
    }

    fun reload(accountId: String) {
        val index = accounts.indexOfFirst { it.accountId == accountId }
        if (index < 0) return

        val itemView = findViewHolderForAdapterPosition(index)?.itemView
        (itemView as? WalletCustomizationCardCell)?.configure(accounts[index])
    }

    fun reload() {
        rvAdapter.reloadData()
    }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath): String? {
        return accounts[indexPath.row].accountId
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int) =
        if (width > 0) accounts.size else 0

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath) = ACCOUNT_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type) =
        WalletCustomizationCardCell(context, cellWidth)

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        (cellHolder.cell as WalletCustomizationCardCell).apply {
            updateCellWidth(this@WalletCustomizationCardsView.cellWidth)
            configure(accounts[indexPath.row])
        }
    }
}
