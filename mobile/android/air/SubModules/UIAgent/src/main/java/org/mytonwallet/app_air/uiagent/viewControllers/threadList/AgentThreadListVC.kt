package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.Manifest
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.SystemClock
import android.text.format.DateFormat
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.toDrawable
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updatePadding
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.AndroidAgentDictationRecorder
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.getAgentSupportRequestText
import org.mytonwallet.app_air.uiagent.agentV2.isAgentSupportHandoffDeclared
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_SUPPORT_HINT_ID
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentConsentGate
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentConsentSheetVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHeldDictation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewChatVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentPromptChatRequest
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSession
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSupportRequestConfirmation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.holdDictationForConsent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.makeAgentSupportHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.showMicrophoneDeniedAlert
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentDustEffect
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSentMessageSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSuggestionRipple
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.calculateAgentSendDurationMs
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.getAgentHostOrigin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.getAgentTextFrame
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.makeAgentPictureView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.makeAgentTextPicture
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.offsetBy
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsFeedVC
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsPreviewModel
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.WAgentHintView
import org.mytonwallet.app_air.uicomponents.drawable.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.WEquatable
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2SupportRequestSource
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings

/** A row of the Agent list: the News row, a section's title, or a chat */
private sealed class AgentThreadListRow : WEquatable<AgentThreadListRow> {
    abstract val key: String

    /** The latest news, or in the Digests view the latest digest, with the count of the new ones */
    data class News(
        val latest: AgentV2NewsFeedItem?,
        val latestDigest: AgentV2NewsFeedDigest?,
        val unreadCount: Int
    ) : AgentThreadListRow() {
        override val key = "news"
    }

    data class Header(val sectionKey: String, val title: String) : AgentThreadListRow() {
        override val key = "header:$sectionKey"
    }

    data class Thread(val item: AgentV2ThreadListItem, val sectionTitle: String) :
        AgentThreadListRow() {
        override val key = "thread:${item.thread.id}"
    }

    // The line at the list's end that loads a page that failed to load again
    data object PageFailure : AgentThreadListRow() {
        override val key = "page-failure"
    }

    override fun isSame(comparing: WEquatable<*>): Boolean =
        (comparing as? AgentThreadListRow)?.key == key

    override fun isChanged(comparing: WEquatable<*>): Boolean = comparing != this
}

@SuppressLint("ViewConstructor")
class AgentThreadListVC(context: Context) :
    WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver,
    WalletCore.UpdatesObserver {
    @Suppress("PropertyName")
    override val TAG = "AgentThreadList"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = LiveAgentV2Client()
    private val model = AgentThreadListModel(scope)

    // The feed finds its discussions among the chats the list has loaded, without keeping the list
    private val threadFinder: (String) -> AgentV2ThreadSummary? = run {
        val weakModel = WeakReference(model)
        val finder: (String) -> AgentV2ThreadSummary? = { threadId ->
            weakModel.get()?.items?.firstOrNull { it.thread.id == threadId }?.thread
        }
        finder
    }
    private val newsModel = AgentNewsPreviewModel(scope)
    private val readState = AgentThreadReadState.shared
    private var rows = emptyList<AgentThreadListRow>()

    // Chats the user deleted: the change that removes one turns its row to dust, as on iOS
    private val deletingThreadIds = mutableSetOf<String>()
    private var dustEffect: AgentDustEffect? = null

    // The change that waits for a deleted chat's dust to show, which hides its row as the rows close up
    private var dustPendingChange: AgentThreadListChange? = null

    // Debug builds remove rows without dust while system animations are off, to keep E2E runs fast
    private val canDissolveRows: Boolean
        get() = AgentDustEffect.isSupported(context) && (!DEBUG_MODE || areSystemAnimatorsEnabled)

    private val areSystemAnimatorsEnabled: Boolean
        get() = Build.VERSION.SDK_INT < Build.VERSION_CODES.O || ValueAnimator.areAnimatorsEnabled()

    private var hasRevealedThreads = false
    private var hasConsent = false
    private var hasConsentResult = false

    // A recording asked for before the list went from the screen doesn't start after; the consent sheet covering the
    // list keeps it
    private val heldDictation = AgentHeldDictation()
    private var consentJob: Job? = null
    private var refreshJob: Job? = null
    private var isAppActive = true
    private var isAgentSearchOpen = false

    /**
     * The root's bottom toolbar the question bar grows out of. With a host the list has no search circle of its
     * own: the toolbar's search field shrinks into it.
     */
    var barHost: AgentListBarHost? = null
        set(value) {
            if (field === value) return
            field = value
            if (isViewConfigured) {
                if (value == null) resetHostedBar()
                updateBarVisibility()
                updateBarExpansion()
                updateComposeHeader(isAnimated = false)
                insetsUpdated()
                setHostedBarProgress(hostedBarProgress)
            }
        }

    /** A screen pushed over the list covers its bar */
    var isBarCovered = false
        private set

    /** A question is being written in the bar, or one sent from it hands the list to its chat */
    val isComposing: Boolean
        get() = (isComposerFocused || isComposedChatPending) && !isBarCovered

    /** The bar's search circle makes way for its field, which records, recognizes or holds a draft */
    val isSearchAway: Boolean
        get() = composer.isFieldInUse
    private var isComposerFocused = false
    private var hostedBarProgress = 1f

    // How far the field has widened over the search circle, as it does while composing, under a chat, or while the
    // field is in use
    private var barExpansion = 0f

    // The chat over the list, whose composer follows the bar while the bar carries the field into it or back
    private var coveringChat: WeakReference<AgentVC>? = null
    private var isChatTakingOver = false
    private var barExpansionAnimator: ValueAnimator? = null
    private val itemAnimator = AgentThreadListItemAnimator()
    private val threadsAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, THREAD_CELL, NEWS_CELL, FAILURE_CELL)
    )
    private val listLayoutManager = LinearLayoutManager(context)
    private val listDecoration = AgentThreadListDecoration(
        sectionTitleAt = ::getSectionTitle,
        isHeaderAt = { rows.getOrNull(it) is AgentThreadListRow.Header }
    )
    private var composeCoverAnimator: ValueAnimator? = null

    // The glass of the bar shows the list as it draws, the composing cover included
    private val recyclerView = object : WRecyclerView(this) {
        override fun glassDrawForeground(canvas: Canvas) = listDecoration.drawCover(canvas)

        override fun glassDrawnStateHash(): Long = listDecoration.coverAlpha.toRawBits().toLong()
    }.apply {
        id = UIComponentsR.id.agent_threads_list
        adapter = threadsAdapter
        layoutManager = listLayoutManager
        clipToPadding = false
        itemAnimator = this@AgentThreadListVC.itemAnimator
        overScrollMode = View.OVER_SCROLL_ALWAYS
        addItemDecoration(listDecoration)
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                updateBlurViews(recyclerView)
                // A page that failed to load waits for its failure line's Retry
                val lastVisible = listLayoutManager.findLastVisibleItemPosition()
                if (lastVisible >= rows.size - LOAD_MORE_THRESHOLD && !model.hasPageLoadFailed) {
                    model.loadMore()
                }
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                // Scrolling the list closes the rows' actions
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) closeSwipes(except = null)
            }
        })
    }
    private val skeletonView = AgentThreadListSkeletonView(context)

    // The failure with Retry in place of the suggestions, under the News row, when the chats failed to load and the
    // list has none to show
    private val loadErrorView = AgentLoadErrorView(context).apply {
        onRetry = { refresh() }
    }
    private val loadMoreSpinner = ProgressBar(context).apply { id = View.generateViewId() }
    private val bottomGradientView = View(context).apply {
        id = View.generateViewId()
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val searchButtonRipple = WRippleDrawable.create(BAR_HEIGHT.dp / 2f)
    private val searchIcon = ImageView(context).apply {
        id = View.generateViewId()
        setImageResource(R.drawable.ic_search_24)
        scaleType = ImageView.ScaleType.CENTER
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val searchButton = WFrameLayout(context).apply {
        id = UIComponentsR.id.agent_threads_search
        contentDescription = LocaleController.getString("Search")
        isClickable = true
        isFocusable = true
        foreground = searchButtonRipple
        addView(
            searchIcon,
            FrameLayout.LayoutParams(SEARCH_ICON.dp, SEARCH_ICON.dp, Gravity.CENTER)
        )
        setOnClickListener { openSearch() }
    }
    private var searchGlass: WGlassView? = null
    private val composer = AgentComposerView(context, recyclerView)
    private val dictation: AgentDictationController by lazy {
        AgentDictationController(
            scope = scope,
            recorderFactory = { AndroidAgentDictationRecorder(context) { dictation.cancel() } },
            requestPermission = { requestMicrophonePermission() },
            transcribe = { audio ->
                client.transcribe(
                    AgentV2TranscriptionRequest(
                        audio,
                        lang = LocaleController.activeLanguage.langCode
                    )
                )
            },
            nowMs = SystemClock::elapsedRealtime,
            onStateChanged = composer::renderDictation,
            onTranscript = composer::setDictationText,
            onFailure = composer::showDictationFailure,
            onRecordingStarted = { Haptics.play(composer, HapticType.LIGHT_TAP) },
            onGestureFeedback = { Haptics.play(composer, HapticType.LIGHT_TAP) }
        )
    }
    private val readStateListener = { reconfigureVisibleRows() }

    // While a question is written: the chats give way to suggestions over the field
    private val composeSuggestions = AgentHintsCell(context).apply {
        visibility = View.GONE
        onHintTap = { hint, card ->
            if (hint.id == AGENT_SUPPORT_HINT_ID) {
                presentSupportRequest()
            } else {
                sendComposed(hint.prompt, card)
            }
        }
    }

    // The suggestion whose question grows into a new chat, out of sight until the list shows again
    private var sentSuggestionCard: WeakReference<WAgentHintView>? = null
    private val composeDismissArea = View(context).apply {
        id = View.generateViewId()
        visibility = View.GONE
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        setOnClickListener { endComposing() }
    }
    private val composeBackButton by lazy {
        WImageButton(context).apply {
            id = View.generateViewId()
            setImageDrawable(context.getDrawableCompat(R.drawable.ic_nav_back))
            contentDescription = LocaleController.getString("Back")
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
            setOnClickListener { endComposing() }
        }
    }
    private var isComposeShown = false
    private var hasKeyboardBeenShown = false

    // A floating keyboard covers nothing, so it shows only in the insets' visibility
    private fun isFloatingKeyboardShown(): Boolean =
        ViewCompat.getRootWindowInsets(view)?.isVisible(WindowInsetsCompat.Type.ime()) == true

    // The keyboard also goes while a system dialog, such as the microphone permission, holds the window, and when a
    // hardware keyboard takes over; neither ends composing
    private fun isKeyboardDismissal(): Boolean = view.hasWindowFocus() && !hasHardwareKeyboard()

    private fun hasHardwareKeyboard(): Boolean =
        context.resources.configuration.hardKeyboardHidden == Configuration.HARDKEYBOARDHIDDEN_NO

    // Back from a system dialog, the field that kept its focus gets its keyboard again
    private fun onWindowFocusChanged(hasWindowFocus: Boolean) {
        if (!hasWindowFocus || !isComposerFocused || hasHardwareKeyboard()) return
        if ((navigationController?.imeInsetBottom ?: 0) > 0 || isFloatingKeyboardShown()) return
        composer.post { composer.showInputKeyboard() }
    }
    private var composeHintsJob: Job? = null

    override fun setupViews() {
        super.setupViews()
        setupNavBar(!isRootTopGradientEnabled)
        updateTitle()
        view.clipChildren = false
        view.addView(recyclerView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(skeletonView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(loadErrorView, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(bottomGradientView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(loadMoreSpinner, ConstraintLayout.LayoutParams(24.dp, 24.dp))
        view.addView(searchButton, ConstraintLayout.LayoutParams(BAR_HEIGHT.dp, BAR_HEIGHT.dp))
        view.addView(composer, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(composeDismissArea, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(composeSuggestions, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        composeSuggestions.backdropSource = view
        view.setConstraints {
            allEdges(recyclerView)
            allEdges(composeDismissArea)
            toStart(composeSuggestions)
            toEnd(composeSuggestions)
            // The suggestions rest 26 dp over the field
            bottomToTop(
                composeSuggestions,
                composer,
                COMPOSE_SUGGESTIONS_GAP - COMPOSER_TOP_PADDING
            )
            toBottom(skeletonView)
            toBottom(bottomGradientView)
            toCenterX(loadMoreSpinner)
            bottomToTop(loadMoreSpinner, composer, 4f)
        }
        searchGlass = WGlassView.attachTo(
            searchButton,
            BAR_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            recyclerView
        )
        composer.bindDictation(dictation)
        composer.onSend = ::sendDraft
        // A recording's audio goes to the Agent, so the first one waits for the user's consent
        composer.shouldHoldDictation = holdDictationForConsent(
            isAwaitingConsent = { !hasConsent },
            heldDictation = heldDictation,
            askForConsent = { onAllowed, _ -> requestConsent(action = onAllowed) },
            startDictation = { dictation.startHandsFree() }
        )
        composer.onHeightChanged = { insetsUpdated() }
        composer.onWindowFocusChanged = ::onWindowFocusChanged
        composer.onInputFocusChanged = { isFocused ->
            isComposerFocused = isFocused
            updateBarExpansion()
            updateComposeState()
            barHost?.onAgentBarStateChanged()
        }
        composer.onFieldInUseChanged = {
            updateBarExpansion()
            barHost?.onAgentBarStateChanged()
        }
        model.onChange = ::updateRows
        model.onError = ::showOperationError
        model.onActivityChange = ::updateActivities
        newsModel.onChange = { updateRows(AgentThreadListChange.DATA) }
        observeNewsView()
        readState.addListener(readStateListener)
        WalletCore.registerObserver(this)
        WalletCore.subscribeToApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        updateRows(AgentThreadListChange.DATA)
        updateTheme()
        insetsUpdated()
        checkConsent()
    }

    override fun didSetupViews() {
        super.didSetupViews()
        bringBarToFront()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        restoreComposeSuggestions()
        // A chat going away hands the field back to the bar, which narrows under the chat's composer
        val isUnderChat = navigationController?.viewControllers?.lastOrNull() !== this
        if (coveringChat?.get() != null && barHost != null && isUnderChat) isChatTakingOver = true
        setBarCovered(false)
        followBarInCoveringChat()
        forEachVisibleThreadCell { cell, _ -> cell.rowView.shouldHoldHighlight = false }
        for (index in 0 until recyclerView.childCount) {
            (recyclerView.getChildAt(index) as? AgentNewsCell)?.rowView?.shouldHoldHighlight = false
        }
        if (hasConsent) refresh() else checkConsent()
        startRefreshTimer()
    }

    override fun viewWillDisappear() {
        if (!isAskingForConsent) heldDictation.drop()
        dictation.cancel()
        closeSwipes(except = null)
        refreshJob?.cancel()
        super.viewWillDisappear()
        // A swipe back that gives up leaves the chat over the list, with its own composer
        if (isChatTakingOver) {
            isChatTakingOver = false
            coveringChat?.get()?.setComposerHandoff(null)
        }
        val stack = navigationController?.viewControllers
        if (stack != null && stack.size > 1 && stack.lastOrNull() !== this) setBarCovered(true)
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        // The chat has gone; its composer no longer follows the bar
        isChatTakingOver = false
        coveringChat = null
    }

    /** The root tells the list a screen was pushed over it, or popped */
    fun setBarCovered(isCovered: Boolean) {
        if (isBarCovered == isCovered) return
        isBarCovered = isCovered
        updateBarExpansion()
        updateComposeState()
        barHost?.onAgentBarStateChanged()
    }

    /**
     * The field's question, which waits for the user's consent the first time, keeping the draft until it is given. A
     * focused field here has the keyboard, which closing the sheet gives back.
     */
    private fun sendDraft(prompt: String): Boolean {
        if (hasConsent) return sendComposed(prompt)
        requestConsent(isFromKeyboard = isComposerFocused) {
            // The field empties once its text has been pictured for the flight, as on a send
            // that needs no consent
            if (sendComposed(prompt)) composer.setDraftText("", focusInput = false)
        }
        return false
    }

    /** Sends [prompt], the field's question, or the question of [card], one of the suggestions */
    private fun sendComposed(prompt: String, card: WAgentHintView? = null): Boolean {
        if (!hasConsent) {
            requestConsent { sendComposed(prompt, card) }
            return false
        }
        // The question grows into the new chat's first bubble as the chat comes in, out of the
        // field's text or the suggestion tapped, which leaves the list meanwhile
        val sentSource = makeSentSource(card)
        // The suggestions stop taking taps as soon as one is sent
        composeSuggestions.setCardsEnabled(false)
        val shouldContinueInPlace = isComposeShown && barHost != null
        // The other suggestions, the spinning top among them, leave at once, rippling away from
        // the one tapped or from the field
        val suggestionsRipple = if (shouldContinueInPlace) {
            rippleComposeSuggestionsAway(card ?: composer)
        } else {
            null
        }
        if (!shouldContinueInPlace && sentSource?.kind is AgentSentMessageSource.Kind.Text) {
            // The emptied field fades back in under the chat sliding in, as its text leaves it
            composer.fadeInFieldText(calculateAgentSendDurationMs(AnimationConstants.NAV_PUSH))
        }
        // The compose screen stays as the field gives up the keyboard, until the chat takes its
        // place
        if (shouldContinueInPlace) isComposedChatPending = true
        composer.hideKeyboard()
        if (shouldContinueInPlace) {
            continueComposedChat(prompt, sentSource, suggestionsRipple)
        } else {
            pushNewChat(prompt, AgentV2EntryPoint(), sentSource)
        }
        return true
    }

    // Pictures of the suggestions leave over the window, where they outlast the list
    private fun rippleComposeSuggestionsAway(origin: View): AgentSuggestionRipple? {
        val root = view.rootView as? ViewGroup ?: return null
        if (!WGlobalStorage.getAreAnimationsActive() || !composeSuggestions.isVisible) return null
        composeSuggestions.finishReveal()
        return AgentSuggestionRipple.start(composeSuggestions.contentViews, origin, root)
    }

    /** What a question sent from [card], or else from the field, grows out of, in the window */
    private fun makeSentSource(card: WAgentHintView?): AgentSentMessageSource? {
        if (card == null) return composer.makeSentTextSource()
        val source = AgentSentMessageSource.makeSuggestion(card) ?: return null
        restoreSentSuggestion()
        card.animate().cancel()
        card.alpha = 0f
        sentSuggestionCard = WeakReference(card)
        return source
    }

    private fun restoreSentSuggestion() {
        sentSuggestionCard?.get()?.alpha = 1f
        sentSuggestionCard = null
    }

    /**
     * The suggestions a question left show again, the one tapped and those that rippled away with
     * the spinning top: the row keeps its cards while its hints stay the same
     */
    private fun restoreComposeSuggestions() {
        restoreSentSuggestion()
        composeSuggestions.contentViews.forEach { it.alpha = 1f }
    }

    /**
     * The new chat's first bubble grows out of [source] over the window as the chat comes in, and
     * its answer comes once the bubble has landed and [suggestionsRipple] has ended
     */
    private fun handOverSentSource(
        chat: AgentVC,
        source: AgentSentMessageSource,
        transitionMs: Long,
        suggestionsRipple: AgentSuggestionRipple? = null
    ) {
        val root = view.rootView as? ViewGroup ?: return
        chat.setOpeningSentSource(source, transitionMs, root, suggestionsRipple)
    }

    /**
     * A question written in the list continues in place: the new chat takes the list's place at
     * once, without a transition of its own, as the question grows into its first bubble over the
     * window. The chat's header and timeline fade in as the list's title fades out, and the chat's
     * field, which takes the place of the list's, goes down with the keyboard.
     */
    private fun continueComposedChat(
        prompt: String,
        sentSource: AgentSentMessageSource?,
        suggestionsRipple: AgentSuggestionRipple?
    ) {
        val navigation = navigationController ?: run {
            isComposedChatPending = false
            suggestionsRipple?.cancel()
            restoreComposeSuggestions()
            updateComposeState()
            return
        }
        val chat = AgentVC(context, prompt = AgentPromptChatRequest(prompt, AgentV2EntryPoint()))
        sentSource?.let {
            handOverSentSource(chat, it, transitionMs = 0L, suggestionsRipple = suggestionsRipple)
        }
        fadeComposeTitleAway()
        isComposedChatPending = false
        navigation.push(chat, animated = false)
        chat.takePlaceOfPreviousScreen(COMPOSED_CHAT_CROSSFADE_MS)
    }

    // A picture of the list's title fades out over the window, where it outlasts the list
    private fun fadeComposeTitleAway() {
        if (!WGlobalStorage.getAreAnimationsActive()) return
        val root = view.rootView as? ViewGroup ?: return
        val bar = navigationBar ?: return
        val title = bar.titleLabel
        if (!title.isShown) return
        val frame = getAgentTextFrame(title) ?: return
        val picture = makeAgentTextPicture(title, frame) ?: return
        val origin = getAgentHostOrigin(title, root)
        val pictureView =
            makeAgentPictureView(context, picture, frame.offsetBy(origin.x, origin.y))
        root.overlay.add(pictureView)
        ValueAnimator.ofFloat(bar.alpha * title.alpha, 0f).apply {
            duration = COMPOSED_CHAT_CROSSFADE_MS
            addUpdateListener { pictureView.alpha = it.animatedValue as Float }
            doOnEnd { root.overlay.remove(pictureView) }
            start()
        }
    }

    private var isComposedChatPending = false

    private fun endComposing() {
        composer.hideKeyboard()
    }

    // Writing a question turns the list into a new chat: its chats fade, suggestions rise over the field, and with a
    // hosting toolbar the root header gives way to a new chat's
    private fun updateComposeState() {
        val shouldShowCompose = isComposing && hasConsentResult
        val shouldAnimate = WGlobalStorage.getAreAnimationsActive()
        if (shouldShowCompose || shouldShowEmptySuggestions) loadComposeHints()
        if (isComposeShown == shouldShowCompose) {
            updateComposeSuggestions(shouldAnimate)
            return
        }
        isComposeShown = shouldShowCompose
        if (shouldShowCompose) {
            closeSwipes(except = null)
        }
        updateComposeCover(if (shouldShowCompose) 1f else 0f, shouldAnimate)
        listOf(skeletonView, loadErrorView).forEach { content ->
            content.animate().cancel()
            if (shouldAnimate) {
                content.animate().alpha(
                    if (shouldShowCompose) 0f else 1f
                ).setDuration(COMPOSE_FADE_MS)
                    .setInterpolator(WInterpolator.smooth).start()
            } else {
                content.alpha = if (shouldShowCompose) 0f else 1f
            }
        }
        recyclerView.importantForAccessibility = if (shouldShowCompose) {
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        } else {
            View.IMPORTANT_FOR_ACCESSIBILITY_AUTO
        }
        composeDismissArea.isVisible = shouldShowCompose
        updateComposeSuggestions(shouldAnimate)
        updateComposeHeader(shouldAnimate)
    }

    // The chats and their card fade into the page as iOS's 0.3 s critically damped spring; the suggestions ride the
    // same animation, so they show exactly as much as the chats give way
    private fun updateComposeCover(target: Float, isAnimated: Boolean) {
        val previous = composeCoverAnimator
        composeCoverAnimator = null
        previous?.cancel()
        if (!isAnimated) {
            listDecoration.coverAlpha = target
            recyclerView.invalidate()
            return
        }
        composeCoverAnimator = ValueAnimator.ofFloat(listDecoration.coverAlpha, target).apply {
            duration = COMPOSE_SPRING_MS
            interpolator = WInterpolator.smooth
            addUpdateListener {
                val cover = it.animatedValue as Float
                listDecoration.coverAlpha = cover
                recyclerView.invalidate()
                if (areSuggestionsFollowingCover) applySuggestionsShare(cover)
            }
            doOnEnd { animation ->
                if (composeCoverAnimator !== animation) return@doOnEnd
                composeCoverAnimator = null
                if (!areSuggestionsFollowingCover) return@doOnEnd
                areSuggestionsFollowingCover = false
                if (target == 0f) composeSuggestions.isVisible = false
            }
            start()
        }
    }

    // While the chats fade, the suggestions take their share from the same animation
    private var areSuggestionsFollowingCover = false

    // A list whose chats failed to load shows the failure in their place. Before consent the list has no chats to load
    // and shows the suggestions at once.
    private val shouldShowEmptySuggestions: Boolean
        get() {
            if (!hasConsentResult || isBarCovered) return false
            return !hasConsent ||
                (model.hasLoaded && model.items.isEmpty() && !model.hasLoadFailed)
        }

    private fun applySuggestionsShare(share: Float) {
        composeSuggestions.alpha = share
        composeSuggestions.translationY = COMPOSE_RISE.dp * (1 - share)
    }

    private fun updateComposeSuggestions(isAnimated: Boolean) {
        val hints = shownComposeHints
        val shouldShow = (isComposeShown || shouldShowEmptySuggestions) && hints.isNotEmpty()
        composeSuggestions.animate().cancel()
        val isCoverAnimating = composeCoverAnimator?.isRunning == true
        areSuggestionsFollowingCover = false
        composeSuggestions.isSupportHintEnabled = canRequestSupportFromList
        if (shouldShow) {
            val wasVisible = composeSuggestions.isVisible
            // Suggestions that load after Contact Support showed alone take their places before it
            composeSuggestions.configure(
                hints,
                shouldShowEmptyStateIcon = true,
                shouldAnimate = false
            )
            if (!wasVisible) {
                applySuggestionsShare(0f)
                composeSuggestions.isVisible = true
            }
            composeSuggestions.setCardsEnabled(true)
            when {
                !isAnimated -> applySuggestionsShare(1f)

                isCoverAnimating && !shouldShowEmptySuggestions -> {
                    areSuggestionsFollowingCover = true
                    applySuggestionsShare(listDecoration.coverAlpha)
                }

                // Suggestions that come after the chats have faded rise by themselves
                else -> composeSuggestions.animate().alpha(1f).translationY(0f)
                    .setDuration(COMPOSE_SPRING_MS)
                    .setInterpolator(WInterpolator.smooth)
                    .start()
            }
        } else if (composeSuggestions.isVisible) {
            when {
                !isAnimated -> composeSuggestions.isVisible = false

                isCoverAnimating -> {
                    areSuggestionsFollowingCover = true
                    applySuggestionsShare(listDecoration.coverAlpha)
                }

                else -> composeSuggestions.animate().alpha(0f).translationY(COMPOSE_RISE.dp)
                    .setDuration(COMPOSE_SPRING_MS)
                    .setInterpolator(WInterpolator.smooth)
                    .withEndAction { composeSuggestions.isVisible = false }
                    .start()
            }
        }
    }

    // Up to five suggestions, cached for a while per language
    private var composeSuggestionsHints: List<AgentHint> = emptyList()

    // Whether the server's suggestions have loaded or failed to, after which Contact Support shows
    private var hasComposeHintsSettled = false

    // The server's suggestions, then Contact Support, which the client offers outside their limit
    private val shownComposeHints: List<AgentHint>
        get() = if (isAgentSupportHandoffDeclared && hasComposeHintsSettled) {
            composeSuggestionsHints + makeAgentSupportHint()
        } else {
            composeSuggestionsHints
        }

    // Contact Support waits until the list knows the consent and, with consent, until the chats have loaded
    private val canRequestSupportFromList: Boolean
        get() = hasConsentResult && (!hasConsent || (model.hasLoaded && !model.hasLoadFailed))

    private fun loadComposeHints() {
        val language = LocaleController.activeLanguage.langCode
        composeHintsCache?.takeIf {
            it.language == language &&
                SystemClock.elapsedRealtime() - it.loadedAtMs < COMPOSE_HINTS_TTL_MS
        }?.let {
            composeSuggestionsHints = it.hints
            hasComposeHintsSettled = true
            return
        }
        if (composeHintsJob?.isActive == true) return
        composeHintsJob = scope.launch {
            val hints = try {
                client.hints(language).items.mapNotNull { localizedAgentV2Hint(it.id) }
                    .take(COMPOSE_HINTS_LIMIT)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Throwable) {
                // Contact Support shows without the suggestions
                if (!hasComposeHintsSettled) {
                    hasComposeHintsSettled = true
                    updateComposeSuggestions(WGlobalStorage.getAreAnimationsActive())
                }
                return@launch
            }
            composeHintsCache = ComposeHints(language, hints, SystemClock.elapsedRealtime())
            composeSuggestionsHints = hints
            hasComposeHintsSettled = true
            updateComposeSuggestions(WGlobalStorage.getAreAnimationsActive())
        }
    }

    private var isComposeHeaderShown = false

    private fun updateComposeHeader(isAnimated: Boolean) {
        val shouldShow = isComposeShown && barHost != null
        if (shouldShow == isComposeHeaderShown) return
        isComposeHeaderShown = shouldShow
        if (shouldShow) {
            val bar = applyComposeHeader() ?: return
            bar.animate().cancel()
            if (isAnimated) {
                bar.alpha = 0f
                bar.animate().alpha(1f).setDuration(COMPOSE_FADE_MS).start()
            } else {
                bar.alpha = 1f
            }
        } else {
            val bar = navigationBar ?: return
            bar.animate().cancel()
            if (isAnimated) {
                bar.animate().alpha(0f).setDuration(COMPOSE_FADE_MS)
                    .withEndAction(::restoreRootHeader)
                    .start()
            } else {
                restoreRootHeader()
            }
        }
    }

    // The list's own bar, laid out as a chat's header in the place of the root's tabs
    private fun applyComposeHeader(): WNavigationBar? {
        setupNavBar(true)
        val bar = navigationBar ?: return null
        bar.setTitleContentVisible(true)
        bar.setTitleGravity(Gravity.CENTER)
        bar.titleLabel.setStyle(COMPOSE_TITLE_SIZE, WFont.Medium)
        setNavTitle(LocaleController.getString("New Chat"), animated = false)
        if (composeBackButton.parent == null) {
            bar.addLeadingView(composeBackButton, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        }
        // A root screen's bar reaches below the tabs' band; the header goes where a chat's does
        bar.translationY = -(navigationController?.additionalRootTopInset ?: 0).toFloat()
        // A tap on the header ends composing, as anywhere else outside the field
        bar.setOnClickListener { endComposing() }
        // The root's top gradient fades the list under the header, not the header's title and arrow
        bar.bringToFront()
        return bar
    }

    private fun restoreRootHeader() {
        if (isComposeHeaderShown) return
        navigationBar?.let { bar ->
            bar.alpha = 1f
            bar.translationY = 0f
            bar.setOnClickListener {
                navigationController?.viewControllers?.lastOrNull()?.scrollToTop()
            }
        }
        setupNavBar(!isRootTopGradientEnabled)
        navigationBar?.setTitleContentVisible(!isRootTopGradientEnabled)
        updateTitle()
    }

    /**
     * How far the toolbar has turned into the list's bar: at 0 the bar is gone into the toolbar's field and button,
     * at 1 it rests beside the search circle. The field appears in the second half and swells with the morph.
     */
    fun setHostedBarProgress(progress: Float) {
        hostedBarProgress = progress
        if (!isViewConfigured || barHost == null) return
        val clamped = progress.coerceIn(0f, 1f)
        val appearance = ((clamped - BAR_APPEAR_START) / (1 - BAR_APPEAR_START)).coerceIn(0f, 1f)
        val swell = (1 + BAR_SWELL * 4 * progress * (1 - progress)).coerceIn(0.9f, 1.2f)
        // The microphone's circle comes with the field where the toolbar's "+" folds away, swelling as it does
        composer.setHostedMorph(appearance, swell, BAR_GROW_FROM)
        if (!composer.isGone) composer.isInvisible = appearance <= 0f
    }

    /**
     * Keeps the hosted bar on the root's toolbar while the list's page slides under it in paging: [shift] undoes the
     * page's offset
     */
    fun setHostedBarShift(shift: Float) {
        if (!isViewConfigured) return
        composer.translationX = if (barHost != null) shift else 0f
    }

    private fun resetHostedBar() {
        composer.translationX = 0f
        composer.setHostedMorph(1f, 1f, 1f)
        if (!composer.isGone) composer.isInvisible = false
    }

    // Opens the global search from the root toolbar's search circle
    fun openSearchFromBar() = openSearch()

    private fun updateBarExpansion() {
        // Over a hosting toolbar's circle the field also widens while composing and under a chat
        val isHostedWide = barHost != null &&
            (isComposerFocused || isComposedChatPending || isBarCovered)
        val isWide = isHostedWide || composer.isFieldInUse
        val target = if (hasSearchCircle && isWide) 1f else 0f
        barExpansionAnimator?.cancel()
        barExpansionAnimator = null
        if (barExpansion == target) return
        if (!WGlobalStorage.getAreAnimationsActive() || !isViewConfigured) {
            barExpansion = target
            if (isViewConfigured) {
                insetsUpdated()
                applySearchSlide()
            }
            return
        }
        barExpansionAnimator = ValueAnimator.ofFloat(barExpansion, target).apply {
            duration = BAR_EXPANSION_MS
            interpolator = BAR_EXPANSION_SPRING
            addUpdateListener {
                barExpansion = it.animatedValue as Float
                applyBarFieldStart()
                applySearchSlide()
                followBarInCoveringChat()
            }
            doOnEnd {
                insetsUpdated()
                followBarInCoveringChat()
            }
            start()
        }
    }

    override fun onDestroy() {
        composeCoverAnimator?.cancel()
        dustEffect?.kill()
        dustEffect = null
        dictation.cancel()
        scope.cancel()
        readState.removeListener(readStateListener)
        WalletCore.unregisterObserver(this)
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        super.onDestroy()
    }

    fun openNewChat(prompt: String? = null, entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()) {
        pushNewChat(prompt, entryPoint, sentSource = null)
    }

    // A question sent from the list grows into the chat's first bubble out of [sentSource] as the
    // chat slides in
    private fun pushNewChat(
        prompt: String?,
        entryPoint: AgentV2EntryPoint,
        sentSource: AgentSentMessageSource?
    ) {
        requestConsent {
            navigationController?.push(
                if (prompt.isNullOrBlank()) {
                    AgentNewChatVC(context)
                } else {
                    val chat = AgentVC(context, prompt = AgentPromptChatRequest(prompt, entryPoint))
                    sentSource?.let { handOverSentSource(chat, it, AnimationConstants.NAV_PUSH) }
                    chat
                }
            )
        }
    }

    /** Contact Support asks before it opens the chat support has, or a new chat that calls an operator */
    private fun presentSupportRequest() {
        if (!canRequestSupportFromList) return
        dictation.cancel()
        AgentSupportRequestConfirmation(hasConsent, ::requestSupport).present(this)
    }

    // Before consent no chat can have support yet: the chat is chosen from the server's chats, which load once the
    // user allows the Agent
    private fun requestSupport() {
        if (!canRequestSupportFromList) return
        requestConsent {
            model.requestSupportThread(::openSupportChat)
        }
    }

    private fun openSupportChat(thread: AgentV2ThreadSummary?) {
        val navigation = navigationController ?: return
        if (isDestroyed || navigation.viewControllers.lastOrNull() !== this) return
        composer.hideKeyboard()
        navigation.push(
            if (thread != null) {
                AgentVC(context, thread)
            } else {
                AgentVC(
                    context,
                    prompt = AgentPromptChatRequest(
                        getAgentSupportRequestText(),
                        AgentV2EntryPoint.supportRequest(AgentV2SupportRequestSource.STARTER_HINT)
                    )
                )
            }
        )
    }

    private fun openNews(cell: AgentNewsCell) {
        closeSwipes(except = null)
        val navigation = navigationController ?: return
        val language = LocaleController.activeLanguage.langCode
        cell.rowView.shouldHoldHighlight = true
        val isPageInLanguage = newsModel.itemsLanguage == language
        navigation.push(
            AgentNewsFeedVC(
                context,
                findThread = threadFinder,
                initialItems = newsModel.items.takeIf { isPageInLanguage }.orEmpty(),
                initialDigests = newsModel.currentDigests.takeIf { isPageInLanguage }.orEmpty()
            )
        ) {
            cell.rowView.shouldHoldHighlight = false
        }
    }

    private fun openThread(thread: AgentV2ThreadSummary, cell: AgentThreadCell) {
        closeSwipes(except = null)
        val navigation = navigationController ?: return
        // The tapped row stays lit until the chat has slid in over it
        cell.rowView.shouldHoldHighlight = true
        val chat = AgentVC(context, thread, isSummaryCached = model.isCacheShown)
        navigation.push(chat) {
            cell.rowView.shouldHoldHighlight = false
            finishChatTakeover(chat)
        }
        beginChatTakeover(chat)
    }

    /**
     * A chat comes over the list and takes the bar's field as its composer: the composer lies over the bar while the
     * field widens to it, so the two show as one field
     */
    private fun beginChatTakeover(chat: AgentVC) {
        coveringChat = WeakReference(chat)
        isChatTakingOver = barHost != null
        followBarInCoveringChat()
    }

    private fun finishChatTakeover(chat: AgentVC) {
        if (coveringChat?.get() !== chat) return
        isChatTakingOver = false
        chat.setComposerHandoff(null)
    }

    // The covering chat's composer starts where the bar's field does while the bar carries the field
    private fun followBarInCoveringChat() {
        if (!isChatTakingOver) return
        coveringChat?.get()?.setComposerHandoff(computeBarFieldStart())
    }

    private fun openSearch() {
        dictation.cancel()
        closeSwipes(except = null)
        val tabs = navigationController?.tabBarController ?: return
        isAgentSearchOpen = tabs.openAgentSearch {
            isAgentSearchOpen = false
            updateBarVisibility()
        }
        updateBarVisibility()
    }

    private fun checkConsent() {
        if (hasConsent || consentJob?.isActive == true || isDestroyed) return
        // The list keeps what it showed while it asks again, as each time it comes back before consent
        if (!hasConsentResult) updateChrome()
        consentJob = scope.launch {
            try {
                showConsentResult(readConsent())
            } finally {
                consentJob = null
            }
        }
    }

    private suspend fun readConsent(): Boolean = try {
        client.consent()
    } catch (error: CancellationException) {
        throw error
    } catch (_: Throwable) {
        false
    }

    // The sheet takes the keyboard's place without ending composing
    private var isAskingForConsent = false

    // What the user does that sends something to the Agent waits for their consent, asked in a sheet
    private val consentGate = AgentConsentGate(
        knownConsent = { hasConsent.takeIf { hasConsentResult } },
        readConsent = ::readConsent,
        askForConsent = { onAllowed, onDeclined ->
            if (isDestroyed) {
                onDeclined()
            } else {
                isAskingForConsent = true
                AgentConsentSheetVC.present(
                    this,
                    onAllowed = {
                        isAskingForConsent = false
                        onAllowed()
                    },
                    onDeclined = {
                        isAskingForConsent = false
                        onDeclined()
                    }
                )
            }
        },
        onAllowed = { showConsentResult(true) }
    )

    private fun requestConsent(isFromKeyboard: Boolean = false, action: () -> Unit) {
        if (hasConsent) return action()
        scope.launch {
            consentGate.request(
                onDeclined = {
                    // Closing the sheet gives the keyboard back to a question sent from it; anything else ends
                    // composing, as the keyboard going does
                    if (isFromKeyboard) composer.focusInputWithKeyboard() else composer.clearFocus()
                },
                action = action
            )
        }
    }

    private fun showConsentResult(isAllowed: Boolean) {
        hasConsent = isAllowed
        hasConsentResult = true
        updateChrome()
        refresh()
    }

    // The News row shows the latest of the feed's view as soon as it switches
    private fun observeNewsView() {
        scope.launch {
            val settings = AgentNewsNotificationSettings.shared
            settings.state.map { settings.newsView }.distinctUntilChanged().drop(1).collect {
                updateRows(AgentThreadListChange.DATA)
                newsModel.refresh()
            }
        }
    }

    // The News load whatever the consent; the chats come with it
    private fun refresh() {
        newsModel.refresh()
        if (!hasConsent) return
        model.syncActivities(AgentSession.getLoadedChats())
        model.refresh()
    }

    // The list refreshes every 30 s while it is on screen and the app is active
    private fun startRefreshTimer() {
        refreshJob?.cancel()
        refreshJob = scope.launch {
            while (isActive) {
                delay(REFRESH_INTERVAL_MS)
                if (hasConsentResult && isAppActive && !isDisappeared) refresh()
            }
        }
    }

    // Rows

    // The News row shows before consent as after it; the chats come with the consent
    private fun buildRows(): List<AgentThreadListRow> = buildList {
        if (!hasConsentResult) return@buildList
        // In the Digests view the row shows the latest digest, or the latest news until a digest has come
        val isDigestsView = newsModel.newsView == AgentNewsFeedView.Digests
        val latestDigest = newsModel.latestDigest.takeIf { isDigestsView }
        add(AgentThreadListRow.News(newsModel.latestItem, latestDigest, newsModel.unreadCount))
        if (!hasConsent || !model.hasLoaded) return@buildList
        val locale = Locale.forLanguageTag(LocaleController.activeLanguage.langCode)
        val now = Date()
        groupAgentThreads(model.items).forEach { section ->
            val title = section.day?.let { day ->
                AgentThreadDateFormatting.formatHeaderText(
                    Date(day),
                    now,
                    today = LocaleController.getString("Today"),
                    yesterday = LocaleController.getString("Yesterday"),
                    locale = locale
                )
            } ?: LocaleController.getString("Pinned")
            add(AgentThreadListRow.Header(section.day?.toString() ?: PINNED_SECTION_KEY, title))
            section.items.forEach { add(AgentThreadListRow.Thread(it, title)) }
        }
        if (model.hasPageLoadFailed && model.items.isNotEmpty()) add(AgentThreadListRow.PageFailure)
    }

    private fun updateRows(change: AgentThreadListChange) {
        if (dustPendingChange != null) {
            if (change == AgentThreadListChange.USER) dustPendingChange = change
            return
        }
        val newRows = buildRows()
        if (dissolveDeletedRows(newRows, change)) return
        applyRows(newRows, change)
    }

    /**
     * Turns the rows of the chats the user deleted that [newRows] no longer has to dust, and applies the rows once the
     * dust stands in their place. Returns false when there is nothing to turn to dust, or the dust can't run.
     */
    private fun dissolveDeletedRows(
        newRows: List<AgentThreadListRow>,
        change: AgentThreadListChange
    ): Boolean {
        val newKeys = newRows.mapTo(HashSet()) { it.key }
        val removedIds = rows.filterIsInstance<AgentThreadListRow.Thread>()
            .filter { it.key !in newKeys }
            .mapTo(HashSet()) { it.item.thread.id }
        val deletedIds = deletingThreadIds.intersect(removedIds)
        deletingThreadIds.removeAll(removedIds)
        if (deletedIds.isEmpty() || !canDissolveRows) return false
        val views = rows.withIndex()
            .filter { (position, row) ->
                (row is AgentThreadListRow.Thread && row.item.thread.id in deletedIds) ||
                    isSectionLeaving(position, newKeys, deletedIds)
            }
            .mapNotNull { (position, _) -> listLayoutManager.findViewByPosition(position) }
        if (views.isEmpty()) return false
        dustPendingChange = change
        val effect = dustEffect?.takeIf { it.isActive } ?: AgentDustEffect(context) { finished ->
            (finished.parent as? ViewGroup)?.removeView(finished)
            if (dustEffect === finished) dustEffect = null
        }.also { effect ->
            effect.id = View.generateViewId()
            view.addView(
                effect,
                view.indexOfChild(recyclerView) + 1,
                ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
            dustEffect = effect
        }
        effect.dissolve(
            recyclerView,
            views,
            onStarted = {
                if (dustPendingChange == null) return@dissolve
                if (!isViewConfigured) {
                    dustPendingChange = null
                    return@dissolve
                }
                // A recycled row shows again once bound to the chat or the title it takes next
                views.forEach { it.visibility = View.INVISIBLE }
                // The deleted chat's place holds while most of its dust drifts off, as the web holds a removed
                // message's, so the rows that stay don't run into it
                val closeGap = Runnable {
                    val pending = dustPendingChange ?: return@Runnable
                    dustPendingChange = null
                    if (isViewConfigured) applyRows(buildRows(), pending)
                }
                recyclerView.postDelayed(closeGap, DISSOLVED_GAP_CLOSE_DELAY_MS)
            },
            onDone = {}
        )
        return true
    }

    // A section's title goes with the last of its chats
    private fun isSectionLeaving(
        position: Int,
        newKeys: Set<String>,
        deletedIds: Set<String>
    ): Boolean {
        val header = rows[position] as? AgentThreadListRow.Header ?: return false
        return header.key !in newKeys && rows.drop(position + 1)
            .takeWhile { it is AgentThreadListRow.Thread }
            .all { (it as AgentThreadListRow.Thread).item.thread.id in deletedIds }
    }

    private fun applyRows(newRows: List<AgentThreadListRow>, change: AgentThreadListChange) {
        val oldRows = rows
        val isReveal = !hasRevealedThreads && model.hasLoaded
        val shouldAnimate = WGlobalStorage.getAreAnimationsActive()
        itemAnimator.mode = when {
            !shouldAnimate -> AgentThreadListItemAnimator.Mode.INSTANT
            isReveal -> AgentThreadListItemAnimator.Mode.INSTANT
            change == AgentThreadListChange.USER -> AgentThreadListItemAnimator.Mode.SPRING
            else -> AgentThreadListItemAnimator.Mode.INSTANT
        }
        // A change that comes with the data keeps the first visible row that stays where it is on screen
        val anchor = if (itemAnimator.mode == AgentThreadListItemAnimator.Mode.INSTANT) {
            captureAnchor(oldRows, newRows)
        } else {
            null
        }
        rows = newRows
        if (itemAnimator.mode == AgentThreadListItemAnimator.Mode.SPRING) {
            listDecoration.easeBottomOnNextChange()
        }
        threadsAdapter.applyChanges(oldRows, newRows, 0, false, shouldDetectMoves = true)
        anchor?.let { (position, offset) ->
            listLayoutManager.scrollToPositionWithOffset(position, offset)
        }
        if (isReveal) {
            hasRevealedThreads = true
            revealThreads(shouldAnimate)
        }
        updateChrome()
    }

    // The first visible row whose place in the order does not change, and its offset under the top inset
    private fun captureAnchor(
        oldRows: List<AgentThreadListRow>,
        newRows: List<AgentThreadListRow>
    ): Pair<Int, Int>? {
        if (oldRows.isEmpty()) return null
        val newIndexes = newRows.withIndex().associate { (index, row) -> row.key to index }
        val first = listLayoutManager.findFirstVisibleItemPosition()
        val last = listLayoutManager.findLastVisibleItemPosition()
        if (first == RecyclerView.NO_POSITION) return null
        for (position in first..last) {
            val row = oldRows.getOrNull(position) ?: continue
            val newIndex = newIndexes[row.key] ?: continue
            if (row is AgentThreadListRow.Thread) {
                val updated = newRows[newIndex] as AgentThreadListRow.Thread
                if (agentThreadActivityDate(updated.item.thread) !=
                    agentThreadActivityDate(row.item.thread) ||
                    updated.item.thread.isPinned != row.item.thread.isPinned
                ) {
                    continue
                }
            }
            val rowView = listLayoutManager.findViewByPosition(position) ?: continue
            return newIndex to (rowView.top - recyclerView.paddingTop)
        }
        return null
    }

    private fun revealThreads(isAnimated: Boolean) {
        skeletonView.animate().cancel()
        recyclerView.animate().cancel()
        if (!isAnimated) {
            recyclerView.alpha = 1f
            skeletonView.isGone = true
            return
        }
        recyclerView.animate().alpha(1f).setDuration(REVEAL_DURATION_MS).start()
        skeletonView.animate().alpha(0f).setDuration(REVEAL_DURATION_MS).withEndAction {
            skeletonView.isGone = true
        }.start()
    }

    private fun getSectionTitle(position: Int): String? =
        when (val row = rows.getOrNull(position)) {
            is AgentThreadListRow.Header -> row.title
            is AgentThreadListRow.Thread -> row.sectionTitle
            else -> null
        }

    private fun updateActivities(threadIds: Set<String>) {
        forEachVisibleThreadCell { cell, item ->
            if (item.thread.id in threadIds && !isLeaving(item.thread.id)) {
                cell.setActivity(model.getActivityText(item.thread.id), model.isUnread(item.thread))
            }
        }
    }

    private fun reconfigureVisibleRows() {
        forEachVisibleThreadCell { cell, item ->
            if (isLeaving(item.thread.id)) return@forEachVisibleThreadCell
            cell.setActivity(model.getActivityText(item.thread.id), model.isUnread(item.thread))
        }
    }

    private fun forEachVisibleThreadCell(block: (AgentThreadCell, AgentV2ThreadListItem) -> Unit) {
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val cell = child as? AgentThreadCell ?: continue
            val position = recyclerView.getChildAdapterPosition(child)
            val row = rows.getOrNull(position) as? AgentThreadListRow.Thread ?: continue
            block(cell, row.item)
        }
    }

    // The row of a chat being deleted, or gone from the list, keeps its status and unread dot, which its deletion
    // clears just before the row leaves, so it turns to dust as it stood
    private fun isLeaving(threadId: String) =
        threadId in deletingThreadIds || model.items.none { it.thread.id == threadId }

    private fun closeSwipes(except: AgentThreadCell?) {
        for (index in 0 until recyclerView.childCount) {
            val cell = recyclerView.getChildAt(index) as? AgentThreadCell ?: continue
            if (cell !== except) cell.closeSwipe(isAnimated = true)
        }
    }

    // Chrome

    private fun updateChrome() {
        recyclerView.visibility = when {
            !hasConsentResult -> View.GONE
            hasConsent && !hasRevealedThreads -> View.INVISIBLE
            else -> View.VISIBLE
        }
        // Once the chats are revealed, the placeholder hides as it finishes fading out
        if (!hasConsent) {
            skeletonView.animate().cancel()
            skeletonView.isGone = true
        } else if (!hasRevealedThreads) {
            recyclerView.animate().cancel()
            recyclerView.alpha = 0f
            skeletonView.animate().cancel()
            skeletonView.alpha = 1f
            skeletonView.isVisible = true
        }
        loadMoreSpinner.isVisible = hasConsent && model.isLoading && model.nextCursor != null &&
            model.hasLoaded
        loadErrorView.setError(
            LocaleController.getString("\$agent_chats_unavailable").takeIf {
                hasConsent && model.hasLoadFailed && model.items.isEmpty()
            }
        )
        updateBarVisibility()
        updatePlaceholderFrames()
        updateComposeState()
    }

    /** The list shows its bar: the list knows whether the Agent is allowed, and no search is open over it */
    val isBarShown: Boolean get() = hasConsentResult && !isAgentSearchOpen
    private var hasBarBeenShown: Boolean? = null

    private fun updateBarVisibility() {
        val isBarShown = isBarShown
        composer.isGone = !isBarShown
        // A hosting toolbar draws the search circle
        searchButton.isGone = !isBarShown || barHost != null ||
            navigationController?.tabBarController?.isAgentSearchSupported != true
        searchGlass?.isGone = searchButton.isGone
        applySearchSlide()
        bottomGradientView.isGone = !hasConsentResult
        if (isBarShown && barHost != null) setHostedBarProgress(hostedBarProgress)
        // Without its bar, as before the list knows the consent, the list needs no toolbar
        if (hasBarBeenShown != isBarShown) {
            hasBarBeenShown = isBarShown
            barHost?.onAgentBarStateChanged()
        }
    }

    private fun updatePlaceholderFrames() {
        view.setConstraints {
            toTopPx(skeletonView, recyclerView.paddingTop)
            toStartPx(skeletonView, recyclerView.paddingStart)
            toEndPx(skeletonView, recyclerView.paddingEnd)
            // In the middle of the list's content, between its top and the field
            toTopPx(loadErrorView, recyclerView.paddingTop)
            toBottomPx(loadErrorView, recyclerView.paddingBottom)
            toStartPx(loadErrorView, recyclerView.paddingStart + LOAD_ERROR_SIDE_INSET.dp)
            toEndPx(loadErrorView, recyclerView.paddingEnd + LOAD_ERROR_SIDE_INSET.dp)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.background = WColor.SecondaryBackground.color.toDrawable()
        searchGlass?.updateTheme()
        searchIcon.setColorFilter(WColor.SecondaryText.color)
        searchButtonRipple.rippleColor = WColor.BackgroundRipple.color
        searchButton.setBackgroundColor(Color.TRANSPARENT, BAR_HEIGHT.dp / 2f, true)
        composer.updateTheme()
        skeletonView.updateTheme()
        loadErrorView.updateTheme()
        val page = WColor.SecondaryBackground.color
        bottomGradientView.background = GradientShaderDrawable(
            intArrayOf(page.colorWithAlpha(0), page.colorWithAlpha(BOTTOM_FADE_ALPHA)),
            floatArrayOf(0f, BOTTOM_FADE_STOP)
        )
        threadsAdapter.updateTheme()
    }

    // A chat pushed over the list leaves it where it was, under the root's tabs
    override val shouldKeepRootInsetWhenCovered: Boolean
        get() = true

    // The bar on the root's toolbar keeps its line while a chat is swiped away over the list
    override val shrinksUnderSwipeBack: Boolean
        get() = barHost == null

    override fun insetsUpdated() {
        super.insetsUpdated()
        val top = (navigationController?.getSystemBars(this)?.top ?: 0) +
            if (isRootTopGradientEnabled) 0 else WNavigationBar.DEFAULT_HEIGHT.dp
        val bottom = navigationController?.getSystemBars()?.bottom ?: 0
        val keyboard = navigationController?.imeInsetBottom ?: 0
        // The keyboard going away, by Back or its own key, ends composing, as the field resigning does on iOS
        val isKeyboardShown = keyboard > 0 || isFloatingKeyboardShown()
        if (hasKeyboardBeenShown && !isKeyboardShown && isComposerFocused &&
            isKeyboardDismissal() && !isAskingForConsent
        ) {
            composer.clearFocus()
        }
        hasKeyboardBeenShown = isKeyboardShown
        val host = barHost
        // A hosted field rests where the toolbar's field does, which also rides the keyboard
        val composerBottom = if (host != null) {
            (host.agentBarBottomInset - composer.paddingBottom).coerceAtLeast(0)
        } else {
            maxOf(bottom, keyboard)
        }
        val sideStart = additionalTabletPadding + systemBarStartInset
        val sideEnd = systemBarEndInset
        val gutter = ViewConstants.HORIZONTAL_PADDINGS.dp
        // The field starts after the search circle, as the root toolbar's field does, and widens over it
        val fieldStart = computeBarFieldStart()
        val frame =
            BarFrame(top, bottom, sideStart, sideEnd, fieldStart, composer.height, host != null)
        if (frame == laidOutBar) {
            // Only the field's line moved, as it rides the keyboard: move what follows it
            if (composerBottom != laidOutComposerBottom) moveBar(composerBottom)
            return
        }
        laidOutBar = frame
        laidOutComposerBottom = composerBottom
        view.setConstraints {
            toStartPx(searchButton, sideStart + BAR_SIDE_INSET.dp)
            bottomToBottomPx(searchButton, composer, composer.paddingBottom)
            toStartPx(composer, sideStart + fieldStart)
            toEndPx(composer, sideEnd)
            toBottomPx(composer, composerBottom)
            toStartPx(bottomGradientView, sideStart)
            toEndPx(bottomGradientView, sideEnd)
        }
        bottomGradientView.layoutParams = bottomGradientView.layoutParams.apply {
            height = composerBottom + composer.height + BOTTOM_FADE_EXTRA.dp
        }
        recyclerView.setPaddingLocalized(
            sideStart + gutter,
            top + ROOT_LIST_TOP_GAP.dp,
            sideEnd + gutter,
            composerBottom + composer.height + LIST_BOTTOM_GAP.dp
        )
        listDecoration.stickyTop = if (isRootTopGradientEnabled) rootTopBarBottom else top
        updateBlurViews(recyclerView)
        updatePlaceholderFrames()
        bringBarToFront()
    }

    private data class BarFrame(
        val top: Int,
        val bottom: Int,
        val sideStart: Int,
        val sideEnd: Int,
        val fieldStart: Int,
        val composerHeight: Int,
        val isHosted: Boolean
    )

    private var laidOutBar: BarFrame? = null
    private var laidOutComposerBottom = 0

    private val hasSearchCircle: Boolean
        get() = barHost != null ||
            navigationController?.tabBarController?.isAgentSearchSupported == true

    // The field starts after the search circle, as the root toolbar's field does, and widens over it
    private fun computeBarFieldStart(): Int {
        if (!hasSearchCircle) return 0
        val circleStart = (BAR_SIDE_INSET + BAR_HEIGHT + BAR_GAP).dp - composer.paddingStart
        return (circleStart * (1 - barExpansion)).roundToInt()
    }

    private fun moveBar(composerBottom: Int) {
        laidOutComposerBottom = composerBottom
        (composer.layoutParams as? ConstraintLayout.LayoutParams)?.let {
            it.bottomMargin = composerBottom
            composer.layoutParams = it
        }
        bottomGradientView.layoutParams = bottomGradientView.layoutParams.apply {
            height = composerBottom + composer.height + BOTTOM_FADE_EXTRA.dp
        }
        recyclerView.updatePadding(bottom = composerBottom + composer.height + LIST_BOTTOM_GAP.dp)
    }

    // The field widens over the circle by its start margin alone
    private fun applyBarFieldStart() {
        val frame = laidOutBar
        val composerParams = composer.layoutParams as? ConstraintLayout.LayoutParams
        if (frame == null || composerParams == null) {
            insetsUpdated()
            return
        }
        val fieldStart = computeBarFieldStart()
        composerParams.marginStart = frame.sideStart + fieldStart
        composer.layoutParams = composerParams
        laidOutBar = frame.copy(fieldStart = fieldStart)
    }

    // The list's own search circle slides off toward the start as the field widens over it, as Telegram's attach button
    // does; a hosting toolbar moves its own
    private fun applySearchSlide() {
        if (barHost != null) return
        val travel = (BAR_SIDE_INSET + BAR_HEIGHT).dp * barExpansion
        val shift = if (LocaleController.isRTL) travel else -travel
        val alpha = 1 - barExpansion
        searchButton.translationX = shift
        searchButton.alpha = alpha
        searchGlass?.translationX = shift
        searchGlass?.alpha = alpha
        if (!searchButton.isGone) searchButton.isInvisible = barExpansion >= 1f
    }

    override fun updateBlurViews(recyclerView: RecyclerView) {
        if (window?.isWideLayout == true) {
            topReversedCornerView?.setBlurAlpha(1f)
            return
        }
        super.updateBlurViews(recyclerView)
    }

    override fun onRootTopGradientModeChanged(enabled: Boolean) {
        if (isComposeHeaderShown) {
            // The new chat's header stays while a question is written
            applyComposeHeader()
        } else {
            setupNavBar(!enabled)
            updateTitle()
        }
        if (isViewConfigured) insetsUpdated()
    }

    override fun onBackPressed(): Boolean {
        // Back ends composing before it leaves the tab
        if (isComposeShown) {
            endComposing()
            return false
        }
        return super.onBackPressed()
    }

    private fun bringBarToFront() {
        bottomGradientView.bringToFront()
        loadMoreSpinner.bringToFront()
        searchGlass?.bringToFront()
        searchButton.bringToFront()
        composer.bringToFront()
        // The root's top gradient stays over the list, and under a new chat's header
        if (isRootTopGradientEnabled) topReversedCornerView?.bringToFront()
        if (window?.isWideLayout == true) {
            topReversedCornerView?.bringToFront()
            navigationBar?.bringToFront()
        } else if (isComposeHeaderShown) {
            navigationBar?.bringToFront()
        }
    }

    private fun updateTitle() {
        setNavTitle(
            if (isRootTopGradientEnabled) "" else LocaleController.getString("Agent"),
            false
        )
    }

    override fun scrollToTop() {
        recyclerView.smoothScrollToPosition(0)
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AppForeground -> {
                isAppActive = true
                if (hasConsentResult && !isDisappeared) refresh()
            }

            WalletEvent.AppBackground -> {
                isAppActive = false
                dictation.onAppBackground()
            }

            WalletEvent.AccountsReset -> {
                hasConsent = false
                hasConsentResult = false
                hasRevealedThreads = false
                consentJob?.cancel()
                dictation.cancel()
                model.reset()
                AgentSession.forgetRecentChats()
                LiveAgentV2Client.forgetKnownConsent()
            }

            is WalletEvent.AgentThreadDeleted -> model.removeDeletedThread(walletEvent.threadId)

            else -> Unit
        }
    }

    override fun onBridgeUpdate(update: ApiUpdate) {
        val agentUpdate = (update as? ApiUpdate.ApiUpdateAgentV2)?.update ?: return
        model.handleUpdate(agentUpdate)
        if (!hasConsent || isDisappeared) return
        when (agentUpdate) {
            is AgentV2Update.ThreadChanged -> model.applyThreadChange(agentUpdate.thread)

            // The answer's preview comes with the list
            is AgentV2Update.MessageCompleted -> model.refresh()

            else -> Unit
        }
    }

    // Thread actions

    private fun showMenu(cell: AgentThreadCell, thread: AgentV2ThreadSummary) {
        dictation.cancel()
        closeSwipes(except = null)
        val isPinned = thread.isPinned == true
        cell.isMenuShown = true
        WMenuPopup.present(
            cell.rowView,
            listOf(
                WMenuPopup.Item(R.drawable.ic_pen, LocaleController.getString("Rename")) {
                    showRename(thread)
                }.apply { testViewId = UIComponentsR.id.agent_thread_menu_rename },
                WMenuPopup.Item(
                    if (isPinned) R.drawable.ic_unpin_30 else R.drawable.ic_pin_30,
                    LocaleController.getString(if (isPinned) "Unpin" else "Pin")
                ) { model.setPinned(thread, !isPinned) }.apply {
                    testViewId = UIComponentsR.id.agent_thread_menu_pin
                },
                WMenuPopup.Item(
                    WMenuPopup.Item.Config.Item(
                        WMenuPopup.Item.Config.Icon(R.drawable.ic_remove, WColor.Red),
                        LocaleController.getString("Delete"),
                        WColor.Red.color
                    )
                ) { showDeleteConfirmation(thread) }.apply {
                    testViewId = UIComponentsR.id.agent_thread_menu_delete
                }
            ),
            popupWidth = MENU_WIDTH.dp,
            positioning = WMenuPopup.Positioning.BELOW,
            // A row near the bottom opens its menu above it
            aboveFallbackYOffset = 0,
            isAlignedToEnd = true,
            windowBackgroundStyle = buildMenuCutout(cell.rowView),
            backdropStyle = WMenuPopup.BackdropStyle.BlurDimmed,
            onDidDismiss = { cell.isMenuShown = false }
        )
    }

    // The row stays sharp over the blur as a rounded card, cut where the top bar or the composer covers it
    private fun buildMenuCutout(rowView: View): WMenuPopup.BackgroundStyle.Cutout {
        val rowTop = rowView.getLocationInWindow().y
        val rowBottom = rowTop + rowView.height
        val listTop = recyclerView.getLocationInWindow().y + recyclerView.paddingTop
        val listBottom = if (composer.isVisible) {
            composer.getLocationInWindow().y
        } else {
            recyclerView.getLocationInWindow().y + recyclerView.height
        }
        return WMenuPopup.BackgroundStyle.Cutout(
            rowView.frameAsPath(
                roundRadius = AgentThreadRowMetrics.CARD_RADIUS.dp,
                topOffset = minOf(0, rowTop - listTop).toFloat(),
                bottomOffset = minOf(0, listBottom - rowBottom).toFloat()
            )
        )
    }

    private fun showRename(thread: AgentV2ThreadSummary) {
        val input = WEditText(context, null, false).apply {
            isSingleLine = true
            setPadding(12.dp, 10.dp, 12.dp, 10.dp)
            setBackgroundColor(WColor.SecondaryBackground.color, 10f.dp)
            setText(thread.title.orEmpty())
            hint = LocaleController.getString("New Chat")
            setSelection(length())
            inputType = EditorInfo.TYPE_CLASS_TEXT or EditorInfo.TYPE_TEXT_FLAG_CAP_SENTENCES
        }
        val container = WFrameLayout(context).apply {
            setPadding(24.dp, 0, 24.dp, 0)
            addView(input, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        WDialog(
            container,
            WDialog.Config(
                title = LocaleController.getString("Rename Chat"),
                actionButton = WDialogButton.Config(LocaleController.getString("Save"), {
                    model.rename(thread, input.text?.toString().orEmpty())
                }),
                secondaryButton = WDialogButton.Config(
                    LocaleController.getString("Cancel"),
                    null,
                    WDialogButton.Config.Style.NORMAL
                )
            )
        ).presentOn(this)
    }

    private fun showDeleteConfirmation(thread: AgentV2ThreadSummary) {
        showAlert(
            LocaleController.getString("Delete Chat?"),
            LocaleController.getString("\$agent_delete_chat_confirmation"),
            button = LocaleController.getString("Delete"),
            buttonPressed = {
                deletingThreadIds.add(thread.id)
                model.delete(thread) {
                    // A chat whose deletion failed stays, and its row shows its status and unread dot again
                    if (deletingThreadIds.remove(thread.id)) reconfigureVisibleRows()
                }
            },
            secondaryButton = LocaleController.getString("Cancel"),
            primaryIsDanger = true
        )
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

    private fun errorText(error: Throwable) = agentV2ErrorText(
        (error as? AgentV2OperationException)?.error?.code ?: error.message
    )

    private fun showOperationError(error: Throwable) = showToast(errorText(error))

    private fun showToast(text: String) {
        Toast.makeText(context, text, Toast.LENGTH_SHORT).show()
    }

    // WRecyclerViewDataSource

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int) = rows.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath) =
        when (rows[indexPath.row]) {
            is AgentThreadListRow.News -> NEWS_CELL
            is AgentThreadListRow.Header -> HEADER_CELL
            is AgentThreadListRow.Thread -> THREAD_CELL
            AgentThreadListRow.PageFailure -> FAILURE_CELL
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> AgentThreadSectionCell(context)
            NEWS_CELL -> AgentNewsCell(context)
            FAILURE_CELL -> AgentSystemMessageCell(context)
            else -> AgentThreadCell(context)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val uses24HourTime = DateFormat.is24HourFormat(context)
        when (val row = rows[indexPath.row]) {
            is AgentThreadListRow.News -> (cellHolder.cell as AgentNewsCell).apply {
                configure(row.latest, row.latestDigest, row.unreadCount, uses24HourTime)
                onTap = { openNews(this) }
            }

            is AgentThreadListRow.Header -> (cellHolder.cell as AgentThreadSectionCell).apply {
                visibility = View.VISIBLE
                configure(row.title)
            }

            is AgentThreadListRow.Thread -> (cellHolder.cell as AgentThreadCell).apply {
                val thread = row.item.thread
                visibility = View.VISIBLE
                configure(
                    row.item,
                    model.getActivityText(thread.id),
                    model.isUnread(thread),
                    uses24HourTime
                )
                onTap = { openThread(thread, this) }
                onLongPress = { showMenu(this, thread) }
                onRename = { showRename(thread) }
                onTogglePin = { model.setPinned(thread, thread.isPinned != true) }
                onDelete = { showDeleteConfirmation(thread) }
                onSwipeBegan = { closeSwipes(except = this) }
            }

            // A chat's failure line, as the feed ends with one when it fails to refresh
            AgentThreadListRow.PageFailure -> (cellHolder.cell as AgentSystemMessageCell).configure(
                AgentMessage(
                    id = row.key,
                    role = AgentMessageRole.SYSTEM,
                    text = LocaleController.getString("\$agent_chats_unavailable"),
                    isFailure = true
                ),
                onRetry = { model.loadMore() }
            )
        }
    }

    private companion object {
        val HEADER_CELL = WCell.Type(1)
        val THREAD_CELL = WCell.Type(2)
        val NEWS_CELL = WCell.Type(3)
        val FAILURE_CELL = WCell.Type(4)
        const val PINNED_SECTION_KEY = "pinned"
        const val LOAD_MORE_THRESHOLD = 5
        const val LOAD_ERROR_SIDE_INSET = 32
        const val REFRESH_INTERVAL_MS = 30_000L
        const val REVEAL_DURATION_MS = 300L
        const val MENU_WIDTH = 194
        const val BAR_HEIGHT = 48
        const val BAR_SIDE_INSET = 16
        const val BAR_GAP = 12
        const val SEARCH_ICON = 26
        const val ROOT_LIST_TOP_GAP = 4
        const val LIST_BOTTOM_GAP = 8
        const val BOTTOM_FADE_EXTRA = 24
        const val BOTTOM_FADE_ALPHA = 229
        const val BOTTOM_FADE_STOP = 0.46f

        // The hosted bar's morph out of the toolbar
        const val BAR_APPEAR_START = 0.45f
        const val BAR_SWELL = 0.2f
        const val BAR_GROW_FROM = 0.7f
        const val BAR_EXPANSION_MS = 416L
        val BAR_EXPANSION_SPRING = WInterpolator.spring(0.75f, ln(1000f) / 0.75f)

        // Composing in the list
        const val COMPOSE_FADE_MS = 300L

        // The smooth curve over this long matches iOS's critically damped 0.3 s spring
        const val COMPOSE_SPRING_MS = 525L
        const val COMPOSED_CHAT_CROSSFADE_MS = 250L
        const val DISSOLVED_GAP_CLOSE_DELAY_MS = 600L
        const val COMPOSE_RISE = 24f
        const val COMPOSE_SUGGESTIONS_GAP = 26f
        const val COMPOSER_TOP_PADDING = 8f
        const val COMPOSE_TITLE_SIZE = 20f
        const val COMPOSE_HINTS_LIMIT = 5
        const val COMPOSE_HINTS_TTL_MS = 10 * 60 * 1000L

        class ComposeHints(val language: String?, val hints: List<AgentHint>, val loadedAtMs: Long)

        var composeHintsCache: ComposeHints? = null
    }
}
