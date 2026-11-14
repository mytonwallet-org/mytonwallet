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
import android.view.animation.LinearInterpolator
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.LinearLayout
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
import kotlin.math.max
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
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationPhase
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.AndroidAgentDictationRecorder
import org.mytonwallet.app_air.uiagent.agentV2.agentActionUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.hasPost
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.agentV2.resolveAgentThreadTitle
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentBulletinDurations
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentReactionAnimation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSupportEventCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentUnreadDividerCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isAgentPicturePinchStart
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isMessageMenuTapTarget
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_HISTORY_LOAD_THRESHOLD
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBottomFadeView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBulletin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentChatTitleView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentDustEffect
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentEdgeGlow
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentHistorySpinner
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMorphClock
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentReactionAnimations
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentScrollToBottomButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSentMessageFlight
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSentMessageSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSkeletonReveal
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSuggestionMorph
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSuggestionRipple
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.attachAgentEdgeGlow
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsDigestPictures
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsSourceLinks
import org.mytonwallet.app_air.uiagent.viewControllers.news.agentNewsDigestMediaViewerItem
import org.mytonwallet.app_air.uiagent.viewControllers.news.agentNewsErrorText
import org.mytonwallet.app_air.uiagent.viewControllers.news.agentNewsMediaViewerItem
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadReadState
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
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
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
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
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadDigestCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

class AgentVC(
    context: Context,
    thread: AgentV2ThreadSummary? = null,
    prompt: AgentPromptChatRequest? = null,
    private val news: AgentNewsChatRequest? = null,
    // The thread's summary comes from the cached list, which may predate an answer
    isSummaryCached: Boolean = false,
    private val onThreadCreated: ((AgentV2ThreadSummary) -> Unit)? = null,
    private val onThreadMissing: ((String) -> Unit)? = null,
    private val digestId: String? = null,
    /** The feed's copy of the digest, whose post the discussion shows until its thread comes */
    private val digestPreview: AgentV2ThreadDigestCard? = null,
    discussionNaming: AgentV2NewsFeedItem.DiscussionNaming? = null,
    shouldDeferCreation: Boolean = false
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    AgentVM.Delegate,
    WalletCore.EventObserver,
    WalletCore.UpdatesObserver,
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
        val SUPPORT_EVENT_CELL = WCell.Type(7)
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
    private val discussionNaming = news?.discussionNaming
        ?: discussionNaming?.takeIf { shouldDeferCreation }
    private val discussionKey = getAgentDeferredDiscussionKey(news, digestId, shouldDeferCreation)

    // A discussion whose first message still waits for its thread opens as it was left
    private val chatOpening = if (prompt != null || news != null || digestId != null) {
        discussionKey?.let(AgentSession.pendingDiscussions::find) ?: AgentChatOpening(
            prompt = prompt,
            news = news,
            digestId = digestId,
            shouldDeferCreation = shouldDeferCreation
        )
    } else {
        null
    }
    private val discussionChat: (AgentVM) -> Unit = ::attachCreatedModel
    private val unreadOpening = AgentUnreadOpening(
        thread,
        hasOpening = chatOpening != null,
        isSummaryCached = isSummaryCached,
        readState = AgentThreadReadState.shared
    )

    private var preparedVM = thread?.let {
        AgentSession.acquire(it, canShowCachedMessages = unreadOpening.canShowCachedMessages)
    } ?: chatOpening?.acquireDiscussion()

    private var unreadDividerMessageId: String? = null
    private val vm: AgentVM get() = checkNotNull(preparedVM)
    private val creationScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var creationJob: Job? = null
    private var isViewActive = false
    private var edgeGlow: AgentEdgeGlow? = null
    private var newsPostArrival: AgentNewsPostArrival? = null
    private val newsFollowupWait by lazy {
        AgentNewsFollowupWait(view::postDelayed, view::removeCallbacks) {
            onHintsUpdated(emptyList())
        }
    }

    // The keyboard's own show or hide animation, which carries the composer frame by frame
    private class KeyboardMotion(val startIme: Int, val startRawIme: Int)

    private var keyboardMotion: KeyboardMotion? = null

    // The field keeps the sides it has without a keyboard while the keyboard the chat came in
    // over goes, as the field it took the place of did
    private var shouldKeepRestingSides = false
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
    private var isAppInForeground = true

    // A recording asked for before the chat went from the screen doesn't start after; the consent sheet covering the
    // chat keeps it
    private val heldDictation = AgentHeldDictation()
    private var readStateThreadId: String? = null

    // Changes only through applyTimeline, which tells the list what changed
    private var timelineItems = listOf<AgentTimelineItem>()

    private var animateFromIndex = -1

    // Debug builds add rows at once while system animations are off, to keep E2E runs fast
    private val canAnimateRows: Boolean
        get() = !DEBUG_MODE || Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ValueAnimator.areAnimatorsEnabled()

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

    // Debug builds show the answer, and pin its question, without the pause while system animations
    // are off, to keep E2E runs fast
    private val incomingMessageDelayMs: Long
        get() = if (!DEBUG_MODE || areSystemAnimatorsEnabled) INCOMING_MESSAGE_DELAY_MS else 0L

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    // What the question being sent came from, its text in the field or the suggestion tapped, for
    // its bubble to grow out of; then, once the chat has added the question, the question's id with
    // it, until its cell takes it
    private var pendingSentSource: AgentSentMessageSource? = null
    private var sentMorphSource: Pair<String, AgentSentMessageSource>? = null

    // A tapped suggestion's morph into its question, started as the chat adds the question and held
    // until its bubble is laid out, with the question's id, until its cell takes it
    private var heldSentMorph: Pair<String, AgentMorphClock>? = null

    // The question this chat opens with, growing out of where it was asked on the screen before
    private var openingMorph: AgentMorphClock? = null

    // The answer this chat opens with, out of the timeline while its question grows into its
    // bubble and the suggestions it was asked among leave
    private var heldOpeningAnswerId: String? = null
    private var openingSuggestionsRipple: AgentSuggestionRipple? = null
    private val releaseOpeningAnswer = Runnable {
        val answerId = heldOpeningAnswerId ?: return@Runnable
        heldOpeningAnswerId = null
        if (!hiddenIncomingMessageIds.contains(answerId)) return@Runnable
        val questionId = findOpeningQuestionId()
        if (questionId == null) {
            hiddenIncomingMessageIds.remove(answerId)
            if (isViewConfigured) rebuildTimeline()
            return@Runnable
        }
        pendingIncomingReveals[questionId] = PendingIncomingReveal(
            questionId,
            incomingMessageId = answerId,
            isOutgoingAnimationFinished = true,
            isDelayElapsed = true
        )
        revealDelayedIncomingMessage(questionId, answerId)
    }
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
            UNREAD_CELL,
            SUPPORT_EVENT_CELL
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

    private val rowGlide by lazy {
        AgentRowGlide(
            chatRecyclerView,
            findRowKey = { position ->
                val items = timelineItems
                if (position in items.indices) timelineRowKey(items, position) else null
            },
            findRow = { key ->
                val items = timelineItems
                items.indices.firstOrNull { timelineRowKey(items, it) == key } ?: -1
            },
            restoreRowsAbove = viewport::restoreRowsAboveChange
        )
    }

    private val bottomGradientView = AgentBottomFadeView(context)
    private val scrollButton = AgentScrollToBottomButton(context).apply {
        setOnClickListener {
            cancelDictation()
            rowGlide.finish()
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
    private val bulletin = AgentBulletin()
    private val messageTextCache = AgentMessageTextCache()
    private var isDissolving = false

    // The dust is on its way over the answer being regenerated, and the chat asks for the new
    // answer once it shows: until then a question would go ahead of the regeneration and take its
    // place, rather than queue behind it
    private var isRegenerationStarting = false
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
            transcribe = { audio ->
                preparedVM?.transcribeAudio(audio)
                    ?: checkNotNull(chatOpening).transcribeAudio(audio)
            },
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
                // The request's own activity pauses the screen, which may cancel the recording before it learns this
                if (!granted && !isDestroyed && !isDisappeared) showMicrophoneDeniedAlert()
                if (continuation.isActive) continuation.resume(granted)
            }
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        if (preparedVM == null) chatOpening?.onBridgeUpdate(update)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AppBackground -> {
                isAppInForeground = false
                setMessageRenderingActive(false)
                dictation.onAppBackground()
            }

            WalletEvent.AppForeground -> {
                isAppInForeground = true
                updateReadStateVisibility()
                if (!isDisappeared) setMessageRenderingActive(true)
                settleThinkingGlow()
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

    private var isConsentSheetShown = false
    private var hasDeclinedConsent = false

    /**
     * A discussion opened before the user allowed the Agent shows its post, its suggestions and the composer, and
     * asks for consent once the user sends, picks a suggestion or dictates there
     */
    private val isAwaitingConsent: Boolean
        get() {
            val model = preparedVM ?: return chatOpening?.let {
                it.isDeferredDiscussion && it.hasConsent != true
            } == true
            return model.currentThread.hasPost &&
                model.hasConsent != true &&
                model.state != AgentVM.State.CONSENT_REQUIRED
        }

    private val discussionConsentGate = createDiscussionConsentGate(
        model = { preparedVM },
        askForConsent = ::askForConsent,
        opening = { chatOpening }
    )

    // Carries out [action], which sends to the Agent, at once, or once the user allows the Agent in the sheet
    private fun withConsent(action: () -> Unit) {
        if (isAwaitingConsent) requestDiscussionConsent(action = action) else action()
    }

    private fun requestDiscussionConsent(onDeclined: () -> Unit = {}, action: () -> Unit) {
        discussionConsentGate.requestDiscussionConsent(
            creationScope,
            opening = { chatOpening?.takeIf { preparedVM == null } },
            onDeclined,
            action
        )
    }

    /**
     * A chat opened before the user allowed the Agent asks for consent in a sheet; without it, the chat closes. A
     * discussion asks as the user sends, picks a suggestion or dictates, carries that out with [onAllowed], and stays
     * open without consent, after [onDeclined].
     */
    private fun askForConsent(onAllowed: () -> Unit = {}, onDeclined: () -> Unit = {}) {
        if (isConsentSheetShown || hasDeclinedConsent || isDeletingChat) return
        isConsentSheetShown = true
        AgentConsentSheetVC.present(
            this,
            onAllowed = {
                isConsentSheetShown = false
                if (preparedVM == null) {
                    if (chatOpening?.isDeferredDiscussion == true) {
                        chatOpening.markConsentAccepted()
                    } else {
                        createChatThread(shouldAcceptConsent = true)
                    }
                } else {
                    vm.acceptConsent()
                }
                onAllowed()
            },
            onDeclined = {
                isConsentSheetShown = false
                if (isAwaitingConsent) return@present onDeclined()
                hasDeclinedConsent = true
                leaveDeclinedChat()
            }
        )
    }

    // Debug builds only: shows UI automation that a run has ended, which nothing else on screen does.
    // It sits at the center, since UI automation does not report a view in the top left corner as displayed.
    private val runIdleMarker: View by lazy {
        View(context).apply {
            id = UIComponentsR.id.agent_run_idle
            contentDescription = "agent_run_idle"
            isGone = true
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
        btn.contentDescription = LocaleController.getString("More")
        btn.setOnMenuClickListener { presentMoreMenu() }
        btn
    }

    // The headset before the "…" button calls a support operator
    private val supportButton: WImageButton by lazy {
        WImageButton(context).apply {
            id = UIComponentsR.id.agent_support_button
            setPaddingDp(8)
            setImageDrawable(context.getDrawableCompat(R.drawable.ic_agent_support_24))
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
            contentDescription = LocaleController.getString("\$agent_support_contact")
            isGone = true
            setOnClickListener { presentSupportRequest(it.id) }
        }
    }

    private val headerButtons: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = View.generateViewId()
            gravity = Gravity.CENTER_VERTICAL
            // The bar keeps trailing views 8 dp in; the design's dots box ends 12 dp from the edge
            translationX = MORE_BUTTON_SHIFT.dp * LocaleController.rtlMultiplier
            addView(supportButton, LinearLayout.LayoutParams(40.dp, 40.dp))
            addView(moreButton, LinearLayout.LayoutParams(40.dp, 40.dp))
        }
    }

    override fun setupViews() {
        super.setupViews()

        updateChatTitle()
        setupNavBar(true)
        navigationBar?.addTrailingView(
            headerButtons,
            ConstraintLayout.LayoutParams(WRAP_CONTENT, 40.dp)
        )
        navigationBar?.setCenteredTitleView(chatTitleView, animated = false)

        composerView.onSend = { text ->
            val messageId = editingMessageId
            if (isAwaitingConsent) {
                // The draft stays while the sheet asks, and goes once the user allows the Agent. Closing the sheet
                // gives the keyboard back to a question sent from it.
                val isFromKeyboard = window?.let(::isAgentKeyboardShown) == true
                requestDiscussionConsent(
                    onDeclined = { if (isFromKeyboard) composerView.focusInputWithKeyboard() }
                ) {
                    if (sendMessage(text)) composerView.setDraftText("", focusInput = false)
                }
                false
            } else if (messageId == null) {
                pendingSentSource = composerView.makeSentTextSource()
                val ripple = rippleInitialHintsAway()
                sendMessage(text).also { isSent ->
                    pendingSentSource = null
                    if (!isSent) ripple?.cancel()
                }
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
        composerView.onStop = { preparedVM?.stopAnswer() }
        // The button keeps to the field's trailing edge
        composerView.onSideInsetChanged = { inset ->
            val shift = (AGENT_SCROLL_BUTTON_END.dp - inset).toFloat()
            scrollButton.translationX = if (LocaleController.isRTL) -shift else shift
        }
        composerView.bindDictation(dictation)
        composerView.shouldHoldDictation = holdDictationForConsent(
            isAwaitingConsent = { isAwaitingConsent },
            heldDictation = heldDictation,
            askForConsent = { onAllowed, onDeclined ->
                requestDiscussionConsent(onDeclined, onAllowed)
            },
            startDictation = { dictation.startHandsFree() }
        )
        composerView.onRecordingCircleVisibilityChanged = { isShown ->
            isRecordingCircleShown = isShown
            updateScrollButton(isAnimated = true)
        }
        WalletCore.registerObserver(this)
        if (chatOpening?.isDeferredDiscussion == true) {
            WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        }
        composerView.onHeightChanged = {
            updateLayout()
        }

        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        // Earlier versions report the keyboard only where it ends up
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            ViewCompat.setWindowInsetsAnimationCallback(contentContainer, keyboardAnimationCallback)
        }
        if (DEBUG_MODE) {
            view.addView(
                runIdleMarker,
                ConstraintLayout.LayoutParams(1.dp, 1.dp).apply {
                    topToTop = ConstraintLayout.LayoutParams.PARENT_ID
                    bottomToBottom = ConstraintLayout.LayoutParams.PARENT_ID
                    startToStart = ConstraintLayout.LayoutParams.PARENT_ID
                    endToEnd = ConstraintLayout.LayoutParams.PARENT_ID
                }
            )
        }
        scrollButtonGlass = WGlassView.attachTo(
            scrollButton,
            AgentScrollToBottomButton.SIZE.dp / 2f,
            GlassProviders.composer(WColor.SearchFieldBackground),
            chatRecyclerView
        )
        scrollButtonBinding = AgentPreDrawBinding(chatRecyclerView, scrollButtonUpdater)
        chatRecyclerView.addOnItemTouchListener(keyboardDismissal)

        composerView.post { updateGradientHeight(animated = false) }
        edgeGlow = attachAgentEdgeGlow(
            host = view,
            headerContent = navigationBar,
            pane = contentContainer,
            under = composerView,
            // The header's rounded corners hang below it, over the chat, and the glow goes over them
            headerBottom = { max(agentHeaderBottom(), topReversedCornerView?.bottom ?: 0) }
        )

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
        val opening = checkNotNull(chatOpening)
        opening.onChange = ::renderChatOpening
        renderChatOpening()
        creationScope.launch {
            opening.readConsent()
            updateHeaderButtons()
        }
        // A creation that failed after the chat was left waits for Retry
        if (opening.error == null) createChatThread()
    }

    private fun attachToSession() {
        showSkeletonIfLoading()
        updateSupportPresentation()
        vm.attach(this)
        isAttachedToSession = true
        if (isViewActive) vm.setActive(this, true)
        updateReadStateVisibility()
        onThreadCreated?.invoke(vm.currentThread)
    }

    private fun updateReadStateVisibility() {
        val isShown = hasAppeared && !isSessionReleased && !unreadOpening.isAwaitingLoadedThread
        val threadId = preparedVM?.currentThread?.id?.takeIf { isShown }
        if (readStateThreadId != threadId) {
            readStateThreadId?.let {
                AgentThreadReadState.shared.onChatDisappeared(it, preparedVM?.seenMessageCount)
            }
            readStateThreadId = threadId
            threadId?.let(AgentThreadReadState.shared::onChatAppeared)
        }
        markVisibleSupportSeen()
    }

    // While support has the chat, the header and the composer tell so, and the list scrolls as a messenger does
    private fun updateSupportPresentation() {
        val model = preparedVM
        val isChatWithSupport = model?.isChatWithSupport == true
        chatTitleView.setSubtitle(model?.supportState?.let(::getAgentSupportSubtitle))
        composerView.placeholder = getAgentComposerPlaceholder(isChatWithSupport)
        viewport.setLiveTailDisabled(isChatWithSupport)
    }

    private fun markVisibleSupportSeen() {
        val model = preparedVM ?: return
        if (!isAppInForeground || readStateThreadId != model.currentThread.id) return
        AgentThreadReadState.shared.markSupportSeen(
            model.currentThread.id,
            model.loadedOperatorMessageAt
        )
    }

    private fun createChatThread(shouldAcceptConsent: Boolean = false) {
        val opening = chatOpening ?: return
        if (isDeletingChat || preparedVM != null || creationJob != null) return
        if (discussionKey != null && opening.hasStagedMessage) {
            AgentSession.pendingDiscussions.create(
                discussionKey,
                opening,
                discussionChat,
                onThreadCreated,
                shouldAcceptConsent
            )
            return
        }
        creationJob = creationScope.launch {
            try {
                val thread = opening.create(shouldAcceptConsent) ?: return@launch
                currentCoroutineContext().ensureActive()
                if (isDeletingChat) return@launch
                attachCreatedModel(
                    if (opening.messages.isNotEmpty()) {
                        AgentSession.acquireOpening(
                            thread,
                            opening.messages,
                            opening.entryPoint,
                            opening.followupText,
                            opening.messageAuthority
                        )
                    } else {
                        AgentSession.acquire(thread)
                    }
                )
            } finally {
                creationJob = null
                renderChatOpening()
            }
        }
    }

    private fun attachCreatedModel(model: AgentVM) {
        preparedVM = model
        attachToSession()
        chatOpening?.releaseHeldReports { comment, onResult ->
            model.reportProblem(null, comment, onResult)
        }
    }

    private fun openingErrorText(error: Throwable): String =
        if (news != null || chatOpening?.isDeferredDiscussion == true) {
            agentNewsErrorText(error)
        } else {
            agentUnavailableText()
        }

    private fun renderChatOpening() {
        val opening = chatOpening ?: return
        if (isDeletingChat || preparedVM != null || isSessionReleased) return
        if (opening.isConsentRequired && !opening.isCreating) askForConsent()
        updateComposerSubmission()
        onMessagesLoaded(displayMessages)
        updateVisibleHintsAvailability()
        updateHeaderButtons()
        updateOpeningSkeleton(opening)
    }

    /**
     * A discussion opened without the feed's copy of its post, as from a digest's headline, holds the post's place with
     * placeholder bubbles until the post comes; a failed opening shows its failure instead
     */
    private fun updateOpeningSkeleton(opening: AgentChatOpening) {
        val isDiscussion = news != null || digestId != null
        val hasPost = buildTimelineItems(displayMessages).isNotEmpty()
        when {
            !isDiscussion || hasPost || opening.error != null || opening.isConsentRequired -> {
                if (skeletonReveal.isShown) hideSkeleton()
            }

            !skeletonReveal.isShown -> {
                skeletonReveal.show()
                updateBlurViews(chatRecyclerView)
            }
        }
    }

    override val headerHandoffContent: List<View>
        get() = listOf(chatTitleView, supportButton, moreButton)

    override fun viewWillAppear() {
        super.viewWillAppear()
        AgentHeaderHandoff.begin(this)
        updateChatTitle()
        isViewActive = true
        settleThinkingGlow()
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
        if (!isConsentSheetShown) heldDictation.drop()
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
     * Where the question this chat opens with was asked on the screen before, the chat list's field
     * or suggestion, in the window: its bubble grows out of [source] as the chat comes in, over
     * [host], the window's root, which shows both screens. The field's text goes in Telegram's
     * send transition, as the chat's field fades in empty, and the suggestion in its morph, each
     * lasting at least as long as the chat's transition of [transitionMs], and each holding where
     * it was asked until the chat lays the bubble out. The answer comes in as soon as the question
     * has landed and [suggestionsRipple], that of the suggestions it was asked among, has ended.
     */
    internal fun setOpeningSentSource(
        source: AgentSentMessageSource,
        transitionMs: Long,
        host: ViewGroup,
        suggestionsRipple: AgentSuggestionRipple?
    ) {
        openingMorph?.cancel()
        val morph = when (source.kind) {
            is AgentSentMessageSource.Kind.Text -> AgentSentMessageFlight.start(
                host,
                ::findOpeningQuestionCell,
                source,
                transitionMs = transitionMs,
                onEnd = ::finishOpeningMorph
            )?.also { composerView.fadeInFieldText(it.durationMs) }

            is AgentSentMessageSource.Kind.Suggestion -> AgentSuggestionMorph.start(
                host,
                ::findOpeningQuestionCell,
                source,
                transitionMs,
                ::finishOpeningMorph
            )
        }
        openingMorph = morph?.takeUnless { it.isFinished }
        if (openingMorph == null) return
        heldOpeningAnswerId = chatOpening?.messages
            ?.lastOrNull { it.role == AgentMessageRole.ASSISTANT }?.id
            ?.also(hiddenIncomingMessageIds::add)
        openingSuggestionsRipple = suggestionsRipple
        suggestionsRipple?.doOnEnd(::releaseOpeningAnswerOnceReady)
    }

    private fun finishOpeningMorph() {
        openingMorph = null
        releaseOpeningAnswerOnceReady()
    }

    // The answer comes in as soon as its question has landed and the suggestions have gone, with
    // no pause after
    private fun releaseOpeningAnswerOnceReady() {
        if (heldOpeningAnswerId == null || openingMorph != null) return
        if (openingSuggestionsRipple?.isFinished == false) return
        openingSuggestionsRipple = null
        chatRecyclerView.removeCallbacks(releaseOpeningAnswer)
        chatRecyclerView.post(releaseOpeningAnswer)
    }

    /**
     * Comes in where the screen it continues was, without a transition of its own: the header's
     * title and menu and the timeline fade in over [durationMs] as that screen's go, and the
     * field, which takes the place of that screen's, keeps its resting sides as the keyboard goes
     */
    internal fun takePlaceOfPreviousScreen(durationMs: Long) {
        if (!isViewConfigured) return
        shouldKeepRestingSides = true
        updateLayout()
        if (!WGlobalStorage.getAreAnimationsActive()) return
        (headerHandoffContent + chatRecyclerView).forEach { part ->
            part.animate().cancel()
            part.alpha = 0f
            part.animate().alpha(1f).setDuration(durationMs)
                .setInterpolator(LinearInterpolator()).start()
        }
    }

    // The bubble of the question the chat opens with, once the chat shows it
    private fun findOpeningQuestionCell(): AgentMessageCell? =
        findOpeningQuestionId()?.let(::findMessageCell)

    // The question the chat opens with, its first
    private fun findOpeningQuestionId(): String? = timelineItems.firstNotNullOfOrNull { item ->
        val message = (item as? AgentTimelineItem.Message)?.message
        message?.id?.takeIf { message.role == AgentMessageRole.USER }
    }

    private fun findMessageCell(messageId: String): AgentMessageCell? {
        val position = viewport.timelineIndexOf(messageId).takeIf { it >= 0 } ?: return null
        val holder = chatRecyclerView.findViewHolderForAdapterPosition(position) as? WCell.Holder
        return (holder?.cell as? AgentMessageCell)?.takeIf { it.messageId == messageId }
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
        newsFollowupWait.cancel()
        isViewActive = false
        menuAfterKeyboard = null
        setComposerHandoff(null)
        chatRecyclerView.removeCallbacks(openMenuAfterKeyboardRunnable)
        newsPostArrival?.cancel()
        heldOpeningAnswerId = null
        openingMorph?.cancel()
        chatRecyclerView.removeCallbacks(releaseOpeningAnswer)
        heldSentMorph?.second?.cancel()
        dustEffect?.kill()
        dustEffect = null
        bulletin.dismiss()
        if (isViewConfigured) ViewCompat.setWindowInsetsAnimationCallback(contentContainer, null)
        keyboardMotion = null
        edgeGlow?.detach()
        edgeGlow = null
        streamRenderer.setActive(false)
        streamRenderer.clear()
        cancelDictation()
        dictationScope.cancel()
        // A discussion reopened before this chat went renders its opening
        if (chatOpening?.onChange == ::renderChatOpening) chatOpening.onChange = null
        discussionKey?.let { AgentSession.pendingDiscussions.leave(it, discussionChat) }
        creationScope.cancel()
        WalletCore.unregisterObserver(this)
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
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
        rowGlide.finish()
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
        chatTitleView.updateTheme()
        scrollButton.updateTheme()
        scrollButtonGlass?.updateTheme()
        messagesSkeleton.updateTheme()
        loadErrorView.updateTheme()
    }

    private fun updateScrollButton(isAnimated: Boolean) {
        val shouldShow = !contentContainer.isGone && !isPopupVisible && !isRecordingCircleShown &&
            isLatestRowOutOfSight()
        scrollButton.setShown(shouldShow, isAnimated && hasAppeared)
    }

    private fun isLatestRowOutOfSight(): Boolean =
        isAgentLatestRowOutOfSight(viewport.measureLatestRowOverhang(), SCROLL_BUTTON_THRESHOLD.dp)

    override fun insetsUpdated() {
        super.insetsUpdated()
        // Margins keep the column's color out from under the side panel
        val start = additionalTabletPadding + systemBarStartInset
        contentContainer.updateLayoutParams<ViewGroup.MarginLayoutParams> {
            leftMargin = if (LocaleController.isRTL) systemBarEndInset else start
            rightMargin = if (LocaleController.isRTL) start else systemBarEndInset
        }
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

    // The chat's header keeps its own background at every scroll position, the chat's very top included
    override fun updateBlurViews(recyclerView: RecyclerView) {
        topReversedCornerView?.setBlurAlpha(1f)
    }

    private fun syncTopBlurAfterLayout() {
        updateBlurViews(chatRecyclerView)
    }

    private fun chatTopPadding(): Int = agentHeaderBottom() + AGENT_LIST_TOP_INSET.dp

    private fun updateLayout() {
        val ime = navigationController?.imeInsetBottom ?: 0
        val navigationBarInset = navigationController?.getSystemBars()?.bottom ?: 0
        val isFollowingKeyboard = keyboardMotion != null
        val bottom = computeComposerBottom(ime, navigationBarInset)
        viewport.updateLayout(bottom, ime, navigationBarInset, isFollowingKeyboard)
        if (ime <= 0 && !isFollowingKeyboard) shouldKeepRestingSides = false
        composerView.setKeyboardShown(ime > 0 && !shouldKeepRestingSides, isFollowingKeyboard)
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
        if (!shouldKeepRestingSides && (motion.startIme > 0) != (endIme > 0)) {
            composerView.followKeyboard(if (endIme > 0) fraction else 1f - fraction)
        }
    }

    private fun finishKeyboardMotion() {
        if (keyboardMotion == null) return
        keyboardMotion = null
        viewport.finishKeyboardMotion()
        val isKeyboardUp = (navigationController?.imeInsetBottom ?: 0) > 0
        composerView.followKeyboard(if (isKeyboardUp && !shouldKeepRestingSides) 1f else 0f)
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
        val model = preparedVM ?: return sendFirstDiscussionMessage(text)
        if (!agentNewsAllowsSubmission(news, model.state) || isReplacementStarting) return false
        val accepted = model.sendMessage(text, entryPoint)
        if (accepted) view.hideKeyboard()
        return accepted
    }

    private fun sendFirstDiscussionMessage(text: String, isFollowup: Boolean = false): Boolean {
        val opening = chatOpening ?: return false
        if (!opening.stageDiscussionMessage(text, isFollowup)) return false
        view.hideKeyboard()
        createChatThread()
        return true
    }

    /**
     * Sends the question of [card], one of [hints], with [send], which tells whether the chat took
     * it: the card turns into its question as the suggestions beside it ripple away
     */
    private fun sendSuggestion(card: WAgentHintView, hints: AgentHintsCell, send: () -> Boolean) {
        hints.finishReveal()
        val source = AgentSentMessageSource.makeSuggestion(card)
        val ripple = source?.let { AgentSuggestionRipple.start(hints.contentViews, card, view) }
        pendingSentSource = source
        val isSent = send()
        pendingSentSource = null
        if (isSent) view.hideKeyboard() else ripple?.cancel()
    }

    /**
     * The question the chat has just added turns into its bubble out of what it came from, wherever
     * the bubble lands: a tapped suggestion in the morph that took its place at the tap, or the
     * field's text in Telegram's send transition, as the emptied field fades back in
     */
    private fun startSentMorph(cell: AgentMessageCell, onEnd: () -> Unit): AgentMorphClock? {
        heldSentMorph?.takeIf { it.first == cell.messageId }?.let { (_, morph) ->
            heldSentMorph = null
            morph.doOnEnd(onEnd)
            return morph.takeUnless { it.isFinished }
        }
        val (messageId, source) = sentMorphSource ?: return null
        sentMorphSource = null
        if (cell.messageId != messageId || !source.isFresh) return null
        return AgentSentMessageFlight.start(
            view,
            { cell },
            source,
            clipTop = agentHeaderBottom().toFloat(),
            onEnd = onEnd
        )?.also { composerView.fadeInFieldText(it.durationMs) }
    }

    /**
     * The empty chat's suggestions, its spinning top included, ripple away from the field as its
     * first question goes, as a tapped suggestion's neighbours do
     */
    private fun rippleInitialHintsAway(): AgentSuggestionRipple? {
        if (!WGlobalStorage.getAreAnimationsActive() ||
            timelineItems.any { it is AgentTimelineItem.Message }
        ) {
            return null
        }
        val index = timelineItems.indexOfLast {
            it is AgentTimelineItem.Hints && it.followupMessageId == null && !it.isLoading
        }
        if (index < 0) return null
        val holder = chatRecyclerView.findViewHolderForAdapterPosition(index) as? WCell.Holder
        val hints = holder?.cell as? AgentHintsCell ?: return null
        hints.finishReveal()
        return AgentSuggestionRipple.start(hints.contentViews, composerView, view)
    }

    // Nothing goes before the chat asks for an edit's or a regeneration's answer, which waits for
    // the rows it replaces to fade or turn to dust; the keyboard's send key skips the dimmed
    // composer
    private val isReplacementStarting: Boolean
        get() = isRegenerationStarting || editFadeAnimator != null

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

        if (canReportProblem) {
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

    // A discussion the user hasn't written in, before consent or after it, is left out of the chat list and has
    // nothing to delete
    private val canDeleteChat: Boolean
        get() {
            if (isDeletingChat) return false
            val model = preparedVM ?: return chatOpening != null && news == null && digestId == null
            return model.isThreadStarted
        }

    // The conversation can be reported from the start: while its thread is being created, the report waits for it
    private val canReportProblem: Boolean
        get() = preparedVM?.canReportProblem ?: (chatOpening?.canReportProblem == true)

    private val isSupportRequestVisible: Boolean
        get() = !isDeletingChat &&
            (preparedVM?.isSupportRequestVisible ?: (chatOpening?.isSupportRequestVisible == true))

    private val canRequestSupport: Boolean
        get() = !isDeletingChat &&
            (preparedVM?.canRequestSupport ?: (chatOpening?.canRequestSupport == true))

    // A menu without items shows no button
    private fun updateHeaderButtons() {
        val model = preparedVM
        val hasItems = agentState == AgentVM.State.ERROR || canReportProblem || canDeleteChat
        moreButton.isGone = (model == null && chatOpening == null) || !hasItems
        supportButton.isGone = !isSupportRequestVisible
        val isSupportEnabled = canRequestSupport
        supportButton.isEnabled = isSupportEnabled
        supportButton.imageAlpha =
            if (isSupportEnabled) 255 else (DISABLED_BUTTON_ALPHA * 255).roundToInt()
    }

    /**
     * Asks before the chat goes to a support operator from the entry point [entryPointId]; Call sends nothing once
     * support can no longer be called
     */
    private fun presentSupportRequest(entryPointId: Int) {
        val source = getAgentSupportRequestSource(entryPointId)
        val model = preparedVM
        if (model == null) {
            val opening = chatOpening ?: return
            if (source != AgentV2SupportRequestSource.HEADER || !canRequestSupport) return
            cancelDictation()
            AgentSupportRequestConfirmation(hasConsent = opening.hasConsent == true) {
                if (isDeletingChat || preparedVM != null || chatOpening !== opening) {
                    return@AgentSupportRequestConfirmation
                }
                if (opening.stageSupportRequest()) createChatThread()
            }.present(this)
            return
        }
        val canRequest = if (source == AgentV2SupportRequestSource.STARTER_HINT) {
            model.canRequestSupportFromStarterHint
        } else {
            canRequestSupport
        }
        if (!canRequest || isDeletingChat) return
        cancelDictation()
        AgentSupportRequestConfirmation(hasConsent = model.hasConsent == true) {
            if (preparedVM !== model || isDeletingChat) return@AgentSupportRequestConfirmation
            if (source == AgentV2SupportRequestSource.STARTER_HINT) {
                model.requestSupportFromStarterHint(::openSupportChat)
            } else {
                model.requestSupport(source)
            }
        }.present(this)
    }

    // Contact Support in an empty chat opens the chat support already has
    private fun openSupportChat(thread: AgentV2ThreadSummary) {
        if (isDestroyed || isDeletingChat) return
        navigationController?.push(AgentVC(context, thread))
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
        preparedVM?.let { AgentSession.deleteChat(it, onFailure) } ?: chatOpening?.let { opening ->
            discussionKey?.let { AgentSession.pendingDiscussions.drop(it, opening) }
            opening.deleteChat(onFailure)
        }
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
                        reportProblem(presentationId, comment) { isSent ->
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

    private fun reportProblem(
        presentationId: String?,
        comment: String,
        onResult: (Boolean) -> Unit
    ) {
        preparedVM?.let { return it.reportProblem(presentationId, comment, onResult) }
        val opening = chatOpening
        if (presentationId != null || opening == null) return onResult(false)
        opening.reportProblem(comment, onResult)
    }

    private fun showProblemReportResult(presentationId: String?, comment: String, isSent: Boolean) {
        // A failed report opens again with its comment, unless the user has left the screen or can no longer report
        if (!isSent && canReportProblem && !isDestroyed && !isDisappeared) {
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
        reloadLastFailureRowIfRetryChanged()
        updateSupportPresentation()
        updateHeaderButtons()
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
        val headline = news?.headline
            ?: digestPreview?.takeIf { chatOpening?.isDeferredDiscussion == true }
                ?.let { LocaleController.getString("\$agent_digest_title") }
        val title = if (thread == null && chatOpening?.isDeferredDiscussion == true &&
            discussionNaming != null
        ) {
            discussionNaming.title
        } else if (!headline.isNullOrBlank() &&
            thread?.title.isNullOrBlank()
        ) {
            headline
        } else {
            thread?.let { resolveAgentThreadTitle(it, firstMessage) } ?: firstMessage.orEmpty()
        }
        val icon = (if (thread != null) thread.icon else discussionNaming?.icon ?: news?.icon)
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
                onThreadMissing?.invoke(model.currentThread.id)
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
        if (state == AgentVM.State.CONSENT_REQUIRED) askForConsent()
        if (DEBUG_MODE) {
            runIdleMarker.isGone = state != AgentVM.State.READY && state != AgentVM.State.ERROR
        }
        updateComposerSubmission()
        updateHeaderButtons()
    }

    override fun onProblemReportAvailabilityChanged() = updateHeaderButtons()

    override fun onMessagesRefreshed(messages: List<AgentMessage>) {
        updateSupportPresentation()
        resolveUnreadDivider()
        updateReadStateVisibility()
        val items = buildTimelineItems(messages)
        val hasChanged = items != timelineItems
        val arrivingDividerIndex = items.findArrivingUnreadDividerIndex(timelineItems)
        val isAtEnd = viewport.isAtEnd
        applyTimeline(items, TimelineUpdate.DIFF)
        // Replies that came while the chat was away show from the first unread one, as when the chat opens at it
        when {
            arrivingDividerIndex != null -> viewport.showItemAtTop(arrivingDividerIndex)
            hasChanged -> viewport.followNewMessages(isAtEnd)
        }
        markVisibleSupportSeen()
    }

    override fun onMessagesLoaded(messages: List<AgentMessage>) {
        updateSupportPresentation()
        updateLoadError()
        updateThinkingGlow()
        scheduleChatTitleUpdate()
        updateHeaderButtons()
        val opensAtUnreadDivider = resolveUnreadDivider()
        updateReadStateVisibility()
        val items = buildTimelineItems(messages)
        if (updateOpeningTimelineInPlace(items)) {
            markVisibleSupportSeen()
            return
        }
        // A news post's suggestions that come with its loaded messages appear as an answer's do
        val followups = (items.lastOrNull() as? AgentTimelineItem.Hints)?.followupMessageId
        if (followups != null && timelineItems.lastOrNull() !is AgentTimelineItem.Hints &&
            updateOpeningTimelineInPlace(items.dropLast(1))
        ) {
            appendHintsAfterContentSettles(followups)
            markVisibleSupportSeen()
            return
        }
        editFadeAnimator?.cancel()
        regeneratingMessageId = null
        editPresentation = null
        animateFromIndex = -1
        rowGlide.finish()
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
        markVisibleSupportSeen()
    }

    private fun resolveUnreadDivider(): Boolean {
        val model = preparedVM ?: return false
        val seen = unreadOpening.resolveSeenMessageCount(model) ?: return false
        unreadDividerMessageId = model.findFirstUnseenMessageId(seen)
        return unreadDividerMessageId != null
    }

    // A News post's suggestions list once the chat is ready, so its placeholder stays until then
    private fun awaitsNewsPostFollowups(messages: List<AgentMessage>): Boolean {
        val owner = messages.findFollowupOwner() ?: return false
        return owner.newsPost && owner.followups.isNotEmpty() &&
            preparedVM?.state == AgentVM.State.LOADING
    }

    private fun updateOpeningTimelineInPlace(items: List<AgentTimelineItem>): Boolean {
        if (chatOpening == null && preparedVM?.currentThread?.hasPost != true &&
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
        if (update != TimelineUpdate.RELOAD) glideWaitingRows(items)
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
        updateFollowupTails(previous, items)
        return update == TimelineUpdate.IN_PLACE && isRefreshedOnCell
    }

    /**
     * The questions that wait glide to their places as rows above them come, go or change on the
     * way to [items], as a stopped or finished answer's, or the next answer's typing row; the rows
     * above stay. Called before the timeline takes [items].
     */
    private fun glideWaitingRows(items: List<AgentTimelineItem>) {
        val model = preparedVM ?: return
        if (!streamRenderer.isActive || chatRecyclerView.isLayoutSuppressed ||
            viewport.isScrollingToLatest
        ) {
            return
        }
        val glideStart = agentWaitingRowsGlideStart(timelineItems, items, model::isMessageQueued)
        if (glideStart >= 0) rowGlide.start(glideStart)
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

    /** The row of [messageId] in [items], when it is the one row [previous] lacks, or -1 */
    private fun findTimelineInsertion(
        previous: List<AgentTimelineItem>,
        items: List<AgentTimelineItem>,
        messageId: String
    ): Int {
        if (items.size != previous.size + 1) return -1
        val index = items.indexOfFirst {
            it is AgentTimelineItem.Message && it.message.id == messageId
        }
        if (index < 0 || items.subList(0, index) != previous.subList(0, index)) return -1
        return index.takeIf { items.subList(index + 1, items.size) == previous.drop(index) } ?: -1
    }

    // A question queued behind a regeneration stays in sight below the answer the dust hides
    private fun isQueuedTimelineRow(index: Int): Boolean {
        val messageId = timelineRowKey(timelineItems, index).second ?: return false
        return preparedVM?.isMessageQueued(messageId) == true
    }

    // The message that suggestions come under or leave loses or regains its tail
    private fun updateFollowupTails(
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
            if (index >= 0) updateFollowupTail(index)
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
        isRegenerationStarting = true
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
                isRegenerationStarting = false
                if (isViewConfigured && !isDestroyed) {
                    regeneratingMessageId = messageId
                    rows.forEach { it.visibility = View.INVISIBLE }
                    beforeRegenerating()
                    if (!vm.regenerateMessage(messageId)) {
                        regeneratingMessageId = null
                        rows.forEach { it.visibility = View.VISIBLE }
                    }
                    // From now on a question queues behind the new answer, or goes without one
                    updateComposerSubmission()
                }
            },
            onDone = {
                isDissolving = false
                isRegenerationStarting = false
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
        val sentSource = pendingSentSource.takeIf { message.role == AgentMessageRole.USER }
        pendingSentSource = null
        updateSupportPresentation()
        updateLoadError()
        updateHeaderButtons()
        updateThinkingGlow()
        if (message.role == AgentMessageRole.USER &&
            displayMessages.firstOrNull { it.role == AgentMessageRole.USER }?.id == message.id
        ) {
            scheduleChatTitleUpdate()
        }
        if (message.role == AgentMessageRole.ASSISTANT) regeneratingMessageId = null
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
        // The empty chat's first question takes the place of its suggestions, which left as it
        // went: their row goes at once, and the question pins under the header at once
        val isFirstQuestion = message.role == AgentMessageRole.USER && !isEditInsertion &&
            oldItems.none { it is AgentTimelineItem.Message }
        var shouldStartOffscreenPin = false
        val isSentToEnd = message.role == AgentMessageRole.USER &&
            getAgentSentQuestionPlacement(viewport.isLiveTailDisabled) ==
            AgentSentQuestionPlacement.END
        val isAtEnd = viewport.isAtEnd
        if (message.role == AgentMessageRole.USER) {
            val source = sentSource?.takeIf { !isEditInsertion }
            sentMorphSource = source?.takeIf { it.kind is AgentSentMessageSource.Kind.Text }
                ?.let { message.id to it }
            // A tapped suggestion turns into its question at once, holding until its bubble is
            // laid out
            heldSentMorph?.second?.cancel()
            heldSentMorph = source?.takeIf { it.kind is AgentSentMessageSource.Kind.Suggestion }
                ?.let { AgentSuggestionMorph.start(view, { findMessageCell(message.id) }, it) }
                ?.let { message.id to it }
            pendingIncomingReveals[message.id] = PendingIncomingReveal(message.id)
            outgoingMessageIdsAwaitingIncoming.add(message.id)
            if (isSentToEnd) {
                viewport.prepareMessageAtEnd()
            } else {
                shouldStartOffscreenPin = viewport.prepareOutgoingMessage(
                    message.id,
                    oldItems,
                    forcePin = isEditInsertion,
                    isInstant = isFirstQuestion
                )
            }
        } else if (message.role == AgentMessageRole.ASSISTANT) {
            // An answer comes for a question that has gone, never for one still queued, as one
            // queued behind a regeneration whose answer this is
            val outgoingMessageId = outgoingMessageIdsAwaitingIncoming
                .firstOrNull { preparedVM?.isMessageQueued(it) != true }
                ?.also { outgoingMessageIdsAwaitingIncoming.remove(it) }
            val pendingReveal = outgoingMessageId?.let { pendingIncomingReveals[it] }
            if (outgoingMessageId != null && pendingReveal != null) {
                pendingReveal.incomingMessageId = message.id
                hiddenIncomingMessageIds.add(message.id)
                schedulePendingIncomingReveal(pendingReveal)
                return
            }
        }
        if (animateFromIndex < 0) {
            animateFromIndex = if (isFirstQuestion) 0 else oldItems.size
            chatRecyclerView.doOnNextLayout {
                animateFromIndex = -1
            }
        }
        // Visible trailing hints keep their place and collapse animated while the new
        // messages are appended after them.
        val trailingHints = (oldItems.lastOrNull() as? AgentTimelineItem.Hints)
            ?.takeUnless { isFirstQuestion }
        var dismissalCell: AgentHintsCell? = null
        if (trailingHints != null && dismissingHints == null) {
            dismissingHints = trailingHints
            dismissingHintsAnchorId = (
                oldItems.getOrNull(oldItems.size - 2)
                    as? AgentTimelineItem.Message
                )?.message?.id
            val holder = chatRecyclerView.findViewHolderForAdapterPosition(oldItems.size - 1)
            dismissalCell = (holder as? WCell.Holder)?.cell as? AgentHintsCell
        }
        val newItems = buildTimelineItems(displayMessages)
        val isAppended =
            newItems.size > oldItems.size && newItems.subList(0, oldItems.size) == oldItems
        // A message that comes above others, as an answer above the questions queued after it,
        // comes in at its place, and the rows below it move down without coming in again
        val insertedAt = if (isAppended || trailingHints != null) {
            -1
        } else {
            findTimelineInsertion(oldItems, newItems, message.id)
        }
        if (insertedAt >= 0 && animateFromIndex == oldItems.size) animateFromIndex = insertedAt
        val isDiff = isAppended || isFirstQuestion || insertedAt >= 0
        if (!isDiff) glideWaitingRows(newItems)
        applyTimeline(newItems, if (isDiff) TimelineUpdate.DIFF else TimelineUpdate.RELOAD)
        if (trailingHints != null && dismissingHints === trailingHints) {
            if (dismissalCell != null) {
                dismissalCell.collapse { finishHintsDismissal() }
            } else {
                finishHintsDismissal()
            }
        }
        when {
            isSentToEnd -> {
                viewport.scrollToBottom()
                chatRecyclerView.doOnNextLayout {
                    chatRecyclerView.post {
                        val pendingReveal = pendingIncomingReveals[message.id]
                        val messageIndex = viewport.timelineIndexOf(message.id)
                        if (pendingReveal?.isOutgoingAnimationFinished == false &&
                            chatRecyclerView.findViewHolderForAdapterPosition(messageIndex) == null
                        ) {
                            onOutgoingInsertAnimationFinished(message.id)
                        }
                    }
                }
            }

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

            viewport.isLiveTailDisabled -> viewport.followNewMessages(isAtEnd)

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
        updateHeaderButtons()
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

            oldItems != newItems -> {
                glideWaitingRows(newItems)
                applyTimeline(newItems, TimelineUpdate.RELOAD)
            }
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
        edgeGlow?.setGlowing(isViewActive && isThinking)
    }

    /**
     * As the chat comes back, from another screen or the background, the glow goes on while the Agent still thinks,
     * and one it no longer needs goes at once rather than fading out
     */
    private fun settleThinkingGlow() {
        val glow = edgeGlow ?: return
        if (isThinking) {
            updateThinkingGlow()
        } else {
            glow.hideAtOnce()
        }
    }

    private val isThinking: Boolean
        get() {
            val answer = displayMessages.lastOrNull { it.role == AgentMessageRole.ASSISTANT }
            return answer != null && answer.isStreaming && !answer.hasText
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
        val item = timelineItems.getOrNull(chatRecyclerView.getChildAdapterPosition(cell))
            as? AgentTimelineItem.Hints ?: return
        cell.setCardsEnabled(canSendHints(item))
        cell.isSupportHintEnabled = preparedVM?.canRequestSupportFromStarterHint == true
    }

    private fun canSendHints(item: AgentTimelineItem.Hints): Boolean =
        item.followupMessageId == null || preparedVM?.canSendFollowup == true ||
            chatOpening?.canSubmitDiscussionMessage == true

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
        val index = viewport.timelineIndexOf(messageId)
        if (index < 0) return
        if (!pendingIncomingReveals.containsKey(messageId)) trackAnswerReveal(messageId)
        if (index == viewport.pinnedMessageId?.let(viewport::timelineIndexOf)) return
        // Decided as the question goes: while the scroll-to-bottom button shows, the list stays
        viewport.placeGoingQuestion(messageId, shouldPin = !isLatestRowOutOfSight())
    }

    // A question queued before the chat opened, or again by Retry, waits for its answer's row as
    // one queued here does, ahead of the questions queued here that still wait
    private fun trackAnswerReveal(questionId: String) {
        val waitingReveals = pendingIncomingReveals.filterKeys {
            preparedVM?.isMessageQueued(it) == true
        }
        pendingIncomingReveals.keys.removeAll(waitingReveals.keys)
        pendingIncomingReveals[questionId] = PendingIncomingReveal(
            outgoingMessageId = questionId,
            isOutgoingAnimationFinished = true
        )
        pendingIncomingReveals.putAll(waitingReveals)
        outgoingMessageIdsAwaitingIncoming.add(questionId)
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
        chatRecyclerView.postDelayed(reveal, incomingMessageDelayMs)
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
            glideWaitingRows(newItems)
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
        // The answer the chat opens with stays out until its question has landed
        heldOpeningAnswerId?.let(hiddenIncomingMessageIds::add)
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

    // A message that suggestions hang from, right under it, has no tail
    private fun hasFollowupsBelow(index: Int): Boolean {
        val message = (timelineItems.getOrNull(index) as? AgentTimelineItem.Message)?.message
            ?: return false
        val hints = timelineItems.getOrNull(index + 1) as? AgentTimelineItem.Hints
        return shouldShowFollowups(message) || hints?.followupMessageId != null
    }

    private fun updateFollowupTail(index: Int) {
        val holder = chatRecyclerView.findViewHolderForAdapterPosition(index) as? WCell.Holder
        when (val cell = holder?.cell) {
            is AgentMessageCell -> cell.setHasFollowupsBelow(hasFollowupsBelow(index))
            is AgentNewsPostCell -> cell.setHasFollowupsBelow(hasFollowupsBelow(index))
        }
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
                    hasFollowupsBelow = hasFollowupsBelow(idx),
                    areActionsDisabled = preparedVM?.isCachedMessage(item.message.id) == true,
                    hasAuthor = item.hasAuthor
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

    private fun openNewsPhoto(messageId: String, post: AgentNewsPostContent) {
        val window = window ?: return
        val url = post.imageUrl ?: return
        cancelDictation()
        view.hideKeyboard()
        MediaViewerVC.present(window, listOf(agentNewsMediaViewerItem(window, url, post)), 0) {
            chatRecyclerView.children
                .filterIsInstance<AgentNewsPostCell>()
                .firstOrNull { it.shownPostId == messageId }
                ?.makePhotoSource()
        }
    }

    private fun openDigestPictures(
        messageId: String,
        post: AgentNewsPostContent,
        pictures: AgentNewsDigestPictures
    ) {
        val window = window ?: return
        cancelDictation()
        view.hideKeyboard()
        val date = parseAgentV2Timestamp(post.publishedAt)
        val items = pictures.headlines.map { agentNewsDigestMediaViewerItem(window, it, date) }
        MediaViewerVC.present(window, items, pictures.index) { index ->
            chatRecyclerView.children
                .filterIsInstance<AgentNewsPostCell>()
                .firstOrNull { it.shownPostId == messageId }
                ?.makeDigestPictureSource(pictures.headlines[index])
        }
    }

    private fun showCopyBulletin() {
        val text = LocaleController.getString("\$agent_message_copied")
        bulletin.showCopied(view, chatRecyclerView, text, ::bulletinBottomOffset)
    }

    // The first like or dislike explains itself in the bulletin, with the reaction's own animation as its icon
    private fun showReactionBulletin(feedback: AgentAnswerFeedback, text: String) {
        val animation =
            AgentReactionAnimations.drawable(context, feedback, AgentReactionAnimation.CENTER)
                ?: return
        bulletin.show(
            view,
            chatRecyclerView,
            text,
            ::bulletinBottomOffset,
            animation,
            AgentBulletinDurations.REACTION_MS
        )
    }

    // The bulletin stands on the question field's top edge, the composer's visible top, wherever the keyboard carries
    // the composer; it rises from behind that edge and hides behind it
    private fun bulletinBottomOffset(): Int =
        (view.height - contentContainer.y - composerView.y - composerView.fieldTop)
            .roundToInt()
            .coerceAtLeast(0)

    private fun onCopyPopupVisibilityChanged(visible: Boolean) {
        if (visible) {
            cancelDictation()
            viewport.finishLatestScroll()
            rowGlide.finish()
            // As in Telegram, the menu takes the keyboard's place
            view.hideKeyboard()
        }
        isPopupVisible = visible
        chatRecyclerView.suppressLayout(visible || !streamRenderer.isActive)
    }

    // The chat's rows a menu's message shows in, lifted over the dim: from the header's bottom down to the field's top,
    // as the chat shows through the composer's space above its field
    private fun getMenuRows(): IntRange {
        val top = navigationBar?.let { it.getLocationInWindow().y + it.height }
            ?: chatRecyclerView.getLocationInWindow().y
        return top until composerView.getLocationInWindow().y + composerView.fieldTop
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
                news,
                model.currentThread.digest ?: digestPreview
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
        updateHeaderButtons()
    }

    override fun onSupportRequestAvailabilityChanged() {
        updateHeaderButtons()
        updateVisibleHintsAvailability()
    }

    override fun onInputLimitChanged() {
        updateComposerSubmission()
        updateHeaderButtons()
        updateVisibleHintsAvailability()
        reloadLastFailureRowIfRetryChanged()
    }

    /**
     * New questions wait while a limit blocks them; the composer then stays dimmed. Behind a
     * regeneration they queue as behind any answer, once the chat has asked for it.
     */
    private fun updateComposerSubmission() {
        val model = preparedVM
        val isInputBlockedByLimit = model?.isInputBlockedByLimit
            ?: (chatOpening?.isInputBlockedByLimit == true)
        composerView.setSubmissionEnabled(
            chatOpening?.canSubmitDiscussionMessage == true ||
                (
                    model != null && !model.hasUnsentOpening &&
                        agentNewsAllowsSubmission(news, agentState) &&
                        agentState != AgentVM.State.CLEARING && !isReplacementStarting &&
                        !isInputBlockedByLimit
                    )
        )
        composerView.isAnswering = model != null && agentState == AgentVM.State.RUNNING
        // As the design's "Limit Reached" frame shows it, the composer's contents are at half their opacity while a
        // limit blocks sending
        composerView.contentAlpha =
            if (isInputBlockedByLimit) DISABLED_BUTTON_ALPHA else 1f
    }

    /**
     * The failure that ends the timeline offers Retry while the chat can use it, above any failed support requests
     * after it; earlier ones don't
     */
    private fun buildFailureRetry(message: AgentMessage): (() -> Unit)? {
        if (!message.isFailure ||
            findFailureRetryRowIndex()?.let { timelineMessageAt(it) }?.id != message.id
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
        val index = findFailureRetryRowIndex() ?: return
        if (timelineMessageAt(index)?.isFailure == true) rvAdapter.notifyItemChanged(index)
    }

    private fun findFailureRetryRowIndex(): Int? {
        val messageIds = timelineItems.map { (it as? AgentTimelineItem.Message)?.message?.id }
        val model = preparedVM ?: return messageIds.indexOfLast { it != null }.takeIf { it >= 0 }
        return model.findFailureRetryRowIndex(messageIds)
    }

    private fun timelineMessageAt(index: Int): AgentMessage? =
        (timelineItems.getOrNull(index) as? AgentTimelineItem.Message)?.message

    override fun onError() {
        if (agentState == AgentVM.State.CONSENT_REQUIRED ||
            agentState == AgentVM.State.ACCEPTING_CONSENT
        ) {
            Toast.makeText(context, agentUnavailableText(), Toast.LENGTH_SHORT).show()
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
    // a News discussion already fills with its post. A card flying in from the feed lands on the post as it is,
    // without placeholders turning into it under the card.
    private fun showSkeletonIfLoading() {
        val model = preparedVM ?: return
        val hasOpening = chatOpening != null
        if (newsPostArrival != null || !shouldShowAgentMessagesSkeleton(model, hasOpening)) return
        skeletonReveal.show()
        updateBlurViews(chatRecyclerView)
    }

    private fun revealMessagesFromSkeleton() {
        skeletonReveal.reveal(hasRows = displayMessages.isNotEmpty())
        syncTopBlurAfterLayout()
    }

    private fun hideSkeleton() {
        skeletonReveal.hide()
        syncTopBlurAfterLayout()
    }

    // Whether the suggestions under the answer show, as the timeline lists them
    private fun shouldShowFollowups(message: AgentMessage): Boolean {
        val owner = displayMessages.findFollowupOwner() ?: return false
        val followups = preparedVM?.visibleFollowups(owner.id) ?: owner.followups
        return owner.id == message.id && followups.isNotEmpty() && !owner.isStreaming &&
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
            news,
            preparedVM?.currentThread?.digest ?: digestPreview,
            discussionNaming = if (preparedVM == null) discussionNaming else news?.discussionNaming
        )
        val shownItems = messageItems.filterNot { hiddenIncomingMessageIds.contains(it.message.id) }
        val hasAuthors = presentationMessages.hasSupportOperatorJoined()
        for (shownItem in shownItems.insertFailureLines()) {
            val item = if (hasAuthors && shownItem.newsPost == null &&
                shownItem.message.role.let {
                    it == AgentMessageRole.ASSISTANT || it == AgentMessageRole.OPERATOR
                }
            ) {
                shownItem.copy(hasAuthor = true)
            } else {
                shownItem
            }
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
        val followupOwner = if (preparedVM == null) {
            messageItems.map { it.message }.findFollowupOwner()
        } else {
            messages.findFollowupOwner()
        }
        val followups = followupOwner?.let {
            preparedVM?.visibleFollowups(it.id) ?: it.followups
        }.orEmpty()
        val pendingNews = shownItems.lastOrNull()?.takeIf { it.newsPost != null }
        if ((followups.isEmpty() || agentState == AgentVM.State.LOADING) &&
            pendingNews != null && !newsFollowupWait.isExpired &&
            (preparedVM != null || chatOpening?.isDeferredDiscussion != true) &&
            displayMessages.none { it.role == AgentMessageRole.USER } &&
            preparedVM?.state != AgentVM.State.ERROR
        ) {
            if (newsFollowupWait.arePlaceholdersDue()) {
                items.add(
                    AgentTimelineItem.Hints(emptyList(), pendingNews.message.id, isLoading = true)
                )
            }
            return items
        }
        if (followups.isNotEmpty() && followupOwner?.isStreaming == false &&
            (
                !followupOwner.newsPost || preparedVM?.state == AgentVM.State.READY ||
                    (preparedVM == null && chatOpening?.isDeferredDiscussion == true)
                ) &&
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
                    item.message.supportEvent != null -> SUPPORT_EVENT_CELL
                    item.message.role == AgentMessageRole.SYSTEM -> SYSTEM_CELL
                    else -> MESSAGE_CELL
                }
            }
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            DATE_CELL -> AgentDateHeaderCell(context)
            SYSTEM_CELL -> AgentSystemMessageCell(context)
            SUPPORT_EVENT_CELL -> AgentSupportEventCell(context)
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
            (
                regenerationStart >= 0 && indexPath.row >= regenerationStart &&
                    !isQueuedTimelineRow(indexPath.row)
                )
        ) {
            View.INVISIBLE
        } else {
            View.VISIBLE
        }
        val animate = animateFromIndex in 0..indexPath.row && canAnimateRows
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
                    onHintTap = onHintTap@{ hint, card ->
                        if (hint.id == AGENT_SUPPORT_HINT_ID) {
                            presentSupportRequest(card.id)
                            return@onHintTap
                        }
                        val messageId = item.followupMessageId
                        withConsent {
                            sendSuggestion(card, this) {
                                if (messageId != null) {
                                    !isReplacementStarting &&
                                        (
                                            preparedVM?.sendFollowup(messageId, hint.id)
                                                ?: sendFirstDiscussionMessage(
                                                    hint.prompt,
                                                    isFollowup = true
                                                )
                                            )
                                } else {
                                    sendMessage(hint.prompt, vm.hintEntryPoint(hint))
                                }
                            }
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
                    setCardsEnabled(canSendHints(item))
                    isSupportHintEnabled = preparedVM?.canRequestSupportFromStarterHint == true
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
                        cell.onDigestPictureClick = { openDigestPictures(messageId, post, it) }
                        // A digest's headline opens its news item over the chat, as the digest's card does over the feed
                        cell.onDigestHeadlineClick = { headline ->
                            cancelDictation()
                            navigationController?.let {
                                AgentNavigation.openNewsChat(context, it, headline.eventId)
                            }
                        }
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
                        cell.onRate = { ratedMessageId, feedback, onSettled ->
                            vm.rateMessage(
                                ratedMessageId,
                                feedback,
                                onSaved = { onSettled(true) }
                            ) {
                                onSettled(false)
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
                        cell.onReactionToast = ::showReactionBulletin
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
                        val hasSentMorph = sentMorphSource?.first == messageId ||
                            heldSentMorph?.first == messageId
                        cell.startSentMorph = if (animate && hasSentMorph) {
                            ::startSentMorph
                        } else {
                            null
                        }
                        cell.configure(
                            item.message,
                            rv.width,
                            preparedVM?.publishesAnswerLinks == true,
                            animate,
                            hasFollowupsBelow = hasFollowupsBelow(indexPath.row),
                            areActionsDisabled = preparedVM?.isCachedMessage(messageId) == true,
                            hasAuthor = item.hasAuthor
                        )
                    }

                    is AgentSystemMessageCell -> cell.configure(
                        item.message,
                        buildFailureRetry(item.message)
                    )

                    is AgentSupportEventCell -> cell.configure(item.message)
                }
            }
        }
    }
}
