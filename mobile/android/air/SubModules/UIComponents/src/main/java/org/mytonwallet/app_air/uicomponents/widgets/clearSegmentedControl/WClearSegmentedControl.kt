package org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.TextView
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.vkryl.core.fromTo
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CenteringLinearLayoutManager
import org.mytonwallet.app_air.uicomponents.helpers.SpacesItemDecoration
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class WClearSegmentedControl(
    context: Context,
) : FrameLayout(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource {

    companion object {
        val ITEM_CELL = WCell.Type(2)
        private const val ANIMATION_DURATION = 200L
        private const val CORNER_RADIUS = 16f
        private const val THUMB_HEIGHT = 32f
        private const val ITEM_SPACING = 8
        private const val DRAG_ELEVATION = 8f
    }

    interface Delegate {
        fun onIndexChanged(to: Int, animated: Boolean)
        fun onItemMoved(from: Int, to: Int)
    }

    var primaryTextColor = WColor.PrimaryText.color
    var secondaryTextColor = WColor.SecondaryText.color
    private var currentPosition: Float = 0f
    private var targetPosition: Float = 0f
    private var lastPosition: Float = -1f
    private var items: MutableList<WClearSegmentedControlItem> = mutableListOf()
    private var selectedItem: Int = 0
    private var delegate: Delegate? = null
    private var isDragEnabled: Boolean = false

    var paintColor: Int? = null
        set(value) {
            field = value
            paint.color = paintColor ?: WColor.SecondaryBackground.color
        }

    private val rect = RectF()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val thumbPath = Path()
    private val fullPath = Path()
    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(ITEM_CELL))

    private val animator = ValueAnimator().apply {
        addUpdateListener { animation ->
            currentPosition = animation.animatedValue as Float
            updateThumbPositionInternal(currentPosition, ensureVisibleThumb = false)
        }
    }

    private var isDraggingItem = false
    private val itemTouchHelper by lazy {
        ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(
            ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT,
            0
        ) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                if (!isDragEnabled) return false

                val fromPosition = viewHolder.adapterPosition
                val toPosition = target.adapterPosition

                if (fromPosition == RecyclerView.NO_POSITION || toPosition == RecyclerView.NO_POSITION) {
                    return false
                }

                moveItem(fromPosition, toPosition)
                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            }

            override fun isLongPressDragEnabled(): Boolean = isDragEnabled

            override fun onSelectedChanged(viewHolder: RecyclerView.ViewHolder?, actionState: Int) {
                super.onSelectedChanged(viewHolder, actionState)

                when (actionState) {
                    ItemTouchHelper.ACTION_STATE_DRAG -> {
                        isDraggingItem = true
                        viewHolder?.itemView?.elevation = DRAG_ELEVATION.dp
                        viewHolder?.itemView?.alpha = 0.8f
                    }

                    ItemTouchHelper.ACTION_STATE_IDLE -> {
                        isDraggingItem = false
                        viewHolder?.itemView?.elevation = 0f
                        viewHolder?.itemView?.alpha = 1f
                    }
                }
            }

            override fun clearView(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ) {
                super.clearView(recyclerView, viewHolder)
                viewHolder.itemView.elevation = 0f
                viewHolder.itemView.alpha = 1f
            }

            override fun canDropOver(
                recyclerView: RecyclerView,
                current: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                return isDragEnabled && super.canDropOver(recyclerView, current, target)
            }
        })
    }

    private val gestureDetector =
        GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapUp(e: MotionEvent): Boolean {
                val childView = recyclerView.findChildViewUnder(e.x, e.y)
                if (childView != null) {
                    val position = recyclerView.getChildAdapterPosition(childView)
                    if (position != RecyclerView.NO_POSITION) {
                        handleCellClick(position, childView as WClearSegmentedControlItemView)
                        return true
                    }
                }
                return false
            }
        })

    private val recyclerViewTouchListener = object : RecyclerView.OnItemTouchListener {
        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            val child = rv.findChildViewUnder(e.x, e.y)
            if (child != null && gestureDetector.onTouchEvent(e)) {
                return false
            }
            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {}
        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
    }

    private val recyclerView: WRecyclerView by lazy {
        createRecyclerView()
    }

    init {
        id = generateViewId()
        addView(recyclerView, createLayoutParams())
    }

    private fun createLayoutParams() = LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
        gravity = Gravity.CENTER
    }

    private fun createRecyclerView() = object : WRecyclerView(context) {
        private var isDrawThumb: Boolean = false

        override fun dispatchDraw(canvas: Canvas) {
            drawOutOfThumb(canvas)
            drawThumbBackground(canvas)
            drawInThumb(canvas)
        }

        private fun drawOutOfThumb(canvas: Canvas) {
            isDrawThumb = false
            canvas.save()
            canvas.clipPath(fullPath)
            super.dispatchDraw(canvas)
            canvas.restore()
        }

        private fun drawThumbBackground(canvas: Canvas) {
            canvas.drawRoundRect(rect, CORNER_RADIUS.dp, CORNER_RADIUS.dp, paint)
        }

        private fun drawInThumb(canvas: Canvas) {
            isDrawThumb = true
            canvas.save()
            canvas.clipPath(thumbPath)
            super.dispatchDraw(canvas)
            canvas.restore()
        }

        override fun drawChild(canvas: Canvas, child: View?, drawingTime: Long): Boolean {
            val itemView = child as? WClearSegmentedControlItemView
                ?: return super.drawChild(canvas, child, drawingTime)

            val textView = itemView.textView
            textView.setTextColor(if (isDrawThumb) primaryTextColor else secondaryTextColor)
            val frameResult = super.drawChild(canvas, itemView, drawingTime)

            drawChildText(canvas, itemView, textView)
            return frameResult
        }

        private fun drawChildText(
            canvas: Canvas,
            itemView: WClearSegmentedControlItemView,
            textView: TextView
        ) {
            canvas.save()
            textView.apply {
                canvas.translate(
                    itemView.x + textView.x,
                    itemView.top + textView.top.toFloat()
                )
                canvas.translate(
                    textView.compoundPaddingLeft.toFloat(),
                    textView.extendedPaddingTop.toFloat()
                )
                textView.layout.draw(canvas)
            }
            canvas.restore()
        }
    }.apply {
        adapter = rvAdapter
        val layoutManager = CenteringLinearLayoutManager(context).apply {
            isSmoothScrollbarEnabled = true
        }
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        addItemDecoration(SpacesItemDecoration(ITEM_SPACING.dp, 0))
        addOnItemTouchListener(recyclerViewTouchListener)

        itemTouchHelper.attachToRecyclerView(this)
        setOnScrollChangeListener { _, _, _, _, _ ->
            if (scrollState == RecyclerView.SCROLL_STATE_IDLE && !isDraggingItem)
                return@setOnScrollChangeListener
            updateThumbPositionInternal(position = currentPosition, ensureVisibleThumb = false)
        }
    }

    fun setItems(items: List<WClearSegmentedControlItem>, selectedItem: Int, delegate: Delegate) {
        this.items = items.toMutableList()
        this.selectedItem = selectedItem
        this.delegate = delegate
        rvAdapter.reloadData()
        recyclerView.post {
            updateThumbPosition(
                position = currentPosition,
                animated = false,
                force = true,
                ensureVisibleThumb = true
            )
        }
    }

    fun updateOnClick(index: Int, onClick: ((v: View) -> Unit)?) {
        if (isValidIndex(index)) {
            items[index].onClick = onClick
            Handler(Looper.getMainLooper()).post {
                updateThumbPosition(
                    position = currentPosition,
                    animated = false,
                    force = true,
                    ensureVisibleThumb = true
                )
                invalidate()
            }
        }
    }

    fun setDragEnabled(enabled: Boolean) {
        isDragEnabled = enabled
        itemTouchHelper.attachToRecyclerView(if (enabled) recyclerView else null)
    }

    fun moveItem(fromPosition: Int, toPosition: Int) {
        if (!isValidIndex(fromPosition) || !isValidIndex(toPosition) || fromPosition == toPosition) {
            return
        }

        val item = items.removeAt(fromPosition)
        items.add(toPosition, item)

        selectedItem = when (selectedItem) {
            fromPosition -> toPosition
            in (minOf(fromPosition, toPosition)..maxOf(fromPosition, toPosition)) -> {
                if (fromPosition < toPosition && selectedItem > fromPosition) selectedItem - 1
                else if (fromPosition > toPosition && selectedItem < fromPosition) selectedItem + 1
                else selectedItem
            }

            else -> selectedItem
        }

        rvAdapter.notifyItemMoved(fromPosition, toPosition)

        updateThumbPosition(
            selectedItem.toFloat(),
            animated = true,
            force = true,
            ensureVisibleThumb = true
        )

        delegate?.onItemMoved(fromPosition, toPosition)
    }

    private fun isValidIndex(index: Int) = index in 0 until items.size

    override fun updateTheme() {
        primaryTextColor = WColor.PrimaryText.color
        secondaryTextColor = WColor.SecondaryText.color
        if (paintColor == null) {
            paint.color = WColor.TrinaryBackground.color
        }
        rvAdapter.reloadData()
        requestLayout()
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = items.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        ITEM_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return WClearSegmentedControlItemView(context)
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val item = items[indexPath.row]
        val cell = cellHolder.cell as WClearSegmentedControlItemView
        cell.configure(item.title)

        if (isDragEnabled) {
            cell.isLongClickable = true
        }
    }

    private fun handleCellClick(
        row: Int,
        cell: WClearSegmentedControlItemView
    ) {
        if (selectedItem == row) {
            items[row].onClick?.invoke(cell)
        } else {
            // Animation is controlled from view-pager scroll
            delegate?.onIndexChanged(row, true)
        }
    }

    fun updateThumbPosition(
        index: Int,
        offset: Float,
        force: Boolean,
        ensureVisibleThumb: Boolean
    ) {
        if (items.isEmpty() || !isValidIndex(index)) return
        selectedItem = index
        val clampedPosition = offset.coerceIn(0f, (items.size - 1).toFloat())
        updateThumbPosition(
            clampedPosition,
            animated = false,
            force = force,
            ensureVisibleThumb = ensureVisibleThumb
        )
    }

    fun updateThumbPosition(
        position: Float,
        animated: Boolean,
        force: Boolean,
        ensureVisibleThumb: Boolean
    ) {
        if (items.isEmpty()) return

        val clampedPosition = position.coerceIn(0f, (items.size - 1).toFloat())
        if (clampedPosition == lastPosition && !animated && !force) return

        targetPosition = clampedPosition
        animator.cancel()

        if (animated) {
            startAnimation()
        } else {
            currentPosition = targetPosition
            updateThumbPositionInternal(clampedPosition, ensureVisibleThumb)
        }
        lastPosition = clampedPosition
    }

    private fun startAnimation() {
        animator.apply {
            setFloatValues(currentPosition, targetPosition)
            duration = ANIMATION_DURATION
            interpolator = AccelerateDecelerateInterpolator()
            start()
        }
    }

    private fun updateThumbPositionInternal(position: Float, ensureVisibleThumb: Boolean = true) {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
        val (index, nextIndex, fraction) = calculatePositionParams(position)
        val (currentView, nextView) = getViews(layoutManager, index, nextIndex)

        if (ensureVisibleThumb)
            ensureItemVisible(index, nextIndex, fraction)

        val thumbBounds = calculateThumbBounds(currentView, nextView, fraction, index, nextIndex)
        updatePaths(thumbBounds)
        updateItemArrowVisibility(index, nextIndex, fraction)
        recyclerView.invalidate()
    }

    private fun ensureItemVisible(index: Int, nextIndex: Int, fraction: Float) {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return

        val targetIndex = if (fraction < 0.5f) index else nextIndex

        val targetView = layoutManager.findViewByPosition(targetIndex)

        if (targetView == null) {
            recyclerView.smoothScrollToPosition(targetIndex)
            return
        }

        val recyclerViewBounds = Rect()
        recyclerView.getGlobalVisibleRect(recyclerViewBounds)

        val itemBounds = Rect()
        targetView.getGlobalVisibleRect(itemBounds)

        val scrollX = recyclerView.scrollX
        val recyclerViewLeft = recyclerView.left
        val recyclerViewRight = recyclerView.right
        val itemLeft = targetView.left - 8.dp
        val itemRight = targetView.right + 8.dp

        val needsScrollLeft = itemLeft < recyclerViewLeft
        val needsScrollRight = itemRight > recyclerViewRight

        if (needsScrollLeft || needsScrollRight) {
            val targetScrollX = when {
                needsScrollLeft -> scrollX + itemLeft - recyclerViewLeft
                needsScrollRight -> scrollX + itemRight - recyclerViewRight
                else -> scrollX
            }

            recyclerView.smoothScrollBy(targetScrollX - scrollX, 0)
        }
    }

    private fun calculatePositionParams(position: Float): Triple<Int, Int, Float> {
        val index = position.toInt().coerceIn(0, items.size - 1)
        val nextIndex = (index + 1).coerceAtMost(items.size - 1)
        val fraction = position - index
        return Triple(index, nextIndex, fraction)
    }

    private fun getViews(
        layoutManager: LinearLayoutManager,
        index: Int,
        nextIndex: Int
    ): Pair<View?, View?> {
        val currentView = layoutManager.findViewByPosition(index)
        val nextView = layoutManager.findViewByPosition(nextIndex)
        return Pair(currentView, nextView)
    }

    private fun calculateThumbBounds(
        currentView: View?,
        nextView: View?,
        fraction: Float,
        index: Int,
        nextIndex: Int
    ): RectF {
        val scrollOffset = recyclerView.scrollX.toFloat()
        val w = calculateWidth(currentView, nextView, fraction, index, nextIndex)
        val h = THUMB_HEIGHT.dp
        val x = currentView?.let {
            calculateX(currentView, nextView, fraction, index, nextIndex, scrollOffset)
        } ?: ((nextView?.left ?: 0) - (w * (1 - fraction)))
        val y = recyclerView.height / 2f - CORNER_RADIUS.dp

        return RectF(x, y, x + w, y + h)
    }

    private fun calculateX(
        currentView: View,
        nextView: View?,
        fraction: Float,
        index: Int,
        nextIndex: Int,
        scrollOffset: Float
    ): Float {
        return if (nextView != null && index != nextIndex) {
            currentView.left + (nextView.left - currentView.left) * fraction - scrollOffset
        } else {
            currentView.left.toFloat() + currentView.width * fraction - scrollOffset
        }
    }

    private fun calculateWidth(
        currentView: View?,
        nextView: View?,
        fraction: Float,
        index: Int,
        nextIndex: Int
    ): Float {
        return currentView?.let {
            if (nextView != null && index != nextIndex) {
                fromTo(currentView.width.toFloat(), nextView.width.toFloat(), fraction)
            } else {
                currentView.width.toFloat()
            }
        } ?: nextView?.width?.toFloat() ?: 0f
    }

    private fun updatePaths(bounds: RectF) {
        rect.set(bounds.left, bounds.top, bounds.right, bounds.bottom)

        thumbPath.reset()
        thumbPath.addRoundRect(rect, CORNER_RADIUS.dp, CORNER_RADIUS.dp, Path.Direction.CW)

        fullPath.reset()
        fullPath.addRect(0f, 0f, width.toFloat(), height.toFloat(), Path.Direction.CW)
        fullPath.addRoundRect(rect, CORNER_RADIUS.dp, CORNER_RADIUS.dp, Path.Direction.CCW)
    }

    private fun updateItemArrowVisibility(index: Int, nextIndex: Int, fraction: Float) {
        for (i in 0 until recyclerView.childCount) {
            val childView = recyclerView.getChildAt(i)
            val position = recyclerView.getChildAdapterPosition(childView)
            if (position >= 0 && position < items.size) {
                val itemView = childView as? WClearSegmentedControlItemView
                val item = items.getOrNull(position)
                val arrowVisibility = when {
                    item?.onClick == null -> 0f
                    position == index && fraction < 0.5f -> 1f - fraction * 2f
                    position == nextIndex && fraction >= 0.5f -> (fraction - 0.5f) * 2f
                    else -> 0f
                }
                itemView?.arrowVisibility = arrowVisibility
            }
        }
    }
}
