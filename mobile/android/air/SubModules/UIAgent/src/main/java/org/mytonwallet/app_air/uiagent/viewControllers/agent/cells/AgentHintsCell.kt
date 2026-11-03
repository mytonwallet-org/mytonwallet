package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.LinearLayout
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.doOnPreDraw
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSpinningTopView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
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

        // The Agent's chips, as the Android design has them
        private const val CHIP_HORIZONTAL_PADDING = 14
        private const val CHIP_BORDER_WIDTH = 0.6f
        private const val EMPTY_STATE_ICON_SIZE = 48
        private const val EMPTY_STATE_ICON_EXTRA_SPACING = 4
        private const val EMPTY_STATE_ICON_SPEED = 0.5f
        private const val EMPTY_STATE_TOP = 16
        private const val COLUMN_START = 18

        // With the answer's own 6 dp, the first suggestion hangs 12 dp under it
        private const val FOLLOWUPS_TOP = 6
        private const val FOLLOWUPS_BOTTOM = 6
        private const val FOLLOWUP_REVEAL_STAGGER_MS = 150L
    }

    // Cards appear/disappear in step with the height animation opening/closing their slot.
    private val cardStagger: Long
        get() = AnimationConstants.VERY_QUICK_ANIMATION / column.childCount.coerceAtLeast(1)

    private val revealStagger: Long
        get() = if (areFollowupsRendered) FOLLOWUP_REVEAL_STAGGER_MS else cardStagger

    var onHintTap: ((AgentHint) -> Unit)? = null

    // Reports each collapse frame's height shrink so the owner can adjust the list
    // padding in the same frame; a one-frame lag lets the layout manager pull the
    // content down to fill the gap.
    var onCollapseFrame: ((delta: Int) -> Unit)? = null

    private val column = LinearLayout(context).apply {
        id = UIComponentsR.id.agent_suggestions
        orientation = LinearLayout.VERTICAL
        clipChildren = false
        clipToPadding = false
    }

    // The empty chat's spinning top turns at half speed over its suggestions
    private val emptyStateIconView = AgentSpinningTopView(context, speed = EMPTY_STATE_ICON_SPEED)
        .apply { isTouchInteractive = true }

    /** What the grown top sees behind it, where the suggestions aren't in a list */
    var backdropSource: View?
        get() = emptyStateIconView.backdropSource
        set(value) {
            emptyStateIconView.backdropSource = value
        }

    private var renderedHints = listOf<AgentHint>()
    private var isLoadingRendered = false
    private var loadingRevealCompletedAt: Long? = null

    private fun showLoading() {
        if (isLoadingRendered) return
        cancelAnimations()
        renderedHints = emptyList()
        isLoadingRendered = true
        areFollowupsRendered = true
        isEmptyStateIconRendered = false
        column.removeAllViews()
        setConstraints {
            toTop(column, FOLLOWUPS_TOP.toFloat())
            toBottom(column, FOLLOWUPS_BOTTOM.toFloat())
        }
        for ((index, width) in listOf(230, 270, 200).withIndex()) {
            val placeholder = AgentMessagesSkeletonView(
                context,
                AgentMessagesSkeletonView.Style.SUGGESTION
            ).apply {
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            column.addView(
                placeholder,
                LinearLayout.LayoutParams(width.dp, 40.dp).apply {
                    if (index > 0) topMargin = CARD_SPACING.dp
                }
            )
        }
    }

    override fun onDetachedFromWindow() {
        cancelAnimations()
        resetPresentation()
        super.onDetachedFromWindow()
    }
    private var isEmptyStateIconRendered = false
    private var areFollowupsRendered = false
    private var revealSpring: SpringAnimation? = null
    private var collapseSpring: SpringAnimation? = null
    private var collapseEnd: (() -> Unit)? = null
    private var expandSpring: SpringAnimation? = null
    private var expandEnd: (() -> Unit)? = null
    private var revealPreDrawListener: OneShotPreDrawListener? = null
    private val loadingOverlays = mutableListOf<Pair<View, View>>()

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
            toTop(column, EMPTY_STATE_TOP.toFloat())
            toBottom(column, 4f)
            toStart(column, COLUMN_START.toFloat())
            toEnd(column, 16f)
            // Keep the column anchored to the top while the cell's height animates;
            // otherwise it gets centered and slides down as the cell expands.
            setVerticalBias(column.id, 0f)
        }
    }

    /**
     * Shows the empty chat's suggestions under its spinning top, or the suggestions under an answer
     * ([areFollowups]), which hang 12 dp under it and lead with a reply arrow
     */
    fun configure(
        hints: List<AgentHint>,
        shouldShowEmptyStateIcon: Boolean,
        shouldAnimate: Boolean,
        areFollowups: Boolean = false,
        isLoading: Boolean = false
    ) {
        if (isLoading) {
            showLoading()
            return
        }
        val loadingPlaceholders = if (isLoadingRendered) {
            (0 until column.childCount).map(column::getChildAt)
        } else {
            emptyList()
        }
        val wasLoading = isLoadingRendered
        val loadingAlreadyRevealed = loadingRevealCompletedAt?.let {
            SystemClock.uptimeMillis() >= it
        } == true
        isLoadingRendered = false
        val hasChanged = wasLoading || hints != renderedHints ||
            shouldShowEmptyStateIcon != isEmptyStateIconRendered ||
            areFollowups != areFollowupsRendered
        if (!hasChanged && !shouldAnimate) {
            updateTheme()
            return
        }
        if ((collapseEnd != null || expandEnd != null) &&
            hints == renderedHints
        ) {
            // Mid-animation rebind (e.g. reloadData); let the running collapse/expand finish.
            return
        }
        // Stop callbacks that still reference the current children before replacing them.
        cancelAnimations()
        if (hasChanged) {
            renderedHints = hints
            isEmptyStateIconRendered = shouldShowEmptyStateIcon
            areFollowupsRendered = areFollowups
            setConstraints {
                toTop(column, (if (areFollowups) FOLLOWUPS_TOP else EMPTY_STATE_TOP).toFloat())
                toBottom(column, if (areFollowups) FOLLOWUPS_BOTTOM.toFloat() else 4f)
            }
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
                val card = WAgentHintView(
                    context,
                    hint.title,
                    contentHorizontalPadding = CHIP_HORIZONTAL_PADDING.dp,
                    borderWidth = CHIP_BORDER_WIDTH.dp,
                    showsIcon = areFollowups
                ) { onHintTap?.invoke(hint) }.apply {
                    contentDescription = hint.title
                    importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
                    accessibilityDelegate = object : AccessibilityDelegate() {
                        override fun onInitializeAccessibilityNodeInfo(
                            host: View,
                            info: AccessibilityNodeInfo
                        ) {
                            super.onInitializeAccessibilityNodeInfo(host, info)
                            info.className = android.widget.Button::class.java.name
                        }
                    }
                }
                for (childIndex in 0 until card.childCount) {
                    card.getChildAt(childIndex).importantForAccessibility =
                        IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                }
                val lp = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (column.childCount > 0) topMargin = CARD_SPACING.dp
                }
                column.addView(card, lp)
            }
        } else {
            updateTheme()
        }
        if (wasLoading && WGlobalStorage.getAreAnimationsActive()) {
            resetPresentation()
            revealPreDrawListener = column.doOnPreDraw {
                revealPreDrawListener = null
                for (index in 0 until minOf(column.childCount, loadingPlaceholders.size)) {
                    val card = column.getChildAt(index)
                    val placeholder = loadingPlaceholders[index]
                    card.pivotX = 0f
                    card.pivotY = 0f
                    card.scaleX = placeholder.width.toFloat() / card.width.coerceAtLeast(1)
                    card.scaleY = placeholder.height.toFloat() / card.height.coerceAtLeast(1)
                    placeholder.layout(0, 0, card.width, card.height)
                    (card as ViewGroup).overlay.add(placeholder)
                    loadingOverlays.add(card to placeholder)
                    card.animate().scaleX(1f).scaleY(1f).setStartDelay(0).setDuration(300).start()
                    placeholder.animate().alpha(0f)
                        .setStartDelay(if (loadingAlreadyRevealed) 0 else index * revealStagger)
                        .setDuration(300)
                        .withEndAction {
                            card.overlay.remove(placeholder)
                            loadingOverlays.remove(card to placeholder)
                        }
                        .start()
                }
            }
        } else if (shouldAnimate && WGlobalStorage.getAreAnimationsActive()) {
            startReveal()
        } else {
            resetPresentation()
        }
    }

    fun updateTheme() {
        for (i in 0 until column.childCount) {
            when (val child = column.getChildAt(i)) {
                is WAgentHintView -> child.updateTheme()
                is AgentMessagesSkeletonView -> child.updateTheme()
            }
        }
    }

    fun setCardsEnabled(enabled: Boolean) {
        for (i in 0 until column.childCount) {
            (column.getChildAt(i) as? WAgentHintView)?.apply {
                isEnabled = enabled
                isClickable = enabled
            }
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
        loadingRevealCompletedAt = null
        // Hand back the pending completions before dropping them: callers such as the hints
        // dismissal own state that is only released by these callbacks.
        val pendingCollapseEnd = collapseEnd
        val pendingExpandEnd = expandEnd
        collapseEnd = null
        expandEnd = null
        setListClipping(true)
        revealPreDrawListener?.removeListener()
        revealPreDrawListener = null
        loadingOverlays.forEach { (card, placeholder) ->
            placeholder.animate().cancel()
            (card as ViewGroup).overlay.remove(placeholder)
        }
        loadingOverlays.clear()
        revealSpring?.cancel()
        revealSpring = null
        collapseSpring?.cancel()
        collapseSpring = null
        expandSpring?.cancel()
        expandSpring = null
        for (i in 0 until column.childCount) {
            column.getChildAt(i).animate().cancel()
        }
        if (pendingCollapseEnd != null || pendingExpandEnd != null) {
            // Deferred: cancelAnimations() runs during configure(), and these callbacks mutate
            // the adapter, which is illegal while the cell is being bound.
            post {
                pendingCollapseEnd?.invoke()
                pendingExpandEnd?.invoke()
            }
        }
    }

    fun reveal(delay: Long = 0) {
        cancelAnimations()
        resetPresentation()
        if (!WGlobalStorage.getAreAnimationsActive()) return
        if (isLoadingRendered) {
            loadingRevealCompletedAt = SystemClock.uptimeMillis() + delay +
                (column.childCount - 1).coerceAtLeast(0) * revealStagger +
                AnimationConstants.VERY_QUICK_ANIMATION
        }
        for (i in 0 until column.childCount) {
            column.getChildAt(i).apply {
                alpha = 0f
                translationY = 8f.dp
                animate().alpha(1f).translationY(0f)
                    .setStartDelay(delay + i * revealStagger)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .start()
            }
        }
    }

    private fun resetPresentation() {
        for (i in 0 until column.childCount) {
            column.getChildAt(i).apply {
                alpha = 1f
                translationY = 0f
                scaleX = 1f
                scaleY = 1f
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
        revealPreDrawListener = doOnPreDraw {
            revealPreDrawListener = null
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
            val revealedViews = (0 until column.childCount).mapNotNull { column.getChildAt(it) }
            if (areFollowupsRendered) {
                revealedViews.forEachIndexed { index, card ->
                    card.animate().alpha(1f).translationY(0f)
                        .setStartDelay(index * revealStagger)
                        .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                        .start()
                }
            }
            val count = revealedViews.size
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
                    for (i in 0 until if (areFollowupsRendered) 0 else count) {
                        val local = ((progress - i * stagger) / window).coerceIn(0f, 1f)
                        revealedViews[i].apply {
                            alpha = local
                            translationY = 8f.dp * (1f - local)
                        }
                    }
                }
                addEndListener { _, canceled, _, _ ->
                    revealSpring = null
                    setListClipping(true)
                    if (!canceled) {
                        if (areFollowupsRendered) clearAnimatedHeight() else resetPresentation()
                    }
                }
                start()
            }
        }
    }
}
