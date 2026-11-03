package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.Manifest
import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.text.InputFilter
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.animation.doOnCancel
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.core.view.OneShotPreDrawListener
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.children
import androidx.core.view.doOnNextLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import kotlin.coroutines.resume
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.AndroidAgentDictationRecorder
import org.mytonwallet.app_air.uiagent.agentV2.agentActionUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentUnreadDividerCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isAgentPicturePinchStart
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isMessageMenuTapTarget
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_HISTORY_LOAD_THRESHOLD
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBottomFadeView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentChatTitleView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentConsentView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentCopyBulletin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentDustEffect
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentEdgeGlow
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentHistorySpinner
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentScrollToBottomButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSkeletonReveal
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.attachAgentEdgeGlow
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsSourceLinks
import org.mytonwallet.app_air.uiagent.viewControllers.news.agentNewsErrorText
import org.mytonwallet.app_air.uiagent.viewControllers.news.agentNewsMediaViewerItem
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadReadState
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

class AgentVC(
    context: Context,
    thread: AgentV2ThreadSummary? = null,
    prompt: AgentPromptChatRequest? = null,
    private val news: AgentNewsChatRequest? = null,
    private val onNewsThreadCreated: ((AgentV2ThreadSummary) -> Unit)? = null,
    private val onNewsThreadMissing: ((String) -> Unit)? = null
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    AgentVM.Delegate,
    WalletCore.EventObserver,
    AgentHeaderHandoffScreen {

    @Suppress("PropertyName")
    override val TAG = "Agent"
    override val ignoreSideGuttering = true

    companion object {
        val DATE_CELL = WCell.Type(1)
        val MESSAGE_CELL = WCell.Type(2)
        val SYSTEM_CELL = WCell.Type(3)
        val HINTS_CELL = WCell.Type(4)
        val NEWS_POST_CELL = WCell.Type(5)
        val UNREAD_CELL = WCell.Type(6)
        private const val DATE_HEADER_GAP_MS = 10 * 60 * 1000L

        // The idle field's bottom sits this far above the navigation bar, on the root toolbar's line as the list's
        // field does, and the toolbar's extra gap higher without the gradient navigation bar
        private const val FIELD_LINE_LIFT = 1
        private const val FIELD_LINE_EXTRA = 7
        private const val KEYBOARD_GAP = 12
        private const val MORE_BUTTON_SHIFT = 4f
        private const val COMPOSER_HEADER_CLEARANCE = 120
        private const val COMPOSER_MIN_MAX_HEIGHT = 132
        private const val HINTS_SETTLE_FALLBACK_MS = 3000L
        private const val INCOMING_MESSAGE_DELAY_MS = 250L
        private const val PROBLEM_REPORT_COMMENT_LINES = 4
        private const val PROBLEM_REPORT_COMMENT_MAX_LENGTH = 1000
        private const val RETRY_CHAT_CREATION = "retryChatCreation"
        private const val SCROLL_BUTTON_THRESHOLD = 60
        private const val DISABLED_BUTTON_ALPHA = 0.5f
        private const val LOAD_ERROR_SIDE_INSET = 32f
        private const val MENU_AFTER_KEYBOARD_TIMEOUT_MS = 600L
    }

    private val WindowInsetsAnimationCompat.isKeyboard: Boolean
        get() = (typeMask and WindowInsetsCompat.Type.ime()) != 0

    private data class PendingIncomingReveal(
        val outgoingMessageId: String,
        var incomingMessageId: String? = null,
        var isOutgoingAnimationFinished: Boolean = false,
        var isDelayElapsed: Boolean = false,
        var revealRunnable: Runnable? = null
    )

    // In dp, from the navigation bar's top to the composer's bottom edge, below the field by its padding
    private val composerBottomOffset: Int
        get() {
            if (window?.isWideLayout == true) return 0
            val extra = if (WGlobalStorage.isGradientNavigationBarActive()) 0 else FIELD_LINE_EXTRA
            val padding = composerView.paddingBottom / context.resources.displayMetrics.density
            return FIELD_LINE_LIFT + extra - padding.roundToInt()
        }
    private val chatOpening = if (prompt != null || news != null) {
        AgentChatOpening(prompt = prompt, news = news)
    } else {
        null
    }
    private var preparedVM = thread?.let(AgentSession::acquire) ?: chatOpening?.acquireDiscussion()

    private val unreadSeenMessageCount = thread?.takeIf { chatOpening == null }
        ?.let(AgentThreadReadState.shared::getSeenMessageCountIfUnread)

    private var unreadDividerMessageId: String? = null
    private var hasResolvedUnreadDivider = false
    private val vm: AgentVM get() = checkNotNull(preparedVM)
    private val creationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var creationJob: Job? = null
    private var isViewActive = false
    private var edgeGlow: AgentEdgeGlow? = null
    private var newsPostArrival: AgentNewsPostArrival? = null
    private var newsFollowupsExpired = false
    private var newsFollowupsTimeout: Runnable? = null

    // The keyboard's own show or hide animation, which carries the composer frame by frame
    private class KeyboardMotion(val startIme: Int, val startRawIme: Int)

    private var keyboardMotion: KeyboardMotion? = null
    private val keyboardAnimationCallback = object : WindowInsetsAnimationCompat.Callback(
        DISPATCH_MODE_CONTINUE_ON_SUBTREE
    ) {
        override fun onPrepare(animation: WindowInsetsAnimationCompat) {
            if (!animation.isKeyboard || !isViewActive) return
            // The insets still hold where the keyboard starts from
            keyboardMotion = KeyboardMotion(
                startIme = navigationController?.imeInsetBottom ?: 0,
                startRawIme = window?.imeInsets?.bottom ?: 0
            )
        }

        override fun onProgress(
            insets: WindowInsetsCompat,
            runningAnimations: List<WindowInsetsAnimationCompat>
        ): WindowInsetsCompat {
            val motion = keyboardMotion ?: return insets
            if (runningAnimations.none { it.isKeyboard }) return insets
            followKeyboard(motion, insets.getInsets(WindowInsetsCompat.Type.ime()).bottom)
            return insets
        }

        override fun onEnd(animation: WindowInsetsAnimationCompat) {
            if (animation.isKeyboard) finishKeyboardMotion()
        }
    }
    private val displayMessages: List<AgentMessage>
        get() {
            preparedVM?.let { return it.messages }
            val opening = chatOpening ?: return emptyList()
            val error = opening.error ?: return opening.messages
            return opening.messages.filterNot { it.isStreaming } + AgentMessage(
                id = "chat-creation-error",
                role = AgentMessageRole.ASSISTANT,
                text = openingErrorText(error),
                date = opening.messages.firstOrNull()?.date
                    ?: news?.publishedAt?.let(::parseAgentV2Timestamp) ?: Date(),
                deeplinks = listOf(
                    AgentDeeplink(
                        LocaleController.getString("Retry"),
                        actionId = RETRY_CHAT_CREATION
                    )
                )
            )
        }
    private var isAttachedToSession = false
    private var isSessionReleased = false
    private var hasAppeared = false
    private var readStateThreadId: String? = null

    // Changes only through applyTimeline, which tells the list what changed
    private var timelineItems = listOf<AgentTimelineItem>()

    private var animateFromIndex = -1
    private var gradientHeightAnimator: ValueAnimator? = null
    private val chatTitleView by lazy { AgentChatTitleView(context) }
    private var pendingTitleLayout: OneShotPreDrawListener? = null
    private val applyChatTitle = Runnable {
        if (!isDestroyed) updateChatTitle()
    }
    private var pendingHintsReveal = false
    private var dismissingHints: AgentTimelineItem.Hints? = null
    private var dismissingHintsAnchorId: String? = null
    private var hintsSettleFallback: Runnable? = null
    private var hintsSettleMessageId: String? = null
    private var isPopupVisible = false
    private val pendingIncomingReveals = linkedMapOf<String, PendingIncomingReveal>()
    private val outgoingMessageIdsAwaitingIncoming = mutableListOf<String>()
    private val hiddenIncomingMessageIds = mutableSetOf<String>()
    private var agentState = AgentVM.State.LOADING
    private var accessibilityStatus: String? = null
    private var isDeletingChat = false

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
            HINTS_CELL,
            NEWS_POST_CELL,
            UNREAD_CELL
        )
    )

    private val chatRecyclerView: WRecyclerView = object : WRecyclerView(this) {
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (isEditFading || editPresentation != null) return true
            return super.dispatchTouchEvent(event)
        }

        override fun onInterceptTouchEvent(e: MotionEvent): Boolean =
            !isAgentPicturePinchStart(this, e) && super.onInterceptTouchEvent(e)
    }.apply {
        id = UIComponentsR.id.agent_chat_list
        adapter = rvAdapter
        itemAnimator = null
        layoutManager = object : LinearLayoutManager(context) {
            override fun calculateExtraLayoutSpace(
                state: RecyclerView.State,
                extraLayoutSpace: IntArray
            ) {
                super.calculateExtraLayoutSpace(state, extraLayoutSpace)
                if (viewport.pinScrollExtraSpace > extraLayoutSpace[1]) {
                    extraLayoutSpace[1] = viewport.pinScrollExtraSpace
                }
            }
        }.apply {
            stackFromEnd = true
        }
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                viewport.onScrollStateChanged(newState)
                if (newState != RecyclerView.SCROLL_STATE_IDLE) updateBlurViews(recyclerView)
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (viewport.isUserScrolling) {
                    viewport.onUserScrolled(dy)
                    val layoutManager = recyclerView.layoutManager as? LinearLayoutManager
                    if (
                        dy < 0 &&
                        layoutManager?.findFirstVisibleItemPosition()
                            ?.let { it in 0..AGENT_HISTORY_LOAD_THRESHOLD } == true
                    ) {
                        viewport.shareScrollPosition()
                        preparedVM?.loadOlderMessages()
                    }
                }
                updateBlurViews(recyclerView)
                viewport.shareScrollPosition()
            }
        })
        // The list reattaches a cell it kept off screen without binding it again, past availability changes it missed
        addOnChildAttachStateChangeListener(object : RecyclerView.OnChildAttachStateChangeListener {
            override fun onChildViewAttachedToWindow(view: View) {
                (view as? AgentHintsCell)?.let(::updateHintsAvailability)
            }

            override fun onChildViewDetachedFromWindow(view: View) = Unit
        })
        addOnLayoutChangeListener { _, left, _, right, _, oldLeft, _, oldRight, _ ->
            val newWidth = right - left
            if (newWidth > 0 && newWidth != oldRight - oldLeft) {
                rvAdapter.updateVisibleCells()
                viewport.restoreSharedScrollPosition()
                doOnNextLayout {
                    viewport.restoreSharedScrollPosition()
                }
            } else if (viewport.pinnedMessageId != null) {
                post { viewport.syncPinnedPadding() }
            }
            viewport.restorePendingPosition()
        }
    }

    private val streamRenderer = AgentStreamRenderer(
        postFrame = { chatRecyclerView.postOnAnimation(it) },
        cancelFrame = { chatRecyclerView.removeCallbacks(it) },
        renderMessages = { messageIds ->
            messageIds.forEach(::onStreamEvent)
            onHintsUpdated(preparedVM?.visibleHints.orEmpty())
        }
    )

    private val viewport: AgentTimelineViewport by lazy {
        AgentTimelineViewport(object : AgentTimelineViewport.Host {
            override fun onMessagePinned(messageId: String) {
                editPresentation?.takeIf { it.outgoingMessageId == messageId }?.hasPinned = true
                finishEditPresentation(messageId)
            }

            override val recyclerView get() = chatRecyclerView
            override val timelineItems get() = this@AgentVC.timelineItems
            override val scrollPosition get() = preparedVM?.scrollPosition
            override val topPadding get() = chatTopPadding()
            override val isPopupVisible get() = this@AgentVC.isPopupVisible
            override val dismissingHintsIndex
                get() = dismissingHints?.let {
                    timelineItems.indexOf(it)
                }
                    ?: -1

            override fun baseBottomPadding(bottom: Int) =
                composerView.height + bottom + composerBottomOffset.dp + AGENT_COMPOSER_LIST_GAP.dp

            override fun publishScrollPosition(position: AgentVM.ScrollPosition) {
                preparedVM?.updateScrollPosition(this@AgentVC, position)
            }

            override fun presentationMessageId(messageId: String) = timelineItems
                .filterIsInstance<AgentTimelineItem.Message>()
                .firstOrNull { it.message.matchesMessageId(messageId) }?.message?.id
                ?: displayMessages.firstOrNull { it.matchesMessageId(messageId) }?.id

            override fun applyComposerBottom(bottom: Int) {
                consentView.updateInsets(topPadding, bottom)
                contentContainer.setConstraints {
                    toBottomPx(composerView, bottom + composerBottomOffset.dp)
                }
                updateGradientHeight(animated = false)
            }

            override fun finishInitialHintsDismissal(): Boolean {
                if (dismissingHints == null || dismissingHintsAnchorId != null) return false
                finishHintsDismissal()
                return true
            }

            override fun syncTopBlurAfterLayout() = this@AgentVC.syncTopBlurAfterLayout()
        })
    }

    private val bottomGradientView = AgentBottomFadeView(context)
    private val scrollButton = AgentScrollToBottomButton(context).apply {
        setOnClickListener {
            cancelDictation()
            viewport.scrollToLatest()
        }
    }
    private var scrollButtonGlass: WGlassView? = null

    // The recording circle covers the button's place
    private var isRecordingCircleShown = false

    // Placeholder bubbles while an existing chat's messages load
    private val messagesSkeleton = AgentMessagesSkeletonView(context).apply { isGone = true }
    private val historySpinner = AgentHistorySpinner(context)
    private val loadErrorView = AgentLoadErrorView(context).apply {
        onRetry = { preparedVM?.failureRetry?.invoke() }
    }
    private val skeletonReveal by lazy { AgentSkeletonReveal(messagesSkeleton, chatRecyclerView) }

    // A touch that stops a scroll opens no menu, like one stopping a fling
    private var hasStoppedScroll = false

    // A tap on the messages away from their buttons puts the keyboard away
    private val keyboardDismissal = object : RecyclerView.SimpleOnItemTouchListener() {
        private val tapDetector = GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapUp(e: MotionEvent): Boolean {
                    if (!isOverButton(chatRecyclerView, e.x, e.y)) view.hideKeyboard()
                    return false
                }
            }
        )

        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN) {
                hasStoppedScroll = viewport.stopProgrammaticScroll()
            }
            tapDetector.onTouchEvent(e)
            return false
        }
    }

    private fun canOpenMenuOnTap(): Boolean = !hasStoppedScroll

    // A message's own tap opens its menu, which puts the keyboard away too
    private fun isOverButton(view: View, x: Float, y: Float): Boolean {
        if (view.hasOnClickListeners() && !view.isMessageMenuTapTarget) return true
        val group = view as? ViewGroup ?: return false
        for (index in group.childCount - 1 downTo 0) {
            val child = group.getChildAt(index)
            if (child.visibility != View.VISIBLE) continue
            val childX = x + group.scrollX - child.left - child.translationX
            val childY = y + group.scrollY - child.top - child.translationY
            if (childX >= 0 && childY >= 0 && childX < child.width && childY < child.height) {
                return isOverButton(child, childX, childY)
            }
        }
        return false
    }

    // The button shows while the latest row reaches more than 60 dp below what the composer leaves visible
    private val scrollButtonUpdater = ViewTreeObserver.OnPreDrawListener {
        updateScrollButton(isAnimated = true)
        true
    }
    private var scrollButtonBinding: AgentPreDrawBinding? = null
    private data class EditPresentation(
        val removedMessages: List<AgentMessage>,
        val hidesRemovedMessages: Boolean = false,
        var outgoingMessageId: String? = null,
        var hasInserted: Boolean = false,
        var hasPinned: Boolean = false
    )

    private var editPresentation: EditPresentation? = null
    private var isEditFading = false
    private var editFadeAnimator: ValueAnimator? = null
    private var regeneratingMessageId: String? = null
    private var dustEffect: AgentDustEffect? = null
    private val copyBulletin = AgentCopyBulletin()
    private val messageTextCache = AgentMessageTextCache()
    private var isDissolving = false
    private var editingMessageId: String? = null

    private val composerView by lazy { AgentComposerView(context, chatRecyclerView) }
    private val dictationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val dictation by lazy {
        AgentDictationController(
            scope = dictationScope,
            recorderFactory = {
                AndroidAgentDictationRecorder(context) { cancelDictation() }
            },
            requestPermission = { requestMicrophonePermission() },
            transcribe = { audio -> vm.transcribeAudio(audio) },
            nowMs = SystemClock::elapsedRealtime,
            onStateChanged = composerView::renderDictation,
            onTranscript = composerView::setDictationText,
            onFailure = composerView::showDictationFailure,
            onRecordingStarted = { Haptics.play(composerView, HapticType.LIGHT_TAP) },
            onGestureFeedback = { Haptics.play(composerView, HapticType.LIGHT_TAP) }
        )
    }

    private fun cancelDictation() {
        dictation.cancel()
    }

    private fun showDictationToast(text: String) {
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }

    private suspend fun requestMicrophonePermission(): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        val currentWindow = window ?: return false
        return suspendCancellableCoroutine { continuation ->
            currentWindow.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO)) {
                    _,
                    results
                ->
                val granted = results.firstOrNull() == PackageManager.PERMISSION_GRANTED
                if (continuation.isActive) {
                    continuation.resume(granted)
                } else if (!granted && hasAppeared && !isDestroyed) {
                    showDictationToast(
                        LocaleController.getString("\$agent_dictation_microphone_denied")
                    )
                }
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AppBackground -> {
                setMessageRenderingActive(false)
                dictation.onAppBackground()
            }

            WalletEvent.AppForeground -> {
                if (!isDisappeared) setMessageRenderingActive(true)
            }

            is WalletEvent.OpenUrl -> {
                if (walletEvent.source == DeeplinkOpenSource.AGENT) cancelDictation()
            }

            is WalletEvent.AgentThreadDeleted -> {
                if (walletEvent.threadId == preparedVM?.currentThread?.id) closeDeletedChat()
            }

            else -> Unit
        }
    }

    private val contentContainer: WView by lazy {
        WView(context).apply {
            clipChildren = false
            clipToPadding = false
            // The placeholder lies under the messages, so they come in over it as it fades, and goes on under the
            // header as they do
            addView(messagesSkeleton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
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
            addView(
                scrollButton,
                ConstraintLayout.LayoutParams(
                    AgentScrollToBottomButton.SIZE.dp,
                    AgentScrollToBottomButton.SIZE.dp
                )
            )
            addView(
                historySpinner,
                ConstraintLayout.LayoutParams(
                    AgentHistorySpinner.SIZE.dp,
                    AgentHistorySpinner.SIZE.dp
                )
            )
            addView(loadErrorView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))

            setConstraints {
                toStart(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toEnd(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toCenterY(loadErrorView)
                toCenterX(historySpinner)
                toTopPx(historySpinner, agentHeaderBottom() + AgentHistorySpinner.TOP_GAP.dp)
                allEdges(chatRecyclerView)
                toStart(messagesSkeleton)
                toEnd(messagesSkeleton)
                toTop(messagesSkeleton)
                bottomToTop(
                    messagesSkeleton,
                    composerView,
                    (AGENT_MESSAGE_BOTTOM_GAP - AGENT_COMPOSER_FIELD_TOP).toFloat()
                )
                toEnd(scrollButton, AGENT_SCROLL_BUTTON_END.toFloat())
                bottomToTop(scrollButton, composerView, AGENT_SCROLL_BUTTON_GAP.toFloat())

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

    private val consentView by lazy {
        AgentConsentView(context).apply {
            isGone = true
            onAllow = {
                showError(null)
                if (preparedVM == null) {
                    createChatThread(shouldAcceptConsent = true)
                } else {
                    vm.acceptConsent()
                }
            }
        }
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.id = UIComponentsR.id.agent_menu_button
        btn.setPaddingDp(8)
        btn.setImageDrawable(
            context.getDrawableCompat(org.mytonwallet.app_air.icons.R.drawable.ic_more)
        )
        btn.updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        // The bar keeps trailing views 8 dp in; the design's dots box ends 12 dp from the edge
        btn.translationX = MORE_BUTTON_SHIFT.dp * LocaleController.rtlMultiplier
        btn.contentDescription = LocaleController.getString("More")
        btn.setOnClickListener { presentMoreMenu() }
        btn
    }

    override fun setupViews() {
        super.setupViews()

        updateChatTitle()
        setupNavBar(true)
        navigationBar?.addTrailingView(moreButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        navigationBar?.setCenteredTitleView(chatTitleView, animated = false)

        composerView.onSend = { text ->
            val messageId = editingMessageId
            if (messageId == null) {
                sendMessage(text)
            } else {
                submitEditedMessage(messageId, text).also { accepted ->
                    if (accepted) {
                        editingMessageId = null
                        view.hideKeyboard()
                    }
                }
            }
        }
        composerView.onDraftCleared = { editingMessageId = null }
        // The button keeps to the field's trailing edge
        composerView.onSideInsetChanged = { inset ->
            val shift = (AGENT_SCROLL_BUTTON_END.dp - inset).toFloat()
            scrollButton.translationX = if (LocaleController.isRTL) -shift else shift
        }
        composerView.bindDictation(dictation)
        composerView.onRecordingCircleVisibilityChanged = { isShown ->
            isRecordingCircleShown = isShown
            updateScrollButton(isAnimated = true)
        }
        WalletCore.registerObserver(this)
        composerView.onHeightChanged = {
            updateLayout()
        }

        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        // Earlier versions report the keyboard only where it ends up
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ViewCompat.setWindowInsetsAnimationCallback(contentContainer, keyboardAnimationCallback)
        }
        view.addView(consentView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        scrollButtonGlass = WGlassView.attachTo(
            scrollButton,
            AgentScrollToBottomButton.SIZE.dp / 2f,
            GlassProviders.composer(WColor.SearchFieldBackground),
            chatRecyclerView
        )
        scrollButtonBinding = AgentPreDrawBinding(chatRecyclerView, scrollButtonUpdater)
        chatRecyclerView.addOnItemTouchListener(keyboardDismissal)

        composerView.post { updateGradientHeight(animated = false) }
        edgeGlow = attachAgentEdgeGlow(view) {
            Rect(
                contentContainer.left + contentContainer.paddingLeft,
                0,
                contentContainer.right - contentContainer.paddingRight,
                view.height
            )
        }

        ContextCompat.registerReceiver(
            context,
            timezoneReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_TIMEZONE_CHANGED)
                addAction(Intent.ACTION_DATE_CHANGED)
                // Also sent when the 24-hour setting changes
                addAction(Intent.ACTION_TIME_CHANGED)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        updateTheme()
        if (preparedVM != null) {
            attachToSession()
        } else {
            showChatOpening()
        }
    }

    private fun showChatOpening() {
        checkNotNull(chatOpening).onChange = ::renderChatOpening
        renderChatOpening()
        createChatThread()
    }

    private fun attachToSession() {
        showSkeletonIfLoading()
        vm.attach(this)
        isAttachedToSession = true
        if (isViewActive) vm.setActive(this, true)
        updateReadStateVisibility()
        onNewsThreadCreated?.invoke(vm.currentThread)
    }

    // A chat on screen holds no unseen answer, for the list's unread dot
    private fun updateReadStateVisibility() {
        val isShown = hasAppeared && !isSessionReleased
        val threadId = preparedVM?.currentThread?.id?.takeIf { isShown }
        if (readStateThreadId == threadId) return
        readStateThreadId?.let {
            AgentThreadReadState.shared.onChatDisappeared(it, preparedVM?.seenMessageCount)
        }
        readStateThreadId = threadId
        threadId?.let(AgentThreadReadState.shared::onChatAppeared)
    }

    private fun createChatThread(shouldAcceptConsent: Boolean = false) {
        val opening = chatOpening ?: return
        if (isDeletingChat || preparedVM != null || creationJob != null) return
        creationJob = creationScope.launch {
            try {
                val thread = opening.create(shouldAcceptConsent) ?: return@launch
                currentCoroutineContext().ensureActive()
                if (isDeletingChat) return@launch
                preparedVM = if (opening.messages.isNotEmpty()) {
                    AgentSession.acquireOpening(thread, opening.messages, opening.entryPoint)
                } else {
                    AgentSession.acquire(thread)
                }
                attachToSession()
            } finally {
                creationJob = null
                renderChatOpening()
            }
        }
    }

    private fun openingErrorText(error: Throwable): String =
        if (news != null) agentNewsErrorText(error) else agentUnavailableText()

    private fun renderChatOpening() {
        val opening = chatOpening ?: return
        if (isDeletingChat || preparedVM != null || isSessionReleased) return
        val showsConsent = opening.isConsentRequired
        contentContainer.isGone = showsConsent
        consentView.isGone = !showsConsent
        consentView.setLoading(opening.isCreating)
        if (showsConsent) consentView.showError(opening.error?.let(::openingErrorText))
        composerView.setSubmissionEnabled(false)
        onMessagesLoaded(displayMessages)
    }

    override val headerHandoffContent: List<View> get() = listOf(chatTitleView, moreButton)

    override fun viewWillAppear() {
        super.viewWillAppear()
        AgentHeaderHandoff.begin(this)
        updateChatTitle()
        isViewActive = true
        updateThinkingGlow()
        setMessageRenderingActive(window?.isPaused != true)
        preparedVM?.setActive(this, true)
        updateVisibleHintsAvailability()
        viewport.restoreSharedScrollPosition()
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        // A swipe back that gives up keeps the chat, which takes its composer back from the list's bar
        setComposerHandoff(null)
        hasAppeared = true
        updateReadStateVisibility()
        viewport.restorePendingPosition()
    }

    override fun viewWillDisappear() {
        AgentHeaderHandoff.begin(this)
        isViewActive = false
        finishKeyboardMotion()
        updateThinkingGlow()
        setMessageRenderingActive(false)
        cancelDictation()
        hasAppeared = false
        updateReadStateVisibility()
        cancelPendingChatTitleUpdate()
        viewport.shareScrollPosition()
        super.viewWillDisappear()
        preparedVM?.setActive(this, false)
    }

    /**
     * Flies a news card from the feed into this chat's news post. The card's picture takes its place over [root] at
     * once, at [frame] in the window, so the feed hides the card itself. Until this chat's header shows, the flight
     * stays under the feed's, whose bottom edge is at [feedHeaderBottom] in the window. Returns whether the card
     * flies, which it does not with animations off.
     */
    internal fun prepareNewsPostArrival(
        snapshot: Bitmap,
        frame: Rect,
        root: ViewGroup,
        feedHeaderBottom: Int
    ): Boolean {
        newsPostArrival?.cancel()
        if (!WGlobalStorage.getAreAnimationsActive()) return false
        val arrival = AgentNewsPostArrival(
            snapshot,
            frame,
            ::findNewsPostArrivalDestination
        ) { findNewsPostArrivalHeaderBottom() ?: feedHeaderBottom }
        arrival.onFinish = {
            if (newsPostArrival === arrival) newsPostArrival = null
            onNewsPostArrivalFinished?.invoke()
            onNewsPostArrivalFinished = null
        }
        newsPostArrival = arrival
        arrival.start(root)
        return true
    }

    /** Called once a card flown in from the feed has landed or given up */
    internal var onNewsPostArrivalFinished: (() -> Unit)? = null

    private fun findNewsPostArrivalHeaderBottom(): Int? {
        if (!isViewConfigured || !view.isAttachedToWindow) return null
        val location = IntArray(2)
        view.getLocationInWindow(location)
        return location[1] + agentHeaderBottom()
    }

    private fun findNewsPostArrivalDestination(): AgentNewsPostArrival.Destination? {
        if (!isViewConfigured || !view.isAttachedToWindow) return null
        var post: AgentNewsPostCell? = null
        var postMessageId: String? = null
        for (index in 0 until chatRecyclerView.childCount) {
            val child = chatRecyclerView.getChildAt(index) as? AgentNewsPostCell ?: continue
            val position = chatRecyclerView.getChildAdapterPosition(child)
            val item = timelineItems.getOrNull(position) as? AgentTimelineItem.Message ?: continue
            post = child
            postMessageId = item.message.id
            break
        }
        val followups = postMessageId?.let { messageId ->
            (0 until chatRecyclerView.childCount).asSequence()
                .mapNotNull { chatRecyclerView.getChildAt(it) as? AgentHintsCell }
                .firstOrNull { child ->
                    (
                        timelineItems.getOrNull(chatRecyclerView.getChildAdapterPosition(child))
                            as? AgentTimelineItem.Hints
                        )?.followupMessageId == messageId
                }
        }
        return AgentNewsPostArrival.Destination(
            post,
            followups,
            composerView
        )
    }

    override fun onDestroy() {
        newsFollowupsTimeout?.let(view::removeCallbacks)
        isViewActive = false
        menuAfterKeyboard = null
        setComposerHandoff(null)
        chatRecyclerView.removeCallbacks(openMenuAfterKeyboardRunnable)
        newsPostArrival?.cancel()
        dustEffect?.kill()
        dustEffect = null
        copyBulletin.dismiss()
        if (isViewConfigured) ViewCompat.setWindowInsetsAnimationCallback(contentContainer, null)
        keyboardMotion = null
        edgeGlow?.detach()
        edgeGlow = null
        streamRenderer.setActive(false)
        streamRenderer.clear()
        cancelDictation()
        dictationScope.cancel()
        chatOpening?.onChange = null
        creationScope.cancel()
        WalletCore.unregisterObserver(this)
        scrollButtonBinding?.release()
        scrollButtonBinding = null
        viewport.shareScrollPosition()
        cancelHintsSettleFallback()
        editPresentation = null
        cancelPendingIncomingReveals()
        preparedVM?.let { model ->
            model.setActive(this, false)
            if (isAttachedToSession) {
                model.detach(this)
                isAttachedToSession = false
            }
            if (!isSessionReleased) AgentSession.release(model)
        }
        isSessionReleased = true
        updateReadStateVisibility()
        viewport.dispose()
        gradientHeightAnimator?.cancel()
        cancelPendingChatTitleUpdate()
        chatTitleView.cancelAnimation()
        context.unregisterReceiver(timezoneReceiver)
        super.onDestroy()
        editFadeAnimator?.cancel()
    }

    override fun updateTheme() {
        super.updateTheme()
        // In a wide window the page shows at the chat's sides
        view.setBackgroundColor(
            if (window?.isWideLayout == true) {
                WColor.SecondaryBackground.color
            } else {
                agentChatBackgroundColor
            }
        )
        // The column's color lies under the placeholder, which lies under the messages, so it fades out under them
        contentContainer.setBackgroundColor(agentChatBackgroundColor)
        chatRecyclerView.background = null
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
        bottomGradientView.isGone = !AgentBottomFadeView.isShown(window?.isWideLayout == true)
        bottomGradientView.updateTheme()
        composerView.updateTheme()
        consentView.updateTheme()
        chatTitleView.updateTheme()
        scrollButton.updateTheme()
        scrollButtonGlass?.updateTheme()
        messagesSkeleton.updateTheme()
        loadErrorView.updateTheme()
    }

    private fun updateScrollButton(isAnimated: Boolean) {
        val shouldShow = !contentContainer.isGone && !isPopupVisible && !isRecordingCircleShown &&
            viewport.measureLatestRowOverhang() > SCROLL_BUTTON_THRESHOLD.dp
        scrollButton.setShown(shouldShow, isAnimated && hasAppeared)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        // Margins keep the column's color out from under the side panel
        val start = additionalTabletPadding + systemBarStartInset
        for (column in listOf(contentContainer, consentView)) {
            column.updateLayoutParams<ViewGroup.MarginLayoutParams> {
                leftMargin = if (LocaleController.isRTL) systemBarEndInset else start
                rightMargin = if (LocaleController.isRTL) start else systemBarEndInset
            }
        }
        consentView.updateInsets(chatTopPadding(), viewport.currentBottom)
        contentContainer.setConstraints {
            toTopPx(historySpinner, agentHeaderBottom() + AgentHistorySpinner.TOP_GAP.dp)
        }
        topReversedCornerView?.setSideInsets(
            systemBarStartInset.toFloat(),
            systemBarEndInset.toFloat()
        )
        updateLayout()
        updateBlurViews(chatRecyclerView)
    }

    override fun updateBlurViews(recyclerView: RecyclerView) {
        if (window?.isWideLayout == true) {
            topReversedCornerView?.setBlurAlpha(1f)
            return
        }
        super.updateBlurViews(recyclerView)
    }

    private fun syncTopBlurAfterLayout() {
        chatRecyclerView.doOnPreDraw {
            if (chatRecyclerView.computeVerticalScrollOffset() > 0 ||
                viewport.pinnedMessageId != null
            ) {
                topReversedCornerView?.setBlurAlpha(1f)
            } else {
                updateBlurViews(chatRecyclerView)
            }
        }
    }

    private fun chatTopPadding(): Int = agentHeaderBottom() + AGENT_LIST_TOP_INSET.dp

    private fun updateLayout() {
        val ime = navigationController?.imeInsetBottom ?: 0
        val navigationBarInset = navigationController?.getSystemBars()?.bottom ?: 0
        val isFollowingKeyboard = keyboardMotion != null
        val bottom = computeComposerBottom(ime, navigationBarInset)
        viewport.updateLayout(bottom, ime, navigationBarInset, isFollowingKeyboard)
        composerView.setKeyboardShown(ime > 0, isFollowingKeyboard)
        updateComposerMaxHeight(bottom)
    }

    // The field grows with its text until it comes 120 dp short of the header, as Telegram's does
    private fun updateComposerMaxHeight(bottom: Int) {
        val height = contentContainer.height.takeIf { it > 0 } ?: return
        val fieldBottom = height - bottom - composerBottomOffset.dp - composerView.inputBottomInset
        val room = fieldBottom - agentHeaderBottom() - COMPOSER_HEADER_CLEARANCE.dp
        composerView.setMaxFieldHeight(maxOf(COMPOSER_MIN_MAX_HEIGHT.dp, room))
    }

    // The composer rests 12 dp above the keyboard, or above the navigation bar while the keyboard
    // is lower
    private fun computeComposerBottom(ime: Int, navigationBarInset: Int): Int {
        val aboveKeyboard = if (ime > 0) {
            ime + KEYBOARD_GAP.dp - composerView.inputBottomInset - composerBottomOffset.dp
        } else {
            0
        }
        return maxOf(aboveKeyboard, navigationBarInset)
    }

    // The insets already hold where the keyboard is going, and `rawIme` where it is in this frame
    private fun followKeyboard(motion: KeyboardMotion, rawIme: Int) {
        val endIme = navigationController?.imeInsetBottom ?: 0
        val endRawIme = window?.imeInsets?.bottom ?: 0
        val distance = endRawIme - motion.startRawIme
        val fraction = if (distance == 0) {
            1f
        } else {
            ((rawIme - motion.startRawIme).toFloat() / distance).coerceIn(0f, 1f)
        }
        val ime = motion.startIme + ((endIme - motion.startIme) * fraction).roundToInt()
        val navigationBarInset = navigationController?.getSystemBars()?.bottom ?: 0
        viewport.followKeyboard(computeComposerBottom(ime, navigationBarInset))
        if ((motion.startIme > 0) != (endIme > 0)) {
            composerView.followKeyboard(if (endIme > 0) fraction else 1f - fraction)
        }
    }

    private fun finishKeyboardMotion() {
        if (keyboardMotion == null) return
        keyboardMotion = null
        viewport.finishKeyboardMotion()
        composerView.followKeyboard(if ((navigationController?.imeInsetBottom ?: 0) > 0) 1f else 0f)
        updateLayout()
        if ((navigationController?.imeInsetBottom ?: 0) <= 0) openMenuAfterKeyboard()
    }

    // The fade under the composer follows it as it rides the keyboard, so it doesn't rise over the messages ahead of it
    private fun updateGradientHeight(animated: Boolean) {
        val lp = bottomGradientView.layoutParams ?: return
        val targetHeight =
            composerView.height + viewport.appliedBottom + AGENT_BOTTOM_FADE_EXTRA.dp

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

    private fun sendMessage(
        text: String,
        entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()
    ): Boolean {
        val model = preparedVM ?: return false
        if (!agentNewsAllowsSubmission(news, model.state)) return false
        val accepted = model.sendMessage(text, entryPoint)
        if (accepted) view.hideKeyboard()
        return accepted
    }

    private fun sendFollowup(messageId: String, followupId: String) {
        if (preparedVM?.sendFollowup(messageId, followupId) == true) view.hideKeyboard()
    }

    private fun presentMoreMenu() {
        val model = preparedVM
        cancelDictation()
        val items = mutableListOf<WMenuPopup.Item>()

        if (model != null && agentState == AgentVM.State.ERROR) {
            items.add(
                WMenuPopup.Item(null, LocaleController.getString("Retry")) {
                    model.retry()
                }.apply { testViewId = UIComponentsR.id.agent_menu_retry }
            )
        }

        if (model?.canReportProblem == true) {
            items.add(
                WMenuPopup.Item(
                    org.mytonwallet.app_air.icons.R.drawable.ic_flag_30,
                    LocaleController.getString("Report a Problem")
                ) {
                    presentProblemReportForm(null)
                }.apply { testViewId = UIComponentsR.id.agent_menu_report }
            )
        }

        if (canDeleteChat) {
            items.add(
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        icon = WMenuPopup.Item.Config.Icon(
                            iconResId = org.mytonwallet.app_air.icons.R.drawable.ic_remove,
                            tintColor = WColor.Red
                        ),
                        title = LocaleController.getString("Delete Chat"),
                        titleColor = WColor.Red.color
                    )
                ) {
                    showDeleteConfirmation()
                }.apply { testViewId = UIComponentsR.id.agent_menu_delete_chat }
            )
        }
        if (items.isEmpty()) return

        WMenuPopup.present(
            moreButton,
            items,
            positioning = WMenuPopup.Positioning.ALIGNED,
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    private val canDeleteChat: Boolean
        get() = !isDeletingChat && (preparedVM != null || chatOpening != null)

    private fun updateMoreButton() {
        val model = preparedVM
        moreButton.isGone = model == null && chatOpening == null
        val hasItems = agentState == AgentVM.State.ERROR ||
            model?.canReportProblem == true || canDeleteChat
        moreButton.isEnabled = hasItems
        moreButton.alpha = if (hasItems) 1f else DISABLED_BUTTON_ALPHA
    }

    private fun showDeleteConfirmation() {
        cancelDictation()
        showAlert(
            LocaleController.getString("Delete Chat?"),
            LocaleController.getString("\$agent_delete_chat_confirmation"),
            button = LocaleController.getString("Delete"),
            buttonPressed = { deleteChat() },
            secondaryButton = LocaleController.getString("Cancel"),
            primaryIsDanger = true
        )
    }

    private fun deleteChat() {
        if (isDeletingChat) return
        isDeletingChat = true
        editingMessageId = null
        val applicationContext = context.applicationContext
        val onFailure: (Throwable) -> Unit = { error ->
            val code = (error as? AgentV2OperationException)?.error?.code ?: error.message
            Toast.makeText(applicationContext, agentV2ErrorText(code), Toast.LENGTH_SHORT).show()
        }
        preparedVM?.let { AgentSession.deleteChat(it, onFailure) }
            ?: chatOpening?.deleteChat(onFailure)
        creationScope.cancel()
        closeDeletedChat()
    }

    /** A deleted thread closes its chat: animated when the user deleted it here, at once on other screens */
    private fun closeDeletedChat() {
        val navigation = navigationController ?: return
        if (navigation.viewControllers.size <= 1 || isDestroyed ||
            this !in navigation.viewControllers
        ) {
            return
        }
        if (navigation.viewControllers.lastOrNull() === this) {
            navigation.pop(animated = isDeletingChat && WGlobalStorage.getAreAnimationsActive())
        } else {
            navigation.removeViewController(this)
        }
    }

    /** Opens the report form; after a failed send it opens again with the [failedComment] the user wrote */
    private fun presentProblemReportForm(presentationId: String?, failedComment: String? = null) {
        cancelDictation()
        val input = object : WEditText(context, null, false) {
            init {
                setPadding(8.dp, 8.dp, 8.dp, 8.dp)
                updateTheme()
            }

            override fun updateTheme() {
                super.updateTheme()
                setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
            }
        }.apply {
            hint = LocaleController.getString("Optional")
            inputType = EditorInfo.TYPE_CLASS_TEXT or
                EditorInfo.TYPE_TEXT_FLAG_CAP_SENTENCES or
                EditorInfo.TYPE_TEXT_FLAG_MULTI_LINE
            gravity = Gravity.TOP or Gravity.START
            // `WDialog` fixes its height on presentation, so the input keeps a fixed height
            setLines(PROBLEM_REPORT_COMMENT_LINES)
            filters = arrayOf(InputFilter.LengthFilter(PROBLEM_REPORT_COMMENT_MAX_LENGTH))
            failedComment?.let { setText(it) }
        }
        val container = FrameLayout(context).apply {
            setPadding(24.dp, 0, 24.dp, 0)
            addView(input, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        WDialog(
            container,
            WDialog.Config(
                title = LocaleController.getString("Report a Problem"),
                subtitle = LocaleController.getString(
                    if (failedComment == null) {
                        "\$agent_report_problem_description"
                    } else {
                        "\$agent_report_problem_failed"
                    }
                ),
                actionButton = WDialogButton.Config(
                    title = LocaleController.getString("Send"),
                    onTap = {
                        val comment = input.text?.toString().orEmpty()
                        vm.reportProblem(presentationId, comment) { isSent ->
                            showProblemReportResult(presentationId, comment, isSent)
                        }
                    }
                ),
                secondaryButton = WDialogButton.Config(
                    title = LocaleController.getString("Cancel"),
                    onTap = null,
                    style = WDialogButton.Config.Style.NORMAL
                )
            )
        ).presentOn(this)
    }

    private fun showProblemReportResult(presentationId: String?, comment: String, isSent: Boolean) {
        // A failed report opens again with its comment, unless the user has left the screen or can no longer report
        if (!isSent && vm.canReportProblem && !isDestroyed && !isDisappeared) {
            presentProblemReportForm(presentationId, comment)
            return
        }
        Toast.makeText(
            context,
            LocaleController.getString(
                if (isSent) "\$agent_report_problem_sent" else "\$agent_report_problem_failed"
            ),
            Toast.LENGTH_SHORT
        ).show()
    }

    // AgentVM.Delegate

    override fun onThreadChanged(thread: AgentV2ThreadSummary) {
        scheduleChatTitleUpdate()
        updateOpeningTimelineInPlace(buildTimelineItems(displayMessages))
    }

    private fun scheduleChatTitleUpdate() {
        if (!hasAppeared) {
            updateChatTitle()
            return
        }
        if (pendingTitleLayout != null) return
        pendingTitleLayout = chatRecyclerView.doOnPreDraw {
            pendingTitleLayout = null
            chatTitleView.removeCallbacks(applyChatTitle)
            chatTitleView.postOnAnimation(applyChatTitle)
        }
        chatRecyclerView.invalidate()
    }

    private fun cancelPendingChatTitleUpdate() {
        pendingTitleLayout?.removeListener()
        pendingTitleLayout = null
        chatTitleView.removeCallbacks(applyChatTitle)
    }

    private fun updateChatTitle() {
        val firstMessage = displayMessages.firstOrNull { it.role == AgentMessageRole.USER }?.text
        val thread = preparedVM?.currentThread
        val title = if (news != null && thread?.title.isNullOrBlank()) {
            news.headline
        } else {
            thread?.let { resolveAgentThreadTitle(it, firstMessage) } ?: firstMessage.orEmpty()
        }
        val icon = (if (thread != null) thread.icon else news?.icon)
            ?.trim()?.takeIf { it.isNotEmpty() }
        setNavTitle(if (icon != null) "$icon $title" else title, animated = false)
        chatTitleView.setTitle(title, icon)
    }

    override fun onStateChanged(state: AgentVM.State) {
        val model = preparedVM
        if (state == AgentVM.State.ERROR && model != null &&
            chatOpening?.recreateMissingDiscussion(model.startupErrorCode) == true
        ) {
            creationScope.launch {
                if (isSessionReleased || preparedVM !== model) return@launch
                model.setActive(this@AgentVC, false)
                model.detach(this@AgentVC)
                isAttachedToSession = false
                preparedVM = null
                AgentSession.release(model)
                onNewsThreadMissing?.invoke(model.currentThread.id)
                showChatOpening()
            }
            return
        }
        agentState = state
        updateLoadError()
        if (state != AgentVM.State.LOADING) {
            if (displayMessages.isEmpty()) {
                hideSkeleton()
            } else {
                // A News post's suggestions list once the chat is ready and come in with its messages
                if (skeletonReveal.isShown &&
                    buildTimelineItems(displayMessages) != timelineItems
                ) {
                    rebuildTimeline()
                }
                revealMessagesFromSkeleton()
            }
        }
        reloadLastFailureRowIfRetryChanged()
        updateThinkingGlow()
        updateAccessibilityStatus(state)
        val showsConsent = state == AgentVM.State.CONSENT_REQUIRED ||
            state == AgentVM.State.ACCEPTING_CONSENT
        contentContainer.isGone = showsConsent
        consentView.isGone = !showsConsent
        consentView.setLoading(state == AgentVM.State.ACCEPTING_CONSENT)
        if (state == AgentVM.State.ACCEPTING_CONSENT) consentView.showError(null)
        updateComposerSubmission()
        updateMoreButton()
    }

    override fun onMessagesLoaded(messages: List<AgentMessage>) {
        updateLoadError()
        updateThinkingGlow()
        scheduleChatTitleUpdate()
        updateMoreButton()
        val opensAtUnreadDivider = resolveUnreadDivider()
        val items = buildTimelineItems(messages)
        if (updateOpeningTimelineInPlace(items)) return
        // A news post's suggestions that come with its loaded messages appear as an answer's do
        val followups = (items.lastOrNull() as? AgentTimelineItem.Hints)?.followupMessageId
        if (followups != null && timelineItems.lastOrNull() !is AgentTimelineItem.Hints &&
            updateOpeningTimelineInPlace(items.dropLast(1))
        ) {
            appendHintsAfterContentSettles(followups)
            return
        }
        editFadeAnimator?.cancel()
        regeneratingMessageId = null
        editPresentation = null
        animateFromIndex = -1
        viewport.resetPlacement()
        cancelPendingIncomingReveals()
        dismissingHints = null
        dismissingHintsAnchorId = null
        cancelHintsSettleFallback()
        val editedId = editingMessageId
        if (editedId != null && messages.none { it.matchesMessageId(editedId) }) {
            editingMessageId = null
        }
        applyTimeline(buildTimelineItems(messages), TimelineUpdate.RELOAD)
        val unreadDividerIndex = timelineItems.indexOf(AgentTimelineItem.UnreadDivider)
        when {
            preparedVM == null && chatOpening != null -> viewport.showInitialChatAtTop()

            opensAtUnreadDivider && unreadDividerIndex >= 0 ->
                viewport.showItemAtTop(unreadDividerIndex)

            !viewport.restoreSharedScrollPosition() -> viewport.scrollToBottom()
        }
        if (messages.isNotEmpty() && !awaitsNewsPostFollowups(messages)) {
            revealMessagesFromSkeleton()
        }
    }

    private fun resolveUnreadDivider(): Boolean {
        val seen = unreadSeenMessageCount ?: return false
        if (hasResolvedUnreadDivider || preparedVM?.seenMessageCount == null) return false
        hasResolvedUnreadDivider = true
        unreadDividerMessageId = preparedVM?.findFirstUnseenMessageId(seen)
        return unreadDividerMessageId != null
    }

    // A News post's suggestions list once the chat is ready, so its placeholder stays until then
    private fun awaitsNewsPostFollowups(messages: List<AgentMessage>): Boolean {
        val owner = messages.findFollowupOwner() ?: return false
        return owner.newsPost && owner.followups.isNotEmpty() &&
            preparedVM?.state == AgentVM.State.LOADING
    }

    private fun updateOpeningTimelineInPlace(items: List<AgentTimelineItem>): Boolean {
        if (chatOpening == null && preparedVM?.currentThread?.news == null &&
            timelineItems.none { it is AgentTimelineItem.Message && it.newsPost != null }
        ) {
            return false
        }
        // Rebind in place: resetting the viewport would move the landed news card
        if (items.isEmpty() || !hasSameTimelineRows(items, timelineItems)) {
            return false
        }
        applyTimeline(items, TimelineUpdate.IN_PLACE)
        return true
    }

    private enum class TimelineUpdate {
        /** Rebinds every row, and the list lays out from scratch */
        RELOAD,

        /** Inserts, removes and rebinds only the rows that differ, so the list keeps its anchor */
        DIFF,

        /** Updates the rows that differ on their cells when no row comes or goes; reloads otherwise */
        IN_PLACE
    }

    /**
     * The one way the timeline changes: its rows and what the list is told go together, so the list never binds a row
     * it was not told about. [TimelineUpdate.IN_PLACE] also updates [refreshedMessageId]'s row, and returns whether
     * the rows stayed and that row was updated on its cell on screen.
     */
    private fun applyTimeline(
        items: List<AgentTimelineItem>,
        update: TimelineUpdate,
        refreshedMessageId: String? = null
    ): Boolean {
        val previous = timelineItems
        timelineItems = items
        if (update == TimelineUpdate.RELOAD ||
            (update == TimelineUpdate.IN_PLACE && !hasSameTimelineRows(items, previous))
        ) {
            rvAdapter.reloadData()
            return false
        }
        var isRefreshedOnCell = refreshedMessageId == null
        if (update == TimelineUpdate.IN_PLACE) {
            items.forEachIndexed { index, item ->
                val isRefreshed =
                    item is AgentTimelineItem.Message && item.message.id == refreshedMessageId
                if (item == previous[index] && !isRefreshed) return@forEachIndexed
                val isOnCell =
                    item is AgentTimelineItem.Message && updateVisibleCell(item.message.id)
                if (!isOnCell) rvAdapter.notifyItemChanged(index)
                if (isRefreshed) isRefreshedOnCell = isOnCell
            }
        } else {
            val previousKeys = previous.indices.map { timelineRowKey(previous, it) }
            val keys = items.indices.map { timelineRowKey(items, it) }
            DiffUtil.calculateDiff(
                object : DiffUtil.Callback() {
                    override fun getOldListSize() = previous.size
                    override fun getNewListSize() = items.size
                    override fun areItemsTheSame(oldPosition: Int, newPosition: Int) =
                        previousKeys[oldPosition] == keys[newPosition]

                    override fun areContentsTheSame(oldPosition: Int, newPosition: Int) =
                        previous[oldPosition] == items[newPosition]
                },
                false
            ).dispatchUpdatesTo(WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0))
        }
        updateNewsPostTails(previous, items)
        return update == TimelineUpdate.IN_PLACE && isRefreshedOnCell
    }

    // A row stays the same row across updates by its message, a date header by the message under it
    private fun timelineRowKey(items: List<AgentTimelineItem>, index: Int): Pair<Any, String?> =
        when (val item = items[index]) {
            is AgentTimelineItem.Message -> AgentTimelineItem.Message::class to item.message.id

            is AgentTimelineItem.DateHeader ->
                AgentTimelineItem.DateHeader::class to
                    (items.getOrNull(index + 1) as? AgentTimelineItem.Message)?.message?.id

            AgentTimelineItem.UnreadDivider -> AgentTimelineItem.UnreadDivider::class to null

            is AgentTimelineItem.Hints -> AgentTimelineItem.Hints::class to null
        }

    private fun hasSameTimelineRows(a: List<AgentTimelineItem>, b: List<AgentTimelineItem>) =
        a.size == b.size && a.indices.all { timelineRowKey(a, it) == timelineRowKey(b, it) }

    // The News post that suggestions come under or leave loses or regains its tail
    private fun updateNewsPostTails(
        previous: List<AgentTimelineItem>,
        items: List<AgentTimelineItem>
    ) {
        fun messageAboveHints(list: List<AgentTimelineItem>): String? {
            val hintsIndex = list.indexOfFirst { it is AgentTimelineItem.Hints }
            return (list.getOrNull(hintsIndex - 1) as? AgentTimelineItem.Message)?.message?.id
        }
        listOfNotNull(
            messageAboveHints(previous),
            messageAboveHints(items)
        ).distinct().forEach { messageId ->
            val index = items.indexOfFirst {
                it is AgentTimelineItem.Message && it.message.id == messageId
            }
            if (index >= 0) updateNewsPostTail(index)
        }
    }

    override fun onMessagesTruncated(removedMessages: List<AgentMessage>) {
        updateThinkingGlow()
        cancelPendingIncomingReveals()
        chatRecyclerView.cancelActiveGesture()
        viewport.prepareEditInsertion(preservePin = editPresentation?.hidesRemovedMessages == true)
        editPresentation = EditPresentation(
            removedMessages,
            hidesRemovedMessages = editPresentation?.hidesRemovedMessages == true
        )
    }

    private fun submitEditedMessage(messageId: String, text: String): Boolean {
        if (text.isBlank() || !vm.canEditMessage(messageId)) return false
        if (displayMessages.firstOrNull { it.matchesMessageId(messageId) }?.text?.trim() ==
            text.trim()
        ) {
            return true
        }
        val latestUserMessage = displayMessages.lastOrNull { it.role == AgentMessageRole.USER }
        if (latestUserMessage?.matchesMessageId(messageId) != true ||
            !WGlobalStorage.getAreAnimationsActive()
        ) {
            return vm.editMessage(messageId, text)
        }
        val index = viewport.timelineIndexOf(latestUserMessage.id)
        if (index < 0) return vm.editMessage(messageId, text)
        chatRecyclerView.cancelActiveGesture()
        chatRecyclerView.stopScroll()
        isEditFading = true
        fadeMessagesFrom(index, onCancelled = {
            if (!isDestroyed && displayMessages.any { it.matchesMessageId(messageId) }) {
                editingMessageId = messageId
                composerView.setDraftText(text)
            }
        }) { rows ->
            editPresentation = EditPresentation(
                displayMessages.dropWhile { it.id != latestUserMessage.id },
                hidesRemovedMessages = true
            )
            rows.forEach { it.visibility = View.INVISIBLE }
            if (!vm.editMessage(messageId, text)) {
                editPresentation = null
                rows.forEach { it.visibility = View.VISIBLE }
                editingMessageId = messageId
                composerView.setDraftText(text)
            }
        }
        return true
    }

    private fun regenerateMessage(messageId: String) {
        if (!vm.canRegenerateMessage(messageId) || editFadeAnimator != null || isDissolving) return
        val messageIndex = displayMessages.indexOfFirst { it.matchesMessageId(messageId) }
        val questionId =
            displayMessages.take(messageIndex).lastOrNull { it.role == AgentMessageRole.USER }?.id
        val pinQuestion: () -> Unit = {
            questionId?.let { viewport.requestMessagePin(it, preservePadding = true) }
        }
        val index = viewport.timelineIndexOf(messageId)
        if (index < 0 || !WGlobalStorage.getAreAnimationsActive()) {
            pinQuestion()
            vm.regenerateMessage(messageId)
            return
        }
        chatRecyclerView.stopScroll()
        if (AgentDustEffect.isSupported(context)) {
            // The pin lays the list out anew, so it waits until the dust has taken the rows' place
            dissolveMessagesFrom(index, messageId, beforeRegenerating = pinQuestion)
            return
        }
        pinQuestion()
        fadeMessagesFrom(index) { rows ->
            regeneratingMessageId = messageId
            rows.forEach { it.visibility = View.INVISIBLE }
            if (!vm.regenerateMessage(messageId)) {
                regeneratingMessageId = null
                rows.forEach { it.visibility = View.VISIBLE }
            }
        }
    }

    // The answer and what follows it turn to dust in place, as Telegram's deleted messages do; the new answer's
    // typing row takes their place
    private fun dissolveMessagesFrom(
        index: Int,
        messageId: String,
        beforeRegenerating: () -> Unit
    ) {
        val rows = (0 until chatRecyclerView.childCount).map { chatRecyclerView.getChildAt(it) }
            .filter { chatRecyclerView.getChildAdapterPosition(it) >= index }
        isDissolving = true
        updateComposerSubmission()
        val effect = dustEffect?.takeIf { it.isActive } ?: AgentDustEffect(context) { finished ->
            (finished.parent as? ViewGroup)?.removeView(finished)
            if (dustEffect === finished) dustEffect = null
        }.also { effect ->
            effect.id = View.generateViewId()
            contentContainer.addView(
                effect,
                contentContainer.indexOfChild(chatRecyclerView) + 1,
                ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
            dustEffect = effect
        }
        effect.dissolve(
            chatRecyclerView,
            rows,
            onStarted = {
                if (isViewConfigured && !isDestroyed) {
                    regeneratingMessageId = messageId
                    rows.forEach { it.visibility = View.INVISIBLE }
                    beforeRegenerating()
                    if (!vm.regenerateMessage(messageId)) {
                        regeneratingMessageId = null
                        rows.forEach { it.visibility = View.VISIBLE }
                    }
                }
            },
            onDone = {
                isDissolving = false
                if (isViewConfigured && !isDestroyed) updateComposerSubmission()
            }
        )
    }

    private fun fadeMessagesFrom(
        index: Int,
        onCancelled: (() -> Unit)? = null,
        onFaded: (List<View>) -> Unit
    ) {
        val rows = (0 until chatRecyclerView.childCount).map { chatRecyclerView.getChildAt(it) }
            .filter { chatRecyclerView.getChildAdapterPosition(it) >= index }
        composerView.setSubmissionEnabled(false)
        var cancelled = false
        editFadeAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            addUpdateListener { animation ->
                val alpha = animation.animatedValue as Float
                rows.forEach { it.alpha = alpha }
            }
            doOnCancel { cancelled = true }
            doOnEnd {
                editFadeAnimator = null
                if (cancelled) onCancelled?.invoke() else onFaded(rows)
                isEditFading = false
                rows.forEach { it.alpha = 1f }
                updateComposerSubmission()
            }
            start()
        }
    }

    private fun finishEditPresentation(messageId: String) {
        val presentation = editPresentation ?: return
        if (presentation.outgoingMessageId != messageId ||
            !presentation.hasInserted || !presentation.hasPinned
        ) {
            return
        }
        chatRecyclerView.post {
            if (editPresentation !== presentation) return@post
            if (chatRecyclerView.isComputingLayout) {
                finishEditPresentation(messageId)
                return@post
            }
            val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager
                ?: return@post
            val top = layoutManager.findViewByPosition(viewport.timelineIndexOf(messageId))?.top
            editPresentation = null
            dismissingHints = null
            dismissingHintsAnchorId = null
            cancelHintsSettleFallback()
            animateFromIndex = -1
            val newItems = buildTimelineItems(displayMessages)
            applyTimeline(newItems, TimelineUpdate.DIFF)
            val index = viewport.timelineIndexOf(messageId)
            if (index >= 0) {
                val anchorIndex = newItems.agentPinAnchorIndex(index)
                if (anchorIndex != index) {
                    // Rebinding clears visibility inherited from the edit presentation
                    rvAdapter.notifyItemChanged(anchorIndex)
                }
                if (viewport.pinnedMessageId == messageId && anchorIndex != index) {
                    layoutManager.scrollToPositionWithOffset(anchorIndex, 0)
                } else if (top != null) {
                    layoutManager.scrollToPositionWithOffset(
                        index,
                        top - chatRecyclerView.paddingTop
                    )
                }
            }
            pendingIncomingReveals[messageId]?.let(::schedulePendingIncomingReveal)
            chatRecyclerView.doOnNextLayout { viewport.shareScrollPosition() }
        }
    }

    override fun onMessagesPrepended(messages: List<AgentMessage>) {
        animateFromIndex = -1
        applyTimeline(buildTimelineItems(messages), TimelineUpdate.RELOAD)
        viewport.restoreSharedScrollPosition()
        chatRecyclerView.doOnNextLayout {
            viewport.restorePendingPosition()
        }
    }

    override fun onMessageAdded(message: AgentMessage, animated: Boolean) {
        updateLoadError()
        updateMoreButton()
        updateThinkingGlow()
        if (message.role == AgentMessageRole.USER &&
            displayMessages.firstOrNull { it.role == AgentMessageRole.USER }?.id == message.id
        ) {
            scheduleChatTitleUpdate()
        }
        if (message.role == AgentMessageRole.ASSISTANT && regeneratingMessageId != null) {
            regeneratingMessageId = null
            updateComposerSubmission()
        }
        if (!animated) {
            animateFromIndex = -1
            pendingHintsReveal = false
            cancelHintsSettleFallback()
            rebuildTimeline()
            return
        }
        val oldItems = timelineItems
        val isEditInsertion = message.role == AgentMessageRole.USER &&
            editPresentation?.outgoingMessageId == null && editPresentation != null
        if (isEditInsertion) editPresentation?.outgoingMessageId = message.id
        var shouldStartOffscreenPin = false
        if (message.role == AgentMessageRole.USER) {
            pendingIncomingReveals[message.id] = PendingIncomingReveal(message.id)
            outgoingMessageIdsAwaitingIncoming.add(message.id)
            shouldStartOffscreenPin = viewport.prepareOutgoingMessage(
                message.id,
                oldItems,
                forcePin = isEditInsertion
            )
        } else if (message.role == AgentMessageRole.ASSISTANT) {
            val outgoingMessageId = outgoingMessageIdsAwaitingIncoming.removeFirstOrNull()
            val pendingReveal = outgoingMessageId?.let { pendingIncomingReveals[it] }
            if (outgoingMessageId != null && pendingReveal != null) {
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
        val newItems = buildTimelineItems(displayMessages)
        val isAppended =
            newItems.size > oldItems.size && newItems.subList(0, oldItems.size) == oldItems
        applyTimeline(newItems, if (isAppended) TimelineUpdate.DIFF else TimelineUpdate.RELOAD)
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
                            val messageIndex = viewport.timelineIndexOf(message.id)
                            if (chatRecyclerView.findViewHolderForAdapterPosition(messageIndex) ==
                                null
                            ) {
                                onOutgoingInsertAnimationFinished(message.id)
                            }
                        }
                        if (viewport.pendingPinMessageId == message.id &&
                            viewport.deferredPinMessageId != message.id
                        ) {
                            viewport.evaluatePinning(message.id)
                        }
                    }
                }
                if (shouldStartOffscreenPin) {
                    preparePinning()
                } else {
                    chatRecyclerView.doOnNextLayout { preparePinning() }
                }
            }

            viewport.pendingPinMessageId != null ||
                viewport.pinnedMessageId != null ||
                viewport.pendingSharedScrollPosition != null -> {
                // The pinned anchor keeps its position; viewport.syncPinnedPadding fits the new
                // content into the reserved space instead of scrolling.
                viewport.pendingPinMessageId?.let { pinnedId ->
                    chatRecyclerView.doOnNextLayout { viewport.evaluatePinning(pinnedId) }
                }
            }

            else -> viewport.scrollToBottom()
        }
    }

    override fun onMessageRemoved(messageId: String) {
        updateLoadError()
        updateMoreButton()
        updateThinkingGlow()
        val oldItems = timelineItems
        val removedIndex = oldItems.indexOfFirst { item ->
            item is AgentTimelineItem.Message && item.message.id == messageId
        }
        pendingIncomingReveals.entries
            .firstOrNull { it.value.incomingMessageId == messageId }
            ?.let { entry ->
                entry.value.revealRunnable?.let(chatRecyclerView::removeCallbacks)
                pendingIncomingReveals.remove(entry.key)
            }
        hiddenIncomingMessageIds.remove(messageId)
        val newItems = buildTimelineItems(displayMessages)
        when {
            removedIndex >= 0 && oldItems.size == newItems.size + 1 ->
                applyTimeline(newItems, TimelineUpdate.DIFF)

            oldItems != newItems -> applyTimeline(newItems, TimelineUpdate.RELOAD)
        }
    }

    override fun onStreamingUpdate(messageId: String) {
        streamRenderer.enqueue(messageId)
        updateThinkingGlow()
    }

    override fun onStreamingFinished(messageId: String) {
        streamRenderer.enqueue(messageId)
        updateThinkingGlow()
    }

    /**
     * TalkBack hears when the Agent starts on an answer and, once it has run, when it is done, except
     * while the user records a question
     */
    private fun updateAccessibilityStatus(state: AgentVM.State) {
        val status = when {
            state == AgentVM.State.RUNNING -> LocaleController.getString("\$agent_chat_running")
            accessibilityStatus != null -> LocaleController.getString("Agent")
            else -> null
        }
        if (status == accessibilityStatus) return
        accessibilityStatus = status
        if (status == null || !isViewActive) return
        if (dictation.state.phase == AgentDictationPhase.RECORDING) return
        @Suppress("DEPRECATION")
        view.announceForAccessibility(status)
    }

    // The screen's edge glows while the Agent works on an answer it has not started writing
    private fun updateThinkingGlow() {
        val glow = edgeGlow ?: return
        val answer = displayMessages.lastOrNull { it.role == AgentMessageRole.ASSISTANT }
        glow.setGlowing(isViewActive && answer != null && answer.isStreaming && !answer.hasText)
    }

    override fun onFollowupsChanged(messageId: String, animated: Boolean) {
        streamRenderer.enqueue(messageId)
        updateVisibleHintsAvailability()
    }

    private fun updateVisibleHintsAvailability() {
        for (index in 0 until chatRecyclerView.childCount) {
            val cell = chatRecyclerView.getChildAt(index) as? AgentHintsCell ?: continue
            updateHintsAvailability(cell)
        }
    }

    private fun updateHintsAvailability(cell: AgentHintsCell) {
        val model = preparedVM ?: return
        val item = timelineItems.getOrNull(chatRecyclerView.getChildAdapterPosition(cell))
            as? AgentTimelineItem.Hints ?: return
        cell.setCardsEnabled(item.followupMessageId == null || model.canSendFollowup)
    }

    override fun onOutgoingMessageFailed(messageId: String) {
        updateThinkingGlow()
        if (editPresentation?.outgoingMessageId == messageId) {
            editPresentation = null
            rebuildTimeline()
            pendingIncomingReveals[messageId]?.let(::schedulePendingIncomingReveal)
        }
        if (regeneratingMessageId == messageId) {
            regeneratingMessageId = null
            rebuildTimeline()
        }
        outgoingMessageIdsAwaitingIncoming.remove(messageId)
        val pendingReveal = pendingIncomingReveals[messageId] ?: return
        if (pendingReveal.incomingMessageId != null) return
        pendingReveal.revealRunnable?.let { chatRecyclerView.removeCallbacks(it) }
        pendingIncomingReveals.remove(messageId)
    }

    override fun onPendingMessageActivated(messageId: String) {
        if (messageId == chatOpening?.messages?.firstOrNull()?.id) return
        if (pendingIncomingReveals.containsKey(messageId) ||
            viewport.timelineIndexOf(messageId) < 0
        ) {
            return
        }
        pendingIncomingReveals[messageId] = PendingIncomingReveal(
            outgoingMessageId = messageId,
            isOutgoingAnimationFinished = true
        )
        outgoingMessageIdsAwaitingIncoming.add(messageId)
        viewport.activatePendingMessage(messageId)
        chatRecyclerView.post {
            if (viewport.pendingPinMessageId == messageId) viewport.evaluatePinning(messageId)
        }
    }

    private fun onStreamEvent(messageId: String) {
        if (hiddenIncomingMessageIds.contains(messageId)) return
        val previousHints = timelineItems.lastOrNull() as? AgentTimelineItem.Hints
        val hadHints = previousHints != null
        var newItems = buildTimelineItems(displayMessages)
        val hintsDue = !hadHints && newItems.lastOrNull() is AgentTimelineItem.Hints
        if (hintsDue) {
            // Hold hints back until the message's own animations (text reveal, deeplink
            // appearance) have finished playing.
            newItems = newItems.dropLast(1)
        } else if (previousHints != null && newItems.lastOrNull() !is AgentTimelineItem.Hints) {
            // Keep the old hints listed until onHintsUpdated finishes their collapse.
            newItems = newItems + previousHints
        }
        // A row the update adds or takes away, such as an answer's failure line, reloads the list
        val updatedInPlace = updateOpeningTimelineInPlace(newItems) ||
            applyTimeline(newItems, TimelineUpdate.IN_PLACE, refreshedMessageId = messageId)
        if (hintsDue) {
            if (updatedInPlace) {
                appendHintsAfterContentSettles(messageId)
            } else {
                cancelHintsSettleFallback()
                appendDueHints(messageId)
            }
        }
        if (viewport.isOnBottom) {
            viewport.scrollToBottom()
        }
    }

    private fun appendHintsAfterContentSettles(messageId: String) {
        cancelHintsSettleFallback()
        val holder = chatRecyclerView
            .findViewHolderForAdapterPosition(viewport.timelineIndexOf(messageId))
        val cell = (holder as? WCell.Holder)?.cell as? AgentMessageCell
        if (cell?.isContentSettling == true) {
            hintsSettleMessageId = messageId
            // A cell bound during layout settles there, where the list cannot take the hints row yet
            cell.onContentSettled = {
                if (chatRecyclerView.isComputingLayout) {
                    chatRecyclerView.post { appendDueHints(messageId) }
                } else {
                    appendDueHints(messageId)
                }
            }
            // The settle callback can get lost if the cell is recycled mid-animation.
            val fallback = Runnable { appendDueHints(messageId) }
            hintsSettleFallback = fallback
            chatRecyclerView.postDelayed(fallback, HINTS_SETTLE_FALLBACK_MS)
        } else {
            appendDueHints(messageId)
        }
    }

    private fun cancelHintsSettleFallback() {
        hintsSettleMessageId = null
        hintsSettleFallback?.let { chatRecyclerView.removeCallbacks(it) }
        hintsSettleFallback = null
    }

    private fun onOutgoingInsertAnimationFinished(messageId: String) {
        editPresentation?.takeIf { it.outgoingMessageId == messageId }?.hasInserted = true
        finishEditPresentation(messageId)
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
        if (editPresentation?.outgoingMessageId == pendingReveal.outgoingMessageId) return
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
        var newItems = buildTimelineItems(displayMessages)
        if (newItems.lastOrNull() is AgentTimelineItem.Hints) {
            newItems = newItems.dropLast(1)
        }
        val insertedAt = newItems.indexOfFirst {
            it is AgentTimelineItem.Message && it.message.id == incomingMessageId
        }
        if (insertedAt < 0 || newItems.size - oldItemCount != 1) {
            animateFromIndex = -1
            applyTimeline(newItems, TimelineUpdate.RELOAD)
        } else {
            animateFromIndex = insertedAt
            applyTimeline(newItems, TimelineUpdate.DIFF)
        }
        val pinMessageId = viewport.deferredPinMessageId.takeIf { it == outgoingMessageId }
        chatRecyclerView.doOnNextLayout {
            animateFromIndex = -1
            if (pinMessageId != null && viewport.pendingPinMessageId == pinMessageId) {
                viewport.clearDeferredPin()
                viewport.evaluatePinning(pinMessageId)
            } else if (viewport.pinnedMessageId != null) {
                viewport.syncPinnedPadding()
            }
            if (buildTimelineItems(displayMessages).lastOrNull() is AgentTimelineItem.Hints) {
                appendHintsAfterContentSettles(incomingMessageId)
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
        viewport.clearOutgoingPlacement()
    }

    private fun appendDueHints(messageId: String) {
        // A settlement scheduled for a superseded response must not release the newer one's hints.
        if (hintsSettleMessageId != null && hintsSettleMessageId != messageId) return
        cancelHintsSettleFallback()
        if (timelineItems.lastOrNull() is AgentTimelineItem.Hints) return
        val canonical = buildTimelineItems(displayMessages)
        if (canonical.lastOrNull() !is AgentTimelineItem.Hints) return
        scheduleHintsReveal()
        applyTimeline(canonical, TimelineUpdate.DIFF)
        viewport.refreshIsOnBottom()
        if (viewport.isOnBottom) viewport.scrollToBottom()
    }

    private fun scheduleHintsReveal() {
        pendingHintsReveal = true
        chatRecyclerView.doOnNextLayout { pendingHintsReveal = false }
    }

    // A News post that suggestions hang from, right under it, has no tail, as an answer's bubble does
    private fun hasFollowupsBelow(index: Int): Boolean {
        val message = (timelineItems.getOrNull(index) as? AgentTimelineItem.Message)?.message
            ?: return false
        val hints = timelineItems.getOrNull(index + 1) as? AgentTimelineItem.Hints
        return shouldShowFollowups(message) || hints?.followupMessageId != null
    }

    private fun updateNewsPostTail(index: Int) {
        val holder = chatRecyclerView.findViewHolderForAdapterPosition(index) as? WCell.Holder
        (holder?.cell as? AgentNewsPostCell)?.setHasFollowupsBelow(hasFollowupsBelow(index))
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
        viewport.preserveCollapsingHintsSpace(delta, hintsIdx, dismissingHintsAnchorId != null)
    }

    private fun finishHintsDismissal() {
        val item = dismissingHints ?: return
        dismissingHints = null
        dismissingHintsAnchorId = null
        val idx = timelineItems.indexOf(item)
        if (idx >= 0) {
            applyTimeline(timelineItems.filterIndexed { i, _ -> i != idx }, TimelineUpdate.DIFF)
        }
        // Hints may be due again already (e.g. the dismissal was caused by a system
        // message rather than a new request).
        val canonical = buildTimelineItems(displayMessages)
        if (canonical.lastOrNull() is AgentTimelineItem.Hints &&
            timelineItems.lastOrNull() !is AgentTimelineItem.Hints
        ) {
            scheduleHintsReveal()
            applyTimeline(canonical, TimelineUpdate.DIFF)
            viewport.refreshIsOnBottom()
            if (viewport.isOnBottom) viewport.scrollToBottom()
        }
    }

    private fun setMessageRenderingActive(active: Boolean) {
        streamRenderer.setActive(active)
        for (index in 0 until chatRecyclerView.childCount) {
            when (val cell = chatRecyclerView.getChildAt(index)) {
                is AgentMessageCell -> cell.setRenderingActive(active)
                is AgentNewsPostCell -> cell.setRenderingActive(active)
            }
        }
        chatRecyclerView.suppressLayout(!active || isPopupVisible)
    }

    private fun updateVisibleCell(messageId: String): Boolean {
        if (!streamRenderer.isActive) return false
        val idx = viewport.timelineIndexOf(messageId)
        if (idx < 0) return false

        val holder = chatRecyclerView.findViewHolderForAdapterPosition(idx)
        if (holder is WCell.Holder) {
            val item = timelineItems[idx] as AgentTimelineItem.Message
            if (holder.itemViewType !=
                recyclerViewCellType(chatRecyclerView, IndexPath(0, idx)).value
            ) {
                rvAdapter.notifyItemChanged(idx)
                return true
            }
            when (val cell = holder.cell) {
                is AgentMessageCell -> cell.configure(
                    item.message,
                    chatRecyclerView.width,
                    preparedVM?.publishesAnswerLinks == true,
                    hasFollowupsBelow = shouldShowFollowups(item.message)
                )

                is AgentNewsPostCell -> {
                    val post = checkNotNull(item.newsPost)
                    cell.configure(
                        item.message.id,
                        item.message.date,
                        post,
                        chatRecyclerView.width,
                        hasFollowupsBelow = hasFollowupsBelow(idx)
                    )
                }

                else -> return false
            }
            return true
        }
        return false
    }

    // While the list's bar carries the question field into this chat or back out of it, the composer lies exactly over
    // the bar: it keeps its place on the screen as the chat slides, and starts where the bar's field does
    private var composerHandoffStart: Int? = null
    private var composerHandoffBinding: AgentPreDrawBinding? = null
    private val composerHandoffFollower = ViewTreeObserver.OnPreDrawListener {
        val shift = -view.translationX
        if (composerView.translationX != shift) composerView.translationX = shift
        true
    }

    /**
     * The list's bar hands its field to this chat or takes it back: the composer follows the bar, its field starting
     * [fieldStart] from the screen's start, until null hands it back to the chat
     */
    fun setComposerHandoff(fieldStart: Int?) {
        if (!isViewConfigured) return
        val wasHandedOff = composerHandoffStart != null
        composerHandoffStart = fieldStart
        if (fieldStart != null && !wasHandedOff) {
            composerHandoffBinding = AgentPreDrawBinding(view, composerHandoffFollower)
        } else if (fieldStart == null && wasHandedOff) {
            composerHandoffBinding?.release()
            composerHandoffBinding = null
            composerView.translationX = 0f
        }
        val marginStart = fieldStart ?: 0
        val params = composerView.layoutParams as? ConstraintLayout.LayoutParams ?: return
        if (params.marginStart != marginStart) {
            params.marginStart = marginStart
            composerView.layoutParams = params
        }
    }

    // A menu asked for over the keyboard, which opens once the keyboard has gone
    private var menuAfterKeyboard: (() -> Unit)? = null
    private val openMenuAfterKeyboardRunnable = Runnable {
        // Without a keyboard animation to end, the menu opens once the keyboard has gone, and not over it
        if ((navigationController?.imeInsetBottom ?: 0) <= 0) {
            openMenuAfterKeyboard()
        } else {
            menuAfterKeyboard = null
        }
    }

    /**
     * Opens a row's menu at once, or, over the keyboard, puts the keyboard away first and opens the menu once the
     * chat has settled under it, as Telegram's menu takes the keyboard's place over a still chat
     */
    private fun presentMenuAfterKeyboard(open: () -> Unit) {
        if ((navigationController?.imeInsetBottom ?: 0) <= 0) {
            open()
            return
        }
        cancelDictation()
        menuAfterKeyboard = open
        view.hideKeyboard()
        chatRecyclerView.removeCallbacks(openMenuAfterKeyboardRunnable)
        chatRecyclerView.postDelayed(openMenuAfterKeyboardRunnable, MENU_AFTER_KEYBOARD_TIMEOUT_MS)
    }

    private fun openMenuAfterKeyboard() {
        val open = menuAfterKeyboard ?: return
        menuAfterKeyboard = null
        chatRecyclerView.removeCallbacks(openMenuAfterKeyboardRunnable)
        // After the layout that follows the keyboard, where the row now is
        chatRecyclerView.post { if (isViewActive && !isDestroyed) open() }
    }

    private fun openNewsPhoto(messageId: String, news: AgentV2ThreadNewsCard) {
        val window = window ?: return
        val url = news.imageUrl ?: return
        cancelDictation()
        view.hideKeyboard()
        MediaViewerVC.present(window, listOf(agentNewsMediaViewerItem(window, url, news)), 0) {
            chatRecyclerView.children
                .filterIsInstance<AgentNewsPostCell>()
                .firstOrNull { it.shownPostId == messageId }
                ?.makePhotoSource()
        }
    }

    private fun showCopyBulletin() {
        val bottomOffset = (view.height - composerView.top).coerceAtLeast(0)
        copyBulletin.show(view, LocaleController.getString("Message Copied"), bottomOffset)
    }

    private fun onCopyPopupVisibilityChanged(visible: Boolean) {
        if (visible) {
            cancelDictation()
            viewport.finishLatestScroll()
            // As in Telegram, the menu takes the keyboard's place
            view.hideKeyboard()
        }
        isPopupVisible = visible
        chatRecyclerView.suppressLayout(visible || !streamRenderer.isActive)
    }

    private fun getMenuRows(): IntRange {
        val top = navigationBar?.let { it.getLocationInWindow().y + it.height }
            ?: chatRecyclerView.getLocationInWindow().y
        return top until composerView.getLocationInWindow().y
    }

    override fun onHintsUpdated(hints: List<AgentHint>) {
        if (streamRenderer.hasPendingUpdates) return
        val hadHints = timelineItems.lastOrNull() is AgentTimelineItem.Hints
        val newItems = buildTimelineItems(displayMessages)
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
            if (timelineItems != newItems && !updateOpeningTimelineInPlace(newItems)) {
                applyTimeline(newItems, TimelineUpdate.RELOAD)
            }
            return
        }

        if (hasHints) {
            if (hintsSettleFallback != null) {
                // Hints are already waiting for the message content to settle.
                return
            }
            scheduleHintsReveal()
            applyTimeline(newItems, TimelineUpdate.DIFF)
            viewport.refreshIsOnBottom()
            if (viewport.isOnBottom) viewport.scrollToBottom()
        } else {
            val hintsIndex = timelineItems.size - 1
            val holder = chatRecyclerView.findViewHolderForAdapterPosition(hintsIndex)
            val cell = (holder as? WCell.Holder)?.cell as? AgentHintsCell
            if (cell?.isCollapsing == true) return
            if (cell != null) {
                cell.collapse {
                    val items = buildTimelineItems(displayMessages)
                    // Hints re-enabled while collapsing restore the cell
                    val isRestored = items.lastOrNull() is AgentTimelineItem.Hints
                    applyTimeline(
                        items,
                        if (isRestored) TimelineUpdate.RELOAD else TimelineUpdate.DIFF
                    )
                }
            } else {
                applyTimeline(newItems, TimelineUpdate.DIFF)
            }
        }
    }

    private fun updateLoadError() {
        val model = preparedVM
        val failure = if (model != null && agentState == AgentVM.State.ERROR) {
            agentNewsPostMessages(
                displayMessages,
                model.historyCursor,
                model.currentThread.news,
                news
            )
                .takeIf { messages ->
                    messages.isNotEmpty() && messages.all { it.message.isFailure }
                }?.lastOrNull()?.message
        } else {
            null
        }
        loadErrorView.setError(failure?.text)
        chatRecyclerView.isInvisible = failure != null
    }

    override fun onOlderMessagesLoadingChanged() {
        historySpinner.setLoading(preparedVM?.isLoadingOlderMessages == true)
    }

    override fun onInputLimitChanged() {
        updateComposerSubmission()
        updateVisibleHintsAvailability()
        reloadLastFailureRowIfRetryChanged()
    }

    /** New questions wait while a limit blocks them; the composer then stays dimmed */
    private fun updateComposerSubmission() {
        val model = preparedVM
        composerView.setSubmissionEnabled(
            model != null && !model.hasUnsentOpening &&
                agentNewsAllowsSubmission(news, agentState) &&
                agentState != AgentVM.State.CLEARING && editFadeAnimator == null &&
                !isDissolving && regeneratingMessageId == null && !model.isInputBlockedByLimit
        )
        // As the design's "Limit Reached" frame shows it, the composer's contents are at half their opacity while a
        // limit blocks sending
        composerView.contentAlpha =
            if (model?.isInputBlockedByLimit == true) DISABLED_BUTTON_ALPHA else 1f
    }

    /** The failure that ends the timeline offers Retry while the chat can use it; earlier ones don't */
    private fun buildFailureRetry(message: AgentMessage): (() -> Unit)? {
        if (!message.isFailure ||
            findLastTimelineMessageIndex()?.let { timelineMessageAt(it) }?.id != message.id
        ) {
            return null
        }
        return preparedVM?.failureRetry.also { isFailureRetryShown = it != null }
    }

    // Whether the failure that ends the timeline shows Retry, which it gains or loses as the chat's state and
    // limits change
    private var isFailureRetryShown = false

    private fun reloadLastFailureRowIfRetryChanged() {
        val isShown = preparedVM?.failureRetry != null
        if (isFailureRetryShown == isShown) return
        isFailureRetryShown = isShown
        reloadLastFailureRow()
    }

    private fun reloadLastFailureRow() {
        val index = findLastTimelineMessageIndex() ?: return
        if (timelineMessageAt(index)?.isFailure == true) rvAdapter.notifyItemChanged(index)
    }

    private fun findLastTimelineMessageIndex(): Int? =
        timelineItems.indexOfLast { it is AgentTimelineItem.Message }.takeIf { it >= 0 }

    private fun timelineMessageAt(index: Int): AgentMessage? =
        (timelineItems.getOrNull(index) as? AgentTimelineItem.Message)?.message

    override fun onError() {
        if (agentState == AgentVM.State.CONSENT_REQUIRED ||
            agentState == AgentVM.State.ACCEPTING_CONSENT
        ) {
            consentView.showError(agentUnavailableText())
        }
    }

    override fun onActionUnavailable(reason: String?) {
        Toast.makeText(context, agentActionUnavailableText(reason), Toast.LENGTH_SHORT).show()
    }

    override fun onOpenDapp(site: MExploreSite) {
        val w = window ?: return
        val url = site.url ?: return
        cancelDictation()
        val uri = url.toUri()
        view.hideKeyboard()
        if (site.isExternal || site.isTelegram || uri.scheme !in setOf("http", "https")) {
            try {
                w.startActivity(Intent(Intent.ACTION_VIEW, uri))
            } catch (_: Exception) {
                onActionUnavailable()
            }
            return
        }
        val nav = WNavigationController(w)
        nav.setRoot(
            InAppBrowserVC(
                context,
                InAppBrowserConfig(
                    url = url,
                    title = site.name,
                    thumbnail = site.iconUrl,
                    injectDappConnect = true,
                    saveInVisitedHistory = true
                )
            )
        )
        w.present(nav)
    }

    /** A link to a screen of the app runs as its deeplink; any other link opens in the in-app browser */
    private fun openAnswerLink(url: String) {
        cancelDictation()
        if (AgentTextLinks.isAppScreenLink(url)) {
            WalletCore.notifyEvent(WalletEvent.OpenUrl(url, source = DeeplinkOpenSource.AGENT))
        } else {
            openInAppBrowser(url)
        }
    }

    private fun openInAppBrowser(url: String) {
        val w = window ?: return
        val config = InAppBrowserConfig(
            url = url,
            injectDappConnect = false
        )
        val inAppBrowserVC = InAppBrowserVC(
            context,
            config
        )
        val nav = WNavigationController(w)
        nav.setRoot(inAppBrowserVC)
        w.present(nav)
    }

    // An existing chat whose messages are still to load shows placeholder bubbles in place of its timeline, which
    // a News discussion already fills with its post
    private fun showSkeletonIfLoading() {
        val model = preparedVM ?: return
        if (chatOpening != null || model.state != AgentVM.State.LOADING ||
            model.messages.isNotEmpty() || model.currentThread.messageCount == 0
        ) {
            return
        }
        skeletonReveal.show()
    }

    private fun revealMessagesFromSkeleton() {
        skeletonReveal.reveal(hasRows = displayMessages.isNotEmpty())
    }

    private fun hideSkeleton() = skeletonReveal.hide()

    // Whether the suggestions under the answer show, as the timeline lists them
    private fun shouldShowFollowups(message: AgentMessage): Boolean {
        val owner = displayMessages.findFollowupOwner() ?: return false
        return owner.id == message.id && owner.followups.isNotEmpty() && !owner.isStreaming &&
            (!owner.newsPost || preparedVM?.state == AgentVM.State.READY) &&
            !hiddenIncomingMessageIds.contains(owner.id) && dismissingHints == null
    }

    private fun rebuildTimeline() {
        applyTimeline(buildTimelineItems(displayMessages), TimelineUpdate.RELOAD)
    }

    private fun buildTimelineItems(messages: List<AgentMessage>): List<AgentTimelineItem> {
        val items = mutableListOf<AgentTimelineItem>()
        var lastDate: Date? = null

        val presentationMessages = editPresentation?.let { presentation ->
            val index = messages.indexOfFirst { it.id == presentation.outgoingMessageId }
            if (index < 0) {
                messages
            } else {
                messages.take(index) + presentation.removedMessages + messages.drop(index)
            }
        } ?: messages
        val messageItems = agentNewsPostMessages(
            presentationMessages,
            preparedVM?.historyCursor,
            preparedVM?.currentThread?.news,
            news
        )
        val shownItems = messageItems.filterNot { hiddenIncomingMessageIds.contains(it.message.id) }
        for (item in shownItems.insertFailureLines()) {
            val message = item.message
            if (lastDate == null || message.date.time - lastDate.time > DATE_HEADER_GAP_MS) {
                items.add(AgentTimelineItem.DateHeader(message.date))
            }
            lastDate = message.date
            if (message.id == unreadDividerMessageId) items.add(AgentTimelineItem.UnreadDivider)
            items.add(item)
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
        val followupOwner = messages.findFollowupOwner()
        val followups = followupOwner?.followups.orEmpty()
        val pendingNews = shownItems.lastOrNull()?.takeIf { it.newsPost != null }
        if ((followups.isEmpty() || agentState == AgentVM.State.LOADING) &&
            pendingNews != null && !newsFollowupsExpired &&
            displayMessages.none { it.role == AgentMessageRole.USER } &&
            preparedVM?.state != AgentVM.State.ERROR
        ) {
            if (newsFollowupsTimeout == null) {
                val timeout = Runnable {
                    newsFollowupsExpired = true
                    onHintsUpdated(emptyList())
                }
                newsFollowupsTimeout = timeout
                view.postDelayed(timeout, 25_000)
            }
            items.add(
                AgentTimelineItem.Hints(emptyList(), pendingNews.message.id, isLoading = true)
            )
            return items
        }
        if (followups.isNotEmpty() && followupOwner?.isStreaming == false &&
            (!followupOwner.newsPost || preparedVM?.state == AgentVM.State.READY) &&
            !hiddenIncomingMessageIds.contains(followupOwner.id)
        ) {
            items.add(
                AgentTimelineItem.Hints(
                    followups.map { AgentHint(it.id, it.text, "", it.text) },
                    followupMessageId = followupOwner.id
                )
            )
        } else {
            val hints = preparedVM?.visibleHints.orEmpty()
            if (hints.isNotEmpty() && messages.lastOrNull()?.isStreaming != true) {
                items.add(AgentTimelineItem.Hints(hints))
            }
        }
        return items
    }

    // WRecyclerViewDataSource

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int = timelineItems.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type =
        when (timelineItems[indexPath.row]) {
            is AgentTimelineItem.DateHeader -> DATE_CELL

            AgentTimelineItem.UnreadDivider -> UNREAD_CELL

            is AgentTimelineItem.Hints -> HINTS_CELL

            is AgentTimelineItem.Message -> {
                val item = timelineItems[indexPath.row] as AgentTimelineItem.Message
                when {
                    item.newsPost != null -> NEWS_POST_CELL
                    item.message.role == AgentMessageRole.SYSTEM -> SYSTEM_CELL
                    else -> MESSAGE_CELL
                }
            }
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            DATE_CELL -> AgentDateHeaderCell(context)
            SYSTEM_CELL -> AgentSystemMessageCell(context)
            HINTS_CELL -> AgentHintsCell(context)
            UNREAD_CELL -> AgentUnreadDividerCell(context)
            NEWS_POST_CELL -> AgentNewsPostCell(context, messageTextCache)
            else -> AgentMessageCell(context, messageTextCache)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        // A cell configured outside the list's binding, as on a width change, skips a row of another kind
        if (cellHolder.itemViewType != recyclerViewCellType(rv, indexPath).value) return
        skeletonReveal.finishRow(cellHolder.cell)
        val presentation = editPresentation
        val removedStart = presentation?.removedMessages?.firstOrNull()?.id
            ?.let(viewport::timelineIndexOf) ?: -1
        val outgoingIndex = presentation?.outgoingMessageId
            ?.let(viewport::timelineIndexOf) ?: timelineItems.size
        val regenerationStart = regeneratingMessageId?.let(viewport::timelineIndexOf) ?: -1
        cellHolder.cell.visibility = if ((
                presentation?.hidesRemovedMessages == true &&
                    indexPath.row in removedStart until outgoingIndex && removedStart >= 0
                ) ||
            (regenerationStart >= 0 && indexPath.row >= regenerationStart)
        ) {
            View.INVISIBLE
        } else {
            View.VISIBLE
        }
        val animate = animateFromIndex in 0..indexPath.row
        when (val item = timelineItems[indexPath.row]) {
            is AgentTimelineItem.DateHeader -> {
                (cellHolder.cell as AgentDateHeaderCell).apply {
                    onPopupVisibilityChanged = ::onCopyPopupVisibilityChanged
                    menuPresenter = ::presentMenuAfterKeyboard
                    menuRows = ::getMenuRows
                    configure(item.date, animate)
                }
            }

            AgentTimelineItem.UnreadDivider -> Unit

            is AgentTimelineItem.Hints -> {
                (cellHolder.cell as AgentHintsCell).apply {
                    onHintTap = { hint ->
                        val messageId = item.followupMessageId
                        if (messageId != null) {
                            sendFollowup(messageId, hint.id)
                        } else {
                            sendMessage(hint.prompt, vm.hintEntryPoint(hint))
                        }
                    }
                    onCollapseFrame = { delta -> onHintsCollapseFrame(delta) }
                    configure(
                        item.hints,
                        shouldShowEmptyStateIcon = displayMessages.isEmpty(),
                        shouldAnimate = pendingHintsReveal,
                        areFollowups = item.followupMessageId != null,
                        isLoading = item.isLoading
                    )
                    setCardsEnabled(
                        item.followupMessageId == null || preparedVM?.canSendFollowup == true
                    )
                }
            }

            is AgentTimelineItem.Message -> {
                when (val cell = cellHolder.cell) {
                    is AgentNewsPostCell -> {
                        val post = checkNotNull(item.newsPost)
                        val messageId = item.message.id
                        val tracksIncomingReveal = pendingIncomingReveals.containsKey(messageId)
                        val tracksPin = messageId == viewport.pendingPinMessageId
                        cell.setRenderingActive(streamRenderer.isActive)
                        cell.onOpenSource = { url ->
                            cancelDictation()
                            AgentNewsSourceLinks.open(context, window, url)
                        }
                        cell.onPopupVisibilityChanged = ::onCopyPopupVisibilityChanged
                        cell.onCopied = ::showCopyBulletin
                        cell.onPictureTap = { openNewsPhoto(messageId, post) }
                        cell.canOpenMenuOnTap = ::canOpenMenuOnTap
                        cell.menuPresenter = ::presentMenuAfterKeyboard
                        cell.menuRows = ::getMenuRows
                        cell.onSizeTransitionFrame = { previousHeight ->
                            viewport.preservePinAcrossSizeTransition(
                                messageId,
                                cell,
                                previousHeight
                            )
                        }
                        cell.onInsertAnimationStarted = if (tracksIncomingReveal || tracksPin) {
                            { targetHeight ->
                                if (tracksIncomingReveal) {
                                    onOutgoingInsertAnimationStarted(
                                        messageId
                                    )
                                }
                                if (tracksPin) {
                                    viewport.onOutgoingInsertAnimationPrepared(
                                        messageId,
                                        targetHeight
                                    )
                                }
                            }
                        } else {
                            null
                        }
                        cell.onInsertAnimationFinished = if (tracksIncomingReveal) {
                            { onOutgoingInsertAnimationFinished(messageId) }
                        } else {
                            null
                        }
                        cell.configure(
                            item.message.id,
                            item.message.date,
                            post,
                            rv.width,
                            animate,
                            hasFollowupsBelow = hasFollowupsBelow(indexPath.row)
                        )
                    }

                    is AgentMessageCell -> {
                        cell.setRenderingActive(streamRenderer.isActive)
                        val messageId = item.message.id
                        val tracksIncomingReveal =
                            pendingIncomingReveals.containsKey(messageId)
                        val tracksPin = messageId == viewport.pendingPinMessageId
                        cell.onOpenUrl = { url -> openAnswerLink(url) }
                        cell.onAction = { actionId ->
                            cancelDictation()
                            if (actionId == RETRY_CHAT_CREATION && preparedVM == null) {
                                createChatThread()
                            } else {
                                preparedVM?.performAction(messageId, actionId)
                            }
                        }
                        cell.onReportProblem = { presentProblemReportForm(messageId) }
                        cell.canReportProblem = { preparedVM?.canReportProblem == true }
                        cell.canEditMessage = {
                            val currentItem = timelineItems.getOrNull(
                                viewport.timelineIndexOf(messageId)
                            )
                                as? AgentTimelineItem.Message
                            currentItem?.newsPost == null &&
                                preparedVM?.canEditMessage(messageId) == true
                        }
                        cell.canRegenerateMessage = {
                            preparedVM?.canRegenerateMessage(messageId) == true
                        }
                        cell.onRegenerate = { regenerateMessage(messageId) }
                        cell.onRate = { feedback ->
                            vm.rateMessage(messageId, feedback) {
                                Toast.makeText(
                                    context,
                                    LocaleController.getString("\$agent_feedback_failed"),
                                    Toast.LENGTH_SHORT
                                ).show()
                            }
                        }
                        cell.onEdit = {
                            if (cell.canEditMessage()) {
                                composerView.setDraftText(item.message.text)
                                editingMessageId = messageId
                            }
                        }
                        cell.onCopied = ::showCopyBulletin
                        cell.onPopupVisibilityChanged = ::onCopyPopupVisibilityChanged
                        cell.canOpenMenuOnTap = ::canOpenMenuOnTap
                        cell.menuPresenter = ::presentMenuAfterKeyboard
                        cell.menuRows = ::getMenuRows
                        cell.onSizeTransitionFrame = { previousHeight ->
                            viewport.preservePinAcrossSizeTransition(
                                messageId,
                                cell,
                                previousHeight
                            )
                        }
                        cell.onInsertAnimationStarted =
                            if (tracksIncomingReveal || tracksPin) {
                                { targetHeight ->
                                    if (tracksIncomingReveal) {
                                        onOutgoingInsertAnimationStarted(messageId)
                                    }
                                    if (tracksPin) {
                                        viewport.onOutgoingInsertAnimationPrepared(
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
                        cell.configure(
                            item.message,
                            rv.width,
                            preparedVM?.publishesAnswerLinks == true,
                            animate,
                            hasFollowupsBelow = shouldShowFollowups(item.message)
                        )
                    }

                    is AgentSystemMessageCell -> cell.configure(
                        item.message,
                        buildFailureRetry(item.message)
                    )
                }
            }
        }
    }
}
