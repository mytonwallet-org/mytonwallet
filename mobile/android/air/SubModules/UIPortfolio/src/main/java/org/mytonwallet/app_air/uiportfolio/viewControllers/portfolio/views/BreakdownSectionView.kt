package org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.SpringSnapHelper
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uiportfolio.viewControllers.portfolio.models.PortfolioBreakdownSlice
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import kotlin.math.abs

@SuppressLint("ViewConstructor")
class BreakdownSectionView(context: Context) : WView(context), WThemedView {

    private val cardWidth = 280.dp

    private val byChainCard = BreakdownCardView(
        context = context,
        titleText = LocaleController.getString("By Chain"),
        showLegend = true,
    )
    private val assetMixCard = BreakdownCardView(
        context = context,
        titleText = LocaleController.getString("Asset Mix"),
        showLegend = true,
    )

    private val cards = listOf(byChainCard, assetMixCard)

    private val springSnap = SpringSnapHelper()

    private val adapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        override fun getItemViewType(position: Int) = position
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            val card = cards[viewType]
            (card.parent as? ViewGroup)?.removeView(card)
            card.layoutParams = RecyclerView.LayoutParams(cardWidth, MATCH_PARENT)
            return object : RecyclerView.ViewHolder(card) {}
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) = Unit
        override fun getItemCount() = cards.size
    }

    private val recyclerView = WRecyclerView(context).apply {
        id = generateViewId()
        layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        isHorizontalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        clipToPadding = false
        setPadding(ViewConstants.HORIZONTAL_PADDINGS.dp, 0, ViewConstants.HORIZONTAL_PADDINGS.dp, 0)
        layoutManager = LinearLayoutManager(context, LinearLayoutManager.HORIZONTAL, false)
        addItemDecoration(object : RecyclerView.ItemDecoration() {
            override fun getItemOffsets(
                outRect: Rect,
                view: View,
                parent: RecyclerView,
                state: RecyclerView.State,
            ) {
                if (parent.getChildAdapterPosition(view) > 0) outRect.left = ViewConstants.GAP.dp
            }
        })
        addOnItemTouchListener(AxisInterceptTouchListener(context))
    }

    init {
        recyclerView.adapter = adapter
        springSnap.attachTo(recyclerView)
        addView(recyclerView, LayoutParams(MATCH_CONSTRAINT, SECTION_HEIGHT_DP.dp))
        setConstraints {
            allEdges(recyclerView)
        }
    }

    fun render(
        chainSlices: List<PortfolioBreakdownSlice>,
        assetSlices: List<PortfolioBreakdownSlice>,
    ) {
        byChainCard.render(chainSlices)
        assetMixCard.render(assetSlices)
    }

    fun maskTargets(): List<Pair<View, Float>> =
        listOf(byChainCard.maskTarget(), assetMixCard.maskTarget())

    fun showPlaceholders() {
        byChainCard.showPlaceholders()
        assetMixCard.showPlaceholders()
    }

    fun hidePlaceholders() {
        byChainCard.hidePlaceholders()
        assetMixCard.hidePlaceholders()
    }

    override fun updateTheme() {
        byChainCard.updateTheme()
        assetMixCard.updateTheme()
    }

    override fun onDetachedFromWindow() {
        springSnap.cancel()
        super.onDetachedFromWindow()
    }

    /**
     * Locks parent intercept on DOWN; releases it back to the outer scroller if the user's
     * gesture turns out to be vertical (dy > dx beyond touch slop).
     */
    private class AxisInterceptTouchListener(context: Context) : RecyclerView.OnItemTouchListener {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var startX = 0f
        private var startY = 0f
        private var decided = false

        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = e.x
                    startY = e.y
                    decided = false
                    rv.parent?.requestDisallowInterceptTouchEvent(true)
                }

                MotionEvent.ACTION_MOVE -> {
                    if (!decided) {
                        val dx = abs(e.x - startX)
                        val dy = abs(e.y - startY)
                        if (dx > slop || dy > slop) {
                            decided = true
                            if (dy > dx) rv.parent?.requestDisallowInterceptTouchEvent(false)
                        }
                    }
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    decided = false
                    rv.parent?.requestDisallowInterceptTouchEvent(false)
                }
            }
            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) = Unit
        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) = Unit
    }

    companion object {
        const val SECTION_HEIGHT_DP = 228
        const val NON_CYLINDER_HEIGHT_DP = 68
        const val CYLINDER_HEIGHT_DP = SECTION_HEIGHT_DP - NON_CYLINDER_HEIGHT_DP
    }
}
