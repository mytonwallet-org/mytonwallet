package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.view.doOnNextLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uiagent.processors.AgentResult
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore

class AgentVC(context: Context, initialPrompt: String? = null) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    AgentVM.Delegate {

    @Suppress("PropertyName")
    override val TAG = "Agent"
    override val ignoreSideGuttering = true

    companion object {
        val DATE_CELL = WCell.Type(1)
        val MESSAGE_CELL = WCell.Type(2)
        val SYSTEM_CELL = WCell.Type(3)
        val HINTS_CELL = WCell.Type(4)
        private const val GRADIENT_EXTRA = 4
        private const val DATE_HEADER_GAP_MS = 10 * 60 * 1000L
        private const val BOTTOM_OFFSET = 17
        private const val MIN_MESSAGE_CELL_HEIGHT = 48
        private const val HINTS_SETTLE_FALLBACK_MS = 3000L
        private const val INCOMING_MESSAGE_DELAY_MS = 250L
    }

    private data class PendingIncomingReveal(
        val outgoingMessageId: String,
        var incomingMessageId: String? = null,
        var isOutgoingAnimationFinished: Boolean = false,
        var isDelayElapsed: Boolean = false,
        var revealRunnable: Runnable? = null
    )

    private val composerBottomOffset: Int
        get() {
            return if (window?.isWideLayout == true) 0 else -BOTTOM_OFFSET
        }
    private val vm = AgentSession.acquire()
    private var isAttachedToSession = false
    private var isSessionReleased = false
    private var initialPromptAwaitingInsertion = initialPrompt?.takeIf { it.isNotBlank() }
    private var pendingInitialPrompt = initialPromptAwaitingInsertion
    private var timelineItems = listOf<AgentTimelineItem>()
    private var animateFromIndex = -1
    private var currentBottom = 0
    private var keyboardAnimator: ValueAnimator? = null
    private var gradientHeightAnimator: ValueAnimator? = null
    private var pendingHintsReveal = false
    private var dismissingHints: AgentTimelineItem.Hints? = null
    private var dismissingHintsAnchorId: String? = null
    private var hintsSettleFallback: Runnable? = null
    private var hintsSettleMessageId: String? = null
    private var isPopupVisible = false
    private var isUserScrolling = false
    private var isApplyingSharedScrollPosition = false
    private var pendingSharedScrollPosition: AgentVM.ScrollPosition? = null
    private var isOnBottom = true
    private var pinnedMessageId: String? = null
    private var pendingPinMessageId: String? = null
    private var pendingOutgoingPreviousMessageId: String? = null
    private var deferredPinMessageId: String? = null
    private val pendingIncomingReveals = linkedMapOf<String, PendingIncomingReveal>()
    private val outgoingMessageIdsAwaitingIncoming = mutableListOf<String>()
    private val hiddenIncomingMessageIds = mutableSetOf<String>()
    private var cachedPinnedTarget = 0
    private var appliedBottom = 0
    private var pinScrollSpring: SpringAnimation? = null
    private var pinScrollExtraSpace = 0

    private val timezoneReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            rebuildTimeline()
        }
    }

    private val rvAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(
            DATE_CELL,
            MESSAGE_CELL,
            SYSTEM_CELL,
            HINTS_CELL
        )
    )

    private val chatRecyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        itemAnimator = null
        layoutManager = object : LinearLayoutManager(context) {
            override fun calculateExtraLayoutSpace(
                state: RecyclerView.State,
                extraLayoutSpace: IntArray
            ) {
                super.calculateExtraLayoutSpace(state, extraLayoutSpace)
                if (pinScrollExtraSpace > extraLayoutSpace[1]) {
                    extraLayoutSpace[1] = pinScrollExtraSpace
                }
            }
        }.apply {
            stackFromEnd = true
        }
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) {
                    isUserScrolling = true
                    pendingSharedScrollPosition = null
                    pinScrollSpring?.cancel()
                } else if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    isUserScrolling = false
                    shareScrollPosition()
                }
                if (newState != RecyclerView.SCROLL_STATE_IDLE) updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (isUserScrolling) {
                    releasePinIfTrailingContentIsBelowViewport(recyclerView, dy)
                    val atBottom = !recyclerView.canScrollVertically(1)
                    if (pinnedMessageId == null && isOnBottom != atBottom) {
                        isOnBottom = atBottom
                        val lm = recyclerView.layoutManager as? LinearLayoutManager ?: return
                        if (!atBottom) {
                            val firstPos = lm.findFirstVisibleItemPosition()
                            if (firstPos == RecyclerView.NO_POSITION) return
                            val firstView = lm.findViewByPosition(firstPos)
                            val offset = (firstView?.top ?: 0) - recyclerView.paddingTop
                            lm.stackFromEnd = false
                            lm.scrollToPositionWithOffset(firstPos, offset)
                        } else {
                            lm.stackFromEnd = true
                        }
                    }
                    updateBlurViews(recyclerView)
                }
                shareScrollPosition()
            }
        })
        addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            val newWidth = right - left
            if (newWidth > 0 && newWidth != oldRight - oldLeft) {
                rvAdapter.updateVisibleCells()
                restoreSharedScrollPosition()
                doOnNextLayout {
                    restoreSharedScrollPosition()
                }
            } else if (pinnedMessageId != null) {
                post { syncPinnedPadding() }
            }
            pendingSharedScrollPosition?.let { position ->
                if (restorePendingSharedScrollPosition(position)) {
                    pendingSharedScrollPosition = null
                    shareScrollPosition()
                }
            }
        }
    }

    private val bottomGradientView = View(context).apply {
        id = View.generateViewId()
    }
    private val composerView by lazy { AgentComposerView(context, chatRecyclerView) }

    private val contentContainer: WView by lazy {
        WView(context).apply {
            addView(chatRecyclerView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(
                bottomGradientView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, 0)
            )
            addView(
                composerView,
                ConstraintLayout.LayoutParams(
                    MATCH_PARENT,
                    ConstraintLayout.LayoutParams.WRAP_CONTENT
                )
            )

            setConstraints {
                allEdges(chatRecyclerView)

                toStart(bottomGradientView)
                toEnd(bottomGradientView)
                toBottom(bottomGradientView)

                toStart(composerView)
                toEnd(composerView)
                toBottomPx(
                    composerView,
                    composerBottomOffset.dp + (navigationController?.getSystemBars()?.bottom ?: 0)
                )
            }
        }
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPaddingDp(8)
        btn.setImageDrawable(
            context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_more)
        )
        btn.updateColors(WColor.PrimaryLightText, WColor.BackgroundRipple)
        btn.setOnClickListener { presentMoreMenu() }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Agent"))
        setupNavBar(true)
        navigationBar?.addTrailingView(moreButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))

        composerView.onSend = { text ->
            sendMessage(text)
        }
        composerView.onHeightChanged = {
            updateLayout()
        }
        composerView.onHintsToggle = {
            vm.toggleHintsVisibility()
        }

        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        composerView.post { updateGradientHeight(animated = false) }

        ContextCompat.registerReceiver(
            context,
            timezoneReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_TIMEZONE_CHANGED)
                addAction(Intent.ACTION_DATE_CHANGED)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        updateTheme()
        vm.attach(this)
        isAttachedToSession = true
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        vm.setActive(this, true)
        if (initialPromptAwaitingInsertion != null) {
            showInitialPromptAtBottom()
        } else {
            restoreSharedScrollPosition()
        }
        vm.checkAccountChanged()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        pendingSharedScrollPosition?.let { position ->
            if (restorePendingSharedScrollPosition(position)) {
                pendingSharedScrollPosition = null
                shareScrollPosition()
            }
        }
        val prompt = pendingInitialPrompt ?: return
        pendingInitialPrompt = null
        showInitialPromptAtBottom()
        submitPrompt(prompt)
    }

    override fun viewWillDisappear() {
        shareScrollPosition()
        super.viewWillDisappear()
        vm.setActive(this, false)
    }

    override fun onDestroy() {
        shareScrollPosition()
        cancelHintsSettleFallback()
        cancelPendingIncomingReveals()
        vm.setActive(this, false)
        if (isAttachedToSession) {
            vm.detach(this)
            isAttachedToSession = false
        }
        if (!isSessionReleased) {
            AgentSession.release(vm)
            isSessionReleased = true
        }
        context.unregisterReceiver(timezoneReceiver)
        super.onDestroy()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        chatRecyclerView.setBackgroundColor(WColor.Background.color)
        if (window?.isWideLayout == true) {
            view.setPaddingLocalized(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0
            )
        } else {
            view.setPadding(0)
        }
        if (window?.isWideLayout == true || WGlobalStorage.isGradientNavigationBarActive()) {
            bottomGradientView.isGone = false
            val bgColor = WColor.Background.color
            val bgColor80 = bgColor.colorWithAlpha(204)
            val bgColor90 = bgColor.colorWithAlpha(230)
            bottomGradientView.background = GradientShaderDrawable(
                intArrayOf(bgColor90 and 0x00FFFFFF, bgColor80, bgColor90),
                floatArrayOf(0f, 0.1f, 1f)
            )
        } else {
            bottomGradientView.isGone = true
        }
        composerView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        contentContainer.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            0,
            systemBarEndInset,
            0
        )
        topReversedCornerView?.setSideInsets(
            systemBarStartInset.toFloat(),
            systemBarEndInset.toFloat()
        )
        updateLayout()
    }

    override fun updateBlurViews(recyclerView: RecyclerView) {
        super.updateBlurViews(recyclerView)
        if (recyclerView.computeVerticalScrollOffset() == 0) {
            composerView.pauseBlurring()
        } else {
            composerView.resumeBlurring()
        }
    }

    private var hasAppliedInitialLayout = false

    private fun updateLayout() {
        val ime = navigationController?.imeInsetBottom ?: 0
        val nav = navigationController?.getSystemBars()?.bottom ?: 0
        val targetBottom = maxOf(ime, nav)
        if (ime == 0) stableBottomInset = nav

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
        appliedBottom = bottom
        contentContainer.setConstraints {
            toBottomPx(composerView, bottom + composerBottomOffset.dp)
        }
        updateGradientHeight(animated = false)

        val topPadding = chatTopPadding()
        val bottomPadding = bottomPaddingOverride ?: chatBottomPadding(bottom)
        val paddingChanged = chatRecyclerView.paddingTop != topPadding ||
            chatRecyclerView.paddingBottom != bottomPadding
        if (paddingChanged) chatRecyclerView.setPadding(0, topPadding, 0, bottomPadding)
    }

    private fun chatTopPadding(): Int =
        (navigationController?.getSystemBars()?.top ?: 0) + (navigationBar?.height ?: 0)

    private var stableBottomInset = 0

    private fun baseChatBottomPadding(bottom: Int = currentBottom): Int =
        composerView.height + bottom + composerBottomOffset.dp + BOTTOM_OFFSET.dp

    private fun chatBottomPadding(bottom: Int): Int {
        val base = baseChatBottomPadding(bottom)
        if (pinnedMessageId == null) return base
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

    private val pinnedTopOffset: Int
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

    private fun updateGradientHeight(animated: Boolean) {
        val lp = bottomGradientView.layoutParams ?: return
        val targetHeight = composerView.height + currentBottom + GRADIENT_EXTRA.dp

        if (!animated) {
            lp.height = targetHeight
            bottomGradientView.layoutParams = lp
            return
        }

        val currentHeight = bottomGradientView.height
        if (currentHeight == targetHeight) return

        gradientHeightAnimator?.cancel()
        gradientHeightAnimator = ValueAnimator.ofInt(currentHeight, targetHeight).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                val p = bottomGradientView.layoutParams ?: return@addUpdateListener
                p.height = animator.animatedValue as Int
                bottomGradientView.layoutParams = p
            }
            start()
        }
    }

    private fun sendMessage(text: String) {
        vm.sendMessage(text)
        view.hideKeyboard()
    }

    fun submitPrompt(text: String) {
        if (text.isNotBlank()) vm.sendMessage(text)
    }

    private fun presentMoreMenu() {
        val items = mutableListOf<WMenuPopup.Item>()

        if (DEBUG_MODE || EnvironmentStore.isBeta) {
            val currentType = vm.processorType
            val types =
                AgentVM.ProcessorType.entries.filter {
                    it != currentType &&
                        (DEBUG_MODE || it != AgentVM.ProcessorType.MOCK)
                }
            for (type in types) {
                val label = when (type) {
                    AgentVM.ProcessorType.MOCK -> "Switch to Mock"
                    AgentVM.ProcessorType.REAL -> "Switch to Real"
                }
                items.add(
                    WMenuPopup.Item(null, label) {
                        vm.setProcessor(type)
                    }
                )
            }
        }

        items.add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = WMenuPopup.Item.Config.Icon(
                        iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_remove,
                        tintColor = null
                    ),
                    title = LocaleController.getString("Clear Chat"),
                    titleColor = WColor.Red.color
                )
            ) {
                clearChat()
            }
        )

        WMenuPopup.present(
            moreButton,
            items,
            positioning = WMenuPopup.Positioning.ALIGNED
        )
    }

    private fun clearChat() {
        vm.clearChat()
    }

    // AgentVM.Delegate

    override fun onMessagesLoaded(messages: List<AgentMessage>) {
        animateFromIndex = -1
        unpin()
        pendingPinMessageId = null
        cancelPendingIncomingReveals()
        dismissingHints = null
        dismissingHintsAnchorId = null
        cancelHintsSettleFallback()
        timelineItems = buildTimelineItems(messages)
        rvAdapter.reloadData()
        if (initialPromptAwaitingInsertion != null) {
            showInitialPromptAtBottom()
        } else if (!restoreSharedScrollPosition()) {
            scrollToBottom()
        }
    }

    override fun onMessageAdded(message: AgentMessage) {
        if (message.role == AgentMessageRole.USER &&
            message.text == initialPromptAwaitingInsertion
        ) {
            initialPromptAwaitingInsertion = null
        }
        val oldItems = timelineItems
        var shouldStartOffscreenPin = false
        if (message.role == AgentMessageRole.USER) {
            pendingIncomingReveals[message.id] = PendingIncomingReveal(message.id)
            outgoingMessageIdsAwaitingIncoming.add(message.id)
            pendingPinMessageId = message.id
            deferredPinMessageId = null
            pendingOutgoingPreviousMessageId = prepareOutgoingPlacement(oldItems)
            shouldStartOffscreenPin =
                pendingOutgoingPreviousMessageId == null &&
                oldItems.any { it is AgentTimelineItem.Message }
        } else if (message.role == AgentMessageRole.ASSISTANT) {
            val outgoingMessageId = outgoingMessageIdsAwaitingIncoming.firstOrNull()
            val pendingReveal = outgoingMessageId?.let { pendingIncomingReveals[it] }
            if (outgoingMessageId != null && pendingReveal != null) {
                outgoingMessageIdsAwaitingIncoming.removeAt(0)
                pendingReveal.incomingMessageId = message.id
                hiddenIncomingMessageIds.add(message.id)
                schedulePendingIncomingReveal(pendingReveal)
                return
            }
        }
        if (animateFromIndex < 0) {
            animateFromIndex = oldItems.size
            chatRecyclerView.doOnNextLayout {
                animateFromIndex = -1
            }
        }
        // Visible trailing hints keep their place and collapse animated while the new
        // messages are appended after them.
        val trailingHints = oldItems.lastOrNull() as? AgentTimelineItem.Hints
        var dismissalCell: AgentHintsCell? = null
        var shouldScrollInitialHintsOffscreen = false
        if (trailingHints != null && dismissingHints == null) {
            dismissingHints = trailingHints
            dismissingHintsAnchorId = (
                oldItems.getOrNull(oldItems.size - 2)
                    as? AgentTimelineItem.Message
                )?.message?.id
            val holder = chatRecyclerView.findViewHolderForAdapterPosition(oldItems.size - 1)
            dismissalCell = (holder as? WCell.Holder)?.cell as? AgentHintsCell
            shouldScrollInitialHintsOffscreen = message.role == AgentMessageRole.USER &&
                dismissingHintsAnchorId == null &&
                dismissalCell != null
        }
        timelineItems = buildTimelineItems(vm.messages)
        val appended = timelineItems.size - oldItems.size
        if (appended > 0 && timelineItems.subList(0, oldItems.size) == oldItems) {
            WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
                .onInserted(oldItems.size, appended)
        } else {
            rvAdapter.reloadData()
        }
        if (trailingHints != null &&
            dismissingHints === trailingHints &&
            !shouldScrollInitialHintsOffscreen
        ) {
            if (dismissalCell != null) {
                dismissalCell.collapse { finishHintsDismissal() }
            } else {
                finishHintsDismissal()
            }
        }
        when {
            message.role == AgentMessageRole.USER -> {
                val preparePinning = {
                    chatRecyclerView.post {
                        val pendingReveal = pendingIncomingReveals[message.id]
                        if (pendingReveal?.isOutgoingAnimationFinished == false) {
                            val messageIndex = timelineIndexOf(message.id)
                            if (chatRecyclerView.findViewHolderForAdapterPosition(messageIndex) ==
                                null
                            ) {
                                onOutgoingInsertAnimationFinished(message.id)
                            }
                        }
                        if (pendingPinMessageId == message.id &&
                            deferredPinMessageId != message.id
                        ) {
                            evaluatePinning(message.id)
                        }
                    }
                }
                if (shouldStartOffscreenPin) {
                    preparePinning()
                } else {
                    chatRecyclerView.doOnNextLayout { preparePinning() }
                }
            }

            pendingPinMessageId != null ||
                pinnedMessageId != null ||
                pendingSharedScrollPosition != null -> {
                // The pinned anchor keeps its position; syncPinnedPadding fits the new
                // content into the reserved space instead of scrolling.
            }

            else -> scrollToBottom()
        }
    }

    override fun onStreamingUpdate(messageId: String, text: String) {
        onStreamEvent(messageId)
    }

    override fun onStreamingFinished(messageId: String) {
        onStreamEvent(messageId)
    }

    private fun onStreamEvent(messageId: String) {
        if (hiddenIncomingMessageIds.contains(messageId)) return
        val hadHints = timelineItems.lastOrNull() is AgentTimelineItem.Hints
        var newItems = buildTimelineItems(vm.messages)
        val hintsDue = !hadHints && newItems.lastOrNull() is AgentTimelineItem.Hints
        if (hintsDue) {
            // Hold hints back until the message's own animations (text reveal, deeplink
            // appearance) have finished playing.
            newItems = newItems.dropLast(1)
        }
        timelineItems = newItems
        val updatedInPlace = updateVisibleCell(messageId)
        if (!updatedInPlace) {
            rvAdapter.reloadData()
        }
        if (hintsDue) {
            // A newer response supersedes any settlement still pending for an older one.
            cancelHintsSettleFallback()
            val holder = chatRecyclerView
                .findViewHolderForAdapterPosition(timelineIndexOf(messageId))
            val cell = (holder as? WCell.Holder)?.cell as? AgentMessageCell
            if (updatedInPlace && cell?.isContentSettling == true) {
                hintsSettleMessageId = messageId
                cell.onContentSettled = { appendDueHints(messageId) }
                // The settle callback can get lost if the cell is recycled mid-animation.
                val fallback = Runnable { appendDueHints(messageId) }
                hintsSettleFallback = fallback
                chatRecyclerView.postDelayed(fallback, HINTS_SETTLE_FALLBACK_MS)
            } else {
                appendDueHints(messageId)
            }
        }
        if (isOnBottom) {
            scrollToBottom()
        }
    }

    private fun cancelHintsSettleFallback() {
        hintsSettleMessageId = null
        hintsSettleFallback?.let { chatRecyclerView.removeCallbacks(it) }
        hintsSettleFallback = null
    }

    private fun onOutgoingInsertAnimationFinished(messageId: String) {
        val pendingReveal = pendingIncomingReveals[messageId] ?: return
        pendingReveal.isOutgoingAnimationFinished = true
        schedulePendingIncomingReveal(pendingReveal)
    }

    private fun onOutgoingInsertAnimationStarted(messageId: String) {
        val pendingReveal = pendingIncomingReveals[messageId] ?: return
        pendingReveal.revealRunnable?.let { chatRecyclerView.removeCallbacks(it) }
        pendingReveal.revealRunnable = null
        pendingReveal.isOutgoingAnimationFinished = false
        pendingReveal.isDelayElapsed = false
    }

    private fun schedulePendingIncomingReveal(pendingReveal: PendingIncomingReveal) {
        if (!pendingReveal.isOutgoingAnimationFinished ||
            pendingReveal.revealRunnable != null
        ) {
            return
        }
        val incomingMessageId = pendingReveal.incomingMessageId ?: return
        val reveal = Runnable {
            pendingReveal.revealRunnable = null
            pendingReveal.isDelayElapsed = true
            revealReadyIncomingMessages()
        }
        pendingReveal.revealRunnable = reveal
        chatRecyclerView.postDelayed(reveal, INCOMING_MESSAGE_DELAY_MS)
    }

    private fun revealReadyIncomingMessages() {
        val pendingReveal = pendingIncomingReveals.values.firstOrNull() ?: return
        val incomingMessageId = pendingReveal.incomingMessageId ?: return
        if (!pendingReveal.isDelayElapsed) return
        revealDelayedIncomingMessage(
            pendingReveal.outgoingMessageId,
            incomingMessageId
        )
    }

    private fun revealDelayedIncomingMessage(outgoingMessageId: String, incomingMessageId: String) {
        val pendingReveal = pendingIncomingReveals[outgoingMessageId] ?: return
        if (pendingReveal.incomingMessageId != incomingMessageId ||
            !hiddenIncomingMessageIds.remove(incomingMessageId)
        ) {
            return
        }
        pendingIncomingReveals.remove(outgoingMessageId)
        val oldItemCount = timelineItems.size
        val newItems = buildTimelineItems(vm.messages)
        val insertedAt = newItems.indexOfFirst {
            it is AgentTimelineItem.Message && it.message.id == incomingMessageId
        }
        timelineItems = newItems
        val insertedCount = newItems.size - oldItemCount
        if (insertedAt < 0 || insertedCount != 1) {
            animateFromIndex = -1
            rvAdapter.reloadData()
        } else {
            animateFromIndex = insertedAt
            WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
                .onInserted(insertedAt, insertedCount)
        }
        val pinMessageId = deferredPinMessageId.takeIf { it == outgoingMessageId }
        chatRecyclerView.doOnNextLayout {
            animateFromIndex = -1
            if (pinMessageId != null && pendingPinMessageId == pinMessageId) {
                deferredPinMessageId = null
                evaluatePinning(pinMessageId)
            } else if (pinnedMessageId != null) {
                syncPinnedPadding()
            }
            revealReadyIncomingMessages()
        }
    }

    private fun cancelPendingIncomingReveals() {
        pendingIncomingReveals.values.forEach { pendingReveal ->
            pendingReveal.revealRunnable?.let { chatRecyclerView.removeCallbacks(it) }
        }
        pendingIncomingReveals.clear()
        outgoingMessageIdsAwaitingIncoming.clear()
        hiddenIncomingMessageIds.clear()
        pendingOutgoingPreviousMessageId = null
        deferredPinMessageId = null
    }

    private fun appendDueHints(messageId: String) {
        // A settlement scheduled for a superseded response must not release the newer one's hints.
        if (hintsSettleMessageId != null && hintsSettleMessageId != messageId) return
        cancelHintsSettleFallback()
        if (timelineItems.lastOrNull() is AgentTimelineItem.Hints) return
        val canonical = buildTimelineItems(vm.messages)
        if (canonical.lastOrNull() !is AgentTimelineItem.Hints) return
        timelineItems = canonical
        scheduleHintsReveal()
        insertHintsItem()
        refreshIsOnBottom()
        if (isOnBottom) scrollToBottom()
    }

    private fun scheduleHintsReveal() {
        pendingHintsReveal = true
        chatRecyclerView.doOnNextLayout { pendingHintsReveal = false }
    }

    // Targeted notifications keep the layout manager's anchor (and the pinned message) in
    // place; reloadData would relayout from scratch and make the chat jump.
    private fun insertHintsItem() {
        WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
            .onInserted(timelineItems.size - 1, 1)
    }

    private fun removeHintsItem(index: Int) {
        WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
            .onRemoved(index, 1)
    }

    private fun onHintsCollapseFrame(delta: Int) {
        preserveDismissingHintsSpace(delta)
    }

    // Transfers the disappearing cell height into bottom padding within the same frame,
    // keeping pinned content and pending outgoing placement from filling the end gap.
    private fun preserveDismissingHintsSpace(delta: Int) {
        if (delta <= 0) return
        val hints = dismissingHints
            ?: timelineItems.lastOrNull() as? AgentTimelineItem.Hints
            ?: return
        val hintsIdx = timelineItems.indexOf(hints)
        if (hintsIdx < 0) return
        val pinnedIdx = pinnedMessageId?.let { timelineIndexOf(it) } ?: -1
        val pendingIdx = pendingPinMessageId?.let { timelineIndexOf(it) } ?: -1
        val preservesPinnedMessage = pinnedIdx >= 0 && hintsIdx > pinnedIdx
        val preservesPendingPlacement =
            dismissingHintsAnchorId != null && pendingIdx >= 0 && hintsIdx < pendingIdx
        if (!preservesPinnedMessage && !preservesPendingPlacement) return
        val bottomPadding = if (preservesPinnedMessage) {
            val pinnedTarget = cachedPinnedTarget.takeIf { it != 0 }
                ?: pinnedPaddingTarget()
                ?: return
            (pinnedTarget + delta).also { cachedPinnedTarget = it }
                .coerceAtLeast(baseChatBottomPadding(appliedBottom))
        } else {
            chatRecyclerView.paddingBottom + delta
        }
        chatRecyclerView.setPadding(
            0,
            chatRecyclerView.paddingTop,
            0,
            bottomPadding
        )
    }

    private fun finishHintsDismissal() {
        val item = dismissingHints ?: return
        dismissingHints = null
        dismissingHintsAnchorId = null
        val idx = timelineItems.indexOf(item)
        if (idx >= 0) {
            timelineItems = timelineItems.filterIndexed { i, _ -> i != idx }
            removeHintsItem(idx)
        }
        // Hints may be due again already (e.g. the dismissal was caused by a system
        // message rather than a new request).
        val canonical = buildTimelineItems(vm.messages)
        if (canonical.lastOrNull() is AgentTimelineItem.Hints &&
            timelineItems.lastOrNull() !is AgentTimelineItem.Hints
        ) {
            timelineItems = canonical
            scheduleHintsReveal()
            insertHintsItem()
            refreshIsOnBottom()
            if (isOnBottom) scrollToBottom()
        }
    }

    private fun updateVisibleCell(messageId: String): Boolean {
        val idx = timelineIndexOf(messageId)
        if (idx < 0) return false

        val holder = chatRecyclerView.findViewHolderForAdapterPosition(idx)
        if (holder is WCell.Holder) {
            val message = (timelineItems[idx] as AgentTimelineItem.Message).message
            (holder.cell as? AgentMessageCell)?.configure(message, chatRecyclerView.width)
            return true
        }
        return false
    }

    private fun preservePinAcrossSizeTransition(
        messageId: String,
        cell: AgentMessageCell,
        previousHeight: Int
    ) {
        if (isUserScrolling) return
        val pinnedId = pinnedMessageId ?: return
        val messageIndex = timelineIndexOf(messageId)
        val pinnedIndex = timelineIndexOf(pinnedId)
        if (messageIndex !in 0 until pinnedIndex) return
        chatRecyclerView.doOnPreDraw {
            if (isUserScrolling || pinnedMessageId != pinnedId) return@doOnPreDraw
            val currentMessageIndex = chatRecyclerView.getChildAdapterPosition(cell)
            val currentPinnedIndex = timelineIndexOf(pinnedId)
            val item = timelineItems.getOrNull(currentMessageIndex)
                as? AgentTimelineItem.Message
            if (item?.message?.id != messageId ||
                currentMessageIndex !in 0 until currentPinnedIndex
            ) {
                return@doOnPreDraw
            }
            val delta = cell.height - previousHeight
            if (delta != 0) {
                chatRecyclerView.scrollBy(0, delta)
            }
        }
    }

    // isOnBottom only tracks user scrolls; a programmatic content change (e.g. the hints
    // collapse) can leave the list resting at the bottom with the flag stale. Recompute
    // it from the actual scroll state before decisions that depend on it.
    private fun refreshIsOnBottom() {
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

    private fun scrollToBottom() {
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
        if (rvAdapter.itemCount == 0) return
        if (isPopupVisible) return
        val targetPosition = rvAdapter.itemCount - 1
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val scroller = object : LinearSmoothScroller(context) {
            override fun getVerticalSnapPreference(): Int = SNAP_TO_END
        }
        scroller.targetPosition = targetPosition
        layoutManager.startSmoothScroll(scroller)
    }

    private fun shareScrollPosition() {
        if (isApplyingSharedScrollPosition || pendingSharedScrollPosition != null) return
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        if (pinnedMessageId == null && !chatRecyclerView.canScrollVertically(1)) {
            vm.updateScrollPosition(
                this,
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
            vm.updateScrollPosition(
                this,
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

    private fun restoreSharedScrollPosition(): Boolean {
        val position = vm.scrollPosition ?: return false
        pendingSharedScrollPosition = position
        isApplyingSharedScrollPosition = true
        try {
            applySharedScrollPosition(position)
        } finally {
            isApplyingSharedScrollPosition = false
        }
        return true
    }

    private fun showInitialPromptAtBottom() {
        isApplyingSharedScrollPosition = false
        val position = AgentVM.ScrollPosition(AgentVM.ScrollAnchor.Bottom)
        pendingSharedScrollPosition = null
        vm.updateScrollPosition(this, position)
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

        clearPin()
        pinnedMessageId = messageId
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
        if (rvAdapter.itemCount == 0) return
        chatRecyclerView.scrollToPosition(rvAdapter.itemCount - 1)
        chatRecyclerView.scrollBy(0, Int.MAX_VALUE)
    }

    private fun scrollAnchorAt(index: Int): AgentVM.ScrollAnchor? =
        when (val item = timelineItems.getOrNull(index)) {
            is AgentTimelineItem.Message -> AgentVM.ScrollAnchor.Message(item.message.id)
            is AgentTimelineItem.Hints -> AgentVM.ScrollAnchor.Hints
            is AgentTimelineItem.DateHeader -> null
            null -> null
        }

    private fun timelineIndexOf(anchor: AgentVM.ScrollAnchor): Int = when (anchor) {
        AgentVM.ScrollAnchor.Bottom -> -1

        AgentVM.ScrollAnchor.Hints ->
            timelineItems.indexOfFirst { it is AgentTimelineItem.Hints }

        is AgentVM.ScrollAnchor.Message -> timelineIndexOf(anchor.messageId)
    }

    private fun timelineIndexOf(messageId: String): Int = timelineItems.indexOfFirst {
        it is AgentTimelineItem.Message && it.message.id == messageId
    }

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

    private fun onOutgoingInsertAnimationPrepared(messageId: String, targetHeight: Int) {
        if (pendingPinMessageId != messageId) return
        val previousMessageId = pendingOutgoingPreviousMessageId
        pendingOutgoingPreviousMessageId = null
        if (previousMessageId != null &&
            outgoingMessageFitsBelow(previousMessageId, messageId, targetHeight)
        ) {
            deferredPinMessageId = messageId
        } else {
            chatRecyclerView.post {
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
        val hintsIndex = dismissingHints?.let { timelineItems.indexOf(it) } ?: -1
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

    private fun evaluatePinning(
        messageId: String,
        targetHeight: Int? = null,
        isRetry: Boolean = false
    ) {
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
            lm.stackFromEnd = false
            if (WGlobalStorage.getAreAnimationsActive()) {
                val scroller = object : LinearSmoothScroller(context) {
                    override fun getVerticalSnapPreference(): Int = SNAP_TO_START

                    override fun calculateDyToMakeVisible(view: View, snapPreference: Int): Int =
                        super.calculateDyToMakeVisible(view, snapPreference) +
                            pinnedMessageOffset(view)

                    override fun onStop() {
                        super.onStop()
                        chatRecyclerView.post {
                            if (pendingPinMessageId == messageId) {
                                evaluatePinning(messageId, isRetry = true)
                            }
                        }
                    }
                }
                scroller.targetPosition = idx
                lm.startSmoothScroll(scroller)
            } else {
                val offset = pinnedMessageOffset(messageHeight)
                lm.scrollToPositionWithOffset(idx, offset)
                chatRecyclerView.doOnNextLayout {
                    if (pendingPinMessageId == messageId) {
                        evaluatePinning(messageId, isRetry = true)
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
        if (WGlobalStorage.getAreAnimationsActive() && !wasOffscreenPin) {
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
        if (wasOffscreenPin && !WGlobalStorage.getAreAnimationsActive()) {
            lm.scrollToPositionWithOffset(idx, pinnedMessageOffset(messageView))
        } else if (paddingChanged) {
            if (!wasOffscreenPin) {
                chatRecyclerView.doOnNextLayout { startPinScroll(messageId) }
            }
        } else if (!wasOffscreenPin) {
            startPinScroll(messageId)
        }
    }

    private fun clearPin() {
        pinnedMessageId = null
        cachedPinnedTarget = 0
        pinScrollExtraSpace = 0
        pinScrollSpring?.cancel()
    }

    private fun startPinScroll(messageId: String) {
        if (pinnedMessageId != messageId) return
        val lm = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return
        val idx = timelineIndexOf(messageId)
        if (idx < 0) return
        val messageView = lm.findViewByPosition(idx)
        val targetOffset = messageView?.let(::pinnedMessageOffset)
        val dy = messageView?.let {
            it.top - (chatRecyclerView.paddingTop + (targetOffset ?: 0))
        }
        if (dy == null || dy <= 0 || !WGlobalStorage.getAreAnimationsActive()) {
            pinScrollExtraSpace = 0
            if (dy == null || dy != 0) {
                lm.scrollToPositionWithOffset(idx, targetOffset ?: -pinnedTopOffset)
            }
            finishInitialHintsDismissal(messageId)
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
                val view = lm.findViewByPosition(idx) ?: return@addUpdateListener
                val desiredTop = startTop - value.roundToInt()
                val delta = view.top - desiredTop
                if (delta != 0) {
                    chatRecyclerView.scrollBy(0, delta)
                }
            }
            addEndListener { _, canceled, _, _ ->
                pinScrollExtraSpace = 0
                if (!canceled && pinnedMessageId == messageId) {
                    val view = lm.findViewByPosition(idx)
                    val offset = view?.let(::pinnedMessageOffset) ?: -pinnedTopOffset
                    if (view?.top != chatRecyclerView.paddingTop + offset) {
                        lm.scrollToPositionWithOffset(idx, offset)
                    }
                    finishInitialHintsDismissal(messageId)
                }
            }
            start()
        }
    }

    private fun finishInitialHintsDismissal(messageId: String) {
        if (dismissingHints == null || dismissingHintsAnchorId != null) return
        finishHintsDismissal()
        chatRecyclerView.doOnNextLayout {
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

    private fun syncPinnedPadding(): Boolean {
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

    private fun onCopyPopupVisibilityChanged(visible: Boolean, bubbleView: View?) {
        isPopupVisible = visible
        chatRecyclerView.suppressLayout(visible)
        if (visible && bubbleView != null) {
            if (viewsOverlap(bubbleView, topReversedCornerView)) {
                topReversedCornerView?.fadeOut()
            }
            if (viewsOverlap(bubbleView, navigationBar?.titleLabel)) {
                navigationBar?.titleLabel?.fadeOut()
            }
            if (viewsOverlap(bubbleView, moreButton)) {
                moreButton.fadeOut()
            }
            val tabBarController = navigationController?.tabBarController
            if (viewsOverlap(bubbleView, tabBarController?.bottomNavigationView)) {
                tabBarController?.hideTabBar()
            }
            if (viewsOverlap(bubbleView, composerView)) {
                composerView.fadeOut()
            }
            if (viewsOverlap(bubbleView, bottomGradientView)) {
                bottomGradientView.fadeOut()
            }
        } else {
            topReversedCornerView?.fadeIn()
            navigationBar?.titleLabel?.fadeIn()
            moreButton.fadeIn()
            navigationController?.tabBarController?.showTabBar()
            composerView.fadeIn()
            if (window?.isWideLayout == true || WGlobalStorage.isGradientNavigationBarActive()) {
                bottomGradientView.fadeIn()
            }
        }
    }

    private fun viewsOverlap(a: View, b: View?): Boolean {
        if (b == null || !a.isShown || !b.isShown) return false

        val locA = IntArray(2)
        val locB = IntArray(2)

        a.getLocationOnScreen(locA)
        b.getLocationOnScreen(locB)

        val topA = locA[1]
        val bottomA = topA + a.height

        val topB = locB[1]
        val bottomB = topB + b.height

        return topA < bottomB &&
            bottomA > topB
    }

    override fun onResultsReceived(messageId: String, results: List<AgentResult>) {
        onStreamEvent(messageId)
    }

    override fun onHintsUpdated(hints: List<AgentHint>) {
        composerView.setHintsAvailable(vm.hasHints)
        composerView.setHintsActive(hints.isNotEmpty())

        val hadHints = timelineItems.lastOrNull() is AgentTimelineItem.Hints
        val newItems = buildTimelineItems(vm.messages)
        val hasHints = newItems.lastOrNull() is AgentTimelineItem.Hints

        if (hasHints == hadHints) {
            if (hasHints) {
                // Toggled back on while the collapse is still playing; reverse it in place.
                val holder =
                    chatRecyclerView.findViewHolderForAdapterPosition(timelineItems.size - 1)
                val cell = (holder as? WCell.Holder)?.cell as? AgentHintsCell
                if (cell?.isCollapsing == true) {
                    cell.expand {}
                }
            }
            if (timelineItems != newItems) {
                timelineItems = newItems
                rvAdapter.reloadData()
            }
            return
        }

        if (hasHints) {
            if (hintsSettleFallback != null) {
                // Hints are already waiting for the message content to settle.
                return
            }
            timelineItems = newItems
            scheduleHintsReveal()
            insertHintsItem()
            refreshIsOnBottom()
            if (isOnBottom) scrollToBottom()
        } else {
            val hintsIndex = timelineItems.size - 1
            val holder = chatRecyclerView.findViewHolderForAdapterPosition(hintsIndex)
            val cell = (holder as? WCell.Holder)?.cell as? AgentHintsCell
            if (cell != null) {
                cell.collapse {
                    val stillListed = timelineItems.lastOrNull() is AgentTimelineItem.Hints
                    timelineItems = buildTimelineItems(vm.messages)
                    when {
                        timelineItems.lastOrNull() is AgentTimelineItem.Hints ->
                            // Hints were re-enabled while collapsing; restore the cell.
                            rvAdapter.reloadData()

                        stillListed -> removeHintsItem(hintsIndex)
                    }
                }
            } else {
                timelineItems = newItems
                removeHintsItem(hintsIndex)
            }
        }
    }

    override fun onError(error: String) {
        // TODO: show error UI
    }

    private fun openInAppBrowser(url: String) {
        val w = window ?: return
        val config = InAppBrowserConfig(
            url = url,
            injectDappConnect = false
        )
        val inAppBrowserVC = InAppBrowserVC(
            context,
            navigationController?.tabBarController,
            config
        )
        val nav = WNavigationController(w)
        nav.setRoot(inAppBrowserVC)
        w.present(nav)
    }

    private fun rebuildTimeline() {
        timelineItems = buildTimelineItems(vm.messages)
        rvAdapter.reloadData()
    }

    private fun buildTimelineItems(messages: List<AgentMessage>): List<AgentTimelineItem> {
        val items = mutableListOf<AgentTimelineItem>()
        var lastDate: Date? = null

        for (message in messages) {
            if (hiddenIncomingMessageIds.contains(message.id)) continue
            if (lastDate == null || message.date.time - lastDate.time > DATE_HEADER_GAP_MS) {
                items.add(AgentTimelineItem.DateHeader(message.date))
            }
            lastDate = message.date
            items.add(AgentTimelineItem.Message(message))
        }
        val dismissing = dismissingHints
        if (dismissing != null) {
            // Keep the collapsing hints anchored below the message they were shown for.
            val anchorId = dismissingHintsAnchorId
            val anchorIdx = if (anchorId == null) {
                -1
            } else {
                items.indexOfLast {
                    it is AgentTimelineItem.Message && it.message.id == anchorId
                }
            }
            items.add(anchorIdx + 1, dismissing)
            return items
        }
        val hints = vm.visibleHints
        if (hints.isNotEmpty() && messages.lastOrNull()?.isStreaming != true) {
            items.add(AgentTimelineItem.Hints(hints))
        }
        return items
    }

    // WRecyclerViewDataSource

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = timelineItems.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (timelineItems[indexPath.row]) {
            is AgentTimelineItem.DateHeader -> DATE_CELL

            is AgentTimelineItem.Hints -> HINTS_CELL

            is AgentTimelineItem.Message -> {
                val msg = (timelineItems[indexPath.row] as AgentTimelineItem.Message).message
                when (msg.role) {
                    AgentMessageRole.SYSTEM -> SYSTEM_CELL
                    else -> MESSAGE_CELL
                }
            }
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            DATE_CELL -> AgentDateHeaderCell(context)
            SYSTEM_CELL -> AgentSystemMessageCell(context)
            HINTS_CELL -> AgentHintsCell(context)
            else -> AgentMessageCell(context)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val animate = animateFromIndex in 0..indexPath.row
        when (val item = timelineItems[indexPath.row]) {
            is AgentTimelineItem.DateHeader -> {
                (cellHolder.cell as AgentDateHeaderCell).configure(item.date, animate)
            }

            is AgentTimelineItem.Hints -> {
                (cellHolder.cell as AgentHintsCell).apply {
                    onHintTap = { hint -> sendMessage(hint.prompt) }
                    onCollapseFrame = { delta -> onHintsCollapseFrame(delta) }
                    configure(
                        item.hints,
                        shouldShowEmptyStateIcon = vm.messages.isEmpty(),
                        animate = pendingHintsReveal
                    )
                }
            }

            is AgentTimelineItem.Message -> {
                when (val cell = cellHolder.cell) {
                    is AgentMessageCell -> {
                        val messageId = item.message.id
                        val tracksIncomingReveal =
                            pendingIncomingReveals.containsKey(messageId)
                        val tracksPin = messageId == pendingPinMessageId
                        cell.onOpenUrl = { url -> openInAppBrowser(url) }
                        cell.onPopupVisibilityChanged = { visible, bubbleView ->
                            onCopyPopupVisibilityChanged(visible, bubbleView)
                        }
                        cell.onSizeTransitionFrame = { previousHeight ->
                            preservePinAcrossSizeTransition(messageId, cell, previousHeight)
                        }
                        cell.onInsertAnimationStarted =
                            if (tracksIncomingReveal || tracksPin) {
                                { targetHeight ->
                                    if (tracksIncomingReveal) {
                                        onOutgoingInsertAnimationStarted(messageId)
                                    }
                                    if (tracksPin) {
                                        onOutgoingInsertAnimationPrepared(
                                            messageId,
                                            targetHeight
                                        )
                                    }
                                }
                            } else {
                                null
                            }
                        cell.onInsertAnimationFinished =
                            if (tracksIncomingReveal) {
                                { onOutgoingInsertAnimationFinished(messageId) }
                            } else {
                                null
                            }
                        cell.configure(item.message, rv.width, animate)
                    }

                    is AgentSystemMessageCell -> cell.configure(item.message)
                }
            }
        }
    }
}
