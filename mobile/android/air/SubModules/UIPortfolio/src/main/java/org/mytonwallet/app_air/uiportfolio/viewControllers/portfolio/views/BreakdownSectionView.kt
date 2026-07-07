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
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
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
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import kotlin.math.abs
import kotlin.math.max

@SuppressLint("ViewConstructor")
class BreakdownSectionView(context: Context) : WView(context), WThemedView {

    private val cardWidth = 280.dp

    private val byChainCard = BreakdownCardView(
        context = context,
        titleText = LocaleController.getString("By Chain"),
        showLegend = true,
        emptyText = LocaleController.getString("No chain balances"),
    )
    private val assetMixCard = BreakdownCardView(
        context = context,
        titleText = LocaleController.getString("Asset Mix"),
        showLegend = true,
        emptyText = LocaleController.getString("No asset balances"),
    )
    private val stakedCard = BreakdownCardView(
        context = context,
        titleText = LocaleController.getString("Staked"),
        showLegend = true,
        emptyText = LocaleController.getString("No staked assets"),
    )

    // By Chain is only shown for multichain accounts. Default to the active
    // account's multichain value so the carousel matches before the first render.
    private var cards = buildVisibleCards(
        showByChain = AccountStore.activeAccount?.isMultichain == true,
    )

    private val allCards = listOf(byChainCard, assetMixCard, stakedCard)

    private fun buildVisibleCards(showByChain: Boolean): List<BreakdownCardView> = buildList {
        if (showByChain) add(byChainCard)
        add(assetMixCard)
        add(stakedCard)
    }

    private var heightAnimator: SpringAnimation? = null
    private var currentSectionHeight = SECTION_HEIGHT_DP.dp

    private val springSnap = SpringSnapHelper()

    private val adapter = object : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        override fun getItemViewType(position: Int) = position
        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            val card = cards[viewType]
            (card.parent as? ViewGroup)?.removeView(card)
            card.layoutParams = RecyclerView.LayoutParams(calculatedCardWidth(), MATCH_PARENT)
            return object : RecyclerView.ViewHolder(card) {}
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            holder.itemView.updateLayoutParams { width = calculatedCardWidth() }
        }
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

    // With only two cards (Asset Mix + Staked) there is no carousel overflow;
    // split the available width between them instead of using the fixed width.
    private fun calculatedCardWidth(): Int {
        if (cards.size != 2) return cardWidth
        val available =
            width - 2 * ViewConstants.HORIZONTAL_PADDINGS.dp - ViewConstants.GAP.dp
        return max(available / 2, cardWidth)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w == oldw || cards.size != 2) return
        val newWidth = calculatedCardWidth()
        cards.forEach { card ->
            if (card.parent != null && card.layoutParams?.width != newWidth)
                card.updateLayoutParams { this.width = newWidth }
        }
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
        stakedSlices: List<PortfolioBreakdownSlice>,
        animated: Boolean,
    ) {
        val newCards = buildVisibleCards(
            showByChain = AccountStore.activeAccount?.isMultichain == true,
        )
        if (newCards != cards) {
            cards = newCards
            adapter.notifyDataSetChanged()
        }
        byChainCard.render(chainSlices)
        assetMixCard.render(assetSlices)
        stakedCard.render(stakedSlices)

        fun rowsOf(card: BreakdownCardView) = when (card) {
            byChainCard -> chainSlices.size
            assetMixCard -> assetSlices.size
            else -> stakedSlices.size
        }

        val targetHeight = sectionHeightForRows(newCards.maxOf { rowsOf(it) }).dp
        if (animated && targetHeight > currentSectionHeight) {
            newCards.forEach { card ->
                if (sectionHeightForRows(rowsOf(card)).dp > currentSectionHeight) {
                    card.fadeInLegend()
                }
            }
        }
        if (animated)
            animateSectionHeight(targetHeight)
        else
            recyclerView.updateLayoutParams { this.height = targetHeight }
    }

    private fun animateSectionHeight(targetHeight: Int) {
        if (targetHeight == currentSectionHeight && heightAnimator?.isRunning != true) return
        heightAnimator?.cancel()
        heightAnimator = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(currentSectionHeight.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = SpringForce.STIFFNESS_LOW
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val height = value.toInt()
                currentSectionHeight = height
                recyclerView.updateLayoutParams { this.height = height }
            }
            start()
        }
    }

    fun maskTargets(): List<Pair<View, Float>> =
        cards.map { it.maskTarget() }

    fun crossFadeTargets(): List<View> =
        cards.flatMap { it.crossFadeTargets() }

    fun showPlaceholders(animated: Boolean = false) {
        allCards.forEach { it.showPlaceholders(animated) }
    }

    fun hidePlaceholders() {
        allCards.forEach { it.hidePlaceholders() }
    }

    override fun updateTheme() {
        allCards.forEach { it.updateTheme() }
    }

    override fun onDetachedFromWindow() {
        heightAnimator?.cancel()
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
        private const val LEGEND_ROW_HEIGHT_DP = 22
        private const val LEGEND_ROW_GAP_DP = 4

        fun sectionHeightForRows(maxRows: Int): Int {
            if (maxRows <= 0) return SECTION_HEIGHT_DP
            val legendHeight =
                maxRows * LEGEND_ROW_HEIGHT_DP + (maxRows - 1).coerceAtLeast(0) * LEGEND_ROW_GAP_DP
            return (NON_CYLINDER_HEIGHT_DP + legendHeight).coerceAtLeast(SECTION_HEIGHT_DP)
        }
    }
}
