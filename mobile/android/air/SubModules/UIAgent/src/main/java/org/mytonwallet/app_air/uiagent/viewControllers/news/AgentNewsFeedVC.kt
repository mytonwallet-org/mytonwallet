package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnNextLayout
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.setMargins
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.agentV2.isAgentV2ThreadStarted
import org.mytonwallet.app_air.uiagent.agentV2.parseAgentV2Timestamp
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_BOTTOM_FADE_EXTRA
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_COMPOSER_FIELD_TOP
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_COMPOSER_LIST_GAP
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_LIST_TOP_INSET
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_MESSAGE_BOTTOM_GAP
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_SCROLL_BUTTON_END
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AGENT_SCROLL_BUTTON_GAP
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHeaderHandoff
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentHeaderHandoffScreen
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNavigation
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsFlightSource
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentRecyclerAnimationScrollHelper
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSession
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVM
import org.mytonwallet.app_air.uiagent.viewControllers.agent.DIGEST_HEADLINE_SEPARATOR
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentChatBackgroundColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentHeaderBottom
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AGENT_DAY_CAPSULE_MARGIN
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentUnreadDividerCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.formatAgentChatTime
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isAgentPicturePinchStart
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_HISTORY_LOAD_THRESHOLD
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBottomFadeView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBulletin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentScrollToBottomButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSkeletonReveal
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.clearSegmentedControl.WClearSegmentedControl
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
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsFeedView
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings

/**
 * The News feed, as a chat with all news or daily digests in the order they came, a day line
 * before each day and "New" before the first unseen news card in the all view, opening there or at the
 * latest card, or at [requestedDigestId] once it comes. The bell in the header opens the digest
 * and notifications sheet. [findThread] finds a discussion's chat among those the chat list has
 * loaded.
 */
@SuppressLint("ViewConstructor")
class AgentNewsFeedVC(
    context: Context,
    private val initialEventId: Int? = null,
    private val findThread: (String) -> AgentV2ThreadSummary? = { null },
    // The first page the list's News row has loaded, shown at once: its news, and its digests while
    // they follow the current digest hour and time zone
    private val initialItems: List<AgentV2NewsFeedItem> = emptyList(),
    requestedDigestId: String? = null,
    private val initialDigests: List<AgentV2NewsFeedDigest> = emptyList()
) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    WalletCore.EventObserver,
    AgentHeaderHandoffScreen {
    @Suppress("PropertyName")
    override val TAG = "AgentNewsFeed"
    override val ignoreSideGuttering = true

    private sealed interface Row {
        val id: String

        data class Day(val timestamp: Long) : Row {
            override val id = "day-$timestamp"
        }

        data object Unread : Row {
            override val id = "unread"
        }

        data class News(val item: AgentV2NewsFeedItem) : Row {
            override val id = "news-${item.eventId}"
        }

        data class Digest(val digest: AgentV2NewsFeedDigest) : Row {
            override val id = "digest-${digest.id}"
        }

        data class Failure(val text: String) : Row {
            override val id = "failure"
        }
    }

    private data class Anchor(val id: String, val offset: Int)

    /** Where a view's rows stood as the feed switched away from it: at their end, or at a card */
    private sealed interface ViewPosition {
        data object End : ViewPosition
        data class At(val anchor: Anchor) : ViewPosition
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val model = AgentNewsFeedModel(
        scope,
        requestedDigestId = requestedDigestId,
        initialView = AgentNewsNotificationSettings.shared.newsView
    )
    val requestedDigestId: String? get() = model.requestedDigestId
    val newsView: AgentNewsFeedView get() = model.view

    fun setView(view: AgentNewsFeedView) {
        scope.launch { AgentNewsNotificationSettings.shared.setNewsView(view) }
    }

    private var rows = emptyList<Row>()
        set(value) {
            field = value
            dayRowPositions = findDayRowPositions(value)
        }

    // The position of the day line each row comes under, or -1
    private var dayRowPositions = IntArray(0)
    private var hasInitialScroll = false

    // Where the other view's rows stood, kept while the feed is open, so a switch back returns there
    private val viewPositions = mutableMapOf<AgentNewsFeedView, ViewPosition>()

    // The view whose rows the list shows
    private var shownView: AgentNewsFeedView? = null

    // The view the feed last started its rows for, which a reset of that same view starts again
    private var resetView = model.view
    private var isVisible = false
    private val chatGate = AgentNewsChatGate()
    private var discussionSession: AgentVM? = null
    private var flightSourceCell: WeakReference<AgentNewsFlightSource>? = null
    private var wasLoadingMore = false
    private var isUserScrolling = false
    private var animateFromIndex = -1
    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(DATE_CELL, UNREAD_CELL, NEWS_CELL, FAILURE_CELL, DIGEST_CELL)
        )
    private val layoutManager = LinearLayoutManager(context).apply { stackFromEnd = true }
    private val recyclerView = object : WRecyclerView(this) {
        override fun onInterceptTouchEvent(e: MotionEvent): Boolean =
            !isAgentPicturePinchStart(this, e) && super.onInterceptTouchEvent(e)
    }.apply {
        adapter = rvAdapter
        layoutManager = this@AgentNewsFeedVC.layoutManager
        clipToPadding = false
        itemAnimator = null
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                when (newState) {
                    RecyclerView.SCROLL_STATE_DRAGGING -> {
                        isUserScrolling = true
                        isPinnedDigestFollowingScroll = true
                        // The user's own scroll is never taken over by the scroll to the requested digest
                        model.stopSeekingRequestedDigest()
                        loadMoreNearTop()
                    }

                    RecyclerView.SCROLL_STATE_IDLE -> {
                        isUserScrolling = false
                        updateFloatingDay()
                    }
                }
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                updateBlurViews(recyclerView)
                if (isUserScrolling && dy < 0) loadMoreNearTop()
                if (isPinnedDigestFollowingScroll) updatePinnedDigestForScrollPosition()
            }
        })
    }

    // Telegram's jump to a row away from the screen, for the latest news and for a pinned digest
    private val jumpScroll = AgentRecyclerAnimationScrollHelper(recyclerView)

    private var hasStoppedScroll = false
    private val scrollStopper = object : RecyclerView.SimpleOnItemTouchListener() {
        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN) hasStoppedScroll = jumpScroll.stop()
            return false
        }
    }
    private var isPopupVisible = false
    private val loadErrorView = AgentLoadErrorView(context).apply {
        onRetry = { model.refresh() }
    }

    private val bottomGradientView = AgentBottomFadeView(context)
    private val contentContainer = WView(context)

    // Placeholder cards until the first page comes
    private val skeleton = AgentMessagesSkeletonView(
        context,
        AgentMessagesSkeletonView.Style.NEWS_CARDS
    ).apply { isGone = true }
    private val skeletonReveal = AgentSkeletonReveal(skeleton, recyclerView)
    private val copyBulletin = AgentBulletin()
    private val textCache = AgentMessageTextCache()
    private val scrollButton = AgentScrollToBottomButton(context).apply {
        setOnClickListener { scrollToLatest() }
    }
    private var scrollButtonGlass: WGlassView? = null

    // The digests as Telegram's pinned messages, under the header: the feed's digests, the oldest first, the one the
    // bar shows, and whether the bar follows the scroll, which it stops doing while a tap on it takes the feed there
    private val pinnedDigestBar = AgentNewsPinnedDigestBar(context).apply {
        id = View.generateViewId()
        isGone = true
        setOnClickListener { goToPinnedDigest() }
    }
    private var pinnedDigestGlass: WGlassView? = null

    // "All News | Digests" in the header, in the title's place: the root header's tabs on their glass capsule, sized by
    // their titles, the thumb at the shown view's index or on its way there. The bar centers [viewSwitchHost] as its
    // title, which holds the switch with room for its glass halo around it.
    private val viewSwitch = WClearSegmentedControl(
        context,
        horizontalPaddingDp = VIEW_SWITCH_INSET,
        thumbHeightDp = VIEW_SWITCH_THUMB_HEIGHT,
        showActiveTabArrow = false,
        itemHorizontalPaddingDp = VIEW_SWITCH_TAB_PADDING,
        minItemHorizontalPaddingDp = VIEW_SWITCH_TAB_PADDING,
        itemSpacingDp = 0
    ).apply {
        setBackgroundColor(Color.TRANSPARENT, VIEW_SWITCH_HEIGHT.dp / 2f, clipToBounds = true)
    }
    private val viewSwitchHost = FrameLayout(context).apply {
        addView(
            viewSwitch,
            FrameLayout.LayoutParams(WRAP_CONTENT, VIEW_SWITCH_HEIGHT.dp, Gravity.CENTER).apply {
                setMargins(WGlassView.GLASS_PADDING_DP.dp)
            }
        )
    }
    private var viewSwitchGlass: WGlassView? = null
    private var viewSwitchIndex = NEWS_VIEWS.indexOf(newsView)
    private var viewSwitchPosition = viewSwitchIndex.toFloat()
    private var viewSwitchAnimator: ValueAnimator? = null
    private val viewSwitchDelegate = object : WClearSegmentedControl.Delegate {
        override fun onIndexChanged(to: Int, animated: Boolean) {
            selectViewSwitchIndex(to, isAnimated = animated)
            setView(NEWS_VIEWS[to])
        }

        override fun onItemMoved(from: Int, to: Int) = Unit

        override fun enterReorderingMode() = Unit
    }
    private var pinnedDigests = emptyList<AgentV2NewsFeedDigest>()
    private var pinnedDigestRows = IntArray(0)
    private var pinnedDigestIndex: Int? = null
    private var isPinnedDigestFollowingScroll = true
    private var dummyDigestCell: AgentNewsDigestCell? = null
    private val digestSettingsButton = WImageButton(context).apply {
        setPaddingDp(8)
        setImageDrawable(context.getDrawableCompat(R.drawable.ic_agent_bell))
        updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        // Where a chat's menu button stands, so the two hand over in place
        translationX = SETTINGS_BUTTON_SHIFT.dp * LocaleController.rtlMultiplier
        contentDescription = LocaleController.getString("\$agent_digest_settings_title")
        setOnClickListener { AgentDigestSettingsSheetVC.present(this@AgentNewsFeedVC) }
    }
    private val scrollButtonUpdater = ViewTreeObserver.OnPreDrawListener {
        updateScrollButton(isAnimated = true)
        markVisibleDigestsReached()
        true
    }
    private var scrollButtonBinding: AgentPreDrawBinding? = null

    // The day of the posts under the list's top edge, pinned there while they scroll under it
    private val floatingDay =
        AgentDateHeaderCell(context, isDayCapsule = true, isFloating = true).apply {
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
            alpha = 0f
            isInvisible = true
        }
    private var floatingDayTimestamp: Long? = null
    private var isFloatingDayShown = false
    private var isFloatingDayHiding = false
    private var stuckDayTimestamp: Long? = null
    private val floatingDayUpdater = ViewTreeObserver.OnPreDrawListener {
        updateFloatingDay()
        true
    }
    private var floatingDayBinding: AgentPreDrawBinding? = null

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        setNavTitle(LocaleController.getString("News"), animated = false)
        navigationBar?.addTrailingView(
            digestSettingsButton,
            ConstraintLayout.LayoutParams(SETTINGS_BUTTON_SIZE.dp, SETTINGS_BUTTON_SIZE.dp)
        )
        navigationBar?.setCenteredTitleView(viewSwitchHost, false)
        viewSwitch.setItems(
            NEWS_VIEWS.map { feedView ->
                WClearSegmentedControl.Item(
                    LocaleController.getString(
                        if (feedView == AgentNewsFeedView.Digests) {
                            "\$agent_news_view_digests"
                        } else {
                            "\$agent_news_view_all"
                        }
                    ),
                    onRemove = null,
                    onClick = null
                )
            },
            viewSwitchIndex,
            viewSwitchDelegate
        )
        // The thumb takes its frame from the segments laid out, which it has none of before the first layout
        viewSwitch.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            moveViewSwitchThumb(viewSwitchPosition)
        }
        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentContainer.apply {
            clipChildren = false
            clipToPadding = false
            // Under the cards, so they come in over it as it fades
            addView(skeleton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(recyclerView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(floatingDay, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(bottomGradientView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
            addView(loadErrorView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(
                pinnedDigestBar,
                ConstraintLayout.LayoutParams(
                    MATCH_CONSTRAINT,
                    AgentNewsPinnedDigestBar.HEIGHT.dp
                )
            )
            addView(
                scrollButton,
                ConstraintLayout.LayoutParams(
                    AgentScrollToBottomButton.SIZE.dp,
                    AgentScrollToBottomButton.SIZE.dp
                )
            )
            setConstraints {
                toStart(pinnedDigestBar, AgentNewsPinnedDigestBar.SIDE_INSET.toFloat())
                toEnd(pinnedDigestBar, AgentNewsPinnedDigestBar.SIDE_INSET.toFloat())
                allEdges(recyclerView)
                toStart(floatingDay)
                toEnd(floatingDay)
                toStart(skeleton)
                toEnd(skeleton)
                toTop(skeleton)
                toStart(bottomGradientView)
                toEnd(bottomGradientView)
                toBottom(bottomGradientView)
                toStart(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toEnd(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toCenterY(loadErrorView)
                toEnd(scrollButton, AGENT_SCROLL_BUTTON_END.toFloat())
            }
        }
        scrollButtonGlass = WGlassView.attachTo(
            scrollButton,
            AgentScrollToBottomButton.SIZE.dp / 2f,
            GlassProviders.composer(WColor.SearchFieldBackground),
            recyclerView
        )
        pinnedDigestGlass = WGlassView.attachTo(
            pinnedDigestBar,
            AgentNewsPinnedDigestBar.CORNER_RADIUS.dp.toFloat(),
            GlassProviders.composer(WColor.SearchFieldBackground),
            recyclerView
        )
        viewSwitchGlass = WGlassView.attachTo(
            viewSwitch,
            VIEW_SWITCH_HEIGHT.dp / 2f,
            GlassProviders.pill(WColor.Background),
            recyclerView
        )
        scrollButtonBinding = AgentPreDrawBinding(recyclerView, scrollButtonUpdater)
        floatingDay.setupBlurWith(recyclerView)
        floatingDayBinding = AgentPreDrawBinding(recyclerView, floatingDayUpdater)
        recyclerView.addOnItemTouchListener(scrollStopper)
        model.onChange = ::updateFeed
        model.onReset = {
            val leftView = shownView?.takeIf { it != model.view }
            if (resetView == model.view) {
                // The view's own rows start again
                viewPositions.remove(model.view)
            } else if (leftView != null && hasInitialScroll && rows.isNotEmpty()) {
                viewPositions[leftView] = if (isNearBottom()) {
                    ViewPosition.End
                } else {
                    visibleAnchor()?.let { ViewPosition.At(it) } ?: ViewPosition.End
                }
            }
            resetView = model.view
            hasInitialScroll = false
            wasLoadingMore = false
            isPinnedDigestFollowingScroll = true
        }
        WalletCore.registerObserver(this)
        observeNewsSettings()
        model.seed(initialItems, initialDigests)
        updateFeed()
        updateTheme()
        insetsUpdated()
    }

    override val headerHandoffContent: List<View>
        get() = listOf(viewSwitchHost, digestSettingsButton)

    /**
     * The local view choice selects its own feed; a new digest time brings that time's digests when the feed is visible
     */
    private fun observeNewsSettings() {
        scope.launch {
            val settings = AgentNewsNotificationSettings.shared
            settings.state
                .map { makeAgentNewsFeedSettingsKey(settings.newsView, it) }
                .distinctUntilChanged()
                .collect { (view, _, _) ->
                    if (view != model.view) {
                        model.setView(view, shouldDeferRefresh = !isVisible)
                    } else if (isVisible) {
                        model.refresh()
                    }
                }
        }
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        AgentHeaderHandoff.begin(this)
        isVisible = true
        chatGate.release()
        restoreFlightSource()
        // Coming back from a discussion, its card may now continue it
        rvAdapter.updateVisibleCells()
        model.setView(AgentNewsNotificationSettings.shared.newsView, shouldDeferRefresh = true)
        model.refresh()
    }

    override fun viewWillDisappear() {
        AgentHeaderHandoff.begin(this)
        isVisible = false
        jumpScroll.finish()
        model.cancel()
        super.viewWillDisappear()
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        jumpScroll.finish()
        scrollButtonBinding?.release()
        scrollButtonBinding = null
        floatingDayBinding?.release()
        floatingDayBinding = null
        floatingDay.animate().cancel()
        viewSwitchAnimator?.cancel()
        releaseDiscussion()
        copyBulletin.dismiss()
        scope.cancel()
        super.onDestroy()
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            WalletEvent.AppForeground -> if (isVisible) model.refresh()

            is WalletEvent.AgentThreadDeleted -> {
                model.removeDiscussion(walletEvent.threadId)
                if (discussionSession?.currentThread?.id == walletEvent.threadId) {
                    releaseDiscussion()
                }
            }

            is WalletEvent.AccountWillChange -> releaseDiscussion()

            else -> Unit
        }
    }

    /** The user has written in the card's discussion */
    private fun isDiscussionStarted(item: AgentV2NewsFeedItem): Boolean =
        item.discussion?.threadId?.let(::findStartedThread) != null

    /** A discussion's thread once the user has written in it */
    private fun findStartedThread(threadId: String): AgentV2ThreadSummary? {
        AgentSession.findLoadedModel(threadId)?.takeIf { it.isThreadStarted }
            ?.let { return it.currentThread }
        return findThread(threadId)?.takeIf(::isAgentV2ThreadStarted)
    }

    private fun openPhoto(item: AgentV2NewsFeedItem) {
        val window = window ?: return
        val photos = rows.mapNotNull { row ->
            (row as? Row.News)?.item?.takeIf { !it.imageUrl.isNullOrBlank() }
        }
        val startIndex = photos.indexOfFirst { it.eventId == item.eventId }
        if (startIndex < 0) return
        val items = photos.map {
            agentNewsMediaViewerItem(window, it.imageUrl!!, it.toNewsPost(model.locale))
        }
        MediaViewerVC.present(window, items, startIndex) { index ->
            val eventId = photos[index].eventId
            val position = rows.indexOfFirst { it is Row.News && it.item.eventId == eventId }
            (layoutManager.findViewByPosition(position) as? AgentNewsPostCell)?.makePhotoSource()
        }
    }

    private fun openDigestPictures(
        digest: AgentV2NewsFeedDigest,
        pictures: AgentNewsDigestPictures
    ) {
        val window = window ?: return
        val date = parseAgentV2Timestamp(digest.deliveredAt)
        val items = pictures.headlines.map { agentNewsDigestMediaViewerItem(window, it, date) }
        MediaViewerVC.present(window, items, pictures.index) { index ->
            val position = rows.indexOfFirst { it is Row.Digest && it.digest.id == digest.id }
            (layoutManager.findViewByPosition(position) as? AgentNewsDigestCell)
                ?.makePictureSource(pictures.headlines[index])
        }
    }

    private fun openDiscussion(item: AgentV2NewsFeedItem) =
        chatGate.open { open(AgentNewsChatTarget.FeedNews(item)) }

    private fun openDigestHeadline(headline: AgentV2NewsDigestHeadline) =
        chatGate.open { open(resolveAgentDigestHeadlineTarget(headline, model.items)) }

    private fun openDigestDiscussion(digest: AgentV2NewsFeedDigest) =
        chatGate.open { open(resolveAgentDigestDiscussionTarget(digest, ::findStartedThread)) }

    /** Pushes the chat over the feed, so Back returns to it; false when it can't */
    private fun open(target: AgentNewsChatTarget): Boolean {
        val navigation = navigationController ?: return false
        when (target) {
            is AgentNewsChatTarget.FeedNews -> return openNewsDiscussion(target.item, navigation)

            is AgentNewsChatTarget.News -> {
                val locale = model.locale ?: return false
                val eventId = target.headline.eventId
                AgentNavigation.openNewsChat(
                    context,
                    navigation,
                    eventId,
                    locale,
                    target.headline.headline,
                    icon = null,
                    threadId = null,
                    onThreadCreated = { thread ->
                        learnDiscussion(thread) { model.markDiscussion(eventId, it) }
                    },
                    onThreadMissing = ::forgetDiscussion
                )
            }

            is AgentNewsChatTarget.Discussion ->
                navigation.push(AgentVC(context, target.thread))

            // A digest's discussion the user hasn't written in starts with the digest's post, which
            // its card flies into
            is AgentNewsChatTarget.Digest ->
                AgentNavigation.openDigestChat(
                    context,
                    navigation,
                    target.id,
                    target.preview,
                    discussionNaming = target.discussionNaming,
                    shouldDeferCreation = target.shouldDeferCreation,
                    onThreadCreated = { thread ->
                        learnDiscussion(thread) { model.markDiscussion(target.id, it) }
                    },
                    onThreadMissing = ::forgetDiscussion
                ) { chat -> prepareFlight(findDigestRow(target.id), chat) }
        }
        return true
    }

    private fun openNewsDiscussion(
        item: AgentV2NewsFeedItem,
        navigation: WNavigationController
    ): Boolean {
        val locale = model.locale ?: return false
        AgentNavigation.openNewsChat(
            context,
            navigation,
            item.eventId,
            locale,
            item.headline,
            item.discussion?.icon,
            item.discussion?.threadId,
            onThreadCreated = { thread ->
                learnDiscussion(thread) { model.markDiscussion(item.eventId, it) }
            },
            onThreadMissing = ::forgetDiscussion,
            excerpt = MarkdownParser.parse(
                item.body,
                codeColor = WColor.SecondaryBackground.color,
                linkColor = null,
                detectsUrls = false
            ).toString(),
            imageUrl = item.imageUrl,
            publishedAt = item.deliveredAt,
            body = item.body,
            sources = item.sources,
            discussionNaming = item.discussionNaming,
            shouldDeferCreation = item.discussion == null,
            beforePush = { chat ->
                // A discussion the user hasn't written in yet starts with the news as the Agent's post, also when its
                // thread was made on an earlier visit; the card flies into that place
                if (!isDiscussionStarted(item)) prepareFlight(findNewsRow(item.eventId), chat)
            }
        )
        return true
    }

    private fun findNewsRow(eventId: Int): Int =
        rows.indexOfFirst { it is Row.News && it.item.eventId == eventId }

    private fun findDigestRow(id: String): Int =
        rows.indexOfFirst { it is Row.Digest && it.digest.id == id }

    /** Flies the card at [position] into the post of [chat] */
    private fun prepareFlight(position: Int, chat: AgentVC) {
        val cell = layoutManager.findViewByPosition(position) as? AgentNewsFlightSource ?: return
        val root = view.rootView as? ViewGroup ?: return
        val (snapshot, frame) = cell.makeFlightSnapshot() ?: return
        val headerBottom = IntArray(2).also(view::getLocationInWindow)[1] + agentHeaderBottom()
        chat.onNewsPostArrivalFinished = ::restoreFlightSource
        if (!chat.prepareNewsPostArrival(snapshot, frame, root, headerBottom)) {
            chat.onNewsPostArrivalFinished = null
            return
        }
        cell.setFlightSourceHidden(true)
        flightSourceCell = WeakReference(cell)
    }

    private fun restoreFlightSource() {
        flightSourceCell?.get()?.setFlightSourceHidden(false)
        flightSourceCell = null
    }

    // A discussion's first message can create its thread after the chat and the feed are gone
    private fun learnDiscussion(
        thread: AgentV2ThreadSummary,
        markDiscussion: (AgentV2ThreadSummary) -> Unit
    ) {
        if (isDestroyed) return
        retainDiscussion(thread)
        markDiscussion(thread)
    }

    private fun retainDiscussion(thread: AgentV2ThreadSummary) {
        val previous = discussionSession
        // A model being deleted has left the session, and the thread may have a new one
        if (previous != null && AgentSession.findLoadedModel(thread.id) === previous) return
        discussionSession = AgentSession.acquire(thread)
        previous?.let(AgentSession::release)
    }

    private fun forgetDiscussion(threadId: String) {
        if (discussionSession?.currentThread?.id == threadId) releaseDiscussion()
        model.removeDiscussion(threadId)
    }

    private fun releaseDiscussion() {
        val previous = discussionSession
        discussionSession = null
        previous?.let(AgentSession::release)
    }

    override fun updateTheme() {
        super.updateTheme()
        val isWideLayout = window?.isWideLayout == true
        view.setBackgroundColor(
            if (isWideLayout) WColor.SecondaryBackground.color else agentChatBackgroundColor
        )
        contentContainer.setBackgroundColor(agentChatBackgroundColor)
        if (isWideLayout) {
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
        loadErrorView.updateTheme()
        skeleton.updateTheme()
        scrollButton.updateTheme()
        scrollButtonGlass?.updateTheme()
        pinnedDigestBar.updateTheme()
        pinnedDigestGlass?.updateTheme()
        viewSwitch.paintColor = WColor.Tint.color.colorWithAlpha(31)
        viewSwitch.primaryTextColorOverride = WColor.Tint.color
        viewSwitch.updateTheme()
        viewSwitch.secondaryTextColor = WColor.SecondaryText.color
        viewSwitchGlass?.updateTheme()
        floatingDay.updateTheme()
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        // The rows go under the bar while it shows, as a chat's under Telegram's pinned message, and the pinned day's
        // capsule stands as far under the bar as Telegram's floating date under its panel: the list's own inset and
        // the capsule's margin above it are part of that distance
        val pinnedDigestInset = if (pinnedDigestBar.isGone) {
            0
        } else {
            val barBottom = AgentNewsPinnedDigestBar.TOP_SPACING + AgentNewsPinnedDigestBar.HEIGHT
            val capsuleTop = barBottom + AgentNewsPinnedDigestBar.DAY_CAPSULE_SPACING
            (capsuleTop - AGENT_LIST_TOP_INSET).dp - AGENT_DAY_CAPSULE_MARGIN.dp.roundToInt()
        }
        val top = agentHeaderBottom() + AGENT_LIST_TOP_INSET.dp + pinnedDigestInset
        val bottom = bottomEdge()
        val start = additionalTabletPadding + systemBarStartInset
        contentContainer.updateLayoutParams<ViewGroup.MarginLayoutParams> {
            leftMargin = if (LocaleController.isRTL) systemBarEndInset else start
            rightMargin = if (LocaleController.isRTL) start else systemBarEndInset
        }
        recyclerView.setPadding(
            0,
            top,
            0,
            bottom + (AGENT_COMPOSER_LIST_GAP + AGENT_COMPOSER_FIELD_TOP).dp
        )
        topReversedCornerView?.setSideInsets(
            systemBarStartInset.toFloat(),
            systemBarEndInset.toFloat()
        )
        bottomGradientView.layoutParams = bottomGradientView.layoutParams.apply {
            height = bottom + (AGENT_COMPOSER_FIELD_TOP + AGENT_BOTTOM_FADE_EXTRA).dp
        }
        contentContainer.setConstraints {
            toTopPx(pinnedDigestBar, agentHeaderBottom() + AgentNewsPinnedDigestBar.TOP_SPACING.dp)
            toTopPx(floatingDay, top)
            toBottomPx(skeleton, bottom + AGENT_MESSAGE_BOTTOM_GAP.dp)
            toBottomPx(
                scrollButton,
                bottom + (AGENT_COMPOSER_FIELD_TOP + AGENT_SCROLL_BUTTON_GAP).dp
            )
        }
    }

    // The feed's header keeps its own background at every scroll position, the feed's very top included, as the
    // chat's does
    override fun updateBlurViews(recyclerView: RecyclerView) {
        topReversedCornerView?.setBlurAlpha(1f)
    }

    private fun bottomEdge(): Int = navigationController?.getSystemBars()?.bottom ?: 0

    private fun updateFeed() {
        selectViewSwitchIndex(NEWS_VIEWS.indexOf(newsView), isAnimated = isVisible)
        val isSwitchingView = shownView != null && shownView != newsView
        shownView = newsView
        // The bar's space comes or goes before the rows keep their place, so they stay where they are on screen. On
        // a view switch the bar comes with the rows rather than fading in after them.
        setPinnedDigestBarShown(
            newsView == AgentNewsFeedView.All &&
                model.entries.any { it is AgentNewsFeedEntry.Digest },
            isInstant = isSwitchingView
        )
        applyRows()
        updatePinnedDigests()
    }

    private fun selectViewSwitchIndex(index: Int, isAnimated: Boolean) {
        if (index == viewSwitchIndex) return
        viewSwitchIndex = index
        viewSwitchAnimator?.cancel()
        viewSwitchAnimator = null
        if (!isAnimated || !WGlobalStorage.getAreAnimationsActive()) {
            moveViewSwitchThumb(index.toFloat())
            return
        }
        // The control moves its thumb only as its owner tells it, as a pager's scroll does for header tabs
        viewSwitchAnimator = ValueAnimator.ofFloat(viewSwitchPosition, index.toFloat()).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = WInterpolator.emphasized
            addUpdateListener { moveViewSwitchThumb(it.animatedValue as Float) }
            start()
        }
    }

    private fun moveViewSwitchThumb(position: Float) {
        viewSwitchPosition = position
        viewSwitch.updateThumbPosition(
            viewSwitchIndex,
            offset = position,
            targetIndex = viewSwitchIndex,
            force = true,
            isAnimatingToPosition = position != viewSwitchIndex.toFloat(),
            animateScroll = false
        )
    }

    private fun applyRows() {
        val finishedPagination = wasLoadingMore
        wasLoadingMore = model.isLoadingMore
        updateSkeleton()
        val error = model.error?.takeIf { model.entries.isEmpty() }
        if (error != null) {
            loadErrorView.setError(agentNewsErrorText(error))
        } else {
            loadErrorView.setMessage(
                LocaleController.getString(
                    if (newsView ==
                        AgentNewsFeedView.Digests
                    ) {
                        "\$agent_news_digests_empty"
                    } else {
                        "\$agent_news_empty"
                    }
                ).takeIf { model.isEmpty }
            )
        }
        val newRows = buildRows()
        val requestedDigestIndex = findRequestedDigestRow(newRows)
        if (newRows == rows && hasInitialScroll && requestedDigestIndex < 0) return
        jumpScroll.finish()
        val anchor = visibleAnchor()
        val stickToBottom = hasInitialScroll && !finishedPagination && isNearBottom()
        if (requestedDigestIndex < 0 && stickToBottom && appendLatest(newRows)) return
        rows = newRows
        rvAdapter.reloadData()
        if (requestedDigestIndex >= 0) {
            // Once, to the digest the feed was opened for, as its card comes into the feed
            hasInitialScroll = true
            layoutManager.scrollToPositionWithOffset(requestedDigestIndex, 0)
            recyclerView.doOnNextLayout {
                if (!isVisible || !model.isSeekingRequestedDigest || !model.hasRequestedDigest) {
                    return@doOnNextLayout
                }
                model.stopSeekingRequestedDigest()
                model.markDigestReached(model.requestedDigestId!!)
            }
            syncTopBlurAfterLayout()
        } else if (!hasInitialScroll && rows.isNotEmpty()) {
            recyclerView.doOnNextLayout {
                if (rows.isNotEmpty()) hasInitialScroll = true
            }
            // A view switched back to returns where it was, and otherwise opens as the feed does
            val position = viewPositions.remove(newsView)
            val anchor = (position as? ViewPosition.At)?.anchor
            val anchorIndex = anchor?.let { rows.indexOfFirst { row -> row.id == it.id } } ?: -1
            val initialNewsIndex = rows.indexOfFirst {
                it is Row.News && it.item.eventId == initialEventId
            }
            val unreadIndex = rows.indexOf(Row.Unread)
            if (anchor != null && anchorIndex >= 0) {
                layoutManager.scrollToPositionWithOffset(anchorIndex, anchor.offset)
            } else if (position == ViewPosition.End) {
                scrollToBottom()
            } else if (initialNewsIndex >= 0) {
                layoutManager.scrollToPositionWithOffset(initialNewsIndex, 0)
            } else if (unreadIndex >= 0) {
                layoutManager.scrollToPositionWithOffset(unreadIndex, 0)
            } else {
                scrollToBottom()
            }
            syncTopBlurAfterLayout()
        } else if (stickToBottom) {
            scrollToBottom()
        } else {
            restore(anchor)
        }
    }

    /**
     * The bar shows once the feed has a digest and goes with the last one. It keeps the digest it shows as pages load,
     * and otherwise shows the one above the rows on screen.
     */
    private fun updatePinnedDigests() {
        val previousId = pinnedDigestIndex?.let { pinnedDigests.getOrNull(it)?.id }
        pinnedDigests = if (newsView == AgentNewsFeedView.All) {
            model.entries.mapNotNull { (it as? AgentNewsFeedEntry.Digest)?.digest }
        } else {
            emptyList()
        }
        pinnedDigestRows = pinnedDigests.map { digest ->
            rows.indexOfFirst { it is Row.Digest && it.digest.id == digest.id }
        }.toIntArray()
        if (pinnedDigests.isEmpty()) {
            pinnedDigestIndex = null
            setPinnedDigestBarShown(false)
            return
        }
        val index = previousId?.let { id -> pinnedDigests.indexOfFirst { it.id == id } }
            ?.takeIf { it >= 0 } ?: getPinnedDigestIndexForScrollPosition()
        showPinnedDigest(index, transition = null)
        setPinnedDigestBarShown(true)
        // Rows put in where the feed opens lay out there on the next layout, before they are drawn: the bar takes the
        // digest above them then, rather than the one above the rows they replace
        if (!hasInitialScroll && previousId == null) {
            recyclerView.doOnNextLayout {
                if (pinnedDigestIndex == null || pinnedDigests.isEmpty()) return@doOnNextLayout
                showPinnedDigest(getPinnedDigestIndexForScrollPosition(), transition = null)
            }
        }
    }

    private fun updatePinnedDigestForScrollPosition() {
        val current = pinnedDigestIndex ?: return
        val index = getPinnedDigestIndexForScrollPosition()
        if (index == current) return
        // The rows the feed opens at are laid out for the first time: the bar shows their digest at once
        showPinnedDigest(
            index,
            when {
                !hasInitialScroll -> null
                index < current -> AgentNewsPinnedDigestBar.Transition.OLDER
                else -> AgentNewsPinnedDigestBar.Transition.NEWER
            }
        )
    }

    /**
     * The newest digest above the rows on screen, as Telegram shows the pinned message above them, or the newest of
     * all when none is above
     */
    private fun getPinnedDigestIndexForScrollPosition(): Int {
        val lastIndex = pinnedDigests.lastIndex
        val first = layoutManager.findFirstVisibleItemPosition()
        if (first == RecyclerView.NO_POSITION) return lastIndex
        val topRow = (first..layoutManager.findLastVisibleItemPosition()).firstOrNull { position ->
            (layoutManager.findViewByPosition(position)?.bottom ?: 0) > recyclerView.paddingTop
        } ?: return lastIndex
        val index = pinnedDigestRows.indexOfLast { it in 0 until topRow }
        return if (index >= 0) index else lastIndex
    }

    private fun showPinnedDigest(index: Int, transition: AgentNewsPinnedDigestBar.Transition?) {
        pinnedDigestIndex = index
        val digest = pinnedDigests[index]
        pinnedDigestBar.setContent(
            AgentNewsPinnedDigestBar.Content(
                // The digest's day, as "November 10"
                title = AgentThreadDateFormatting.formatDayText(
                    parseAgentV2Timestamp(digest.deliveredAt) ?: Date(0),
                    Date(),
                    LocaleController.activeLanguage.langCode
                ),
                text = digest.top.joinToString(DIGEST_HEADLINE_SEPARATOR) { it.headline },
                index = index,
                count = pinnedDigests.size
            ),
            transition
        )
    }

    private fun setPinnedDigestBarShown(isShown: Boolean, isInstant: Boolean = false) {
        if (pinnedDigestBar.isGone != isShown) return
        pinnedDigestBar.isGone = !isShown
        insetsUpdated()
        if (!isShown || isInstant || !isVisible || !WGlobalStorage.getAreAnimationsActive()) return
        pinnedDigestBar.alpha = 0f
        pinnedDigestBar.animate().alpha(1f).setDuration(PINNED_DIGEST_FADE_MS).start()
    }

    /**
     * Goes to the digest the bar shows, as a tap on Telegram's pinned message does in `scrollToMessageId`, and the bar
     * moves on to the one before it, and from the oldest back to the newest. A digest laid out scrolls to its place;
     * another lays out there at once, the rows on screen sliding out as its rows slide in.
     */
    private fun goToPinnedDigest() {
        val index = pinnedDigestIndex ?: return
        val row = pinnedDigestRows.getOrNull(index)?.takeIf { it >= 0 } ?: return
        model.stopSeekingRequestedDigest()
        isPinnedDigestFollowingScroll = false
        recyclerView.stopScroll()
        jumpScroll.finish()
        val isSystemMotionOn = !DEBUG_MODE ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            ValueAnimator.areAnimatorsEnabled()
        val canAnimate = WGlobalStorage.getAreAnimationsActive() && isSystemMotionOn
        val boxStart = recyclerView.paddingTop
        val boxEnd = recyclerView.height - recyclerView.paddingBottom
        val view = layoutManager.findViewByPosition(row)
        if (view != null) {
            val targetTop = getPinnedDigestTop(view.height, boxStart, boxEnd)
            val scrollY = min(view.top - targetTop, getScrollDownLimit())
            if (scrollY != 0 && canAnimate) {
                recyclerView.smoothScrollBy(0, scrollY)
            } else if (scrollY != 0) {
                recyclerView.scrollBy(0, scrollY)
            }
        } else {
            val height = measureDigestHeight(pinnedDigests[index])
            val offset = getPinnedDigestTop(height, boxStart, boxEnd) - boxStart
            val jump = { layoutManager.scrollToPositionWithOffset(row, offset) }
            val first = layoutManager.findFirstVisibleItemPosition()
            when {
                !canAnimate || first == RecyclerView.NO_POSITION -> jump()
                row < first -> jumpScroll.scrollUp(jump)
                else -> jumpScroll.scrollDown(jump)
            }
        }
        val previous = if (index == 0) pinnedDigests.lastIndex else index - 1
        showPinnedDigest(
            previous,
            if (previous < index) {
                AgentNewsPinnedDigestBar.Transition.OLDER
            } else {
                AgentNewsPinnedDigestBar.Transition.NEWER
            }
        )
    }

    /** How far the list scrolls down before its last row's bottom meets the visible part's, or more when it is away */
    private fun getScrollDownLimit(): Int {
        val last = layoutManager.findViewByPosition(rows.lastIndex) ?: return Int.MAX_VALUE
        return max(0, last.bottom - (recyclerView.height - recyclerView.paddingBottom))
    }

    /** The height of a digest's card that is not laid out, measured as Telegram measures a message on its dummy cell */
    private fun measureDigestHeight(digest: AgentV2NewsFeedDigest): Int {
        val cell = dummyDigestCell ?: AgentNewsDigestCell(context).also { dummyDigestCell = it }
        cell.configure(makeDigestCardContent(digest))
        cell.measure(
            View.MeasureSpec.makeMeasureSpec(recyclerView.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        )
        return cell.measuredHeight
    }

    private fun makeDigestCardContent(digest: AgentV2NewsFeedDigest): AgentNewsDigestCardContent {
        // Only the time, under its day's capsule, as the news cards show theirs
        val time = parseAgentV2Timestamp(digest.deliveredAt)
            ?.let { formatAgentChatTime(context, it) }
            .orEmpty()
        return AgentNewsDigestCardContent(
            digest,
            time,
            isInDigestsView = newsView == AgentNewsFeedView.Digests
        )
    }

    /**
     * Where Telegram puts a message its pinned panel goes to: in the middle of the list's visible part when it fits
     * there, otherwise with its top at the part's top
     */
    private fun getPinnedDigestTop(height: Int, boxStart: Int, boxEnd: Int): Int =
        boxStart + ((boxEnd - boxStart - height) / 2).coerceAtLeast(0)

    /** The row of the digest the feed was opened for while the feed seeks it, or -1 */
    private fun findRequestedDigestRow(rows: List<Row>): Int {
        if (!model.isSeekingRequestedDigest) return -1
        val id = model.requestedDigestId ?: return -1
        return rows.indexOfFirst { it is Row.Digest && it.digest.id == id }
    }

    /** Returns false when [newRows] change more than the feed's end. */
    private fun appendLatest(newRows: List<Row>): Boolean {
        val oldCount = rows.size
        if (oldCount == 0 || newRows.size <= oldCount || newRows.subList(0, oldCount) != rows) {
            return false
        }
        rows = newRows
        animateFromIndex = oldCount
        WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
            .onInserted(oldCount, newRows.size - oldCount)
        recyclerView.doOnNextLayout { animateFromIndex = -1 }
        val scroller = object : LinearSmoothScroller(context) {
            override fun getVerticalSnapPreference(): Int = SNAP_TO_END
        }
        scroller.targetPosition = rows.lastIndex
        layoutManager.startSmoothScroll(scroller)
        return true
    }

    private fun updateSkeleton() {
        val hasEntries = model.entries.isNotEmpty()
        val shouldShow =
            model.isLoading && !hasEntries && model.error == null && !model.hasLoaded
        if (shouldShow == skeletonReveal.isShown) return
        if (shouldShow) {
            skeletonReveal.show()
        } else {
            skeletonReveal.reveal(hasRows = hasEntries)
        }
    }

    private fun loadMoreNearTop() {
        if (hasInitialScroll && isVisible &&
            layoutManager.findFirstVisibleItemPosition() in 0..AGENT_HISTORY_LOAD_THRESHOLD
        ) {
            model.loadMore()
        }
    }

    private fun markVisibleDigestsReached() {
        if (!isVisible || !hasInitialScroll) return
        val top = recyclerView.paddingTop
        val bottom = recyclerView.height - recyclerView.paddingBottom
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            if (child.bottom <= top || child.top >= bottom) continue
            val position = recyclerView.getChildAdapterPosition(child)
            val row = rows.getOrNull(position) as? Row.Digest ?: continue
            model.markDigestReached(row.digest.id)
        }
    }

    private fun buildRows(): List<Row> = buildList {
        var previousDay: Long? = null
        val entries = model.entries
        entries.forEach { entry ->
            val date = parseAgentV2Timestamp(entry.deliveredAt) ?: Date(0)
            val day = AgentThreadDateFormatting.startOfDay(date, TimeZone.getDefault())
            if (day != previousDay) {
                add(Row.Day(day))
                previousDay = day
            }
            when (entry) {
                is AgentNewsFeedEntry.News -> {
                    if (entry.item.eventId == model.unreadEventId) add(Row.Unread)
                    add(Row.News(entry.item))
                }

                is AgentNewsFeedEntry.Digest -> {
                    if (entry.digest.id == model.unreadDigestId) add(Row.Unread)
                    add(Row.Digest(entry.digest))
                }
            }
        }
        if (entries.isNotEmpty()) {
            model.refreshError?.let { add(Row.Failure(agentNewsErrorText(it))) }
        }
    }

    /**
     * Pins the day of the posts under the list's top edge there once its own line has scrolled under the header,
     * hiding that line, and lets the next day's line push it away, as Telegram's date does in a chat. With another
     * day's line on screen it shows only while the user scrolls, and goes half a second after the scroll stops.
     */
    private fun updateFloatingDay() {
        val listTop = recyclerView.paddingTop
        var topPosition = RecyclerView.NO_POSITION
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index)
            val position = recyclerView.getChildAdapterPosition(child)
            if (position == RecyclerView.NO_POSITION || child.bottom <= listTop) continue
            if (topPosition == RecyclerView.NO_POSITION || position < topPosition) {
                topPosition = position
            }
        }
        val dayPosition = dayRowPositions.getOrElse(topPosition) { -1 }
        val day = rows.getOrNull(dayPosition) as? Row.Day
        val dayView = layoutManager.findViewByPosition(dayPosition) as? AgentDateHeaderCell
        // The capsules are compared where they show on screen, so the pinned one takes the place of the day's own
        // capsule, and gives it back, without moving it. The pinned one's place leaves out the push it is given here.
        val pinnedCapsuleTop =
            floatingDay.getCapsuleScreenTop() - floatingDay.translationY.roundToInt()
        val dayCapsuleTop = dayView?.getCapsuleScreenTop()
        val isStuck = day != null && (dayCapsuleTop == null || dayCapsuleTop < pinnedCapsuleTop)
        var nextDayCapsuleTop: Int? = null
        for (index in 0 until recyclerView.childCount) {
            val child = recyclerView.getChildAt(index) as? AgentDateHeaderCell ?: continue
            val position = recyclerView.getChildAdapterPosition(child)
            child.setCapsuleHidden(isStuck && position == dayPosition)
            val capsuleTop = child.getCapsuleScreenTop()
            if (position > dayPosition && capsuleTop < (nextDayCapsuleTop ?: Int.MAX_VALUE)) {
                nextDayCapsuleTop = capsuleTop
            }
        }
        val hasDayBeenStuck = day != null && stuckDayTimestamp == day.timestamp
        stuckDayTimestamp = day?.timestamp?.takeIf { isStuck }
        if (day == null || !isStuck) {
            hideFloatingDay(isAnimated = false)
            return
        }
        if (floatingDayTimestamp != day.timestamp) {
            floatingDayTimestamp = day.timestamp
            floatingDay.configure(Date(day.timestamp))
            // The layout pass of this frame is over, so the capsule takes the new day's width before it is drawn
            floatingDay.measure(
                View.MeasureSpec.makeMeasureSpec(floatingDay.width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(floatingDay.height, View.MeasureSpec.EXACTLY)
            )
            floatingDay.apply { layout(left, top, right, bottom) }
        }
        floatingDay.translationY = nextDayCapsuleTop
            ?.let { (it - pinnedCapsuleTop - floatingDay.capsuleRowHeight).coerceAtMost(0) }
            ?.toFloat()
            ?: 0f
        // It shows while the feed scrolls and goes once it rests, also with no other day's capsule on screen,
        // as on iOS and the web
        if (isUserScrolling) {
            // Where the day's own capsule has just gone under the header, the pinned one takes its place in the same
            // frame, so the day never blinks out; it fades in only when it comes back after going at rest
            showFloatingDay(isAnimated = hasDayBeenStuck)
        } else {
            hideFloatingDay(isAnimated = true)
        }
    }

    private fun showFloatingDay(isAnimated: Boolean) {
        if (isFloatingDayShown && !isFloatingDayHiding) return
        isFloatingDayShown = true
        isFloatingDayHiding = false
        floatingDay.animate().cancel()
        floatingDay.isInvisible = false
        if (isAnimated && WGlobalStorage.getAreAnimationsActive()) {
            floatingDay.animate().alpha(1f).setStartDelay(0).setDuration(FLOATING_DAY_FADE_MS)
                .start()
        } else {
            floatingDay.alpha = 1f
        }
    }

    private fun hideFloatingDay(isAnimated: Boolean) {
        if (!isFloatingDayShown) return
        val shouldFade = isAnimated && WGlobalStorage.getAreAnimationsActive()
        if (shouldFade && isFloatingDayHiding) return
        floatingDay.animate().cancel()
        if (!shouldFade) {
            isFloatingDayShown = false
            isFloatingDayHiding = false
            floatingDay.alpha = 0f
            floatingDay.isInvisible = true
            return
        }
        isFloatingDayHiding = true
        floatingDay.animate().alpha(0f).setStartDelay(FLOATING_DAY_HIDE_DELAY_MS)
            .setDuration(FLOATING_DAY_FADE_MS)
            .withEndAction {
                isFloatingDayShown = false
                isFloatingDayHiding = false
                floatingDay.isInvisible = true
            }
            .start()
    }

    private fun findDayRowPositions(rows: List<Row>): IntArray {
        var dayPosition = -1
        return IntArray(rows.size) { position ->
            if (rows[position] is Row.Day) dayPosition = position
            dayPosition
        }
    }

    private fun visibleAnchor(): Anchor? {
        val first = layoutManager.findFirstVisibleItemPosition()
        val last = layoutManager.findLastVisibleItemPosition()
        for (position in first..last) {
            // The feed keeps its cards in place rather than its day lines
            val row = rows.getOrNull(position)?.takeIf { it is Row.News || it is Row.Digest }
                ?: continue
            val child = layoutManager.findViewByPosition(position) ?: continue
            return Anchor(row.id, child.top - recyclerView.paddingTop)
        }
        return null
    }

    private fun restore(anchor: Anchor?) {
        if (anchor == null) return
        val position = rows.indexOfFirst { it.id == anchor.id }
        if (position >= 0) layoutManager.scrollToPositionWithOffset(position, anchor.offset)
    }

    // How far the latest card reaches below the part of the list that shows
    private fun measureLatestRowOverhang(): Int {
        if (rows.isEmpty()) return 0
        val last = layoutManager.findViewByPosition(rows.lastIndex)
            ?: return Int.MAX_VALUE
        return last.bottom - (recyclerView.height - recyclerView.paddingBottom)
    }

    private fun isNearBottom(): Boolean = measureLatestRowOverhang() <= NEAR_BOTTOM.dp

    private fun updateScrollButton(isAnimated: Boolean) {
        val shouldShow = hasInitialScroll && rows.isNotEmpty() && !isPopupVisible && !isNearBottom()
        scrollButton.setShown(shouldShow, isAnimated && isVisible)
    }

    private fun syncTopBlurAfterLayout() {
        updateBlurViews(recyclerView)
    }

    private fun scrollToBottom() {
        if (rows.isEmpty()) return
        recyclerView.scrollToPosition(rows.lastIndex)
        recyclerView.post {
            val last = layoutManager.findViewByPosition(rows.lastIndex) ?: return@post
            recyclerView.scrollBy(0, last.bottom - recyclerView.height + recyclerView.paddingBottom)
        }
    }

    private fun scrollToLatest() {
        // A scroll the user asks for is never taken over by the scroll to the requested digest
        model.stopSeekingRequestedDigest()
        if (rows.isEmpty()) return
        recyclerView.stopScroll()
        // A jump to a pinned digest still sliding ends where it is, so the jump to the end isn't dropped
        jumpScroll.finish()
        // The bar follows the list again, and shows the digest of the end as the jump lays the end out, before the
        // rows slide there, as Telegram's panel does
        isPinnedDigestFollowingScroll = true
        jumpScroll.scrollDown { layoutManager.scrollToPosition(rows.lastIndex) }
    }

    private fun imageHeightChanged() {
        jumpScroll.finish()
        val anchor = visibleAnchor()
        val stickToBottom = isNearBottom()
        recyclerView.post { if (stickToBottom) scrollToBottom() else restore(anchor) }
    }

    private fun onPopupVisibilityChanged(visible: Boolean) {
        isPopupVisible = visible
        if (visible) jumpScroll.finish()
        recyclerView.suppressLayout(visible)
        updateScrollButton(isAnimated = true)
    }

    private fun getMenuRows(): IntRange {
        val top = navigationBar?.let { it.getLocationInWindow().y + it.height }
            ?: recyclerView.getLocationInWindow().y
        return top until view.rootView.height - (navigationController?.getSystemBars()?.bottom ?: 0)
    }

    private fun showCopyBulletin() {
        copyBulletin.showCopied(
            view,
            recyclerView,
            LocaleController.getString("\$agent_message_copied")
        ) { bottomEdge() + AGENT_COMPOSER_FIELD_TOP.dp }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int) = rows.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath) =
        when (rows[indexPath.row]) {
            is Row.News -> NEWS_CELL
            is Row.Digest -> DIGEST_CELL
            is Row.Day -> DATE_CELL
            Row.Unread -> UNREAD_CELL
            is Row.Failure -> FAILURE_CELL
        }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath) =
        rows[indexPath.row].id

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            NEWS_CELL -> AgentNewsPostCell(context, textCache, AgentNewsPostCell.Style.FEED_CARD)
            DIGEST_CELL -> AgentNewsDigestCell(context)
            UNREAD_CELL -> AgentUnreadDividerCell(context)
            FAILURE_CELL -> AgentSystemMessageCell(context)
            else -> AgentDateHeaderCell(context, isDayCapsule = true)
        }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        skeletonReveal.finishRow(cellHolder.cell)
        val animate = animateFromIndex in 0..indexPath.row
        when (val row = rows[indexPath.row]) {
            is Row.News -> (cellHolder.cell as AgentNewsPostCell).apply {
                val item = row.item
                configure(
                    row.id,
                    parseAgentV2Timestamp(item.deliveredAt) ?: Date(0),
                    item.toNewsPost(model.locale),
                    rv.width,
                    animate
                )
                discussStrip?.configure(item, isDiscussionStarted(item))
                discussStrip?.onClick = { openDiscussion(item) }
                onOpenSource = { url -> AgentNewsSourceLinks.open(context, window, url) }
                onPictureTap = { openPhoto(item) }
                onCopied = ::showCopyBulletin
                onPopupVisibilityChanged = ::onPopupVisibilityChanged
                menuRows = ::getMenuRows
                canOpenMenuOnTap = { !hasStoppedScroll }
                onSizeTransitionFrame = { imageHeightChanged() }
            }

            is Row.Digest -> (cellHolder.cell as AgentNewsDigestCell).apply {
                val digest = row.digest
                configure(makeDigestCardContent(digest))
                onCopied = ::showCopyBulletin
                onPopupVisibilityChanged = ::onPopupVisibilityChanged
                menuRows = ::getMenuRows
                canOpenMenuOnTap = { !hasStoppedScroll }
                onHeadlineClick = ::openDigestHeadline
                onPictureClick = { openDigestPictures(digest, it) }
                discussStrip.onClick = { openDigestDiscussion(digest) }
            }

            is Row.Day -> (cellHolder.cell as AgentDateHeaderCell).apply {
                onPopupVisibilityChanged = ::onPopupVisibilityChanged
                menuRows = ::getMenuRows
                configure(Date(row.timestamp), animate)
            }

            Row.Unread -> Unit

            is Row.Failure -> (cellHolder.cell as AgentSystemMessageCell).configure(
                AgentMessage(
                    id = row.id,
                    role = AgentMessageRole.SYSTEM,
                    text = row.text,
                    isFailure = true
                ),
                onRetry = { model.refresh() }
            )
        }
    }

    private companion object {
        val DATE_CELL = WCell.Type(1)
        val NEWS_CELL = WCell.Type(2)
        val UNREAD_CELL = WCell.Type(3)
        val FAILURE_CELL = WCell.Type(4)
        val DIGEST_CELL = WCell.Type(5)

        const val LOAD_ERROR_SIDE_INSET = 32f
        const val NEAR_BOTTOM = 60

        // Telegram's floating date fades in and out in 150 ms, out half a second after the scroll stops
        const val FLOATING_DAY_FADE_MS = 150L
        const val FLOATING_DAY_HIDE_DELAY_MS = 500L

        const val SETTINGS_BUTTON_SIZE = 40

        // The bar keeps trailing views 8 dp in; a chat's menu button stands 4 dp nearer the edge
        const val SETTINGS_BUTTON_SHIFT = 4f

        const val PINNED_DIGEST_FADE_MS = 200L

        val NEWS_VIEWS = listOf(AgentNewsFeedView.All, AgentNewsFeedView.Digests)

        // As the root header's tabs in `PhoneTabsVC`
        const val VIEW_SWITCH_HEIGHT = 44
        const val VIEW_SWITCH_THUMB_HEIGHT = 36f
        const val VIEW_SWITCH_INSET = 4f
        const val VIEW_SWITCH_TAB_PADDING = 20
    }
}

internal fun AgentV2NewsFeedItem.toNewsPost(locale: String?) = AgentNewsPostContent(
    AgentV2ThreadNewsCard(
        eventId = eventId,
        headline = headline,
        imageUrl = imageUrl,
        publishedAt = deliveredAt,
        body = body,
        sources = sources
    ),
    locale
)
