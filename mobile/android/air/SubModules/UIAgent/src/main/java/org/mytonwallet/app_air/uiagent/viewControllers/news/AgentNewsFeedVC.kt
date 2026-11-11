package org.mytonwallet.app_air.uiagent.viewControllers.news

import android.annotation.SuppressLint
import android.content.Context
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
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import java.util.TimeZone
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
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
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentNewsPostContent
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentRecyclerAnimationScrollHelper
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentSession
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVC
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentVM
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentChatBackgroundColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentHeaderBottom
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageTextCache
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentNewsPostCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentUnreadDividerCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.isAgentPicturePinchStart
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_HISTORY_LOAD_THRESHOLD
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBottomFadeView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBulletin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentChatTitleView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentScrollToBottomButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSkeletonReveal
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
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
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsDigestHeadline
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedDigest
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary
import org.mytonwallet.app_air.walletcore.pushNotifications.AgentNewsNotificationSettings

/**
 * The News feed, as a chat with the news: cards and daily digests in the order they came, a day
 * line before each day and "New" before the first unseen card, opening at that line or at the
 * latest card, or at [requestedDigestId] once it comes. The bell in the header opens the digest
 * and notifications sheet. [findThread] finds a discussion's chat among those the chat list has
 * loaded.
 */
@SuppressLint("ViewConstructor")
class AgentNewsFeedVC(
    context: Context,
    private val initialEventId: Int? = null,
    private val findThread: (String) -> AgentV2ThreadSummary? = { null },
    // The first page the list's News row has loaded, shown at once
    private val initialItems: List<AgentV2NewsFeedItem> = emptyList(),
    requestedDigestId: String? = null
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

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val model = AgentNewsFeedModel(scope, requestedDigestId = requestedDigestId)
    val requestedDigestId: String? get() = model.requestedDigestId
    private var rows = emptyList<Row>()
        set(value) {
            field = value
            dayRowPositions = findDayRowPositions(value)
        }

    // The position of the day line each row comes under, or -1
    private var dayRowPositions = IntArray(0)
    private var hasInitialScroll = false
    private var isVisible = false
    private val chatGate = AgentNewsChatGate()
    private var discussionSession: AgentVM? = null
    private var flightSourceCell: WeakReference<AgentNewsPostCell>? = null
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
            }
        })
    }
    private val latestScroll = AgentRecyclerAnimationScrollHelper(recyclerView)

    private var hasStoppedScroll = false
    private val scrollStopper = object : RecyclerView.SimpleOnItemTouchListener() {
        override fun onInterceptTouchEvent(rv: RecyclerView, e: MotionEvent): Boolean {
            if (e.actionMasked == MotionEvent.ACTION_DOWN) hasStoppedScroll = latestScroll.stop()
            return false
        }
    }
    private var isPopupVisible = false
    private val chatTitleView by lazy { AgentChatTitleView(context) }
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
        chatTitleView.setTitle(LocaleController.getString("News"), null)
        setNavTitle(LocaleController.getString("News"), animated = false)
        navigationBar?.addTrailingView(
            digestSettingsButton,
            ConstraintLayout.LayoutParams(SETTINGS_BUTTON_SIZE.dp, SETTINGS_BUTTON_SIZE.dp)
        )
        navigationBar?.setCenteredTitleView(chatTitleView, false)
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
                scrollButton,
                ConstraintLayout.LayoutParams(
                    AgentScrollToBottomButton.SIZE.dp,
                    AgentScrollToBottomButton.SIZE.dp
                )
            )
            setConstraints {
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
        scrollButtonBinding = AgentPreDrawBinding(recyclerView, scrollButtonUpdater)
        floatingDay.setupBlurWith(recyclerView)
        floatingDayBinding = AgentPreDrawBinding(recyclerView, floatingDayUpdater)
        recyclerView.addOnItemTouchListener(scrollStopper)
        model.onChange = ::updateFeed
        model.onReset = {
            hasInitialScroll = false
            wasLoadingMore = false
        }
        WalletCore.registerObserver(this)
        observeDigestHour()
        model.seed(initialItems)
        updateFeed()
        updateTheme()
        insetsUpdated()
    }

    override val headerHandoffContent: List<View>
        get() = listOf(chatTitleView, digestSettingsButton)

    /**
     * A new digest hour, set in the bell's sheet or anywhere else, brings that hour's digests; a hidden feed takes them
     * as it shows again, when it refreshes
     */
    private fun observeDigestHour() {
        scope.launch {
            AgentNewsNotificationSettings.shared.state
                .map { it.digestHour }
                .distinctUntilChanged()
                .drop(1)
                .collect { if (isVisible) model.refresh() }
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
        model.refresh()
    }

    override fun viewWillDisappear() {
        AgentHeaderHandoff.begin(this)
        isVisible = false
        latestScroll.finish()
        model.cancel()
        super.viewWillDisappear()
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        latestScroll.finish()
        scrollButtonBinding?.release()
        scrollButtonBinding = null
        floatingDayBinding?.release()
        floatingDayBinding = null
        floatingDay.animate().cancel()
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
        val items = photos.map { agentNewsMediaViewerItem(window, it.imageUrl!!, it.toNewsPost()) }
        MediaViewerVC.present(window, items, startIndex) { index ->
            val eventId = photos[index].eventId
            val position = rows.indexOfFirst { it is Row.News && it.item.eventId == eventId }
            (layoutManager.findViewByPosition(position) as? AgentNewsPostCell)?.makePhotoSource()
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
                        retainDiscussion(thread)
                        model.markDiscussion(eventId, thread)
                    },
                    onThreadMissing = ::forgetDiscussion
                )
            }

            is AgentNewsChatTarget.Discussion ->
                navigation.push(AgentVC(context, target.thread))

            is AgentNewsChatTarget.Digest ->
                AgentNavigation.openDigestChat(context, navigation, target.id)
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
                retainDiscussion(thread)
                model.markDiscussion(item.eventId, thread)
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
            beforePush = { chat -> prepareFlight(item, chat) }
        )
        return true
    }

    // A discussion the user hasn't written in yet starts with the news as the Agent's post, also when its thread was
    // made on an earlier visit; the card flies into that place
    private fun prepareFlight(item: AgentV2NewsFeedItem, chat: AgentVC) {
        if (isDiscussionStarted(item)) return
        val position = rows.indexOfFirst { it is Row.News && it.item.eventId == item.eventId }
        val cell = layoutManager.findViewByPosition(position) as? AgentNewsPostCell ?: return
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
        chatTitleView.updateTheme()
        skeleton.updateTheme()
        scrollButton.updateTheme()
        scrollButtonGlass?.updateTheme()
        floatingDay.updateTheme()
        rvAdapter.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val top = agentHeaderBottom() + AGENT_LIST_TOP_INSET.dp
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
        val finishedPagination = wasLoadingMore
        wasLoadingMore = model.isLoadingMore
        updateSkeleton()
        val error = model.error?.takeIf { model.entries.isEmpty() }
        if (error != null) {
            loadErrorView.setError(agentNewsErrorText(error))
        } else {
            loadErrorView.setMessage(
                LocaleController.getString("\$agent_news_empty").takeIf { model.isEmpty }
            )
        }
        val newRows = buildRows()
        val requestedDigestIndex = findRequestedDigestRow(newRows)
        if (newRows == rows && hasInitialScroll && requestedDigestIndex < 0) return
        latestScroll.finish()
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
            val initialNewsIndex = rows.indexOfFirst {
                it is Row.News && it.item.eventId == initialEventId
            }
            val unreadIndex = rows.indexOf(Row.Unread)
            if (initialNewsIndex >= 0) {
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

                is AgentNewsFeedEntry.Digest -> add(Row.Digest(entry.digest))
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
        latestScroll.scrollDown { layoutManager.scrollToPosition(rows.lastIndex) }
    }

    private fun imageHeightChanged() {
        latestScroll.finish()
        val anchor = visibleAnchor()
        val stickToBottom = isNearBottom()
        recyclerView.post { if (stickToBottom) scrollToBottom() else restore(anchor) }
    }

    private fun onPopupVisibilityChanged(visible: Boolean) {
        isPopupVisible = visible
        if (visible) latestScroll.finish()
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
                    item.toNewsPost(),
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
                val time = parseAgentV2Timestamp(digest.deliveredAt)
                    ?.let { AgentNewsTextBlock.formatPostTime(context, it) }
                    .orEmpty()
                configure(AgentNewsDigestCardContent(digest, time))
                onHeadlineClick = ::openDigestHeadline
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
    }
}

private fun AgentV2NewsFeedItem.toNewsPost() = AgentNewsPostContent(
    AgentV2ThreadNewsCard(
        eventId = eventId,
        headline = headline,
        imageUrl = imageUrl,
        publishedAt = deliveredAt,
        body = body,
        sources = sources
    )
)
