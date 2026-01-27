package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ScrollView
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.suppressLayoutCompat
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import kotlin.math.min
import kotlin.math.roundToInt


@SuppressLint("ViewConstructor")
class WMenuPopupView(
    context: Context,
    val items: List<WMenuPopup.Item>,
    private val onWillDismiss: (() -> Unit)?,
    private val onDismiss: () -> Unit,
) : WFrameLayout(context), WThemedView {

    var popupWindow: INavigationPopup? = null
    private val itemViews = ArrayList<FrameLayout>(items.size)
    private var currentHeight: Int = 0
    private var currentFrameHeight: Int = 0
    private val itemHeights: IntArray = IntArray(items.size)
    private val itemYPositions: IntArray = IntArray(items.size)
    private var isAnimating = false
    private var presentFromTop = true
    private var finalTranslationY = 0f
    var finalHeight = 0
        private set
    var isDismissed = false
    private val contentContainer: FrameLayout
    private val scrollView: ScrollView
    private var maxHeight: Int = 0

    init {
        val displayMetrics = context.resources.displayMetrics
        maxHeight = displayMetrics.heightPixels - 100.dp

        scrollView = ScrollView(context).apply {
            isVerticalScrollBarEnabled = false
            scrollBarStyle = SCROLLBARS_INSIDE_OVERLAY
        }
        contentContainer = FrameLayout(context)
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
                    if (item.config == Config.Back)
                        44.dp
                    else
                        if (item.getSubTitle().isNullOrEmpty())
                            48.dp
                        else
                            56.dp
                itemHeight = itemContentHeight + if (item.hasSeparator) 7.dp else 0

                itemView = WMenuPopupViewItem(context, item).apply {
                    alpha = 0f
                    visibility = INVISIBLE
                }.apply {
                    setOnClickListener {
                        if (!item.getSubItems().isNullOrEmpty()) {
                            val window = popupWindow
                            window?.push(
                                WMenuPopupView(
                                    context, item.getSubItems()!!.toMutableList().apply {
                                        add(0, WMenuPopup.Item(Config.Back, true))
                                    }, onWillDismiss = {
                                        onWillDismiss?.invoke()
                                    },
                                    onDismiss = {
                                        popupWindow?.dismiss()
                                    }).apply {
                                    popupWindow = window
                                }
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
            contentContainer.addView(itemView, LayoutParams(WRAP_CONTENT, itemHeight))
        }
        finalHeight = min(totalHeight, maxHeight)
    }

    fun present(initialHeight: Int, fromTop: Boolean, updateListener: ((fraction: Float) -> Unit)? = null) {
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
                    if (isFirstPresentation)
                        (easeVal * finalHeight).roundToInt()
                    else
                        finalHeight
                val emphasizedVal = WInterpolator.emphasized.getInterpolation(animatedFraction)
                currentFrameHeight =
                    (initialHeight + (emphasizedVal * (finalHeight - initialHeight))).roundToInt()
                if (isFirstPresentation)
                    (parent as? ViewGroup)?.alpha = easeVal
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
                        if (itemView.visibility != VISIBLE)
                            itemView.visibility = VISIBLE
                        val itemVisibleFraction =
                            (currentHeight - itemTop) / (finalHeight - itemTop).toFloat()

                        itemView.alpha = itemVisibleFraction
                        if (i > 0 || items.size < 3)
                            itemView.translationY =
                                -additionalYOffset - (1 - itemVisibleFraction) * 10.dp
                    }
                } else {
                    val itemBottom = itemTop + itemHeights[i]
                    val distanceFromBottom = finalHeight - itemBottom
                    if (currentHeight > distanceFromBottom) {
                        if (itemView.visibility != VISIBLE)
                            itemView.visibility = VISIBLE
                        val itemVisibleFraction =
                            ((currentHeight - distanceFromBottom) / itemBottom.toFloat())
                                .coerceIn(0f, 1f)

                        itemView.alpha = itemVisibleFraction
                        if (i < items.size - 1 || items.size < 3)
                            itemView.translationY =
                                -additionalYOffset + (1 - itemVisibleFraction) * 10.dp
                        else
                            itemView.translationY = -additionalYOffset.toFloat()
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
            if (additionalYOffset != 0)
                translationY = finalTranslationY + additionalYOffset
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

        contentContainer.measure(0.unspecified, totalHeight.exactly)

        val contentWidth = contentContainer.measuredWidth
        val widthMode = MeasureSpec.getMode(widthMeasureSpec)
        val widthSize = MeasureSpec.getSize(widthMeasureSpec)

        val width = when (widthMode) {
            MeasureSpec.EXACTLY -> widthSize
            MeasureSpec.AT_MOST -> minOf(contentWidth + 16.dp, widthSize)
            else -> contentWidth
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
        scrollView.layout(0, 0, measuredWidth, measuredHeight)

        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0
        contentContainer.layout(0, 0, measuredWidth, totalHeight)

        for (i in 0 until contentContainer.childCount) {
            val child = contentContainer.getChildAt(i)
            if (child.visibility != GONE) {
                val itemY = itemYPositions[i]
                child.layout(0, itemY, measuredWidth, itemY + itemHeights[i])
            }
        }
    }
}
