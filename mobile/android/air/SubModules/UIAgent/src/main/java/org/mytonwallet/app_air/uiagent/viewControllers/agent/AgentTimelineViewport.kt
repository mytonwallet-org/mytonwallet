package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.ValueAnimator
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
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
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
    var isUserScrolling = false
        private set
    private var isApplyingSharedScrollPosition = false
    var pendingSharedScrollPosition: AgentVM.ScrollPosition? = null
        private set
    var isOnBottom = true
        private set
    var pinnedMessageId: String? = null
        private set
    var pendingPinMessageId: String? = null
        private set
    private var pendingOutgoingPreviousMessageId: String? = null
    private var outgoingEditMessageId: String? = null
    var deferredPinMessageId: String? = null
        private set
    private var cachedPinnedTarget = 0
    private var appliedBottom = 0
    private var pinScrollSpring: SpringAnimation? = null
    var pinScrollExtraSpace = 0
        private set

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
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (atBottom) {
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
        unpin()
        pendingPinMessageId = null
        clearOutgoingPlacement()
    }

    fun requestMessagePin(messageId: String, preservePadding: Boolean = false) {
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
        chatRecyclerView.stopScroll()
    }

    fun prepareOutgoingMessage(
        messageId: String,
        items: List<AgentTimelineItem>,
        forcePin: Boolean = false
    ): Boolean {
        pendingSharedScrollPosition = null
        pendingPinMessageId = messageId
        deferredPinMessageId = null
        outgoingEditMessageId = messageId.takeIf { forcePin }
        val previousMessageId = prepareOutgoingPlacement(items)
        pendingOutgoingPreviousMessageId = if (forcePin) null else previousMessageId
        return pendingOutgoingPreviousMessageId == null &&
            items.any { it is AgentTimelineItem.Message }
    }

    fun prepareEditInsertion(preservePin: Boolean = false) {
        pendingSharedScrollPosition = null
        if (preservePin) pinScrollSpring?.cancel() else clearPin()
        pendingPinMessageId = null
        clearOutgoingPlacement()
        chatRecyclerView.stopScroll()
    }

    fun activatePendingMessage(messageId: String) {
        pendingPinMessageId = messageId
        clearOutgoingPlacement()
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
        pendingPosts.forEach(chatRecyclerView::removeCallbacks)
        pendingPosts.clear()
        pendingLayouts.forEach(chatRecyclerView::removeOnLayoutChangeListener)
        pendingLayouts.clear()
        pendingDraws.forEach { it.removeListener() }
        pendingDraws.clear()
        keyboardAnimator?.cancel()
        clearPin()
        pendingPinMessageId = null
        pendingSharedScrollPosition = null
        chatRecyclerView.stopScroll()
    }

    private var hasAppliedInitialLayout = false

    fun updateLayout(targetBottom: Int, ime: Int, navigationBottom: Int) {
        if (isDisposed) return
        if (ime == 0) stableBottomInset = navigationBottom

        if (targetBottom != currentBottom) {
            val fromBottom = currentBottom
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
            keyboardAnimator = ValueAnimator.ofInt(fromBottom, targetBottom).apply {
                duration = 220
                interpolator = DecelerateInterpolator()
                addUpdateListener { animator ->
                    val value = animator.animatedValue as Int
                    val bottomPadding = keyboardPaddingStart?.let { start ->
                        val target = baseChatBottomPadding(targetBottom)
                        start + ((target - start) * animator.animatedFraction).roundToInt()
                    }
                    applyBottom(value, bottomPadding)
                }
                start()
            }
        } else if (keyboardAnimator?.isRunning != true) {
            applyBottom(targetBottom)
        }
    }

    private fun applyBottom(bottom: Int, bottomPaddingOverride: Int? = null) {
        if (isDisposed) return
        appliedBottom = bottom
        host.applyComposerBottom(bottom)

        val topPadding = chatTopPadding()
        val bottomPadding = bottomPaddingOverride ?: chatBottomPadding(bottom)
        val paddingChanged = chatRecyclerView.paddingTop != topPadding ||
            chatRecyclerView.paddingBottom != bottomPadding
        if (paddingChanged) chatRecyclerView.setPadding(0, topPadding, 0, bottomPadding)
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

    val pinnedTopOffset: Int
        get() = ViewConstants.TOOLBAR_RADIUS.dp.roundToInt()

    private fun pinnedMessageOffset(messageHeight: Int): Int {
        val regularOffset = -pinnedTopOffset
        val messageBottom =
            chatTopPadding() + regularOffset + messageHeight
        val previewTop =
            chatRecyclerView.height - baseChatBottomPadding(appliedBottom) -
                MIN_MESSAGE_CELL_HEIGHT.dp
        return regularOffset - (messageBottom - previewTop).coerceAtLeast(0)
    }

    private fun pinnedMessageHeight(view: View): Int =
        (view as? AgentMessageCell)?.layoutTargetHeight ?: view.height

    private fun pinnedMessageOffset(view: View): Int =
        pinnedMessageOffset(pinnedMessageHeight(view))

    private fun pinnedPaddingTarget(): Int? {
        val messageId = pinnedMessageId ?: return null
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return null
        val idx = timelineIndexOf(messageId)
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
            pinnedMessageOffset(messageHeight)
        cachedPinnedTarget = target
        return target
    }

    fun preservePinAcrossSizeTransition(
        messageId: String,
        cell: AgentMessageCell,
        previousHeight: Int
    ) {
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
        val pinnedTop = (chatRecyclerView.layoutManager as? LinearLayoutManager)
            ?.findViewByPosition(pinnedIndex)
            ?.let { pinnedView ->
                val expectedTop = chatRecyclerView.paddingTop + pinnedMessageOffset(pinnedView)
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
        val pinnedIndex = timelineIndexOf(pinnedId)
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
        if (atBottom == isOnBottom) return
        isOnBottom = atBottom
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (atBottom) {
            lm.stackFromEnd = true
        } else {
            val firstPos = lm.findFirstVisibleItemPosition()
            if (firstPos == RecyclerView.NO_POSITION) return
            val offset =
                (lm.findViewByPosition(firstPos)?.top ?: 0) - chatRecyclerView.paddingTop
            lm.stackFromEnd = false
            lm.scrollToPositionWithOffset(firstPos, offset)
        }
    }

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
        if (pinnedMessageId == null && !chatRecyclerView.canScrollVertically(1)) {
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
        val position = host.scrollPosition ?: return false
        pendingSharedScrollPosition = position
        isApplyingSharedScrollPosition = true
        try {
            applySharedScrollPosition(position)
        } finally {
            isApplyingSharedScrollPosition = false
        }
        return true
    }

    fun showInitialPromptAtBottom() {
        isApplyingSharedScrollPosition = false
        val position = AgentVM.ScrollPosition(AgentVM.ScrollAnchor.Bottom)
        pendingSharedScrollPosition = null
        host.publishScrollPosition(position)
        applySharedScrollPosition(position)
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
        if (messageId == null || bottomPadding <= 0 || timelineIndexOf(messageId) < 0) {
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
            is AgentTimelineItem.DateHeader -> null
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
        animated: Boolean = WGlobalStorage.getAreAnimationsActive()
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
        if (messageView == null) {
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
                targetHeight?.takeIf { it != 0 } ?: MIN_MESSAGE_CELL_HEIGHT.dp
            cachedPinnedTarget = maxOf(
                baseChatBottomPadding(appliedBottom),
                chatRecyclerView.height - chatTopPadding() -
                    messageHeight - pinnedMessageOffset(messageHeight)
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

                    override fun calculateDyToMakeVisible(view: View, snapPreference: Int): Int =
                        super.calculateDyToMakeVisible(view, snapPreference) +
                            pinnedMessageOffset(view)

                    override fun onStop() {
                        super.onStop()
                        post {
                            if (pendingPinMessageId == messageId) {
                                evaluatePinning(messageId, isRetry = true, animated = animated)
                            }
                        }
                    }
                }
                scroller.targetPosition = idx
                lm.startSmoothScroll(scroller)
            } else {
                val offset = pinnedMessageOffset(messageHeight)
                lm.scrollToPositionWithOffset(idx, offset)
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
            pinScrollExtraSpace = messageView.top
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
        if (wasOffscreenPin && !animated) {
            lm.scrollToPositionWithOffset(idx, pinnedMessageOffset(messageView))
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

    private fun startPinScroll(
        messageId: String,
        animated: Boolean = WGlobalStorage.getAreAnimationsActive()
    ) {
        if (isDisposed) return
        if (pinnedMessageId != messageId) return
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val idx = timelineIndexOf(messageId)
        if (idx < 0) return
        val messageView = lm.findViewByPosition(idx)
        val targetOffset = messageView?.let(::pinnedMessageOffset)
        val dy = messageView?.let {
            it.top - (chatRecyclerView.paddingTop + (targetOffset ?: 0))
        }
        if (dy == null || dy <= 0 || !animated) {
            pinScrollExtraSpace = 0
            if (dy == null || dy != 0) {
                lm.scrollToPositionWithOffset(idx, targetOffset ?: -pinnedTopOffset)
            }
            finishInitialHintsDismissal(messageId)
            notifyMessagePinned(messageId)
            return
        }
        val startTop = messageView.top
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
                val currentIndex = timelineIndexOf(messageId)
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
                    val currentIndex = timelineIndexOf(messageId)
                    val view = lm.findViewByPosition(currentIndex)
                    val offset = view?.let(::pinnedMessageOffset) ?: -pinnedTopOffset
                    if (currentIndex >= 0 && view?.top != chatRecyclerView.paddingTop + offset) {
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
            val idx = timelineIndexOf(messageId)
            if (idx >= 0) {
                val view = lm.findViewByPosition(idx)
                val offset = view?.let(::pinnedMessageOffset) ?: -pinnedTopOffset
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
