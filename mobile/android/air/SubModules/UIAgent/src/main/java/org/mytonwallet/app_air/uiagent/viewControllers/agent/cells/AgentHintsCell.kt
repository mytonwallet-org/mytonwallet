package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.doOnPreDraw
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class AgentHintsCell(context: Context) :
    WCell(
        context,
        LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    ) {

    companion object {
        private const val CARD_SPACING = 12
        private const val EMPTY_STATE_ICON_SIZE = 48
        private const val EMPTY_STATE_ICON_EXTRA_SPACING = 4
    }

    // Cards appear/disappear in step with the height animation opening/closing their slot.
    private val cardStagger: Long
        get() = AnimationConstants.VERY_QUICK_ANIMATION / column.childCount.coerceAtLeast(1)

    var onHintTap: ((AgentHint) -> Unit)? = null

    // Reports each collapse frame's height shrink so the owner can adjust the list
    // padding in the same frame; a one-frame lag lets the layout manager pull the
    // content down to fill the gap.
    var onCollapseFrame: ((delta: Int) -> Unit)? = null

    private val column = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
        clipChildren = false
        clipToPadding = false
    }
    private val emptyStateIconView = AppCompatImageView(context).apply {
        setImageResource(org.mytonwallet.app_air.icons.R.drawable.ic_agent_hint)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private var renderedHints = listOf<AgentHint>()
    private var isEmptyStateIconRendered = false
    private var revealSpring: SpringAnimation? = null
    private var collapseSpring: SpringAnimation? = null
    private var collapseEnd: (() -> Unit)? = null
    private var expandSpring: SpringAnimation? = null
    private var expandEnd: (() -> Unit)? = null

    val isCollapsing: Boolean
        get() = collapseEnd != null

    // The animating cell is smaller than its content; let the cards overflow instead of
    // being clipped at the cell's bottom edge while the height catches up.
    private fun setListClipping(enabled: Boolean) {
        (parent as? ViewGroup)?.clipChildren = enabled
    }

    private var animatedHeight = -1
    private var naturalHeight = 0

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        naturalHeight = measuredHeight
        if (animatedHeight >= 0) {
            setMeasuredDimension(measuredWidth, animatedHeight)
        }
    }

    private fun setAnimatedHeight(value: Int) {
        if (animatedHeight != value) {
            animatedHeight = value
            requestLayout()
        }
    }

    private fun clearAnimatedHeight() {
        if (animatedHeight != -1) {
            animatedHeight = -1
            requestLayout()
        }
    }

    init {
        clipChildren = false
        clipToPadding = false
        addView(column, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(column, 16f)
            toBottom(column, 4f)
            toStart(column, 16f)
            toEnd(column, 16f)
            // Keep the column anchored to the top while the cell's height animates;
            // otherwise it gets centered and slides down as the cell expands.
            setVerticalBias(column.id, 0f)
        }
    }

    fun configure(hints: List<AgentHint>, shouldShowEmptyStateIcon: Boolean, animate: Boolean) {
        if ((collapseEnd != null || expandEnd != null) &&
            hints == renderedHints
        ) {
            // Mid-animation rebind (e.g. reloadData); let the running collapse/expand finish.
            return
        }
        if (hints != renderedHints || shouldShowEmptyStateIcon != isEmptyStateIconRendered) {
            renderedHints = hints
            isEmptyStateIconRendered = shouldShowEmptyStateIcon
            column.removeAllViews()
            if (shouldShowEmptyStateIcon) {
                column.addView(
                    emptyStateIconView,
                    LinearLayout.LayoutParams(
                        EMPTY_STATE_ICON_SIZE.dp,
                        EMPTY_STATE_ICON_SIZE.dp
                    ).apply {
                        bottomMargin = EMPTY_STATE_ICON_EXTRA_SPACING.dp
                    }
                )
            }
            for (hint in hints) {
                val card = WAgentHintView(context, hint.title) { onHintTap?.invoke(hint) }
                val lp = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (column.childCount > 0) topMargin = CARD_SPACING.dp
                }
                column.addView(card, lp)
            }
        } else {
            updateTheme()
        }
        cancelAnimations()
        if (animate && WGlobalStorage.getAreAnimationsActive()) {
            startReveal()
        } else {
            resetPresentation()
        }
    }

    fun updateTheme() {
        for (i in 0 until column.childCount) {
            (column.getChildAt(i) as? WAgentHintView)?.updateTheme()
        }
    }

    fun collapse(onEnd: () -> Unit) {
        cancelAnimations()
        if (!WGlobalStorage.getAreAnimationsActive() || height <= 0) {
            if (height > 0) onCollapseFrame?.invoke(height)
            onEnd()
            return
        }
        collapseEnd = onEnd
        setListClipping(false)
        // Reverse of the reveal: cards fade back down, bottom-up.
        val count = column.childCount
        for (i in 0 until count) {
            column.getChildAt(i).animate()
                .alpha(0f)
                .translationY(8f.dp)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setStartDelay((count - 1 - i) * cardStagger)
                .setInterpolator(AccelerateDecelerateInterpolator())
                .start()
        }
        // Same spring as the pinned-message scroll so both play in sync.
        var lastValue = height
        collapseSpring = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(lastValue.toFloat())
            spring = SpringForce(1f).apply {
                stiffness = SpringForce.STIFFNESS_LOW
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val newHeight = value.roundToInt().coerceAtLeast(1)
                if (newHeight != lastValue) {
                    val delta = lastValue - newHeight
                    lastValue = newHeight
                    setAnimatedHeight(newHeight)
                    if (delta > 0) onCollapseFrame?.invoke(delta)
                }
            }
            addEndListener { _, canceled, _, _ ->
                collapseSpring = null
                setListClipping(true)
                val callback = collapseEnd
                collapseEnd = null
                if (!canceled) {
                    onCollapseFrame?.invoke(lastValue)
                    callback?.invoke()
                }
            }
            start()
        }
    }

    // Reverses a running collapse: cards fade back in and the height springs from
    // wherever it currently is to the natural size.
    fun expand(onEnd: () -> Unit) {
        cancelAnimations()
        if (!WGlobalStorage.getAreAnimationsActive()) {
            resetPresentation()
            onEnd()
            return
        }
        expandEnd = onEnd
        setListClipping(false)
        for (i in 0 until column.childCount) {
            column.getChildAt(i).animate()
                .alpha(1f)
                .translationY(0f)
                .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                .setStartDelay(i * cardStagger)
                .setInterpolator(AccelerateDecelerateInterpolator())
                .start()
        }
        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        // measuredHeight reports animatedHeight while animating; the natural size is
        // captured by onMeasure during the measure call above.
        val targetHeight = naturalHeight
        if (targetHeight <= 0) {
            resetPresentation()
            expandEnd = null
            onEnd()
            return
        }
        var lastValue = height
        expandSpring = SpringAnimation(FloatValueHolder()).apply {
            setStartValue(lastValue.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = SpringForce.STIFFNESS_LOW
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                val newHeight = value.roundToInt()
                if (newHeight != lastValue) {
                    lastValue = newHeight
                    setAnimatedHeight(newHeight)
                }
            }
            addEndListener { _, canceled, _, _ ->
                expandSpring = null
                setListClipping(true)
                val callback = expandEnd
                expandEnd = null
                if (!canceled) {
                    clearAnimatedHeight()
                    callback?.invoke()
                }
            }
            start()
        }
    }

    private fun cancelAnimations() {
        collapseEnd = null
        expandEnd = null
        setListClipping(true)
        revealSpring?.cancel()
        revealSpring = null
        collapseSpring?.cancel()
        collapseSpring = null
        expandSpring?.cancel()
        expandSpring = null
        for (i in 0 until column.childCount) {
            column.getChildAt(i).animate().cancel()
        }
    }

    private fun resetPresentation() {
        for (i in 0 until column.childCount) {
            column.getChildAt(i).apply {
                alpha = 1f
                translationY = 0f
            }
        }
        clearAnimatedHeight()
    }

    private fun startReveal() {
        for (i in 0 until column.childCount) {
            column.getChildAt(i).apply {
                alpha = 0f
                translationY = 8f.dp
            }
        }
        setAnimatedHeight(1)
        doOnPreDraw {
            measure(
                MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
            )
            // measuredHeight reports animatedHeight while animating; the natural size is
            // captured by onMeasure during the measure call above.
            val targetHeight = naturalHeight
            if (targetHeight <= 0) {
                resetPresentation()
                return@doOnPreDraw
            }
            setListClipping(false)
            val count = column.childCount
            val totalMs = (
                (count - 1).coerceAtLeast(0) * cardStagger +
                    AnimationConstants.VERY_QUICK_ANIMATION
                ).toFloat()
            val window = AnimationConstants.VERY_QUICK_ANIMATION / totalMs
            val stagger = cardStagger / totalMs
            revealSpring = SpringAnimation(FloatValueHolder()).apply {
                setStartValue(1f)
                spring = SpringForce(targetHeight.toFloat()).apply {
                    stiffness = SpringForce.STIFFNESS_LOW
                    dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                }
                addUpdateListener { _, value, _ ->
                    val newHeight = value.roundToInt().coerceIn(1, targetHeight)
                    setAnimatedHeight(newHeight)
                    val progress = (newHeight - 1f) / (targetHeight - 1).coerceAtLeast(1)
                    for (i in 0 until count) {
                        val local = ((progress - i * stagger) / window).coerceIn(0f, 1f)
                        column.getChildAt(i).apply {
                            alpha = local
                            translationY = 8f.dp * (1f - local)
                        }
                    }
                }
                addEndListener { _, canceled, _, _ ->
                    revealSpring = null
                    setListClipping(true)
                    if (!canceled) resetPresentation()
                }
                start()
            }
        }
    }
}
