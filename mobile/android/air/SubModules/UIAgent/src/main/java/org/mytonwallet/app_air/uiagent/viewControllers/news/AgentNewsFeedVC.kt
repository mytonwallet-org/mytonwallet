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
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import java.util.TimeZone
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
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
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentChatTitleView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentCopyBulletin
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentHistorySpinner
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentLoadErrorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentMessagesSkeletonView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentPreDrawBinding
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentScrollToBottomButton
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentSkeletonReveal
import org.mytonwallet.app_air.uiagent.viewControllers.threadList.AgentThreadDateFormatting
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer.MediaViewerVC
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2NewsFeedItem
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadNewsCard
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2ThreadSummary

/**
 * The News feed, as a chat with the news: cards in the order they came, a day line before each
 * day and "New" before the first unseen card, opening at that line or at the latest card.
 * [findThread] finds a discussion's chat among those the chat list has loaded.
 */
@SuppressLint("ViewConstructor")
class AgentNewsFeedVC(
    context: Context,
    private val initialEventId: Int? = null,
    private val findThread: (String) -> AgentV2ThreadSummary? = { null },
    // The first page the list's News row has loaded, shown at once
    private val initialItems: List<AgentV2NewsFeedItem> = emptyList()
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

        data class Failure(val text: String) : Row {
            override val id = "failure"
        }
    }

    private data class Anchor(val id: String, val offset: Int)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val model = AgentNewsFeedModel(scope)
    private var rows = emptyList<Row>()
    private var hasInitialScroll = false
    private var isVisible = false
    private var isOpeningDiscussion = false
    private var discussionSession: AgentVM? = null
    private var flightSourceCell: WeakReference<AgentNewsPostCell>? = null
    private var wasLoadingMore = false
    private var isUserScrolling = false
    private var animateFromIndex = -1
    private val rvAdapter =
        WRecyclerViewAdapter(
            WeakReference(this),
            arrayOf(DATE_CELL, UNREAD_CELL, NEWS_CELL, FAILURE_CELL)
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
                        loadMoreNearTop()
                    }

                    RecyclerView.SCROLL_STATE_IDLE -> isUserScrolling = false
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
    private val paginationSpinner = AgentHistorySpinner(context)
    private val copyBulletin = AgentCopyBulletin()
    private val textCache = AgentMessageTextCache()
    private val scrollButton = AgentScrollToBottomButton(context).apply {
        setOnClickListener { scrollToLatest() }
    }
    private var scrollButtonGlass: WGlassView? = null
    private val scrollButtonUpdater = ViewTreeObserver.OnPreDrawListener {
        updateScrollButton(isAnimated = true)
        true
    }
    private var scrollButtonBinding: AgentPreDrawBinding? = null

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        chatTitleView.setTitle(LocaleController.getString("News"), null)
        setNavTitle(LocaleController.getString("News"), animated = false)
        navigationBar?.setCenteredTitleView(chatTitleView, false)
        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contentContainer.apply {
            clipChildren = false
            clipToPadding = false
            // Under the cards, so they come in over it as it fades
            addView(skeleton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(recyclerView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, 0))
            addView(bottomGradientView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
            addView(loadErrorView, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
            addView(
                paginationSpinner,
                ConstraintLayout.LayoutParams(
                    AgentHistorySpinner.SIZE.dp,
                    AgentHistorySpinner.SIZE.dp
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
                allEdges(recyclerView)
                toStart(skeleton)
                toEnd(skeleton)
                toTop(skeleton)
                toStart(bottomGradientView)
                toEnd(bottomGradientView)
                toBottom(bottomGradientView)
                toStart(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toEnd(loadErrorView, LOAD_ERROR_SIDE_INSET)
                toCenterY(loadErrorView)
                toCenterX(paginationSpinner)
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
        recyclerView.addOnItemTouchListener(scrollStopper)
        model.onChange = ::updateFeed
        model.onReset = {
            hasInitialScroll = false
            wasLoadingMore = false
        }
        WalletCore.registerObserver(this)
        model.seed(initialItems)
        updateFeed()
        updateTheme()
        insetsUpdated()
    }

    override val headerHandoffContent: List<View> get() = listOf(chatTitleView)

    override fun viewWillAppear() {
        super.viewWillAppear()
        AgentHeaderHandoff.begin(this)
        isVisible = true
        isOpeningDiscussion = false
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
    private fun isDiscussionStarted(item: AgentV2NewsFeedItem): Boolean {
        val threadId = item.discussion?.threadId ?: return false
        val loaded = AgentSession.findLoadedModel(threadId)
        if (loaded?.messages?.any { it.role == AgentMessageRole.USER } == true) return true
        return (findThread(threadId)?.messageCount ?: 0) > 1
    }

    private fun openPhoto(item: AgentV2NewsFeedItem) {
        val window = window ?: return
        val photos = rows.mapNotNull { row ->
            (row as? Row.News)?.item?.takeIf { !it.imageUrl.isNullOrBlank() }
        }
        val startIndex = photos.indexOfFirst { it.eventId == item.eventId }
        if (startIndex < 0) return
        val items = photos.map { agentNewsMediaViewerItem(window, it.imageUrl!!, it.toNewsCard()) }
        MediaViewerVC.present(window, items, startIndex) { index ->
            val eventId = photos[index].eventId
            val position = rows.indexOfFirst { it is Row.News && it.item.eventId == eventId }
            (layoutManager.findViewByPosition(position) as? AgentNewsPostCell)?.makePhotoSource()
        }
    }

    private fun openDiscussion(item: AgentV2NewsFeedItem) {
        if (isOpeningDiscussion) return
        val navigation = navigationController ?: return
        val locale = model.locale ?: return
        isOpeningDiscussion = true
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
            onThreadMissing = { threadId ->
                if (discussionSession?.currentThread?.id == threadId) releaseDiscussion()
                model.removeDiscussion(threadId)
            },
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
            toTopPx(paginationSpinner, agentHeaderBottom() + AgentHistorySpinner.TOP_GAP.dp)
            toBottomPx(skeleton, bottom + AGENT_MESSAGE_BOTTOM_GAP.dp)
            toBottomPx(
                scrollButton,
                bottom + (AGENT_COMPOSER_FIELD_TOP + AGENT_SCROLL_BUTTON_GAP).dp
            )
        }
    }

    override fun updateBlurViews(recyclerView: RecyclerView) {
        if (window?.isWideLayout == true) {
            topReversedCornerView?.setBlurAlpha(1f)
            return
        }
        super.updateBlurViews(recyclerView)
    }

    private fun bottomEdge(): Int = navigationController?.getSystemBars()?.bottom ?: 0

    private fun updateFeed() {
        val finishedPagination = wasLoadingMore
        wasLoadingMore = model.isLoadingMore
        updateSkeleton()
        paginationSpinner.setLoading(model.isLoadingMore)
        loadErrorView.setError(
            model.error?.takeIf { model.items.isEmpty() }?.let(::agentNewsErrorText)
        )
        val newRows = buildRows()
        if (newRows == rows && hasInitialScroll) return
        latestScroll.finish()
        val anchor = visibleAnchor()
        val stickToBottom = hasInitialScroll && !finishedPagination && isNearBottom()
        if (stickToBottom && appendLatest(newRows)) return
        rows = newRows
        rvAdapter.reloadData()
        if (!hasInitialScroll && rows.isNotEmpty()) {
            hasInitialScroll = true
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
        val shouldShow = model.isLoading && model.items.isEmpty() && model.error == null
        if (shouldShow == skeletonReveal.isShown) return
        if (shouldShow) {
            skeletonReveal.show()
        } else {
            skeletonReveal.reveal(hasRows = model.items.isNotEmpty())
        }
    }

    private fun loadMoreNearTop() {
        if (hasInitialScroll && isVisible &&
            layoutManager.findFirstVisibleItemPosition() in 0..AGENT_HISTORY_LOAD_THRESHOLD
        ) {
            model.loadMore()
        }
    }

    private fun buildRows(): List<Row> = buildList {
        var previousDay: Long? = null
        model.items.forEach { item ->
            val date = parseAgentV2Timestamp(item.deliveredAt) ?: Date(0)
            val day = AgentThreadDateFormatting.startOfDay(date, TimeZone.getDefault())
            if (day != previousDay) {
                add(Row.Day(day))
                previousDay = day
            }
            if (item.eventId == model.unreadEventId) add(Row.Unread)
            add(Row.News(item))
        }
        if (model.items.isNotEmpty()) {
            model.refreshError?.let { add(Row.Failure(agentNewsErrorText(it))) }
        }
    }

    private fun visibleAnchor(): Anchor? {
        val first = layoutManager.findFirstVisibleItemPosition()
        val last = layoutManager.findLastVisibleItemPosition()
        for (position in first..last) {
            val row = rows.getOrNull(position) as? Row.News ?: continue
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

    // The header's backing is final from the first frame the cards are laid out under it, not once they scroll
    private fun syncTopBlurAfterLayout() {
        recyclerView.doOnPreDraw { updateBlurViews(recyclerView) }
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
        copyBulletin.show(
            view,
            LocaleController.getString("Message Copied"),
            bottomEdge() + AGENT_COMPOSER_FIELD_TOP.dp
        )
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int) = rows.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath) =
        when (rows[indexPath.row]) {
            is Row.News -> NEWS_CELL
            is Row.Day -> DATE_CELL
            Row.Unread -> UNREAD_CELL
            is Row.Failure -> FAILURE_CELL
        }

    override fun recyclerViewCellItemId(rv: RecyclerView, indexPath: IndexPath) =
        rows[indexPath.row].id

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell =
        when (cellType) {
            NEWS_CELL -> AgentNewsPostCell(context, textCache, AgentNewsPostCell.Style.FEED_CARD)
            UNREAD_CELL -> AgentUnreadDividerCell(context)
            FAILURE_CELL -> AgentSystemMessageCell(context)
            else -> AgentDateHeaderCell(context)
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
                    item.toNewsCard(),
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

            is Row.Day -> (cellHolder.cell as AgentDateHeaderCell).apply {
                onPopupVisibilityChanged = ::onPopupVisibilityChanged
                menuRows = ::getMenuRows
                configure(Date(row.timestamp), animate, isDayOnly = true)
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

        const val LOAD_ERROR_SIDE_INSET = 32f
        const val NEAR_BOTTOM = 60
    }
}

private fun AgentV2NewsFeedItem.toNewsCard() = AgentV2ThreadNewsCard(
    eventId = eventId,
    headline = headline,
    imageUrl = imageUrl,
    publishedAt = deliveredAt,
    body = body,
    sources = sources
)
