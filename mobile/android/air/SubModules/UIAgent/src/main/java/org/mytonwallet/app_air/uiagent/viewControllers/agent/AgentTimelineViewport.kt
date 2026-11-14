package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.ValueAnimator
import android.os.Build
import android.util.DisplayMetrics
import android.view.View
import android.view.animation.DecelerateInterpolator
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.setPadding
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

internal class AgentTimelineViewport(private val host: Host) {
    interface Host {
        val recyclerView: RecyclerView
        val timelineItems: List<AgentTimelineItem>
        val scrollPosition: AgentVM.ScrollPosition?
        val topPadding: Int
        val isPopupVisible: Boolean
        val dismissingHintsIndex: Int
        fun baseBottomPadding(bottom: Int): Int
        fun publishScrollPosition(position: AgentVM.ScrollPosition)
        fun presentationMessageId(messageId: String): String?
        fun applyComposerBottom(bottom: Int)
        fun finishInitialHintsDismissal(): Boolean
        fun syncTopBlurAfterLayout()
        fun onMessagePinned(messageId: String)
    }

    private val chatRecyclerView get() = host.recyclerView
    private val context get() = chatRecyclerView.context
    private val timelineItems get() = host.timelineItems
    private var isDisposed = false
    var currentBottom = 0
        private set
    private var keyboardAnimator: ValueAnimator? = null
    private var keyboardTransition: KeyboardTransition? = null
    var isUserScrolling = false
        private set
    private var isApplyingSharedScrollPosition = false
    var pendingSharedScrollPosition: AgentVM.ScrollPosition? = null
        private set
    var isOnBottom = true
        private set

    private var isShowingItemAtTop = false
    var pinnedMessageId: String? = null
        private set
    var pendingPinMessageId: String? = null
        private set
    private var pendingOutgoingPreviousMessageId: String? = null
    private var outgoingEditMessageId: String? = null
    var deferredPinMessageId: String? = null
        private set

    // A question that pins without scrolling there, as an empty chat's first does
    private var instantPinMessageId: String? = null
    private var cachedPinnedTarget = 0

    /** The composer's bottom as laid out now, which moves to [currentBottom] with the keyboard */
    var appliedBottom = 0
        private set

    private var pinScrollSpring: SpringAnimation? = null

    // Debug builds pin a question at once while system animations are off, to keep E2E runs fast
    private val canAnimatePin: Boolean
        get() = WGlobalStorage.getAreAnimationsActive() &&
            (!DEBUG_MODE || areSystemAnimatorsEnabled)

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    private val latestScroll = AgentRecyclerAnimationScrollHelper(host.recyclerView)
    var pinScrollExtraSpace = 0
        private set

    /**
     * While support has the chat, the list scrolls as a messenger does: a question sent goes to the end, without a pin
     * or a reserve for an answer, and the list follows new messages while it rests at its end
     */
    var isLiveTailDisabled = false
        private set

    // A question pinned as support takes the chat keeps its place, and the messages that come with the switch stay
    // under it
    private var isFollowHeldOnce = false

    /** Whether the list shows its end, so that it follows new messages there */
    val isAtEnd: Boolean
        get() = !chatRecyclerView.canScrollVertically(1)

    fun setLiveTailDisabled(isDisabled: Boolean) {
        if (isLiveTailDisabled == isDisabled) return
        isLiveTailDisabled = isDisabled
        isFollowHeldOnce = isDisabled && (pinnedMessageId != null || pendingPinMessageId != null)
    }

    /** Places a question about to be sent at the end; the reserve of a question pinned before goes */
    fun prepareMessageAtEnd() {
        latestScroll.finish()
        pendingSharedScrollPosition = null
        pendingPinMessageId = null
        outgoingEditMessageId = null
        isFollowHeldOnce = false
        clearOutgoingPlacement()
        unpin()
    }

    /** Follows the messages just added to the end while the list showed it, [wasAtEnd] before they were added */
    fun followNewMessages(wasAtEnd: Boolean) {
        if (isDisposed || pendingPinMessageId != null) return
        if (isFollowHeldOnce) {
            isFollowHeldOnce = false
            return
        }
        val isAtEnd = wasAtEnd && !isUserScrolling
        doOnPreDraw {
            if (pendingPinMessageId != null) return@doOnPreDraw
            val follow = getAgentNewMessagesFollow(
                isAtEnd,
                isPinned = pinnedMessageId != null,
                latestRowOverhang = measureLatestRowOverhang()
            )
            if (follow == AgentNewMessagesFollow.RELEASE_PIN_AND_END) unpin()
            if (follow != AgentNewMessagesFollow.NONE) scrollToBottom()
        }
    }

    fun onScrollStateChanged(state: Int) {
        if (isDisposed) return
        if (state == RecyclerView.SCROLL_STATE_DRAGGING) {
            isUserScrolling = true
            pendingSharedScrollPosition = null
            pinScrollSpring?.cancel()
        } else if (state == RecyclerView.SCROLL_STATE_IDLE) {
            isUserScrolling = false
            shareScrollPosition()
        }
    }

    fun onUserScrolled(dy: Int) {
        if (isDisposed) return
        releasePinIfTrailingContentIsBelowViewport(chatRecyclerView, dy)
        val atBottom = !chatRecyclerView.canScrollVertically(1)
        if (pinnedMessageId != null || isOnBottom == atBottom) return
        isOnBottom = atBottom
        // A scroll callback may run within a layout pass, where the layout manager must not change
        if (isBottomAnchorPending) return
        isBottomAnchorPending = true
        post {
            isBottomAnchorPending = false
            if (pinnedMessageId == null) applyBottomAnchor()
        }
    }

    private var isBottomAnchorPending = false

    /** Anchors the list to its bottom while [isOnBottom], and to the first visible row otherwise */
    private fun applyBottomAnchor() {
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (lm.stackFromEnd == isOnBottom) return
        if (isOnBottom) {
            lm.stackFromEnd = true
            return
        }
        val firstPos = lm.findFirstVisibleItemPosition()
        if (firstPos == RecyclerView.NO_POSITION) return
        val offset = (lm.findViewByPosition(firstPos)?.top ?: 0) - chatRecyclerView.paddingTop
        lm.stackFromEnd = false
        lm.scrollToPositionWithOffset(firstPos, offset)
    }

    fun restorePendingPosition() {
        if (isDisposed) return
        val position = pendingSharedScrollPosition ?: return
        if (restorePendingSharedScrollPosition(position)) {
            pendingSharedScrollPosition = null
            shareScrollPosition()
        }
    }

    fun resetPlacement() {
        latestScroll.finish()
        unpin()
        pendingPinMessageId = null
        clearOutgoingPlacement()
    }

    fun requestMessagePin(messageId: String, preservePadding: Boolean = false) {
        latestScroll.finish()
        pendingSharedScrollPosition = null
        if (preservePadding) {
            val lm = chatRecyclerView.layoutManager as? LinearLayoutManager
            val first = lm?.findFirstVisibleItemPosition() ?: RecyclerView.NO_POSITION
            val offset = lm?.findViewByPosition(first)?.top?.minus(chatRecyclerView.paddingTop)
            clearPin()
            clearOutgoingPlacement()
            chatRecyclerView.setPadding(
                0,
                chatRecyclerView.paddingTop,
                0,
                maxOf(chatRecyclerView.paddingBottom, chatRecyclerView.height - chatTopPadding())
            )
            lm?.stackFromEnd = false
            if (first >= 0 && offset != null) lm?.scrollToPositionWithOffset(first, offset)
            isOnBottom = false
        } else {
            resetPlacement()
        }
        pendingPinMessageId = messageId
        // Only a sent question's own placement is instant; a pin asked for later scrolls to it
        instantPinMessageId = null
        chatRecyclerView.stopScroll()
    }

    /** [isInstant]: the question pins where it goes at once, without scrolling there */
    fun prepareOutgoingMessage(
        messageId: String,
        items: List<AgentTimelineItem>,
        forcePin: Boolean = false,
        isInstant: Boolean = false
    ): Boolean {
        latestScroll.finish()
        pendingSharedScrollPosition = null
        pendingPinMessageId = messageId
        deferredPinMessageId = null
        instantPinMessageId = messageId.takeIf { isInstant }
        outgoingEditMessageId = messageId.takeIf { forcePin }
        val previousMessageId = prepareOutgoingPlacement(items)
        pendingOutgoingPreviousMessageId = if (forcePin) null else previousMessageId
        return pendingOutgoingPreviousMessageId == null &&
            items.any { it is AgentTimelineItem.Message }
    }

    fun prepareEditInsertion(preservePin: Boolean = false) {
        latestScroll.finish()
        pendingSharedScrollPosition = null
        if (preservePin) pinScrollSpring?.cancel() else clearPin()
        pendingPinMessageId = null
        clearOutgoingPlacement()
        chatRecyclerView.stopScroll()
    }

    /**
     * A question that waited in the chat goes. With [shouldPin] it comes up to the top as a
     * question just sent does, once its answer's row comes in. Otherwise the pin held for it, as
     * the latest question queued, drops, and the list stays.
     */
    fun placeGoingQuestion(messageId: String, shouldPin: Boolean) {
        if (shouldPin) {
            pendingPinMessageId = messageId
            pendingOutgoingPreviousMessageId = null
            deferredPinMessageId = messageId
        } else if (pendingPinMessageId == messageId) {
            pendingPinMessageId = null
            clearOutgoingPlacement()
        }
    }

    fun clearOutgoingPlacement() {
        pendingOutgoingPreviousMessageId = null
        deferredPinMessageId = null
    }

    fun clearDeferredPin() {
        deferredPinMessageId = null
    }

    fun preserveCollapsingHintsSpace(delta: Int, hintsIndex: Int, hasAnchor: Boolean) {
        val pinnedIndex = pinnedMessageId?.let(::timelineIndexOf) ?: -1
        val pendingIndex = pendingPinMessageId?.let(::timelineIndexOf) ?: -1
        val preservesPinned = pinnedIndex >= 0 && hintsIndex > pinnedIndex
        val preservesPending = hasAnchor && pendingIndex >= 0 && hintsIndex < pendingIndex
        if (!preservesPinned && !preservesPending) return
        val padding = if (preservesPinned) {
            val target = cachedPinnedTarget.takeIf { it != 0 } ?: pinnedPaddingTarget() ?: return
            cachedPinnedTarget = target + delta
            cachedPinnedTarget.coerceAtLeast(baseChatBottomPadding(appliedBottom))
        } else {
            chatRecyclerView.paddingBottom + delta
        }
        chatRecyclerView.setPadding(0, chatRecyclerView.paddingTop, 0, padding)
    }

    private val pendingPosts = mutableSetOf<Runnable>()
    private val pendingLayouts = mutableSetOf<View.OnLayoutChangeListener>()
    private val pendingDraws = mutableSetOf<OneShotPreDrawListener>()

    private fun post(action: () -> Unit) {
        if (isDisposed) return
        val runnable = object : Runnable {
            override fun run() {
                pendingPosts.remove(this)
                if (!isDisposed) action()
            }
        }
        pendingPosts.add(runnable)
        chatRecyclerView.post(runnable)
    }

    private fun doOnNextLayout(action: () -> Unit) {
        if (isDisposed) return
        val listener = object : View.OnLayoutChangeListener {
            override fun onLayoutChange(
                view: View,
                l: Int,
                t: Int,
                r: Int,
                b: Int,
                oldL: Int,
                oldT: Int,
                oldR: Int,
                oldB: Int
            ) {
                view.removeOnLayoutChangeListener(this)
                pendingLayouts.remove(this)
                if (!isDisposed) action()
            }
        }
        pendingLayouts.add(listener)
        chatRecyclerView.addOnLayoutChangeListener(listener)
    }

    private fun doOnPreDraw(action: () -> Unit) {
        if (isDisposed) return
        lateinit var listener: OneShotPreDrawListener
        listener = OneShotPreDrawListener.add(chatRecyclerView) {
            pendingDraws.remove(listener)
            if (!isDisposed) action()
        }
        pendingDraws.add(listener)
    }

    fun dispose() {
        isDisposed = true
        latestScroll.finish()
        pendingPosts.forEach(chatRecyclerView::removeCallbacks)
        pendingPosts.clear()
        pendingLayouts.forEach(chatRecyclerView::removeOnLayoutChangeListener)
        pendingLayouts.clear()
        pendingDraws.forEach { it.removeListener() }
        pendingDraws.clear()
        keyboardAnimator?.cancel()
        keyboardTransition = null
        clearPin()
        pendingPinMessageId = null
        pendingSharedScrollPosition = null
        chatRecyclerView.stopScroll()
    }

    private var hasAppliedInitialLayout = false

    /**
     * Moves the composer's bottom to [targetBottom]. With [shouldFollowKeyboard] the keyboard's own
     * animation carries it there through [followKeyboard]; otherwise it slides there by itself.
     */
    fun updateLayout(
        targetBottom: Int,
        ime: Int,
        navigationBottom: Int,
        shouldFollowKeyboard: Boolean = false
    ) {
        if (isDisposed) return
        if (ime == 0) stableBottomInset = navigationBottom

        if (targetBottom != currentBottom) {
            latestScroll.finish()
            val fromBottom = if (hasAppliedInitialLayout) appliedBottom else currentBottom
            val keyboardPaddingStart =
                if (ime > 0 && targetBottom > fromBottom) {
                    releasePinForKeyboardIfCovered(targetBottom)
                } else {
                    null
                }
            currentBottom = targetBottom

            if (!hasAppliedInitialLayout) {
                hasAppliedInitialLayout = true
                applyBottom(targetBottom)
                return
            }

            keyboardAnimator?.cancel()
            keyboardAnimator = null
            val transition = KeyboardTransition(fromBottom, targetBottom, keyboardPaddingStart)
            if (shouldFollowKeyboard) {
                keyboardTransition = transition
                return
            }
            keyboardTransition = null
            keyboardAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 220
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    applyTransition(transition, animator.animatedValue as Float)
                }
                start()
            }
        } else if (keyboardTransition != null && !shouldFollowKeyboard) {
            finishKeyboardMotion()
        } else if (keyboardAnimator?.isRunning != true && keyboardTransition == null) {
            applyBottom(targetBottom)
        }
    }

    /** Places the composer's bottom at [bottom], where the keyboard's motion has brought it */
    fun followKeyboard(bottom: Int) {
        val transition = keyboardTransition ?: return
        val distance = transition.targetBottom - transition.fromBottom
        val fraction = if (distance == 0) {
            1f
        } else {
            ((bottom - transition.fromBottom).toFloat() / distance).coerceIn(0f, 1f)
        }
        applyTransition(transition, fraction)
    }

    /** The keyboard has come to rest, and the composer with it */
    fun finishKeyboardMotion() {
        val transition = keyboardTransition ?: return
        keyboardTransition = null
        applyTransition(transition, 1f)
    }

    private fun applyTransition(transition: KeyboardTransition, fraction: Float) {
        val distance = transition.targetBottom - transition.fromBottom
        val bottomPadding = transition.paddingStart?.let { start ->
            val target = baseChatBottomPadding(transition.targetBottom)
            start + ((target - start) * fraction).roundToInt()
        }
        applyBottom(transition.fromBottom + (distance * fraction).roundToInt(), bottomPadding)
    }

    // A move of the composer's bottom; a pin released because the keyboard would cover its content
    // hands the list's bottom padding over from `paddingStart`
    private class KeyboardTransition(
        val fromBottom: Int,
        val targetBottom: Int,
        val paddingStart: Int?
    )

    private fun applyBottom(bottom: Int, bottomPaddingOverride: Int? = null) {
        if (isDisposed) return
        appliedBottom = bottom
        host.applyComposerBottom(bottom)

        val topPadding = chatTopPadding()
        val bottomPadding = bottomPaddingOverride ?: chatBottomPadding(bottom)
        val bottomPaddingChange = bottomPadding - chatRecyclerView.paddingBottom
        val paddingChanged = chatRecyclerView.paddingTop != topPadding || bottomPaddingChange != 0
        if (paddingChanged) chatRecyclerView.setPadding(0, topPadding, 0, bottomPadding)
        if (bottomPaddingChange != 0) keepMessagesOnComposer(bottomPaddingChange)
    }

    /** Scrolled up, the list lays out from its top, so messages must scroll with the keyboard themselves. */
    private fun keepMessagesOnComposer(bottomPaddingChange: Int) {
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val isHeldInPlace = pinnedMessageId != null || pendingPinMessageId != null ||
            pendingSharedScrollPosition != null
        if (!hasAppliedInitialLayout || lm.stackFromEnd || isUserScrolling || isHeldInPlace) return
        chatRecyclerView.scrollBy(0, bottomPaddingChange)
    }

    private fun chatTopPadding(): Int = host.topPadding
    private var stableBottomInset = 0

    private fun baseChatBottomPadding(bottom: Int = currentBottom): Int =
        host.baseBottomPadding(bottom)

    private fun chatBottomPadding(bottom: Int): Int {
        val base = baseChatBottomPadding(bottom)
        if (pinnedMessageId == null) {
            return if (pendingPinMessageId !=
                null
            ) {
                maxOf(base, chatRecyclerView.paddingBottom)
            } else {
                base
            }
        }
        if (pendingPinMessageId == pinnedMessageId && cachedPinnedTarget > 0) {
            return maxOf(base, cachedPinnedTarget)
        }
        val pinned = pinnedPaddingTarget()
        if (pinned == null) {
            clearPin()
            return base
        }
        return maxOf(base, pinned)
    }

    private fun pinnedItemOffset(index: Int, itemHeight: Int): Int {
        val topInset = if (index > 0) AGENT_LIST_TOP_INSET.dp else 0
        val reveal = timelineItems.agentPinPreviousLineReveal(index, AGENT_PIN_PREVIOUS_LINE.dp)
        return agentPinnedItemOffset(
            timelineItems[index],
            itemHeight,
            chatTopPadding() - topInset + reveal,
            chatRecyclerView.height - baseChatBottomPadding(appliedBottom) -
                MIN_MESSAGE_CELL_HEIGHT.dp
        ) - topInset + reveal
    }

    private fun pinnedMessageHeight(view: View): Int = when (view) {
        is AgentMessageCell -> view.layoutTargetHeight
        is AgentNewsPostCell -> view.layoutTargetHeight
        else -> view.height
    }

    private fun pinnedItemOffset(index: Int, view: View?): Int =
        if (view == null) 0 else pinnedItemOffset(index, pinnedMessageHeight(view))

    private fun pinAnchorIndex(messageId: String): Int =
        timelineItems.agentPinAnchorIndex(timelineIndexOf(messageId))

    private fun pinnedPaddingTarget(): Int? {
        val messageId = pinnedMessageId ?: return null
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return null
        val idx = pinAnchorIndex(messageId)
        if (idx < 0) return null
        var contentBelow = 0
        var messageHeight = 0
        for (i in idx until timelineItems.size) {
            val itemView = lm.findViewByPosition(i)
                ?: return if (cachedPinnedTarget > 0) {
                    cachedPinnedTarget
                } else {
                    null
                }
            // Use laid-out geometry: a cell animating its own height (hints reveal, message
            // insert) can carry a stale measured height for a frame, which would collapse
            // the reserved padding all at once and drop the pinned message.
            contentBelow += lm.getDecoratedBottom(itemView) - lm.getDecoratedTop(itemView)
            if (i == idx) {
                messageHeight = pinnedMessageHeight(itemView)
            }
        }
        val target = chatRecyclerView.height - chatTopPadding() - contentBelow -
            pinnedItemOffset(idx, messageHeight)
        cachedPinnedTarget = target
        return target
    }

    fun preservePinAcrossSizeTransition(messageId: String, cell: View, previousHeight: Int) {
        if (isUserScrolling || pendingPinMessageId != null ||
            pinScrollSpring?.isRunning == true ||
            chatRecyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE
        ) {
            return
        }
        val pinnedId = pinnedMessageId ?: return
        val messageIndex = timelineIndexOf(messageId)
        val pinnedIndex = timelineIndexOf(pinnedId)
        if (messageIndex < 0 || pinnedIndex < 0 || messageIndex == pinnedIndex) return
        val anchorIndex = pinAnchorIndex(pinnedId)
        val pinnedTop = (chatRecyclerView.layoutManager as? LinearLayoutManager)
            ?.findViewByPosition(anchorIndex)
            ?.let { pinnedView ->
                val expectedTop = chatRecyclerView.paddingTop +
                    pinnedItemOffset(anchorIndex, pinnedView)
                expectedTop.takeIf { pinnedView.top == expectedTop }
            }
        doOnPreDraw {
            if (isUserScrolling || pinnedMessageId != pinnedId ||
                pendingPinMessageId != null || pinScrollSpring?.isRunning == true ||
                chatRecyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE
            ) {
                return@doOnPreDraw
            }
            val currentMessageIndex = chatRecyclerView.getChildAdapterPosition(cell)
            val currentPinnedIndex = timelineIndexOf(pinnedId)
            val item = timelineItems.getOrNull(currentMessageIndex)
                as? AgentTimelineItem.Message
            if (item?.message?.id != messageId ||
                currentPinnedIndex < 0 || currentMessageIndex == currentPinnedIndex
            ) {
                return@doOnPreDraw
            }
            val delta = cell.height - previousHeight
            when {
                delta != 0 && currentMessageIndex < currentPinnedIndex ->
                    chatRecyclerView.scrollBy(0, delta)

                delta < 0 && currentMessageIndex > currentPinnedIndex ->
                    pinnedTop?.let(::preservePinnedMessageAcrossTrailingShrink)
            }
        }
    }

    /**
     * Scrolls the rows above a change back up by [shift] when the list moved them down to fill
     * the space the change freed at its end. The padding of the question pinned among them takes
     * that space, so they stay where they were.
     */
    fun restoreRowsAboveChange(shift: Int, changeIndex: Int) {
        if (isDisposed || isUserScrolling || pinScrollSpring?.isRunning == true ||
            chatRecyclerView.scrollState != RecyclerView.SCROLL_STATE_IDLE
        ) {
            return
        }
        val pinnedIndex = pinnedMessageId?.let(::pinAnchorIndex) ?: return
        if (pinnedIndex !in 0 until changeIndex) return
        syncPinnedPadding()
        chatRecyclerView.scrollBy(0, shift)
    }

    private fun preservePinnedMessageAcrossTrailingShrink(pinnedTop: Int) {
        val requiredPadding = maxOf(
            baseChatBottomPadding(appliedBottom),
            pinnedPaddingTarget() ?: return
        )
        if (requiredPadding <= chatRecyclerView.paddingBottom) return
        chatRecyclerView.setPadding(
            0,
            chatRecyclerView.paddingTop,
            0,
            requiredPadding
        )

        val pinnedId = pinnedMessageId ?: return
        val pinnedIndex = pinAnchorIndex(pinnedId)
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val pinnedView = lm.findViewByPosition(pinnedIndex) ?: return
        val delta = pinnedView.top - pinnedTop
        if (delta != 0) chatRecyclerView.scrollBy(0, delta)
    }

    // isOnBottom only tracks user scrolls; a programmatic content change (e.g. the hints
    // collapse) can leave the list resting at the bottom with the flag stale. Recompute
    // it from the actual scroll state before decisions that depend on it.
    fun refreshIsOnBottom() {
        if (isUserScrolling ||
            pinnedMessageId != null ||
            pendingPinMessageId != null ||
            pendingSharedScrollPosition != null
        ) {
            return
        }
        val atBottom = !chatRecyclerView.canScrollVertically(1)
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (atBottom && !lm.stackFromEnd && !chatRecyclerView.canScrollVertically(-1)) return
        if (atBottom == isOnBottom) return
        isOnBottom = atBottom
        applyBottomAnchor()
    }

    /** How far the latest row reaches below the part of the list that the composer leaves visible */
    fun measureLatestRowOverhang(): Int {
        val lastIndex = timelineItems.lastIndex
        if (isDisposed || lastIndex < 0 || chatRecyclerView.childCount == 0) return 0
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return 0
        val visibleBottom = chatRecyclerView.height - baseChatBottomPadding(appliedBottom)
        val view = lm.findViewByPosition(lastIndex)
            ?: return if (lm.findLastVisibleItemPosition() < lastIndex) Int.MAX_VALUE else 0
        return lm.getDecoratedBottom(view) - visibleBottom
    }

    fun scrollToLatest() {
        if (isDisposed || timelineItems.isEmpty() || latestScroll.isRunning) return
        pendingSharedScrollPosition = null
        pendingPinMessageId = null
        clearOutgoingPlacement()
        unpin()
        chatRecyclerView.stopScroll()
        isUserScrolling = false
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager
        if (layoutManager == null || host.isPopupVisible) {
            scrollToBottom()
            return
        }
        isOnBottom = true
        layoutManager.stackFromEnd = true
        latestScroll.scrollDown { layoutManager.scrollToPosition(timelineItems.lastIndex) }
    }

    fun finishLatestScroll() = latestScroll.finish()

    /** Whether the rows slide to the latest one, as [scrollToLatest] moves them */
    val isScrollingToLatest: Boolean
        get() = latestScroll.isRunning

    fun scrollToBottom() {
        if (isDisposed) return
        if (isUserScrolling) return
        if (pinnedMessageId != null ||
            pendingPinMessageId != null ||
            pendingSharedScrollPosition != null
        ) {
            return
        }
        isOnBottom = true
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager
        if (lm?.stackFromEnd == false) {
            val firstPos = lm.findFirstVisibleItemPosition()
            if (firstPos == RecyclerView.NO_POSITION) {
                lm.stackFromEnd = true
                return
            }
            val offset =
                lm.findViewByPosition(firstPos)?.let { it.top - chatRecyclerView.paddingTop } ?: 0
            lm.stackFromEnd = true
            lm.scrollToPositionWithOffset(firstPos, offset)
        }
        if (timelineItems.size == 0) return
        if (host.isPopupVisible) return
        val targetPosition = timelineItems.size - 1
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val scroller = object : LinearSmoothScroller(context) {
            override fun getVerticalSnapPreference(): Int = SNAP_TO_END
        }
        scroller.targetPosition = targetPosition
        layoutManager.startSmoothScroll(scroller)
    }

    fun shareScrollPosition() {
        if (isDisposed) return
        if (isApplyingSharedScrollPosition || pendingSharedScrollPosition != null) return
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (pinnedMessageId == null && layoutManager.stackFromEnd &&
            !chatRecyclerView.canScrollVertically(1)
        ) {
            host.publishScrollPosition(
                AgentVM.ScrollPosition(AgentVM.ScrollAnchor.Bottom)
            )
            return
        }

        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()
        if (firstVisible == RecyclerView.NO_POSITION || lastVisible == RecyclerView.NO_POSITION) {
            return
        }
        for (index in firstVisible..lastVisible) {
            val anchor = scrollAnchorAt(index) ?: continue
            val itemView = layoutManager.findViewByPosition(index) ?: continue
            host.publishScrollPosition(
                currentScrollPosition(
                    anchor,
                    itemView.top - chatRecyclerView.paddingTop
                )
            )
            return
        }
    }

    private fun currentScrollPosition(
        anchor: AgentVM.ScrollAnchor,
        offset: Int
    ): AgentVM.ScrollPosition {
        val pinnedId = pinnedMessageId
        return AgentVM.ScrollPosition(
            anchor = anchor,
            offset = offset,
            pinnedMessageId = pinnedId,
            pinnedBottomPadding = if (pinnedId == null) {
                0
            } else {
                chatRecyclerView.paddingBottom
            }
        )
    }

    fun restoreSharedScrollPosition(): Boolean {
        if (isDisposed) return false
        if (isShowingItemAtTop) return true
        val position = host.scrollPosition ?: return false
        latestScroll.finish()
        pendingSharedScrollPosition = position
        isApplyingSharedScrollPosition = true
        try {
            applySharedScrollPosition(position)
        } finally {
            isApplyingSharedScrollPosition = false
        }
        return true
    }

    /** Until the row is laid out there, the chat's shared position waits. */
    fun showItemAtTop(index: Int) {
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        latestScroll.finish()
        pendingSharedScrollPosition = null
        unpin()
        isOnBottom = false
        layoutManager.stackFromEnd = false
        layoutManager.scrollToPositionWithOffset(index, 0)
        isShowingItemAtTop = true
        doOnNextLayout {
            isShowingItemAtTop = false
            refreshIsOnBottom()
            shareScrollPosition()
        }
    }

    fun showInitialChatAtTop() {
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        latestScroll.finish()
        pendingSharedScrollPosition = null
        isOnBottom = false
        layoutManager.stackFromEnd = false
        layoutManager.scrollToPositionWithOffset(0, 0)
    }

    private fun applySharedScrollPosition(position: AgentVM.ScrollPosition) {
        chatRecyclerView.stopScroll()
        pendingPinMessageId = null

        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (position.anchor == AgentVM.ScrollAnchor.Bottom) {
            pendingSharedScrollPosition = null
            unpin()
            scrollToBottomImmediately(layoutManager)
            return
        }

        val index = timelineIndexOf(position.anchor)
        if (index < 0) {
            pendingSharedScrollPosition = null
            unpin()
            scrollToBottomImmediately(layoutManager)
            return
        }
        restorePinnedState(position)
        isOnBottom = false
        layoutManager.stackFromEnd = false
        layoutManager.scrollToPositionWithOffset(index, position.offset)
    }

    private fun restorePendingSharedScrollPosition(position: AgentVM.ScrollPosition): Boolean {
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return false
        val index = timelineIndexOf(position.anchor)
        if (index < 0) return true
        val itemView = layoutManager.findViewByPosition(index)
        val expectedTop = chatRecyclerView.paddingTop + position.offset
        if (itemView?.top == expectedTop) return true
        if (itemView != null) {
            chatRecyclerView.scrollBy(0, itemView.top - expectedTop)
            return layoutManager.findViewByPosition(index)?.top == expectedTop
        }
        layoutManager.stackFromEnd = false
        layoutManager.scrollToPositionWithOffset(index, position.offset)
        return false
    }

    private fun restorePinnedState(position: AgentVM.ScrollPosition) {
        val messageId = position.pinnedMessageId
        val bottomPadding = position.pinnedBottomPadding
        // A question pinned when the chat was on screen last is not pinned again while support has the chat
        if (messageId == null || bottomPadding <= 0 || timelineIndexOf(messageId) < 0 ||
            isLiveTailDisabled
        ) {
            unpin()
            return
        }
        val presentationId = presentationMessageId(messageId) ?: run {
            unpin()
            return
        }

        clearPin()
        pinnedMessageId = presentationId
        cachedPinnedTarget = maxOf(bottomPadding, baseChatBottomPadding(appliedBottom))
        chatRecyclerView.setPadding(
            0,
            chatTopPadding(),
            0,
            cachedPinnedTarget
        )
    }

    private fun scrollToBottomImmediately(layoutManager: LinearLayoutManager) {
        isOnBottom = true
        layoutManager.stackFromEnd = true
        if (timelineItems.size == 0) return
        chatRecyclerView.scrollToPosition(timelineItems.size - 1)
        chatRecyclerView.scrollBy(0, Int.MAX_VALUE)
    }

    private fun scrollAnchorAt(index: Int): AgentVM.ScrollAnchor? =
        when (val item = timelineItems.getOrNull(index)) {
            is AgentTimelineItem.Message -> AgentVM.ScrollAnchor.Message(item.message.id)
            is AgentTimelineItem.Hints -> AgentVM.ScrollAnchor.Hints
            is AgentTimelineItem.DateHeader, AgentTimelineItem.UnreadDivider -> null
            null -> null
        }

    fun timelineIndexOf(anchor: AgentVM.ScrollAnchor): Int = when (anchor) {
        AgentVM.ScrollAnchor.Bottom -> -1

        AgentVM.ScrollAnchor.Hints ->
            timelineItems.indexOfFirst { it is AgentTimelineItem.Hints }

        is AgentVM.ScrollAnchor.Message -> timelineIndexOf(anchor.messageId)
    }

    fun timelineIndexOf(messageId: String): Int {
        val presentationId = presentationMessageId(messageId) ?: return -1
        return timelineItems.indexOfFirst {
            it is AgentTimelineItem.Message && it.message.id == presentationId
        }
    }

    fun presentationMessageId(messageId: String): String? = host.presentationMessageId(messageId)

    private fun prepareOutgoingPlacement(items: List<AgentTimelineItem>): String? {
        val previousIndex = items.indexOfLast { it is AgentTimelineItem.Message }
        val previousMessage =
            (items.getOrNull(previousIndex) as? AgentTimelineItem.Message)?.message ?: return null
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return null
        val previousView = lm.findViewByPosition(previousIndex) ?: return null
        val contentTop = chatRecyclerView.paddingTop
        val contentBottom =
            chatRecyclerView.height - baseChatBottomPadding(appliedBottom)
        if (previousView.bottom <= contentTop || previousView.top >= contentBottom) return null

        if (lm.stackFromEnd) {
            val firstPosition = lm.findFirstVisibleItemPosition()
            val firstView = lm.findViewByPosition(firstPosition) ?: return null
            val firstOffset = firstView.top - chatRecyclerView.paddingTop
            lm.stackFromEnd = false
            lm.scrollToPositionWithOffset(firstPosition, firstOffset)
        }
        return previousMessage.id
    }

    fun onOutgoingInsertAnimationPrepared(messageId: String, targetHeight: Int) {
        if (pendingPinMessageId != messageId) return
        val previousMessageId = pendingOutgoingPreviousMessageId
        pendingOutgoingPreviousMessageId = null
        if (previousMessageId != null &&
            outgoingMessageFitsBelow(previousMessageId, messageId, targetHeight)
        ) {
            deferredPinMessageId = messageId
        } else {
            post {
                if (pendingPinMessageId == messageId) {
                    evaluatePinning(messageId, targetHeight)
                }
            }
        }
    }

    private fun outgoingMessageFitsBelow(
        previousMessageId: String,
        messageId: String,
        targetHeight: Int
    ): Boolean {
        if (targetHeight <= 0) return false
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return false
        val previousIndex = timelineIndexOf(previousMessageId)
        val messageIndex = timelineIndexOf(messageId)
        if (previousIndex < 0 || messageIndex < 0) return false
        val previousView = lm.findViewByPosition(previousIndex) ?: return false
        val messageView = lm.findViewByPosition(messageIndex) ?: return false
        val hintsIndex = host.dismissingHintsIndex
        val reclaimableHintsHeight =
            if (hintsIndex in (previousIndex + 1) until messageIndex) {
                lm.findViewByPosition(hintsIndex)?.height ?: 0
            } else {
                0
            }
        val projectedMessageTop = messageView.top - reclaimableHintsHeight
        val contentBottom =
            chatRecyclerView.height - baseChatBottomPadding(appliedBottom)
        return projectedMessageTop >= previousView.bottom &&
            projectedMessageTop + targetHeight <= contentBottom
    }

    fun evaluatePinning(
        messageId: String,
        targetHeight: Int? = null,
        isRetry: Boolean = false,
        animated: Boolean = canAnimatePin && messageId != instantPinMessageId
    ) {
        if (isDisposed) return
        if (pendingPinMessageId != messageId) return
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val idx = timelineIndexOf(messageId)
        if (idx < 0) {
            pendingPinMessageId = null
            pendingOutgoingPreviousMessageId = null
            if (isRetry) scrollToBottom()
            return
        }
        val messageView = lm.findViewByPosition(idx)
        val anchorIndex = pinAnchorIndex(messageId)
        val anchorView = lm.findViewByPosition(anchorIndex)
        if (messageView == null || anchorView == null) {
            if (pinnedMessageId == messageId && !isRetry) return
            if (isRetry) {
                pendingPinMessageId = null
                pendingOutgoingPreviousMessageId = null
                unpin()
                scrollToBottom()
                return
            }
            chatRecyclerView.stopScroll()
            pinnedMessageId = messageId
            val messageHeight =
                targetHeight?.takeIf { it != 0 } ?: messageView?.let(::pinnedMessageHeight)
                    ?: MIN_MESSAGE_CELL_HEIGHT.dp
            cachedPinnedTarget = maxOf(
                baseChatBottomPadding(appliedBottom),
                chatRecyclerView.height - chatTopPadding() -
                    messageHeight - pinnedItemOffset(anchorIndex, messageHeight)
            )
            pinScrollExtraSpace = cachedPinnedTarget
            isOnBottom = false
            chatRecyclerView.setPadding(
                0,
                chatTopPadding(),
                0,
                cachedPinnedTarget
            )
            if (lm.stackFromEnd) {
                val firstPosition = lm.findFirstVisibleItemPosition()
                val firstView = lm.findViewByPosition(firstPosition)
                val firstOffset = firstView?.top?.minus(chatRecyclerView.paddingTop)
                lm.stackFromEnd = false
                if (firstPosition >= 0 && firstOffset != null) {
                    lm.scrollToPositionWithOffset(firstPosition, firstOffset)
                }
            }
            if (animated) {
                val scroller = object : LinearSmoothScroller(context) {
                    override fun getVerticalSnapPreference(): Int = SNAP_TO_START

                    override fun calculateSpeedPerPixel(displayMetrics: DisplayMetrics): Float =
                        if (outgoingEditMessageId == messageId) {
                            90f / displayMetrics.densityDpi
                        } else {
                            super.calculateSpeedPerPixel(displayMetrics)
                        }

                    override fun calculateDyToMakeVisible(view: View, snapPreference: Int): Int {
                        val currentIndex = pinAnchorIndex(messageId)
                        val offset = if (currentIndex >= 0) {
                            pinnedItemOffset(currentIndex, view)
                        } else {
                            0
                        }
                        return super.calculateDyToMakeVisible(view, snapPreference) + offset
                    }

                    override fun onStop() {
                        super.onStop()
                        post {
                            if (pendingPinMessageId == messageId) {
                                evaluatePinning(messageId, isRetry = true, animated = animated)
                            }
                        }
                    }
                }
                scroller.targetPosition = anchorIndex
                lm.startSmoothScroll(scroller)
            } else {
                val offset = pinnedItemOffset(anchorIndex, messageHeight)
                lm.scrollToPositionWithOffset(anchorIndex, offset)
                doOnNextLayout {
                    if (pendingPinMessageId == messageId) {
                        evaluatePinning(messageId, isRetry = true, animated = animated)
                    }
                }
            }
            return
        }
        val wasOffscreenPin = pinnedMessageId == messageId
        pendingPinMessageId = null
        pendingOutgoingPreviousMessageId = null
        val available =
            chatRecyclerView.height - chatTopPadding() - baseChatBottomPadding(stableBottomInset)
        if (available <= 0) {
            if (isRetry) scrollToBottom()
            return
        }
        pinnedMessageId = messageId
        cachedPinnedTarget = 0
        isOnBottom = false
        if (animated && !wasOffscreenPin) {
            pinScrollExtraSpace = anchorView.top
        } else {
            pinScrollExtraSpace = 0
        }
        if (lm.stackFromEnd) {
            val firstPos = lm.findFirstVisibleItemPosition()
            val firstOffset =
                (lm.findViewByPosition(firstPos)?.top ?: 0) - chatRecyclerView.paddingTop
            lm.stackFromEnd = false
            if (firstPos != RecyclerView.NO_POSITION) {
                lm.scrollToPositionWithOffset(firstPos, firstOffset)
            }
        }
        val paddingChanged = syncPinnedPadding()
        if (wasOffscreenPin && (!animated || anchorIndex != idx)) {
            lm.scrollToPositionWithOffset(anchorIndex, pinnedItemOffset(anchorIndex, anchorView))
            host.syncTopBlurAfterLayout()
        } else if (paddingChanged) {
            if (!wasOffscreenPin) {
                if (animated) {
                    doOnNextLayout { startPinScroll(messageId, animated = true) }
                } else {
                    startPinScroll(messageId, animated = false)
                }
            }
        } else if (!wasOffscreenPin) {
            startPinScroll(messageId, animated)
        }
        if (wasOffscreenPin) notifyMessagePinned(messageId)
    }

    private fun clearPin() {
        pinnedMessageId = null
        cachedPinnedTarget = 0
        pinScrollExtraSpace = 0
        pinScrollSpring?.cancel()
    }

    /** Returns whether a scroll ran. */
    fun stopProgrammaticScroll(): Boolean {
        if (latestScroll.stop()) {
            refreshIsOnBottom()
            return true
        }
        val spring = pinScrollSpring?.takeIf { it.isRunning } ?: return false
        spring.cancel()
        return true
    }

    private fun startPinScroll(messageId: String, animated: Boolean = canAnimatePin) {
        if (isDisposed) return
        if (pinnedMessageId != messageId) return
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val idx = pinAnchorIndex(messageId)
        if (idx < 0) return
        val anchorView = lm.findViewByPosition(idx)
        val targetOffset = pinnedItemOffset(idx, anchorView)
        val dy = anchorView?.let {
            it.top - (chatRecyclerView.paddingTop + targetOffset)
        }
        if (dy == null || dy <= 0 || !animated) {
            pinScrollExtraSpace = 0
            if (dy == null || dy != 0) {
                lm.scrollToPositionWithOffset(idx, targetOffset)
            }
            finishInitialHintsDismissal(messageId)
            notifyMessagePinned(messageId)
            return
        }
        val startTop = anchorView.top
        pinScrollSpring?.cancel()
        pinScrollSpring = SpringAnimation(FloatValueHolder()).apply {
            spring = SpringForce(dy.toFloat()).apply {
                stiffness = SpringForce.STIFFNESS_LOW
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                if (pinnedMessageId != messageId) {
                    pinScrollSpring?.cancel()
                    return@addUpdateListener
                }
                // Scroll toward the message's actual position instead of by blind
                // increments, so concurrent content changes (hints collapsing above)
                // can't make the spring overshoot.
                val currentIndex = pinAnchorIndex(messageId)
                val view = lm.findViewByPosition(currentIndex) ?: return@addUpdateListener
                val desiredTop = startTop - value.roundToInt()
                val delta = view.top - desiredTop
                if (delta != 0) {
                    chatRecyclerView.scrollBy(0, delta)
                }
            }
            addEndListener { _, canceled, _, _ ->
                pinScrollExtraSpace = 0
                if (!canceled && pinnedMessageId == messageId) {
                    val currentIndex = pinAnchorIndex(messageId)
                    if (currentIndex < 0) return@addEndListener
                    val view = lm.findViewByPosition(currentIndex)
                    val offset = pinnedItemOffset(currentIndex, view)
                    if (view?.top != chatRecyclerView.paddingTop + offset) {
                        lm.scrollToPositionWithOffset(currentIndex, offset)
                    }
                    finishInitialHintsDismissal(messageId)
                    notifyMessagePinned(messageId)
                }
            }
            start()
        }
    }

    private fun notifyMessagePinned(messageId: String) {
        doOnPreDraw {
            if (pinnedMessageId == messageId && pendingPinMessageId == null) {
                host.onMessagePinned(messageId)
            }
        }
    }

    private fun finishInitialHintsDismissal(messageId: String) {
        if (!host.finishInitialHintsDismissal()) return
        doOnNextLayout {
            if (pinnedMessageId != messageId) return@doOnNextLayout
            val lm = chatRecyclerView.layoutManager as? LinearLayoutManager
                ?: return@doOnNextLayout
            val idx = pinAnchorIndex(messageId)
            if (idx >= 0) {
                val view = lm.findViewByPosition(idx)
                val offset = pinnedItemOffset(idx, view)
                lm.scrollToPositionWithOffset(idx, offset)
            }
        }
    }

    fun syncPinnedPadding(): Boolean {
        if (isDisposed) return false
        if (pinnedMessageId == null) return false
        val topPadding = chatTopPadding()
        val bottomPadding = chatBottomPadding(appliedBottom)
        if (chatRecyclerView.paddingTop != topPadding ||
            chatRecyclerView.paddingBottom != bottomPadding
        ) {
            chatRecyclerView.setPadding(0, topPadding, 0, bottomPadding)
            return true
        }
        return false
    }

    private fun unpin() {
        val wasPinned = pinnedMessageId != null || cachedPinnedTarget != 0
        clearPin()
        if (!wasPinned) return
        chatRecyclerView.setPadding(
            0,
            chatTopPadding(),
            0,
            baseChatBottomPadding(appliedBottom)
        )
    }

    private fun releasePinIfTrailingContentIsBelowViewport(recyclerView: RecyclerView, dy: Int) {
        if (dy >= 0 || pinnedMessageId == null) return
        val basePadding = baseChatBottomPadding(appliedBottom)
        if (recyclerView.paddingBottom <= basePadding) return
        val lm = recyclerView.layoutManager as? LinearLayoutManager ?: return
        val lastPosition = timelineItems.lastIndex
        if (lastPosition < 0) return
        val trailingView = lm.findViewByPosition(lastPosition)
        val contentBottom = recyclerView.height - basePadding
        if (trailingView == null || lm.getDecoratedBottom(trailingView) > contentBottom) {
            unpin()
        }
    }

    private fun releasePinForKeyboardIfCovered(targetBottom: Int): Int? {
        if (pinnedMessageId == null ||
            pendingPinMessageId != null ||
            chatRecyclerView.canScrollVertically(1)
        ) {
            return null
        }
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return null
        val trailingView = lm.findViewByPosition(timelineItems.lastIndex) ?: return null
        val contentBottom =
            chatRecyclerView.height - baseChatBottomPadding(targetBottom)
        if (lm.getDecoratedBottom(trailingView) <= contentBottom) return null

        val paddingStart = chatRecyclerView.paddingBottom
        clearPin()
        isOnBottom = true
        lm.stackFromEnd = true
        return paddingStart
    }

    private companion object {
        private const val MIN_MESSAGE_CELL_HEIGHT = 48
    }
}

/** Where a question just sent goes: pinned under the header with room for its answer, or to the end as a messenger has it */
internal enum class AgentSentQuestionPlacement {
    PIN,
    END
}

internal fun getAgentSentQuestionPlacement(
    isLiveTailDisabled: Boolean
): AgentSentQuestionPlacement =
    if (isLiveTailDisabled) AgentSentQuestionPlacement.END else AgentSentQuestionPlacement.PIN

internal enum class AgentNewMessagesFollow {
    NONE,
    END,
    RELEASE_PIN_AND_END
}

/**
 * How the list follows new messages: to the end while it rested there, past a pinned question only once they outgrow
 * its reserve, and not at all when the user has scrolled up
 */
internal fun getAgentNewMessagesFollow(
    wasAtEnd: Boolean,
    isPinned: Boolean,
    latestRowOverhang: Int
): AgentNewMessagesFollow = when {
    !wasAtEnd -> AgentNewMessagesFollow.NONE
    !isPinned -> AgentNewMessagesFollow.END
    latestRowOverhang > 0 -> AgentNewMessagesFollow.RELEASE_PIN_AND_END
    else -> AgentNewMessagesFollow.NONE
}

/**
 * The unread divider that an update of the timeline brings, which the list shows at its top as a chat that opens at it
 * does; null when the divider was there before or isn't there
 */
internal fun List<AgentTimelineItem>.findArrivingUnreadDividerIndex(
    previous: List<AgentTimelineItem>
): Int? = indexOf(AgentTimelineItem.UnreadDivider)
    .takeIf { it >= 0 && AgentTimelineItem.UnreadDivider !in previous }

internal fun List<AgentTimelineItem>.agentPinAnchorIndex(messageIndex: Int): Int =
    if (getOrNull(messageIndex - 1) is AgentTimelineItem.DateHeader) {
        messageIndex - 1
    } else {
        messageIndex
    }

/**
 * How far below the content top the item at [anchorIndex] pins, so that the last line of a message above it stays in
 * view: [lineReveal], or nothing with no message above
 */
internal fun List<AgentTimelineItem>.agentPinPreviousLineReveal(
    anchorIndex: Int,
    lineReveal: Int
): Int {
    val hasMessageAbove = (anchorIndex - 1 downTo 0).any { this[it] is AgentTimelineItem.Message }
    return if (hasMessageAbove) lineReveal else 0
}

/**
 * Whether the latest row reaches more than [threshold] below the part of the list that the
 * composer leaves visible, by [overhang], so the scroll-to-bottom button shows. The chat follows
 * its end otherwise, and a question that waited comes up to the top as it goes.
 */
internal fun isAgentLatestRowOutOfSight(overhang: Int, threshold: Int): Boolean =
    overhang > threshold

/** A question reaching below [previewTop] moves up so its answer's start shows. */
internal fun agentPinnedItemOffset(
    item: AgentTimelineItem,
    itemHeight: Int,
    topPadding: Int,
    previewTop: Int
): Int {
    if (item is AgentTimelineItem.DateHeader) return 0
    return -(topPadding + itemHeight - previewTop).coerceAtLeast(0)
}
