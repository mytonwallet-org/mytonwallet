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
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.Item.Config
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import kotlin.math.min
import kotlin.math.roundToInt


@SuppressLint("ViewConstructor")
class WMenuPopupView(
    context: Context,
    val items: List<WMenuPopup.Item>,
    private val onDismiss: () -> Unit
) : FrameLayout(context) {

    var popupWindow: WPopupWindow? = null
    private val itemViews = ArrayList<WMenuPopupViewItem>(items.size)
    private var currentHeight: Int = 0
    private var currentFrameHeight: Int = 0
    private val itemHeights: IntArray = IntArray(items.size)
    private val itemYPositions: IntArray = IntArray(items.size)
    private var isAnimating = false
    private var finalHeight = 0
    var isDismissed = false
    private val contentContainer: FrameLayout
    private val scrollView: ScrollView
    private var maxHeight: Int = 0

    init {
        id = generateViewId()

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
            val itemContentHeight =
                if (item.config == Config.Back)
                    44.dp
                else
                    if (item.getSubTitle().isNullOrEmpty())
                        48.dp
                    else
                        56.dp
            val itemHeight = itemContentHeight + if (item.hasSeparator) 7.dp else 0
            itemHeights[index] = itemHeight
            itemYPositions[index] = totalHeight
            totalHeight += itemHeight

            val itemView = WMenuPopupViewItem(context, item).apply {
                alpha = 0f
                visibility = INVISIBLE
            }.apply {
                setOnClickListener {
                    if (!item.getSubItems().isNullOrEmpty()) {
                        val window = popupWindow
                        window?.push(
                            WMenuPopupView(context, item.getSubItems()!!.toMutableList().apply {
                                add(0, WMenuPopup.Item(Config.Back, true))
                            }, onDismiss = {
                                popupWindow?.dismiss()
                            }).apply {
                                popupWindow = window
                            }
                        )
                        return@setOnClickListener
                    }
                    item.onTap?.invoke() ?: run {
                        // Back Button
                        if (index == 0) {
                            popupWindow?.pop()
                            return@setOnClickListener
                        }
                    }
                    dismiss()
                }
            }
            itemViews.add(itemView)
            contentContainer.addView(itemView, LayoutParams(WRAP_CONTENT, itemHeight))
        }
    }

    fun present(initialHeight: Int) {
        val isFirstPresentation = initialHeight == 0
        isAnimating = true
        measureChildren(MeasureSpec.UNSPECIFIED, MeasureSpec.UNSPECIFIED)
        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0
        finalHeight = min(totalHeight, maxHeight)
        ValueAnimator.ofInt(0, 1).apply {
            duration =
                if (isFirstPresentation) AnimationConstants.MENU_PRESENT else AnimationConstants.QUICK_ANIMATION
            addUpdateListener {
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
                }
            })
            start()
        }
    }

    fun dismiss() {
        (parent as FrameLayout).animate().setDuration(AnimationConstants.MENU_DISMISS)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .alpha(0f)
            .translationY((-8f).dp)
            .withEndAction {
                isDismissed = true
                onDismiss()
            }
    }

    private fun onUpdate() {
        if (isAnimating) {
            for (i in itemViews.indices) {
                val itemView = itemViews[i]
                val itemTop = itemYPositions[i]

                alpha = (currentHeight * 4f / finalHeight).coerceIn(0f, 1f)
                if (itemTop < currentHeight) {
                    if (itemView.visibility != VISIBLE)
                        itemView.visibility = VISIBLE
                    val itemVisibleFraction =
                        (currentHeight - itemTop) / (finalHeight - itemTop).toFloat()

                    itemView.alpha = itemVisibleFraction
                    if (i > 0 || items.size < 3)
                        itemView.translationY = -(1 - itemVisibleFraction) * 10.dp
                }
            }
        } else {
            for (itemView in itemViews) {
                itemView.visibility = VISIBLE
                itemView.alpha = 1f
                itemView.translationY = 0f
            }
        }
        (parent as? ViewGroup)?.updateLayoutParams {
            height = currentFrameHeight
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val totalHeight = itemYPositions.lastOrNull()?.plus(itemHeights.lastOrNull() ?: 0) ?: 0

        contentContainer.measure(
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED),
            MeasureSpec.makeMeasureSpec(totalHeight, MeasureSpec.EXACTLY)
        )

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

        scrollView.measure(
            MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)
        )

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
