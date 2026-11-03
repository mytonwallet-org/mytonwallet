package org.mytonwallet.app_air.uiagent.viewControllers.threadList

import android.Manifest
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.format.DateFormat
import android.view.Gravity
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.Window
import android.view.inputmethod.EditorInfo
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.annotation.RequiresApi
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.animation.doOnEnd
import androidx.core.content.ContextCompat
import androidx.core.graphics.createBitmap
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
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.uiagent.agentV2.AgentDictationController
import org.mytonwallet.app_air.uiagent.agentV2.AgentV2OperationException
import org.mytonwallet.app_air.uiagent.agentV2.AndroidAgentDictationRecorder
import org.mytonwallet.app_air.uiagent.agentV2.LiveAgentV2Client
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ErrorText
import org.mytonwallet.app_air.uiagent.agentV2.localizedAgentV2Hint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHint
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewChatVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentPromptChatRequest
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSession
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentConsentView
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsFeedVC
import org.mytonwallet.app_air.uiagent.viewControllers.news.AgentNewsPreviewModel
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
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
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadListItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2TranscriptionRequest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2Update
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate

/** A row of the Agent list: the News row, a section's title, or a chat */
private sealed class AgentThreadListRow : WEquatable<AgentThreadListRow> {
    abstract val key: String

    data class News(val latest: AgentV2NewsFeedItem?, val unreadCount: Int) : AgentThreadListRow() {
        override val key = "news"
    }

    data class Header(val sectionKey: String, val title: String) : AgentThreadListRow() {
        override val key = "header:$sectionKey"
    }

    data class Thread(val item: AgentV2ThreadListItem, val sectionTitle: String) :
        AgentThreadListRow() {
        override val key = "thread:${item.thread.id}"
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
    private var hasRevealedThreads = false
    private var hasConsent = false
    private var hasConsentResult = false
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

    /** A question is being written in the bar, or one sent from it waits for its chat to come */
    val isComposing: Boolean
        get() = (isComposerFocused || isComposedChatPending) && !isBarCovered
    private var isComposerFocused = false
    private var hostedBarProgress = 1f

    // How far the field has widened over the search circle, as it does while composing or under a chat
    private var barExpansion = 0f

    // The chat over the list, whose composer follows the bar while the bar carries the field into it or back
    private var coveringChat: WeakReference<AgentVC>? = null
    private var isChatTakingOver = false
    private var barExpansionAnimator: ValueAnimator? = null
    private val itemAnimator = AgentThreadListItemAnimator()
    private val threadsAdapter = WRecyclerViewAdapter(
        WeakReference(this),
        arrayOf(HEADER_CELL, THREAD_CELL, NEWS_CELL)
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
                val lastVisible = listLayoutManager.findLastVisibleItemPosition()
                if (lastVisible >= rows.size - LOAD_MORE_THRESHOLD) model.loadMore()
            }

            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                // Scrolling the list closes the rows' actions
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) closeSwipes(except = null)
            }
        })
    }
    private val skeletonView = AgentThreadListSkeletonView(context)
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
    private val consentView = AgentConsentView(context).apply {
        onAllow = { acceptConsent() }
    }
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
        onHintTap = { hint -> sendComposed(hint.prompt) }
    }
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
        view.addView(bottomGradientView, ConstraintLayout.LayoutParams(0, 0))
        view.addView(loadMoreSpinner, ConstraintLayout.LayoutParams(24.dp, 24.dp))
        view.addView(searchButton, ConstraintLayout.LayoutParams(BAR_HEIGHT.dp, BAR_HEIGHT.dp))
        view.addView(composer, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(composeDismissArea, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(composeSuggestions, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        composeSuggestions.backdropSource = view
        view.addView(consentView, ConstraintLayout.LayoutParams(0, 0))
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
            allEdges(consentView)
        }
        searchGlass = WGlassView.attachTo(
            searchButton,
            BAR_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.SearchFieldBackground),
            recyclerView
        )
        composer.bindDictation(dictation)
        composer.onSend = { prompt -> sendComposed(prompt) }
        composer.onHeightChanged = { insetsUpdated() }
        composer.onWindowFocusChanged = ::onWindowFocusChanged
        composer.onInputFocusChanged = { isFocused ->
            isComposerFocused = isFocused
            updateBarExpansion()
            updateComposeState()
            barHost?.onAgentBarStateChanged()
        }
        model.onChange = ::updateRows
        model.onError = ::showOperationError
        model.onActivityChange = ::updateActivities
        newsModel.onChange = { updateRows(AgentThreadListChange.DATA) }
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

    private fun sendComposed(prompt: String): Boolean {
        // One question at a time: a chat waiting for the window's copy is already on its way
        if (!hasConsent || isComposedChatPending) return false
        // The suggestions stop taking taps as soon as one is sent
        composeSuggestions.setCardsEnabled(false)
        val shouldContinueInPlace = isComposeShown && barHost != null
        // The compose screen stays until the chat comes over it, so the list doesn't show in between
        if (shouldContinueInPlace) isComposedChatPending = true
        // The field gives up the keyboard before the chat comes
        composer.hideKeyboard()
        if (shouldContinueInPlace) {
            continueComposedChat(prompt)
        } else {
            openNewChat(prompt)
        }
        return true
    }

    // A question written in the list continues in place: the new chat dissolves in over the list instead of sliding
    private fun continueComposedChat(prompt: String) {
        val navigation = navigationController ?: run {
            isComposedChatPending = false
            updateComposeState()
            return
        }
        val chat = AgentVC(context, prompt = AgentPromptChatRequest(prompt, AgentV2EntryPoint()))
        val surface = window?.window
        val shouldDissolve = WGlobalStorage.getAreAnimationsActive() && navigation.width > 0 &&
            navigation.height > 0
        if (shouldDissolve && surface != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pushDissolving(navigation, surface, chat)
        } else {
            isComposedChatPending = false
            navigation.push(chat, animated = false)
        }
    }

    // The window's pixels at half size, copied off the main thread, stand in for the list as the chat comes
    @RequiresApi(Build.VERSION_CODES.O)
    private fun pushDissolving(navigation: WNavigationController, surface: Window, chat: AgentVC) {
        isComposedChatPending = true
        val location = IntArray(2)
        navigation.getLocationInWindow(location)
        val snapshot = createBitmap(
            (navigation.width / DISSOLVE_DOWNSCALE).coerceAtLeast(1),
            (navigation.height / DISSOLVE_DOWNSCALE).coerceAtLeast(1)
        )
        val source = Rect(
            location[0],
            location[1],
            location[0] + navigation.width,
            location[1] + navigation.height
        )
        val onCopied = PixelCopy.OnPixelCopyFinishedListener { result ->
            if (result == PixelCopy.SUCCESS && navigation.isAttachedToWindow) {
                dissolveIn(navigation, snapshot)
            } else {
                snapshot.recycle()
            }
            isComposedChatPending = false
            navigation.push(chat, animated = false)
        }
        try {
            PixelCopy.request(surface, source, snapshot, onCopied, Handler(Looper.getMainLooper()))
        } catch (_: IllegalArgumentException) {
            snapshot.recycle()
            isComposedChatPending = false
            navigation.push(chat, animated = false)
        }
    }

    private var isComposedChatPending = false

    private fun dissolveIn(navigation: View, snapshot: Bitmap) {
        val dissolve = snapshot.toDrawable(navigation.resources).apply {
            setBounds(0, 0, navigation.width, navigation.height)
            isFilterBitmap = true
        }
        navigation.overlay.add(dissolve)
        ValueAnimator.ofInt(255, 0).apply {
            duration = COMPOSED_CHAT_DISSOLVE_MS
            addUpdateListener { dissolve.alpha = it.animatedValue as Int }
            doOnEnd {
                navigation.overlay.remove(dissolve)
                snapshot.recycle()
            }
            start()
        }
    }

    private fun endComposing() {
        composer.hideKeyboard()
    }

    // Writing a question turns the list into a new chat: its chats fade, suggestions rise over the field, and with a
    // hosting toolbar the root header gives way to a new chat's
    private fun updateComposeState() {
        val shouldShowCompose = isComposing && hasConsent
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
        listOf(skeletonView).forEach { content ->
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

    private val shouldShowEmptySuggestions: Boolean
        get() = hasConsent && model.hasLoaded && model.items.isEmpty() && !isBarCovered

    private fun applySuggestionsShare(share: Float) {
        composeSuggestions.alpha = share
        composeSuggestions.translationY = COMPOSE_RISE.dp * (1 - share)
    }

    private fun updateComposeSuggestions(isAnimated: Boolean) {
        val shouldShow =
            (isComposeShown || shouldShowEmptySuggestions) && composeSuggestionsHints.isNotEmpty()
        composeSuggestions.animate().cancel()
        val isCoverAnimating = composeCoverAnimator?.isRunning == true
        areSuggestionsFollowingCover = false
        if (shouldShow) {
            if (!composeSuggestions.isVisible) {
                composeSuggestions.configure(
                    composeSuggestionsHints,
                    shouldShowEmptyStateIcon = true,
                    shouldAnimate = false
                )
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

    private fun loadComposeHints() {
        val language = LocaleController.activeLanguage.langCode
        composeHintsCache?.takeIf {
            it.language == language &&
                SystemClock.elapsedRealtime() - it.loadedAtMs < COMPOSE_HINTS_TTL_MS
        }?.let {
            composeSuggestionsHints = it.hints
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
                return@launch
            }
            composeHintsCache = ComposeHints(language, hints, SystemClock.elapsedRealtime())
            composeSuggestionsHints = hints
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
        val isWide = isComposerFocused || isComposedChatPending || isBarCovered
        val target = if (barHost != null && isWide) 1f else 0f
        barExpansionAnimator?.cancel()
        barExpansionAnimator = null
        if (barExpansion == target) return
        if (!WGlobalStorage.getAreAnimationsActive() || !isViewConfigured) {
            barExpansion = target
            if (isViewConfigured) insetsUpdated()
            return
        }
        barExpansionAnimator = ValueAnimator.ofFloat(barExpansion, target).apply {
            duration = BAR_EXPANSION_MS
            interpolator = BAR_EXPANSION_SPRING
            addUpdateListener {
                barExpansion = it.animatedValue as Float
                applyBarFieldStart()
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
        dictation.cancel()
        scope.cancel()
        readState.removeListener(readStateListener)
        WalletCore.unregisterObserver(this)
        WalletCore.unsubscribeFromApiUpdates(ApiUpdate.ApiUpdateAgentV2::class.java, this)
        super.onDestroy()
    }

    fun openNewChat(prompt: String? = null, entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()) {
        navigationController?.push(
            if (prompt.isNullOrBlank()) {
                AgentNewChatVC(context)
            } else {
                AgentVC(context, prompt = AgentPromptChatRequest(prompt, entryPoint))
            }
        )
    }

    private fun openNews(cell: AgentNewsCell) {
        closeSwipes(except = null)
        val navigation = navigationController ?: return
        val language = LocaleController.activeLanguage.langCode
        cell.rowView.shouldHoldHighlight = true
        navigation.push(
            AgentNewsFeedVC(
                context,
                findThread = threadFinder,
                initialItems = newsModel.items.takeIf {
                    newsModel.itemsLanguage == language
                }.orEmpty()
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
        val chat = AgentVC(context, thread)
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
        hasConsentResult = false
        updateChrome()
        consentJob = scope.launch {
            try {
                showConsentResult(client.consent())
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                showConsentResult(false)
                consentView.showError(errorText(error))
            } finally {
                consentJob = null
            }
        }
    }

    private fun acceptConsent() {
        if (consentJob?.isActive == true) return
        consentView.setLoading(true)
        consentView.showError(null)
        consentJob = scope.launch {
            try {
                client.acceptConsent()
                showConsentResult(true)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                consentView.showError(errorText(error))
            } finally {
                consentView.setLoading(false)
                consentJob = null
            }
        }
    }

    private fun showConsentResult(isAllowed: Boolean) {
        hasConsent = isAllowed
        hasConsentResult = true
        updateChrome()
        if (isAllowed) refresh()
    }

    private fun refresh() {
        model.syncActivities(AgentSession.getLoadedChats())
        model.refresh()
        newsModel.refresh()
    }

    // The list refreshes every 30 s while it is on screen and the app is active
    private fun startRefreshTimer() {
        refreshJob?.cancel()
        refreshJob = scope.launch {
            while (isActive) {
                delay(REFRESH_INTERVAL_MS)
                if (hasConsent && isAppActive && !isDisappeared) refresh()
            }
        }
    }

    // Rows

    private fun buildRows(): List<AgentThreadListRow> = buildList {
        add(AgentThreadListRow.News(newsModel.latestItem, newsModel.unreadCount))
        if (!model.hasLoaded) return@buildList
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
    }

    private fun updateRows(change: AgentThreadListChange) {
        val newRows = buildRows()
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
            if (item.thread.id in threadIds) {
                cell.setActivity(model.getActivityText(item.thread.id), model.isUnread(item.thread))
            }
        }
    }

    private fun reconfigureVisibleRows() {
        forEachVisibleThreadCell { cell, item ->
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

    private fun closeSwipes(except: AgentThreadCell?) {
        for (index in 0 until recyclerView.childCount) {
            val cell = recyclerView.getChildAt(index) as? AgentThreadCell ?: continue
            if (cell !== except) cell.closeSwipe(isAnimated = true)
        }
    }

    // Chrome

    private fun updateChrome() {
        consentView.isGone = !hasConsentResult || hasConsent
        recyclerView.visibility = when {
            !hasConsent -> View.GONE
            !hasRevealedThreads -> View.INVISIBLE
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
        updateBarVisibility()
        updatePlaceholderFrames()
        updateComposeState()
    }

    /** The list shows its bar: the Agent is allowed and no search is open over the list */
    val isBarShown: Boolean get() = hasConsent && !isAgentSearchOpen
    private var hasBarBeenShown: Boolean? = null

    private fun updateBarVisibility() {
        val isBarShown = isBarShown
        composer.isGone = !isBarShown
        // A hosting toolbar draws the search circle
        searchButton.isGone = !isBarShown || barHost != null ||
            navigationController?.tabBarController?.isAgentSearchSupported != true
        searchGlass?.isGone = searchButton.isGone
        bottomGradientView.isGone = !hasConsent
        if (isBarShown && barHost != null) setHostedBarProgress(hostedBarProgress)
        // Without its bar, as on the consent screen, the list needs no toolbar
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
        consentView.updateTheme()
        skeletonView.updateTheme()
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
            isKeyboardDismissal()
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
        val endsAboveBottomBar =
            additionalTabletPadding > 0 && !WGlobalStorage.isGradientNavigationBarActive()
        val consentGutter = if (additionalTabletPadding > 0) gutter else 0
        view.setConstraints {
            toStartPx(consentView, sideStart + consentGutter)
            toEndPx(consentView, sideEnd + consentGutter)
            toBottomPx(consentView, if (endsAboveBottomBar) bottom else 0)
        }
        consentView.updateInsets(top, bottom, endsAboveBottomBar)
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

    // The field starts after the search circle, as the root toolbar's field does, and widens over it
    private fun computeBarFieldStart(): Int {
        val hasCircle = barHost != null ||
            navigationController?.tabBarController?.isAgentSearchSupported == true
        if (!hasCircle) return 0
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
        consentView.bringToFront()
        if (window?.isWideLayout == true) {
            topReversedCornerView?.bringToFront()
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
                if (hasConsent && !isDisappeared) refresh()
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
            buttonPressed = { model.delete(thread) },
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
                if (continuation.isActive) {
                    continuation.resume(results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
                }
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
        }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            HEADER_CELL -> AgentThreadSectionCell(context)
            NEWS_CELL -> AgentNewsCell(context)
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
                configure(row.latest, row.unreadCount, uses24HourTime)
                onTap = { openNews(this) }
            }

            is AgentThreadListRow.Header ->
                (cellHolder.cell as AgentThreadSectionCell).configure(row.title)

            is AgentThreadListRow.Thread -> (cellHolder.cell as AgentThreadCell).apply {
                val thread = row.item.thread
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
        }
    }

    private companion object {
        val HEADER_CELL = WCell.Type(1)
        val THREAD_CELL = WCell.Type(2)
        val NEWS_CELL = WCell.Type(3)
        const val PINNED_SECTION_KEY = "pinned"
        const val LOAD_MORE_THRESHOLD = 5
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
        const val COMPOSED_CHAT_DISSOLVE_MS = 250L
        const val DISSOLVE_DOWNSCALE = 2
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
