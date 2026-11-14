package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Rect
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ScrollView
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.suppressLayoutCompat
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

@SuppressLint("ViewConstructor")
class WMenuPopupView(
    context: Context,
    val items: List<WMenuPopup.Item>,
    private val onWillDismiss: (() -> Unit)?,
    private val onDismiss: () -> Unit,
    private val hasExpandingHeader: Boolean = false,
    private val verticalContentPadding: Int = 0,
    /** The theme the menu takes its colors from, dark (true) or light (false), or the app's */
    val themeIsDark: Boolean? = null,
    /** Lets a finger slide across the items, activating the one under it and choosing it on lift */
    private val isSlideSelectionEnabled: Boolean = false,
    private val onReorder: ((fromPosition: Int, toPosition: Int) -> Unit)? = null
) : WFrameLayout(context),
    WThemedView {

    companion object {
        private const val LIFTED_SCALE = 1.04f

        fun measureWidth(context: Context, items: List<WMenuPopup.Item>): Int = WMenuPopupView(
            context,
            items,
            onWillDismiss = null,
            onDismiss = {}
        ).apply {
            measure(ApplicationContextHolder.screenWidth.atMost, 0.unspecified)
        }.measuredWidth
    }

    var popupWindow: INavigationPopup? = null
    private val itemViews = ArrayList<FrameLayout>(items.size)
    private var currentHeight: Int = 0
    private var currentFrameHeight: Int = 0
    private val itemHeights: IntArray = IntArray(items.size)
    private val itemYPositions: IntArray = IntArray(items.size)
    private val preparedSubmenus = arrayOfNulls<WMenuPopupView>(items.size)
    private val initializedSubmenus = BooleanArray(items.size)
    private val expandingSubmenuWarmupIndices = items.indices
        .filter { index ->
            items[index].getSubmenuTransition() == WMenuPopup.SubmenuTransition.EXPAND_FROM_ITEM &&
                !items[index].getSubItems().isNullOrEmpty()
        }
        .sortedByDescending { index -> items[index].getSubItems()?.size ?: 0 }
    private var nextSubmenuWarmupPosition = 0
    private var isSubmenuWarmupScheduled = false
    private var isAnimating = false
    private var presentFromTop = true
    private var finalTranslationY = 0f
    var finalHeight = 0
        private set
    var isDismissed = false
    private val contentContainer: FrameLayout
    private val contentHeight: Int
    private val scrollView: ScrollView
    private val expandingBodyContainer = if (hasExpandingHeader) FrameLayout(context) else null
    private var expandingBodySpring: SpringAnimation? = null
    private var maxHeight: Int = 0
    private var isSlideSelecting = false
    private var activeItemView: WMenuPopupViewItem? = null
    private val itemBounds = Rect()

    // The items' indices in the order they show; a held item can be dragged to another place
    private val itemOrder = items.indices.toMutableList()
    private val canReorder = onReorder != null && !hasExpandingHeader && items.all {
        it.config is Config.Item && it.getSubItems().isNullOrEmpty()
    }
    private var draggedIndex: Int? = null
    private var dragStartRawY = 0f
    private var dragStartTop = 0
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var heldItemView: WMenuPopupViewItem? = null
    private var holdX = 0f
    private var holdY = 0f
    private val liftHeldItem = Runnable {
        val itemView = heldItemView ?: return@Runnable
        heldItemView = null
        endSelection(performAction = false)
        isSlideSelecting = false
        performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        startDrag(itemViews.indexOf(itemView))
    }

    /** Where a menu taller than it shows opens scrolled to, its selected choice in its middle, until it is laid out */
    private var pendingScrollY: Int? = null

    private fun makeExpandingHeaderItem(item: WMenuPopup.Item): WMenuPopup.Item {
        val config = item.config as? Config.Item ?: return item.copy()
        return item.copy(
            config = config.copy(trailingView = null),
            hasSeparator = true
        )
    }

    private fun makeSubmenuView(index: Int, window: INavigationPopup): WMenuPopupView? {
        val item = items.getOrNull(index) ?: return null
        val subItems = item.getSubItems()?.takeIf { it.isNotEmpty() } ?: return null
        val transition = item.getSubmenuTransition()
        val nextItems = if (transition == WMenuPopup.SubmenuTransition.EXPAND_FROM_ITEM) {
            listOf(makeExpandingHeaderItem(item)) + subItems
        } else {
            subItems.toMutableList().apply {
                add(0, WMenuPopup.Item(Config.Back, true))
            }
        }
        return WMenuPopupView(
            context,
            nextItems,
            onWillDismiss = { onWillDismiss?.invoke() },
            onDismiss = { popupWindow?.dismiss() },
            hasExpandingHeader = transition == WMenuPopup.SubmenuTransition.EXPAND_FROM_ITEM,
            themeIsDark = themeIsDark
        ).apply {
            popupWindow = window
        }
    }

    private fun makePreparedSubmenuView(index: Int, window: INavigationPopup): WMenuPopupView? {
        val submenuView = makeSubmenuView(index, window) ?: return null
        val exactWidth = width.takeIf { it > 0 } ?: measuredWidth.takeIf { it > 0 }
        if (exactWidth != null) {
            submenuView.measure(exactWidth.exactly, 0.unspecified)
            submenuView.layout(0, 0, exactWidth, submenuView.measuredHeight)
        }
        return submenuView
    }

    fun prepareExpandingSubmenus() {
        if (isSubmenuWarmupScheduled || !isAttachedToWindow) return
        val window = popupWindow ?: return
        while (
            nextSubmenuWarmupPosition < expandingSubmenuWarmupIndices.size &&
            initializedSubmenus[expandingSubmenuWarmupIndices[nextSubmenuWarmupPosition]]
        ) {
            nextSubmenuWarmupPosition++
        }
        val index = expandingSubmenuWarmupIndices.getOrNull(nextSubmenuWarmupPosition) ?: return

        nextSubmenuWarmupPosition++
        isSubmenuWarmupScheduled = true
        postOnAnimation {
            isSubmenuWarmupScheduled = false
            if (!isAttachedToWindow || popupWindow !== window) return@postOnAnimation
            if (!initializedSubmenus[index]) {
                preparedSubmenus[index] = makePreparedSubmenuView(index, window)
                initializedSubmenus[index] = true
            }
            prepareExpandingSubmenus()
        }
    }

    init {
        val displayMetrics = context.resources.displayMetrics
        maxHeight = displayMetrics.heightPixels - 100.dp

        scrollView = ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            scrollBarStyle = SCROLLBARS_INSIDE_OVERLAY
        }
        contentContainer = FrameLayout(context)
        expandingBodyContainer?.let {
            contentContainer.addView(it, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        scrollView.addView(contentContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(scrollView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        var totalHeight = verticalContentPadding
        items.forEachIndexed { index, item ->
            var itemHeight: Int
            var itemView: FrameLayout
            if (item.config is Config.CustomView) {
                itemView = item.config.customView.apply {
                    item.testViewId?.let { id = it }
                    alpha = 0f
                    visibility = INVISIBLE
                }
                itemHeight = item.config.height + if (item.hasSeparator) 7.dp else 0
            } else {
                val itemContentHeight =
                    if (item.getRowStyle() == WMenuPopup.RowStyle.WALLET) {
                        56.dp
                    } else if (item.config == Config.Back) {
                        44.dp
                    } else {
                        if (item.getSubTitle().isNullOrEmpty()) 48.dp else 52.dp
                    }
                itemHeight = itemContentHeight + if (item.hasSeparator) 7.dp else 0

                itemView = WMenuPopupViewItem(context, item, themeIsDark).apply {
                    item.testViewId?.let { id = it }
                    alpha = 0f
                    visibility = INVISIBLE
                }.apply {
                    if (canReorder) {
                        setOnLongClickListener {
                            startDrag(index)
                            true
                        }
                    }
                    setOnClickListener {
                        if (hasExpandingHeader && index == 0) {
                            popupWindow?.pop()
                            return@setOnClickListener
                        }
                        if (!item.getSubItems().isNullOrEmpty()) {
                            val window = popupWindow ?: return@setOnClickListener
                            val transition = item.getSubmenuTransition()
                            val nextPopupView = preparedSubmenus[index]
                                ?: makeSubmenuView(index, window)
                                ?: return@setOnClickListener
                            preparedSubmenus[index] = null
                            initializedSubmenus[index] = true
                            window.push(
                                nextPopupView,
                                transition = transition,
                                sourceItemIndex = index
                            )
                            return@setOnClickListener
                        }
                        item.onTap?.invoke() ?: run {
                            // Back Button
                            if (item.config is Config.Back) {
                                popupWindow?.pop()
                                return@setOnClickListener
                            }
                            return@setOnClickListener
                        }
                        if (!item.shouldKeepOpen) popupWindow?.dismiss()
                    }
                }
            }
            itemHeights[index] = itemHeight
            itemYPositions[index] = totalHeight
            totalHeight += itemHeight
            itemViews.add(itemView)
            val itemParent = expandingBodyContainer?.takeIf { hasExpandingHeader && index > 0 }
                ?: contentContainer
            itemParent.addView(itemView, LayoutParams(WRAP_CONTENT, itemHeight))
        }
        expandingBodyContainer?.updateLayoutParams {
            height = (
                totalHeight - verticalContentPadding -
                    (itemHeights.firstOrNull() ?: 0)
                ).coerceAtLeast(0)
        }
        contentHeight = totalHeight + verticalContentPadding
        finalHeight = min(contentHeight, maxHeight)
    }

    private var dragHighlightedItem: View? = null
    private val dragHitRect = Rect()

    fun updateDragSelection(x: Float, y: Float) {
        val item = if (isAnimating || isDismissed || !isEnabled) null else findItem(x, y)
        if (item === dragHighlightedItem) return
        dragHighlightedItem?.isPressed = false
        dragHighlightedItem = item
        if (item == null) return
        item.drawableHotspotChanged(x - dragHitRect.left, y - dragHitRect.top)
        item.isPressed = true
        Haptics.play(this, HapticType.SELECTION)
    }

    fun endDragSelection(performAction: Boolean) {
        val item = dragHighlightedItem ?: return
        dragHighlightedItem = null
        item.isPressed = false
        if (performAction) item.performClick()
    }

    private fun findItem(x: Float, y: Float): View? = itemViews.firstOrNull { view ->
        view.hasOnClickListeners() && view.isShown &&
            view.getGlobalVisibleRect(dragHitRect) && dragHitRect.contains(x.toInt(), y.toInt())
    }

    fun getItemTop(index: Int): Int = itemYPositions[index] - scrollView.scrollY

    fun getItemHeight(index: Int): Int = itemHeights[index]

    fun limitHeight(height: Int) {
        maxHeight = min(maxHeight, height)
        finalHeight = min(contentHeight, maxHeight)
    }

    fun prepareForExpandingPresentation() {
        scrollView.scrollTo(0, 0)
        expandingBodySpring?.cancel()
        expandingBodySpring = null
        expandingBodyContainer?.apply {
            animate().cancel()
            setLayerType(View.LAYER_TYPE_NONE, null)
            alpha = 0f
            translationY = 8f.dp
        }
        itemViews.forEach { itemView ->
            itemView.visibility = VISIBLE
            itemView.alpha = 1f
            itemView.translationY = 0f
        }
        (itemViews.firstOrNull() as? WMenuPopupViewItem)
            ?.setSubmenuExpansionProgress(0f)
    }

    private fun setExpandingAppearanceProgress(progress: Float) {
        val safeProgress = progress.coerceIn(0f, 1f)
        expandingBodyContainer?.apply {
            alpha = (safeProgress * 1.25f).coerceAtMost(1f)
            translationY = (1f - safeProgress) * 8f.dp
        }
    }

    fun startExpandingAppearanceAnimation() {
        val bodyContainer = expandingBodyContainer ?: return
        expandingBodySpring?.cancel()
        bodyContainer.setLayerType(View.LAYER_TYPE_HARDWARE, null)
        val springAnimation = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(0f)
            setMinimumVisibleChange(0.001f)
            spring = SpringForce(1f).apply {
                stiffness = 700f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                setExpandingAppearanceProgress(value)
            }
        }
        springAnimation.addEndListener { animation, canceled, _, _ ->
            if (!canceled) {
                setExpandingAppearanceProgress(1f)
            }
            if (expandingBodySpring === animation) {
                expandingBodySpring = null
                bodyContainer.setLayerType(View.LAYER_TYPE_NONE, null)
            }
        }
        expandingBodySpring = springAnimation
        springAnimation.start()
    }

    fun finishExpandingAppearanceAnimation() {
        expandingBodySpring?.cancel()
        expandingBodySpring = null
        expandingBodyContainer?.setLayerType(View.LAYER_TYPE_NONE, null)
        setExpandingAppearanceProgress(1f)
    }

    fun setExpandingPresentationProgress(progress: Float, updateAppearance: Boolean = true) {
        val safeProgress = progress.coerceIn(0f, 1f)
        (itemViews.firstOrNull() as? WMenuPopupViewItem)
            ?.setSubmenuExpansionProgress(safeProgress)
        if (updateAppearance) {
            setExpandingAppearanceProgress(safeProgress)
        }
    }

    fun resetExpandingPresentationScroll() {
        finishExpandingAppearanceAnimation()
        scrollView.scrollTo(0, 0)
    }

    fun notifyWillDismiss() {
        onWillDismiss?.invoke()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        lastTouchRawY = event.rawY
        draggedIndex?.let { index ->
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> moveDraggedItem(index, event.rawY)
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> dropDraggedItem(index)
            }
            return true
        }
        if (event.actionMasked == MotionEvent.ACTION_DOWN) {
            // A menu taller than the window scrolls under the finger instead
            isSlideSelecting = isSlideSelectionEnabled && !isAnimating &&
                !scrollView.canScrollVertically(-1) && !scrollView.canScrollVertically(1)
        }
        if (!isSlideSelecting) return super.dispatchTouchEvent(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN ->
                activateItem(event.x, event.y, shouldPlayHaptic = false)

            MotionEvent.ACTION_MOVE ->
                activateItem(event.x, event.y, shouldPlayHaptic = true)

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isSlideSelecting = false
                endSelection(performAction = event.actionMasked == MotionEvent.ACTION_UP)
            }
        }
        return true
    }

    private fun activateItem(x: Float, y: Float, shouldPlayHaptic: Boolean) {
        val itemView = findItemView(x, y)
        if (itemView !== activeItemView) {
            activeItemView?.isPressed = false
            activeItemView = itemView
            if (itemView != null && shouldPlayHaptic) Haptics.play(this, HapticType.SELECTION)
        }
        holdItem(itemView, x, y)
        itemView ?: return
        updateItemBounds(itemView)
        itemView.drawableHotspotChanged(x - itemBounds.left, y - itemBounds.top)
        itemView.isPressed = true
    }

    // Only a finger resting on one item for the long-press time lifts it: moving off the item or
    // past the touch slop starts the wait again, so sliding across the items never lifts one
    private fun holdItem(itemView: WMenuPopupViewItem?, x: Float, y: Float) {
        if (!canReorder) return
        if (itemView != null && itemView === heldItemView &&
            abs(x - holdX) <= touchSlop && abs(y - holdY) <= touchSlop
        ) {
            return
        }
        removeCallbacks(liftHeldItem)
        heldItemView = itemView
        if (itemView == null) return
        holdX = x
        holdY = y
        postDelayed(liftHeldItem, ViewConfiguration.getLongPressTimeout().toLong())
    }

    private fun findItemView(x: Float, y: Float): WMenuPopupViewItem? {
        if (x < 0 || y < 0 || x >= width || y >= height) return null
        return itemViews.firstNotNullOfOrNull { itemView ->
            (itemView as? WMenuPopupViewItem)?.takeIf {
                it.isShown && it.isEnabled && updateItemBounds(it).contains(x.toInt(), y.toInt())
            }
        }
    }

    /** Sets `itemBounds` to [itemView]'s bounds in this view's coordinates and returns it */
    private fun updateItemBounds(itemView: View): Rect = itemBounds.apply {
        set(0, 0, itemView.width, itemView.height)
        offsetDescendantRectToMyCoords(itemView, this)
    }

    private fun endSelection(performAction: Boolean) {
        removeCallbacks(liftHeldItem)
        heldItemView = null
        val itemView = activeItemView ?: return
        activeItemView = null
        itemView.isPressed = false
        if (performAction) itemView.performClick()
    }

    fun present(
        initialHeight: Int,
        fromTop: Boolean,
        updateListener: ((fraction: Float) -> Unit)? = null,
        onPresented: (() -> Unit)? = null
    ) {
        presentFromTop = fromTop
        isAnimating = true
        pendingScrollY = calculateSelectedItemScrollY()
        measureChildren(MeasureSpec.UNSPECIFIED, MeasureSpec.UNSPECIFIED)
        finalTranslationY = (parent as? ViewGroup)?.translationY ?: 0f
        post {
            contentContainer.suppressLayoutCompat(true)
        }
        ValueAnimator.ofInt(0, 1).apply {
            val isFirstPresentation = initialHeight == 0
            duration = AnimationConstants.MENU_PRESENT
            addUpdateListener {
                updateListener?.invoke(animatedFraction)
                val easeVal = WInterpolator.easeOut(animatedFraction)
                currentHeight =
                    if (isFirstPresentation) (easeVal * finalHeight).roundToInt() else finalHeight
                val emphasizedVal = WInterpolator.emphasized.getInterpolation(animatedFraction)
                currentFrameHeight =
                    (initialHeight + (emphasizedVal * (finalHeight - initialHeight))).roundToInt()
                if (isFirstPresentation) (parent as? ViewGroup)?.alpha = easeVal
                onUpdate()
            }

            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    isAnimating = false

                    itemViews.forEach { itemView ->
                        itemView.visibility = VISIBLE
                        itemView.alpha = 1f
                        itemView.translationY = 0f
                    }
                    contentContainer.suppressLayoutCompat(false)
                    prepareExpandingSubmenus()
                    onPresented?.invoke()
                }
            })
            start()
        }
    }

    fun dismiss(updateListener: ((fraction: Float) -> Unit)? = null) {
        onWillDismiss?.invoke()
        val parentLayout = parent as? FrameLayout ?: return
        parentLayout.animate().setDuration(AnimationConstants.MENU_DISMISS)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .alpha(0f)
            .translationY(parentLayout.translationY - 8f.dp).apply {
                setUpdateListener {
                    updateListener?.invoke(it.animatedFraction)
                }
            }
            .withEndAction {
                isDismissed = true
                onDismiss()
            }
    }

    /** Centers a selected choice the menu's height leaves out of sight; null when it has none or shows it */
    private fun calculateSelectedItemScrollY(): Int? {
        val index = items.indexOfFirst { (it.config as? Config.SelectableItem)?.isSelected == true }
        if (index < 0 || itemYPositions[index] + itemHeights[index] <= finalHeight) return null
        val maxScrollY = (contentHeight - finalHeight).coerceAtLeast(0)
        val centeredScrollY = itemYPositions[index] - (finalHeight - itemHeights[index]) / 2
        return centeredScrollY.coerceIn(0, maxScrollY)
    }

    private fun onUpdate() {
        val additionalYOffset = if (presentFromTop) 0 else finalHeight - currentFrameHeight
        if (isAnimating) {
            // The items come in from the menu's edge as it opens, wherever it is scrolled to
            val scrollY = pendingScrollY ?: scrollView.scrollY
            for (i in itemViews.indices) {
                val itemView = itemViews[i]
                val itemTop = itemYPositions[i] - scrollY

                alpha = (currentHeight * 4f / finalHeight).coerceIn(0f, 1f)

                if (presentFromTop) {
                    if (itemTop < currentHeight) {
                        if (itemView.visibility != VISIBLE) itemView.visibility = VISIBLE
                        val itemVisibleFraction =
                            (currentHeight - itemTop) / (finalHeight - itemTop).toFloat()

                        itemView.alpha = itemVisibleFraction
                        if (i > 0 || items.size < 3) {
                            itemView.translationY =
                                -additionalYOffset - (1 - itemVisibleFraction) * 10.dp
                        }
                    }
                } else {
                    val itemBottom = itemTop + itemHeights[i]
                    val distanceFromBottom = finalHeight - itemBottom
                    if (currentHeight > distanceFromBottom) {
                        if (itemView.visibility != VISIBLE) itemView.visibility = VISIBLE
                        val itemVisibleFraction =
                            ((currentHeight - distanceFromBottom) / itemBottom.toFloat())
                                .coerceIn(0f, 1f)

                        itemView.alpha = itemVisibleFraction
                        if (i < items.size - 1 || items.size < 3) {
                            itemView.translationY =
                                -additionalYOffset + (1 - itemVisibleFraction) * 10.dp
                        } else {
                            itemView.translationY = -additionalYOffset.toFloat()
                        }
                    }
                }
            }
        } else {
            for (itemView in itemViews) {
                itemView.visibility = VISIBLE
                itemView.alpha = 1f
                itemView.translationY = 0f
            }
        }
        (parent as? ViewGroup)?.apply {
            if (additionalYOffset != 0) translationY = finalTranslationY + additionalYOffset
            updateLayoutParams {
                height = currentFrameHeight
            }
        }
    }

    override fun updateTheme() {
        itemViews.filterIsInstance<WThemedView>().forEach { it.updateTheme() }
    }

    private var lastTouchRawY = 0f

    override fun onDetachedFromWindow() {
        removeCallbacks(liftHeldItem)
        heldItemView = null
        super.onDetachedFromWindow()
    }

    private fun startDrag(index: Int) {
        if (draggedIndex != null || isAnimating) return
        draggedIndex = index
        dragStartRawY = lastTouchRawY
        dragStartTop = itemYPositions[index]
        // The item stops being pressed, and the list stops scrolling under the finger
        val cancel = MotionEvent.obtain(0, 0, MotionEvent.ACTION_CANCEL, 0f, 0f, 0)
        super.dispatchTouchEvent(cancel)
        cancel.recycle()
        parent?.requestDisallowInterceptTouchEvent(true)
        itemViews[index].apply {
            bringToFront()
            animate().cancel()
            animate().scaleX(LIFTED_SCALE).scaleY(LIFTED_SCALE).translationZ(8f.dp)
                .setDuration(AnimationConstants.QUICK_ANIMATION).start()
        }
    }

    private fun moveDraggedItem(index: Int, rawY: Float) {
        val position = itemOrder.indexOf(index)
        val minTop = verticalContentPadding
        val maxTop = contentHeight - verticalContentPadding - itemHeights[index]
        val top = (dragStartTop + rawY - dragStartRawY).coerceIn(minTop.toFloat(), maxTop.toFloat())
        val newPosition = findReorderPosition(
            rowTops = itemOrder.map { itemYPositions[it] },
            rowHeights = itemOrder.map { itemHeights[it] },
            position = position,
            top = top
        )
        if (newPosition != position) {
            val oldTops = itemYPositions.copyOf()
            itemOrder.removeAt(position)
            itemOrder.add(newPosition, index)
            updateItemPositions()
            itemViews.forEachIndexed { i, itemView ->
                val itemTop = itemYPositions[i]
                itemView.layout(0, itemTop, itemView.width, itemTop + itemHeights[i])
            }
            itemViews.forEachIndexed { i, itemView ->
                if (i == index || oldTops[i] == itemYPositions[i]) return@forEachIndexed
                itemView.translationY += oldTops[i] - itemYPositions[i]
                itemView.animate().translationY(0f).setDuration(AnimationConstants.QUICK_ANIMATION)
                    .setInterpolator(WInterpolator.emphasized).start()
            }
            performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            onReorder?.invoke(position, newPosition)
        }
        itemViews[index].translationY = top - itemYPositions[index]
    }

    private fun dropDraggedItem(index: Int) {
        draggedIndex = null
        itemViews[index].animate().scaleX(1f).scaleY(1f).translationZ(0f).translationY(0f)
            .setDuration(AnimationConstants.QUICK_ANIMATION)
            .setInterpolator(WInterpolator.emphasized)
            .start()
    }

    private fun updateItemPositions() {
        var top = verticalContentPadding
        itemOrder.forEach { index ->
            itemYPositions[index] = top
            top += itemHeights[index]
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)

        val width = when (widthMode) {
            MeasureSpec.EXACTLY -> widthSize

            else -> {
                contentContainer.measure(0.unspecified, contentHeight.exactly)
                val contentWidth = contentContainer.measuredWidth
                if (widthMode == MeasureSpec.AT_MOST) {
                    minOf(contentWidth + 16.dp, widthSize)
                } else {
                    contentWidth
                }
            }
        }

        val height = if (isAnimating) {
            currentFrameHeight
        } else {
            min(contentHeight, maxHeight)
        }

        scrollView.measure(width.exactly, height.exactly)

        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val scrollOffset = scrollView.scrollY
        scrollView.layout(0, 0, measuredWidth, measuredHeight)

        contentContainer.layout(0, 0, measuredWidth, contentHeight)

        val bodyTop = if (expandingBodyContainer != null && itemViews.size > 1) {
            itemYPositions[1]
        } else {
            verticalContentPadding + (itemHeights.firstOrNull() ?: 0)
        }
        expandingBodyContainer?.layout(
            0,
            bodyTop,
            measuredWidth,
            contentHeight - verticalContentPadding
        )

        for (i in itemViews.indices) {
            val child = itemViews[i]
            if (child.visibility != GONE) {
                val itemY = itemYPositions[i] - if (
                    expandingBodyContainer != null && i > 0
                ) {
                    bodyTop
                } else {
                    0
                }
                child.layout(0, itemY, measuredWidth, itemY + itemHeights[i])
            }
        }
        val scrollY = pendingScrollY ?: scrollOffset
        pendingScrollY = null
        if (scrollView.scrollY != scrollY) scrollView.scrollTo(0, scrollY)
    }
}

/**
 * The place a row dragged from [position] takes with its top at [top], among rows whose tops and
 * heights in their current order are [rowTops] and [rowHeights]. The row passes a neighbor once its
 * near edge crosses the neighbor's middle, so with its top held inside the list it still reaches
 * the first and the last place.
 */
internal fun findReorderPosition(
    rowTops: List<Int>,
    rowHeights: List<Int>,
    position: Int,
    top: Float
): Int {
    val bottom = top + rowHeights[position]
    var newPosition = position
    while (newPosition > 0 && top < rowTops[newPosition - 1] + rowHeights[newPosition - 1] / 2f) {
        newPosition--
    }
    while (newPosition < rowTops.lastIndex &&
        bottom > rowTops[newPosition + 1] + rowHeights[newPosition + 1] / 2f
    ) {
        newPosition++
    }
    return newPosition
}
