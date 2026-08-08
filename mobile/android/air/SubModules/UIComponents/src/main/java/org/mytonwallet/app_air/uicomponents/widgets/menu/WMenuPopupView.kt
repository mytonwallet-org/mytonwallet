package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ScrollView
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.atMost
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.suppressLayoutCompat
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
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
    private val hasExpandingHeader: Boolean = false
) : WFrameLayout(context),
    WThemedView {

    companion object {
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
    private val scrollView: ScrollView
    private val expandingBodyContainer = if (hasExpandingHeader) FrameLayout(context) else null
    private var expandingBodySpring: SpringAnimation? = null
    private var maxHeight: Int = 0

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
            hasExpandingHeader = transition == WMenuPopup.SubmenuTransition.EXPAND_FROM_ITEM
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

        var totalHeight = 0
        items.forEachIndexed { index, item ->
            var itemHeight: Int
            var itemView: FrameLayout
            if (item.config is Config.CustomView) {
                itemView = item.config.customView.apply {
                    alpha = 0f
                    visibility = INVISIBLE
                }
                itemHeight = (56 + if (item.hasSeparator) 7 else 0).dp
            } else {
                val itemContentHeight =
                    if (item.config == Config.Back) {
                        44.dp
                    } else {
                        if (item.getSubTitle().isNullOrEmpty()) 48.dp else 52.dp
                    }
                itemHeight = itemContentHeight + if (item.hasSeparator) 7.dp else 0

                itemView = WMenuPopupViewItem(context, item).apply {
                    alpha = 0f
                    visibility = INVISIBLE
                }.apply {
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
                        }
                        popupWindow?.dismiss()
                    }
                }
            }
            itemHeights[index] = itemHeight
            itemYPositions[index] = totalHeight
            totalHeight += itemHeight
            itemViews.add(itemView)
            val itemParent = if (hasExpandingHeader && index > 0) {
                expandingBodyContainer!!
            } else {
                contentContainer
            }
            itemParent.addView(itemView, LayoutParams(WRAP_CONTENT, itemHeight))
        }
        expandingBodyContainer?.updateLayoutParams {
            height = (totalHeight - (itemHeights.firstOrNull() ?: 0)).coerceAtLeast(0)
        }
        finalHeight = min(totalHeight, maxHeight)
    }

    fun getItemTop(index: Int): Int = itemYPositions[index] - scrollView.scrollY

    fun getItemHeight(index: Int): Int = itemHeights[index]

    fun limitHeight(height: Int) {
        maxHeight = min(maxHeight, height)
        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0
        finalHeight = min(totalHeight, maxHeight)
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

    fun present(
        initialHeight: Int,
        fromTop: Boolean,
        updateListener: ((fraction: Float) -> Unit)? = null
    ) {
        presentFromTop = fromTop
        isAnimating = true
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

    private fun onUpdate() {
        val additionalYOffset = if (presentFromTop) 0 else finalHeight - currentFrameHeight
        if (isAnimating) {
            for (i in itemViews.indices) {
                val itemView = itemViews[i]
                val itemTop = itemYPositions[i]

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

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0

        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)

        val width = when (widthMode) {
            MeasureSpec.EXACTLY -> widthSize

            else -> {
                contentContainer.measure(0.unspecified, totalHeight.exactly)
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
            min(totalHeight, maxHeight)
        }

        scrollView.measure(width.exactly, height.exactly)

        setMeasuredDimension(width, height)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val scrollOffset = scrollView.scrollY
        scrollView.layout(0, 0, measuredWidth, measuredHeight)

        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0
        contentContainer.layout(0, 0, measuredWidth, totalHeight)

        val bodyTop = if (expandingBodyContainer != null && itemViews.size > 1) {
            itemYPositions[1]
        } else {
            itemHeights.firstOrNull() ?: 0
        }
        expandingBodyContainer?.layout(0, bodyTop, measuredWidth, totalHeight)

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
        if (scrollView.scrollY != scrollOffset) scrollView.scrollTo(0, scrollOffset)
    }
}
