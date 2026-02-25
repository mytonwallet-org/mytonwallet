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
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.animation.doOnEnd
import androidx.core.graphics.withClip
import androidx.core.graphics.withSave
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import me.vkryl.core.fromTo
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.SpacesItemDecoration
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.recyclerView.CustomItemTouchHelper
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.max

// TODO: Refactor this class to improve performance and readability.
@SuppressLint("ViewConstructor")
class WClearSegmentedControl(
    context: Context,
) : FrameLayout(context), WThemedView, WRecyclerViewAdapter.WRecyclerViewDataSource {
    data class Item(
        val title: String,
        // Called whenever user taps on remove icon
        val onRemove: ((v: View) -> Unit)?,
        // onClick, usually opens a popup menu
        var onClick: ((v: View) -> Unit)?,
        var arrowVisibility: Float? = null
    )

    var horizontalFadingEdge: Boolean
        get() {
            return recyclerView.isHorizontalFadingEdgeEnabled
        }
        set(value) {
            // TODO:: Handle this
            //recyclerView.isHorizontalFadingEdgeEnabled = value
        }

    companion object {
        val ITEM_CELL = WCell.Type(2)
        private const val ANIMATION_DURATION = 200L
        private const val CORNER_RADIUS = 16f
        private const val THUMB_HEIGHT = 32f
        private const val ITEM_SPACING = 6
        private const val DRAG_ELEVATION = 8f
    }

    interface Delegate {
        fun onIndexChanged(to: Int, animated: Boolean)
        fun onItemMoved(from: Int, to: Int)
        fun enterReorderingMode()
    }

    var primaryTextColor = WColor.PrimaryText.color
    var secondaryTextColor = WColor.SecondaryText.color
    private var currentPosition: Float = 0f

    // Used to animate dragMode enter/exit animations
    private var dragModePresentationFraction: Float = 0f
    private var targetPosition: Float? = null
    private var lastPosition: Float = -1f
    private var items: MutableList<Item> = mutableListOf()
    private var selectedItem: Int = 0
    private var delegate: Delegate? = null
    var isDragAllowed: Boolean = false
    var isAnimatingDragMode: Boolean = false
    var isInDragMode: Boolean = false
        private set

    fun setDragMode(value: Boolean, animated: Boolean) {
        if (isInDragMode == value) return
        if (value && !isDragAllowed) return
        isInDragMode = value
        isAnimatingDragMode = true
        configureDragMode(animated)
    }

    private val shouldRenderHoveringThumb: Boolean
        get() {
            return !isInDragMode || removingItem
        }

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

    private val positionHolder = FloatValueHolder(0f)
    private val springAnimation = SpringAnimation(positionHolder).apply {
        spring = SpringForce().apply {
            dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            stiffness = 500f
        }
        addUpdateListener { _, value, _ ->
            currentPosition = value
            updateThumbPositionInternal(
                currentPosition,
                ensureVisibleThumb = false,
                targetIndex = targetPosition?.toInt()
            )
        }
    }
    private val dragModeAnimator = ValueAnimator().apply {
        addUpdateListener { animation ->
            dragModePresentationFraction = animation.animatedValue as Float
            updateThumbPositionInternal(
                currentPosition,
                ensureVisibleThumb = false,
                targetIndex = targetPosition?.toInt()
            )
        }
        doOnEnd {
            isAnimatingDragMode = false
            updateThumbPositionInternal(
                currentPosition,
                ensureVisibleThumb = false,
                targetIndex = targetPosition?.toInt()
            )
        }
    }

    private var isDraggingItem = false
    private var invalidationRunnable: Runnable? = null
    private val itemTouchHelper by lazy {
        CustomItemTouchHelper(object : CustomItemTouchHelper.SimpleCallback(
            ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT,
            0
        ) {
            override fun onMove(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                if (!isDragAllowed) return false

                val fromPosition = viewHolder.adapterPosition
                val toPosition = target.adapterPosition

                if (fromPosition == RecyclerView.NO_POSITION || toPosition == RecyclerView.NO_POSITION) {
                    return false
                }

                moveItem(fromPosition, toPosition)
                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {}

            override fun isLongPressDragEnabled(): Boolean = isDragAllowed

            override fun onSelectedChanged(viewHolder: RecyclerView.ViewHolder?, actionState: Int) {
                super.onSelectedChanged(viewHolder, actionState)
                when (actionState) {
                    ItemTouchHelper.ACTION_STATE_DRAG -> {
                        isDraggingItem = true
                        viewHolder?.itemView?.apply {
                            elevation = DRAG_ELEVATION.dp
                            alpha = 0.8f
                        }
                    }

                    ItemTouchHelper.ACTION_STATE_IDLE -> {
                        isDraggingItem = false
                        viewHolder?.itemView?.apply {
                            elevation = 0f
                            alpha = 1f
                        }
                    }
                }
            }

            override fun clearView(
                recyclerView: RecyclerView,
                viewHolder: RecyclerView.ViewHolder
            ) {
                super.clearView(recyclerView, viewHolder)
                viewHolder.itemView.apply {
                    elevation = 0f
                    alpha = 1f
                }
            }

            override fun canDropOver(
                recyclerView: RecyclerView,
                current: RecyclerView.ViewHolder,
                target: RecyclerView.ViewHolder
            ): Boolean {
                return isDragAllowed && super.canDropOver(recyclerView, current, target)
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
        private var startedDrag = false
        private var touchDownX = 0f
        private var touchDownY = 0f
        private val mSwipeSlop = ViewConfiguration.get(context).scaledTouchSlop

        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    val child = rv.findChildViewUnder(e.x, e.y)

                    if (isInDragMode) {
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

            val child = rv.findChildViewUnder(e.x, e.y)
            if (child != null) {
                gestureDetector.onTouchEvent(e)
            }
            return false
        }

        override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {
            itemTouchHelper.injectTouchEvent(e)
        }

        override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
    }

    private val recyclerView: WRecyclerView by lazy {
        createRecyclerView()
    }

    init {
        id = generateViewId()
        addView(recyclerView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
        })
    }

    private fun createRecyclerView() = object : WRecyclerView(context) {
        private var isDrawThumb: Boolean = false

        override fun dispatchDraw(canvas: Canvas) {
            if (!shouldRenderHoveringThumb) {
                super.dispatchDraw(canvas)
                return
            }
            isNestedScrollingEnabled = true
            drawOutOfThumb(canvas)
            drawThumbBackground(canvas)
            drawInThumb(canvas)
        }

        private fun drawOutOfThumb(canvas: Canvas) {
            isDrawThumb = false
            canvas.withClip(fullPath) {
                super.dispatchDraw(this)
            }
        }

        private fun drawThumbBackground(canvas: Canvas) {
            canvas.drawRoundRect(rect, CORNER_RADIUS.dp, CORNER_RADIUS.dp, paint)
        }

        private fun drawInThumb(canvas: Canvas) {
            isDrawThumb = shouldRenderHoveringThumb
            canvas.withClip(thumbPath) {
                super.dispatchDraw(this)
            }
        }

        override fun drawChild(canvas: Canvas, child: View?, drawingTime: Long): Boolean {
            if (!shouldRenderHoveringThumb) {
                return super.drawChild(canvas, child, drawingTime)
            }

            val itemView = child as? WClearSegmentedControlItemView
                ?: return super.drawChild(canvas, child, drawingTime)

            val position = getChildAdapterPosition(child)
            if (position == NO_POSITION || position >= items.size) {
                if (itemView.alpha < 1.0f || itemView.scaleX < 1.0f || itemView.scaleY < 1.0f) {
                    // View is being animated out, let it complete
                    return super.drawChild(canvas, itemView, drawingTime)
                }
                return false
            }

            val textView = itemView.textView
            textView.setTextColor(if (isDrawThumb) primaryTextColor else secondaryTextColor)
            textView.paint.typeface = if (isDrawThumb) WFont.DemiBold.typeface else WFont.Medium.typeface
            val frameResult = super.drawChild(canvas, itemView, drawingTime)

            drawChildText(canvas, itemView, textView)
            return frameResult
        }

        private fun drawChildText(
            canvas: Canvas,
            itemView: WClearSegmentedControlItemView,
            textView: TextView
        ) {
            canvas.withSave {
                textView.apply {
                    translate(
                        itemView.x + textView.x,
                        itemView.top + textView.top.toFloat()
                    )
                    translate(
                        textView.compoundPaddingLeft.toFloat(),
                        textView.extendedPaddingTop.toFloat()
                    )
                    if (itemView.scaleX != 1f || itemView.scaleY != 1f) {
                        scale(
                            itemView.scaleX,
                            itemView.scaleY,
                            -(2 * textView.width) * (1 - itemView.scaleX),
                            height / 2f
                        )
                    }
                    rotate(itemView.rotation, textView.width / 2f, textView.height / 2f)
                    textView.layout.draw(this@withSave)
                }
            }
        }

        override fun canScrollHorizontally(direction: Int): Boolean {
            if (isInDragMode)
                return false
            return super.canScrollHorizontally(direction)
        }
    }.apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context).apply {
            isSmoothScrollbarEnabled = true
            orientation = RecyclerView.HORIZONTAL
        }
        setLayoutManager(layoutManager)
        addItemDecoration(SpacesItemDecoration(ITEM_SPACING.dp, 0))
        addOnItemTouchListener(recyclerViewTouchListener)
        setPaddingDp(11, 0, 11, 0)
        clipToPadding = false
        overScrollMode = OVER_SCROLL_NEVER

        itemAnimator?.removeDuration = 0

        itemTouchHelper.attachToRecyclerView(this)
        itemTouchHelper.setBeforeLongPressListener {
            delegate?.enterReorderingMode()
        }
        itemTouchHelper.setExternalTouchListener(object : RecyclerView.OnItemTouchListener {
            override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
                return false
            }

            override fun onTouchEvent(rv: RecyclerView, e: MotionEvent) {
                if (isInDragMode) {
                    val child = rv.findChildViewUnder(e.x, e.y)
                    if (child != null) {
                        val viewHolder = rv.getChildViewHolder(child)
                        (viewHolder.itemView as? WClearSegmentedControlItemView)?.let { itemView ->
                            val localX = e.x - child.left
                            val localY = e.y - child.top
                            val localEvent = MotionEvent.obtain(e).apply {
                                setLocation(localX, localY)
                            }
                            itemView.dispatchTouchEvent(localEvent)
                            localEvent.recycle()
                        }
                    }
                }
            }

            override fun onRequestDisallowInterceptTouchEvent(disallowIntercept: Boolean) {}
        })
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {

                // TODO:: This is a workaround to fix ui glitches; can be improved
                rvAdapter.updateVisibleCells()

                updateThumbPositionInternal(
                    position = currentPosition,
                    ensureVisibleThumb = false,
                    targetIndex = targetPosition?.toInt()
                )
            }
        })
    }

    fun setItems(items: List<Item>, selectedItem: Int, delegate: Delegate) {
        this.items = items.toMutableList()
        this.items.forEach {
            it.arrowVisibility = null
        }
        this.selectedItem = selectedItem
        this.targetPosition = selectedItem.toFloat()
        this.delegate = delegate
        rvAdapter.reloadData()
        updateThumbPositionInternal(selectedItem.toFloat(), false, selectedItem)
    }

    fun updateItemsTrailingViews() {
        recyclerView.post {
            updateThumbPosition(
                position = currentPosition,
                targetPosition = currentPosition.toInt(),
                animated = false,
                force = true,
                isAnimatingToPosition = false
            )
        }
    }

    var removingItem = false
    fun removeItem(index: Int, nextIndex: Int, onCompletion: () -> Unit) {
        removingItem = true
        val viewHolder = recyclerView.findViewHolderForAdapterPosition(index) ?: run {
            items.removeAt(index)
            rvAdapter.reloadData()
            if (index == selectedItem) {
                selectedItem = nextIndex
                updateThumbPosition(
                    selectedItem.toFloat(), selectedItem,
                    animated = true,
                    force = false,
                    isAnimatingToPosition = true
                )
            }
            removingItem = false
            onCompletion()
            return
        }

        val itemView = viewHolder.itemView
        val originalWidth = itemView.width
        val cellView = itemView as? WClearSegmentedControlItemView
        val trailingImageView = cellView?.trailingImageView
        val originalTrailingAlpha = cellView?.arrowVisibility ?: 0f
        val hasVisibleTrailing = originalTrailingAlpha > 0f

        if (index == selectedItem) {
            selectedItem = nextIndex
            updateThumbPosition(
                selectedItem.toFloat(), nextIndex,
                animated = true,
                force = false,
                isAnimatingToPosition = true
            )
        }
        val animator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = ANIMATION_DURATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animation ->
                val progress = animation.animatedValue as Float

                val animatedWidth = (originalWidth * progress).toInt()
                val layoutParams = itemView.layoutParams
                layoutParams.width = animatedWidth
                itemView.layoutParams = layoutParams

                itemView.alpha = progress

                if (hasVisibleTrailing) {
                    val alphaMult = max(0f, (progress - 0.8f) * 5f)
                    val arrowAlpha = originalTrailingAlpha * alphaMult
                    cellView?.arrowVisibility = arrowAlpha
                    trailingImageView?.scaleX = alphaMult
                    trailingImageView?.scaleY = alphaMult
                }

                itemView.apply {
                    scaleX = progress
                    scaleY = progress
                    pivotX = 0f
                    pivotY = height / 2f
                }
            }
        }

        animator.doOnEnd {
            val layoutParams = itemView.layoutParams
            layoutParams.width = WRAP_CONTENT
            itemView.layoutParams = layoutParams
            itemView.alpha = 1f
            itemView.apply {
                scaleX = 1f
                scaleY = 1f
            }
            trailingImageView?.apply {
                scaleX = 1f
                scaleY = 1f
            }
            cellView?.arrowVisibility = originalTrailingAlpha

            items.removeAt(index)
            selectedItem = nextIndex
            updateThumbPosition(
                nextIndex.toFloat(),
                nextIndex,
                animated = false,
                force = true,
                isAnimatingToPosition = true
            )
            rvAdapter.reloadData()
            removingItem = false
            onCompletion()
        }

        animator.start()
    }

    fun updateOnMenuPressed(index: Int, onMenuPressed: ((v: View) -> Unit)?) {
        if (!isEnabled)
            return
        if (isValidIndex(index)) {
            items[index].onClick = onMenuPressed
            Handler(Looper.getMainLooper()).post {
                updateThumbPosition(
                    position = currentPosition,
                    targetPosition = currentPosition.toInt(),
                    animated = false,
                    force = true,
                    isAnimatingToPosition = false
                )
                invalidate()
            }
        }
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
            targetPosition = selectedItem,
            animated = false,
            force = true,
            isAnimatingToPosition = false
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
        val onRemove = items[indexPath.row].onRemove
        val cell = cellHolder.cell as WClearSegmentedControlItemView
        val isSelected = selectedItem == indexPath.row
        // Workaround to handle first appearance ui glitches
        if (item.arrowVisibility == null) {
            item.arrowVisibility =
                if (item.onClick != null &&
                    !isInDragMode &&
                    ((!isAnimatingDragMode && isSelected) || item.onRemove != null)
                ) 1f else 0f
        }
        cell.configure(
            item,
            isInDragMode,
            !shouldRenderHoveringThumb,
            isSelected = isSelected,
            paintColor = paintColor,
            onRemove = {
                onRemove?.invoke(cell)
            }
        )
    }

    private fun handleCellClick(
        row: Int,
        cell: WClearSegmentedControlItemView
    ) {
        if (isInDragMode || !isEnabled)
            return
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
        targetIndex: Int?,
        force: Boolean,
        isAnimatingToPosition: Boolean
    ) {
        if (items.isEmpty() || !isValidIndex(index)) return
        selectedItem = index
        val clampedPosition = offset.coerceIn(0f, (items.size - 1).toFloat())
        updateThumbPosition(
            clampedPosition,
            targetPosition = targetIndex,
            animated = false,
            force = force,
            isAnimatingToPosition = isAnimatingToPosition
        )
    }

    fun updateThumbPosition(
        position: Float,
        targetPosition: Int?,
        animated: Boolean,
        force: Boolean,
        isAnimatingToPosition: Boolean,
    ) {
        if (items.isEmpty()) return

        val clampedPosition = position.coerceIn(0f, (items.size - 1).toFloat())
        if (clampedPosition == lastPosition && !animated && !force) return

        springAnimation.cancel()

        if (animated) {
            this.targetPosition = targetPosition?.toFloat()
            startAnimation()
        } else {
            currentPosition = clampedPosition
            updateThumbPositionInternal(
                clampedPosition,
                ensureVisibleThumb = !isAnimatingToPosition,
                if (isAnimatingToPosition) targetPosition else null
            )
        }
        lastPosition = clampedPosition
    }

    private fun startAnimation() {
        positionHolder.value = currentPosition
        springAnimation.animateToFinalPosition(targetPosition ?: 0f)
    }

    private fun updateThumbPositionInternal(
        position: Float,
        ensureVisibleThumb: Boolean = true,
        targetIndex: Int?
    ) {
        val layoutManager = recyclerView.layoutManager as? LinearLayoutManager ?: return
        val (index, nextIndex, fraction) = calculatePositionParams(position)
        val (currentView, nextView) = getViews(layoutManager, index, nextIndex)

        if (ensureVisibleThumb)
            ensureItemVisible(index, nextIndex, fraction)

        val thumbBounds = calculateThumbBounds(currentView, nextView, fraction, index, nextIndex)
        updatePaths(thumbBounds)
        updateItemArrowVisibility(index, nextIndex, fraction, targetIndex)
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
        val x = (currentView?.let {
            calculateX(currentView, nextView, fraction, index, nextIndex, scrollOffset)
        } ?: ((nextView?.left ?: 0) - (w * (1 - fraction))))
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

    private fun updateItemArrowVisibility(
        index: Int,
        nextIndex: Int,
        fraction: Float,
        limitArrowToPosition: Int?,
    ) {
        for (i in 0 until recyclerView.childCount) {
            val childView = recyclerView.getChildAt(i)
            val position = recyclerView.getChildAdapterPosition(childView)
            if (position >= 0 && position < items.size) {
                val itemView = childView as? WClearSegmentedControlItemView
                val item = itemView?.item
                val showingRemoveButton = isInDragMode || isAnimatingDragMode
                itemView?.setTrailingButton(
                    if (item?.onRemove != null &&
                        (isInDragMode || (isAnimatingDragMode && selectedItem != position))
                    )
                        WClearSegmentedControlItemView.TrailingButton.Remove else WClearSegmentedControlItemView.TrailingButton.Arrow
                )
                var arrowVisibility = when {
                    item?.onClick == null -> 0f
                    position == index && fraction < 0.5f -> 1f - fraction * 2f
                    position == nextIndex && fraction >= 0.5f -> (fraction - 0.5f) * 2f
                    else -> 0f
                }
                if (showingRemoveButton)
                    arrowVisibility = if (item?.onRemove != null)
                        arrowVisibility.coerceAtLeast(dragModePresentationFraction)
                    else
                        max(
                            0f,
                            arrowVisibility - dragModePresentationFraction
                        ) // Reduce width animated
                val shouldShowTrailingButton =
                    showingRemoveButton ||
                        limitArrowToPosition == null || limitArrowToPosition == position
                if (
                    shouldShowTrailingButton ||
                    arrowVisibility < (itemView?.arrowVisibility ?: 1f)
                ) {
                    itemView?.arrowVisibility = arrowVisibility
                    item?.arrowVisibility = arrowVisibility
                }
            }
        }
    }

    private fun configureDragMode(animated: Boolean) {
        if (isInDragMode) {
            startFrameInvalidation()
            dragModeAnimator.cancel()
            dragModeAnimator.apply {
                setFloatValues(dragModePresentationFraction, 1f)
                duration =
                    if (animated && WGlobalStorage.getAreAnimationsActive()) AnimationConstants.VERY_QUICK_ANIMATION else 0
                interpolator = AccelerateDecelerateInterpolator()
                start()
            }
        } else {
            dragModeAnimator.apply {
                setFloatValues(dragModePresentationFraction, 0f)
                duration =
                    if (animated && WGlobalStorage.getAreAnimationsActive()) AnimationConstants.VERY_QUICK_ANIMATION else 0
                interpolator = AccelerateDecelerateInterpolator()
                start()
            }
            stopFrameInvalidation()
        }
        // Do not use reloadData, to prevent losing touch event when going to drag mode.
        rvAdapter.updateVisibleCells()
        updateThumbPositionInternal(selectedItem.toFloat(), false, selectedItem)
    }

    private fun startFrameInvalidation() {
        stopFrameInvalidation()
        invalidationRunnable = object : Runnable {
            override fun run() {
                if (isInDragMode) {
                    recyclerView.invalidate()
                    post(this)
                }
            }
        }
        post(invalidationRunnable)
    }

    private fun stopFrameInvalidation() {
        invalidationRunnable?.let {
            removeCallbacks(it)
            invalidationRunnable = null
        }
    }
}
