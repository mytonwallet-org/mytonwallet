package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.animation.Animator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.PathInterpolator
import android.widget.LinearLayout
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.doOnPreDraw
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_SUPPORT_HINT_ID
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBlurTransition
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSpinningTopView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
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

        // The suggestions under an answer come in one after another, each out of a blur as it rises
        // 8 dp into place
        internal const val FOLLOWUP_REVEAL_MS = 300L
        private const val FOLLOWUP_REVEAL_STAGGER_MS = 150L
        private const val FOLLOWUP_REVEAL_OFFSET = 8f

        // Core Animation's ease-out, on which iOS brings the suggestions in
        private val FOLLOWUP_REVEAL_CURVE = PathInterpolator(0f, 0f, 0.58f, 1f)

        // The row opens on iOS's list scroll spring, critically damped, on which a list resting on its end there
        // scrolls the suggestions into view
        private const val FOLLOWUP_OPENING_STIFFNESS = 555.027f

        // In dp, iOS's placeholder pills
        private val PLACEHOLDER_WIDTHS = intArrayOf(230, 270, 200)
        private const val PLACEHOLDER_HEIGHT = 40

        // As on iOS, a suggestion's title comes in 140 ms after its placeholder starts to resize to it
        private const val CONTENT_REVEAL_DELAY_MS = 140L
    }

    // Cards appear/disappear in step with the height animation opening/closing their slot.
    private val cardStagger: Long
        get() = AnimationConstants.VERY_QUICK_ANIMATION / column.childCount.coerceAtLeast(1)

    private val revealStagger: Long
        get() = if (areFollowupsRendered) FOLLOWUP_REVEAL_STAGGER_MS else cardStagger

    // Debug builds show the cards at once while system animations are off, to keep E2E runs fast
    private val canReveal: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (!DEBUG_MODE || areSystemAnimatorsEnabled)

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    /** Called with the hint tapped and its card */
    var onHintTap: ((AgentHint, WAgentHintView) -> Unit)? = null

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

    // The empty chat's spinning top turns at half speed over its suggestions, standing on the ground
    private val emptyStateIconView = AgentSpinningTopView(
        context,
        speed = EMPTY_STATE_ICON_SPEED,
        showsGround = true
    ).apply { isTouchInteractive = true }

    /** What the grown top sees behind it, where the suggestions aren't in a list */
    var backdropSource: View?
        get() = emptyStateIconView.backdropSource
        set(value) {
            emptyStateIconView.backdropSource = value
        }

    private var renderedHints = listOf<AgentHint>()
    private var areCardsEnabled = true

    // Contact Support, the client's own suggestion after the server's, with its own availability
    private var supportCard: WAgentHintView? = null

    /** Whether Contact Support takes taps; it shows dimmed while it doesn't */
    var isSupportHintEnabled = true
        set(value) {
            if (field == value) return
            field = value
            supportCard?.let(::applySupportCardState)
        }
    private val followupReveals = mutableMapOf<View, Animator>()

    /** What the row shows: the cards, with the empty chat's spinning top or the placeholders */
    val contentViews: List<View>
        get() = (0 until column.childCount).map(column::getChildAt)

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
        for ((index, width) in PLACEHOLDER_WIDTHS.withIndex()) {
            // The pill a suggestion has, which turns into the suggestion once it comes
            val placeholder = makeCard("", showsIcon = true) {}.apply {
                isPlaceholder = true
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            }
            column.addView(
                placeholder,
                LinearLayout.LayoutParams(width.dp, PLACEHOLDER_HEIGHT.dp).apply {
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

    val isCollapsing: Boolean
        get() = collapseEnd != null

    // Whether the row is opening its space, or is about to on the next frame
    private val isOpening: Boolean
        get() = revealPreDrawListener != null || revealSpring != null

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
            val isComingIn = !isLoadingRendered
            showLoading()
            // Placeholders that come in late come in as the suggestions do, one by one out of a blur
            if (isComingIn && shouldAnimate && canReveal) {
                loadingRevealCompletedAt = computeRevealEnd(delay = 0)
                startReveal()
            }
            return
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
        // The placeholders turn into the suggestions in place, so their borders keep turning
        val shouldTurnPlaceholdersIntoHints = hasChanged && wasLoading && areFollowups &&
            !shouldShowEmptyStateIcon && WGlobalStorage.getAreAnimationsActive()
        val placeholders = if (shouldTurnPlaceholdersIntoHints) {
            (0 until minOf(column.childCount, hints.size))
                .mapNotNull { column.getChildAt(it) as? WAgentHintView }
        } else {
            emptyList()
        }
        val previousHeight = height
        // Stop callbacks that still reference the current children before replacing them. A row still opening its
        // space goes on opening as its placeholders turn into the suggestions, and they go on coming in.
        cancelAnimations(shouldKeepOpening = placeholders.isNotEmpty(), keptReveals = placeholders)
        if (hasChanged) {
            renderedHints = hints
            isEmptyStateIconRendered = shouldShowEmptyStateIcon
            areFollowupsRendered = areFollowups
            setConstraints {
                toTop(column, (if (areFollowups) FOLLOWUPS_TOP else EMPTY_STATE_TOP).toFloat())
                toBottom(column, if (areFollowups) FOLLOWUPS_BOTTOM.toFloat() else 4f)
            }
            for (index in column.childCount - 1 downTo placeholders.size) column.removeViewAt(index)
            supportCard = null
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
            for ((index, hint) in hints.withIndex()) {
                val placeholder = placeholders.getOrNull(index)
                if (placeholder != null) {
                    // Only the title comes in, after the placeholder's own entrance, and the pill resizes to it
                    placeholder.setOnClickListener { onHintTap?.invoke(hint, placeholder) }
                    makeAccessible(placeholder, hint)
                    placeholder.updateLayoutParams<LinearLayout.LayoutParams> {
                        width = WRAP_CONTENT
                        height = WRAP_CONTENT
                    }
                    val stagger = if (loadingAlreadyRevealed) 0L else index * revealStagger
                    placeholder.revealContent(hint.title, CONTENT_REVEAL_DELAY_MS + stagger)
                    continue
                }
                lateinit var card: WAgentHintView
                val isSupportHint = hint.id == AGENT_SUPPORT_HINT_ID
                card = makeCard(
                    hint.title,
                    showsIcon = areFollowups,
                    leadingIconResId = R.drawable.ic_agent_support.takeIf { isSupportHint }
                ) {
                    onHintTap?.invoke(hint, card)
                }
                makeAccessible(card, hint)
                if (isSupportHint) {
                    card.id = UIComponentsR.id.agent_support_hint
                    supportCard = card
                    applySupportCardState(card)
                }
                val lp = LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    if (column.childCount > 0) topMargin = CARD_SPACING.dp
                }
                column.addView(card, lp)
            }
            if (placeholders.isNotEmpty()) {
                // The row takes the suggestions' height on the spring it opens on rather than at once, so that a list
                // resting on its end moves with it
                when {
                    isOpening -> Unit
                    canReveal && previousHeight > 0 -> openFollowups(from = previousHeight)
                    else -> resetPresentation()
                }
                if (canReveal) {
                    // The suggestions past the placeholders come in after the last of them, one by one
                    val lastPlaceholderSlot =
                        if (loadingAlreadyRevealed) 0 else placeholders.lastIndex
                    revealFollowups(
                        fromIndex = placeholders.size,
                        delay = (lastPlaceholderSlot + 1) * FOLLOWUP_REVEAL_STAGGER_MS
                    )
                }
                return
            }
        } else {
            updateTheme()
        }
        if (shouldAnimate && canReveal) {
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

    fun setCardsEnabled(enabled: Boolean) {
        areCardsEnabled = enabled
        for (i in 0 until column.childCount) {
            val card = column.getChildAt(i) as? WAgentHintView ?: continue
            if (card.isPlaceholder) continue
            if (card === supportCard) {
                applySupportCardState(card)
                continue
            }
            card.isEnabled = enabled
            card.isClickable = enabled
        }
    }

    private fun applySupportCardState(card: WAgentHintView) {
        val isEnabled = areCardsEnabled && isSupportHintEnabled
        card.isEnabled = isEnabled
        card.isClickable = isEnabled
        card.isDimmed = !isSupportHintEnabled
    }

    private fun makeCard(
        title: String,
        showsIcon: Boolean,
        leadingIconResId: Int? = null,
        onTap: () -> Unit
    ) = WAgentHintView(
        context,
        title,
        contentHorizontalPadding = CHIP_HORIZONTAL_PADDING.dp,
        borderWidth = CHIP_BORDER_WIDTH.dp,
        showsIcon = showsIcon,
        leadingIconResId = leadingIconResId,
        onTap = onTap
    )

    private fun makeAccessible(card: WAgentHintView, hint: AgentHint) {
        card.contentDescription = hint.title
        card.importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        card.accessibilityDelegate = object : AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfo
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = android.widget.Button::class.java.name
            }
        }
        for (childIndex in 0 until card.childCount) {
            card.getChildAt(childIndex).importantForAccessibility =
                IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
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

    // A row still opening the suggestions' space goes on opening with [shouldKeepOpening], and the cards in
    // [keptReveals] go on coming in
    private fun cancelAnimations(
        shouldKeepOpening: Boolean = false,
        keptReveals: Collection<View> = emptyList()
    ) {
        loadingRevealCompletedAt = null
        finishReveal(keptReveals)
        // Hand back the pending completions before dropping them: callers such as the hints
        // dismissal own state that is only released by these callbacks.
        val pendingCollapseEnd = collapseEnd
        val pendingExpandEnd = expandEnd
        collapseEnd = null
        expandEnd = null
        if (!shouldKeepOpening) {
            setListClipping(true)
            revealPreDrawListener?.removeListener()
            revealPreDrawListener = null
            revealSpring?.cancel()
            revealSpring = null
        }
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

    /** Ends the suggestions' blur-in where it would end, except on the cards in [keptReveals] */
    fun finishReveal(keptReveals: Collection<View> = emptyList()) {
        val reveals = followupReveals.filterKeys { it !in keptReveals }
        followupReveals.keys.removeAll(reveals.keys)
        reveals.values.forEach { it.end() }
    }

    fun reveal(delay: Long = 0) {
        // A row still opening its space goes on opening, so that a list resting on its end doesn't jump, and only its
        // suggestions come in again
        val shouldKeepOpening = areFollowupsRendered && isOpening
        cancelAnimations(shouldKeepOpening)
        if (!shouldKeepOpening) resetPresentation()
        if (!canReveal) return
        if (isLoadingRendered) loadingRevealCompletedAt = computeRevealEnd(delay)
        if (areFollowupsRendered) {
            revealFollowups(delay)
            return
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

    // When the cards coming in one by one after `delay` are all in
    private fun computeRevealEnd(delay: Long): Long {
        val duration = if (areFollowupsRendered) {
            FOLLOWUP_REVEAL_MS
        } else {
            AnimationConstants.VERY_QUICK_ANIMATION
        }
        return SystemClock.uptimeMillis() + delay +
            (column.childCount - 1).coerceAtLeast(0) * revealStagger + duration
    }

    private fun resetPresentation() {
        for (i in 0 until column.childCount) {
            val child = column.getChildAt(i)
            // A card still coming in out of its blur ends where its own entrance does
            if (followupReveals[child]?.isStarted == true) continue
            child.apply {
                alpha = 1f
                translationY = 0f
                scaleX = 1f
                scaleY = 1f
            }
        }
        clearAnimatedHeight()
    }

    private fun startReveal() {
        if (areFollowupsRendered) {
            revealFollowups(delay = 0)
            openFollowups(from = 1)
            return
        }
        for (i in 0 until column.childCount) {
            column.getChildAt(i).apply {
                alpha = 0f
                translationY = 8f.dp
            }
        }
        setAnimatedHeight(1)
        revealPreDrawListener = doOnPreDraw {
            revealPreDrawListener = null
            val targetHeight = measureNaturalHeight()
            if (targetHeight <= 0) {
                resetPresentation()
                return@doOnPreDraw
            }
            setListClipping(false)
            val revealedViews = (0 until column.childCount).mapNotNull { column.getChildAt(it) }
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
                    for (i in 0 until count) {
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
                    if (!canceled) resetPresentation()
                }
                start()
            }
        }
    }

    /**
     * The suggestions under an answer come in one after another, each out of a blur as it fades in
     * and rises into place, as on iOS
     */
    private fun revealFollowups(delay: Long, fromIndex: Int = 0) {
        for (index in fromIndex until column.childCount) {
            val card = column.getChildAt(index)
            followupReveals[card] = AgentBlurTransition.animateIn(
                card,
                FOLLOWUP_REVEAL_MS,
                delayMs = delay + (index - fromIndex) * FOLLOWUP_REVEAL_STAGGER_MS,
                fromOffsetDp = FOLLOWUP_REVEAL_OFFSET,
                interpolator = FOLLOWUP_REVEAL_CURVE
            )
        }
    }

    /**
     * Opens the suggestions' row from [from] to the height they take, which a list resting on its end follows, so
     * that it scrolls them into view as iOS's list does. The row follows that height while it changes, as a
     * placeholder's pill resizes to its suggestion.
     */
    private fun openFollowups(from: Int) {
        setAnimatedHeight(from)
        revealPreDrawListener = doOnPreDraw {
            revealPreDrawListener = null
            var targetHeight = measureNaturalHeight()
            if (targetHeight <= 0) {
                resetPresentation()
                return@doOnPreDraw
            }
            setListClipping(false)
            revealSpring = SpringAnimation(FloatValueHolder()).apply {
                setStartValue(from.toFloat())
                spring = SpringForce(targetHeight.toFloat()).apply {
                    stiffness = FOLLOWUP_OPENING_STIFFNESS
                    dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
                }
                addUpdateListener { _, value, _ ->
                    // Each layout of the list measures the height the suggestions take by then
                    if (naturalHeight > 0 && naturalHeight != targetHeight) {
                        targetHeight = naturalHeight
                        animateToFinalPosition(targetHeight.toFloat())
                    }
                    setAnimatedHeight(value.roundToInt().coerceAtLeast(1))
                }
                addEndListener { _, canceled, _, _ ->
                    revealSpring = null
                    setListClipping(true)
                    if (!canceled) clearAnimatedHeight()
                }
                start()
            }
        }
    }

    // measuredHeight reports animatedHeight while animating; the natural size is captured by onMeasure
    private fun measureNaturalHeight(): Int {
        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        return naturalHeight
    }
}
