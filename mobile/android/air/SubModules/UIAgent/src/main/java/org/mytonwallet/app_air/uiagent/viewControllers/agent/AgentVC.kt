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
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.core.view.doOnNextLayout
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.LinearSmoothScroller
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uiagent.processors.AgentHint
import org.mytonwallet.app_air.uiagent.processors.AgentResult
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentHintsSectionView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.stores.EnvironmentStore
import java.lang.ref.WeakReference
import java.util.Date
import kotlin.math.roundToInt

class AgentVC(context: Context) : WViewController(context),
    WRecyclerViewAdapter.WRecyclerViewDataSource,
    AgentVM.Delegate {

    override val TAG = "Agent"
    override val ignoreSideGuttering = true

    companion object {
        val DATE_CELL = WCell.Type(1)
        val MESSAGE_CELL = WCell.Type(2)
        val SYSTEM_CELL = WCell.Type(3)
        private const val HINTS_SECTION = 64.66f
        private const val HINTS_SPACING = 12
        private const val GRADIENT_EXTRA = 4
        private const val DATE_HEADER_GAP_MS = 10 * 60 * 1000L
    }

    private val hintsHiddenTranslationY = (HINTS_SECTION + HINTS_SPACING).dp

    private val vm = AgentVM(this)
    private var timelineItems = listOf<AgentTimelineItem>()
    private var animateFromIndex = -1
    private var currentBottom = 0
    private var keyboardAnimator: ValueAnimator? = null
    private var hintsPaddingAnimator: ValueAnimator? = null
    private var gradientHeightAnimator: ValueAnimator? = null
    private var isPopupVisible = false
    private var isUserScrolling = false
    private var isOnBottom = true

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
            SYSTEM_CELL
        )
    )

    private val chatRecyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        layoutManager = LinearLayoutManager(context).apply {
            stackFromEnd = true
        }
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrollStateChanged(recyclerView: RecyclerView, newState: Int) {
                if (newState == RecyclerView.SCROLL_STATE_DRAGGING) {
                    isUserScrolling = true
                } else if (newState == RecyclerView.SCROLL_STATE_IDLE) {
                    isUserScrolling = false
                }
            }

            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                if (!isUserScrolling) return
                val atBottom = !recyclerView.canScrollVertically(1)
                if (isOnBottom != atBottom) {
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
            }
        })
    }

    private val bottomGradientView = View(context).apply {
        id = View.generateViewId()
    }
    private val composerView = AgentComposerView(context)
    private val hintsSectionView = AgentHintsSectionView(context).apply {
        layoutParams = ConstraintLayout.LayoutParams(
            MATCH_PARENT, HINTS_SECTION.dp.roundToInt()
        )
        alpha = 0f
        isEnabled = false
        translationY = hintsHiddenTranslationY
    }

    private val moreButton: WImageButton by lazy {
        val btn = WImageButton(context)
        btn.setPaddingDp(8)
        btn.setImageDrawable(
            ContextCompat.getDrawable(context, org.mytonwallet.app_air.icons.R.drawable.ic_more)
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
        hintsSectionView.onHintTap = { hint ->
            sendMessage(hint.prompt)
        }
        composerView.onHintsToggle = {
            vm.toggleHintsVisibility()
        }

        view.addView(chatRecyclerView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomGradientView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, 0)
        )
        view.addView(hintsSectionView)
        view.addView(
            composerView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, ConstraintLayout.LayoutParams.WRAP_CONTENT)
        )

        view.setConstraints {
            allEdges(chatRecyclerView)

            toStart(bottomGradientView)
            toEnd(bottomGradientView)
            toBottom(bottomGradientView)

            toStart(composerView)
            toEnd(composerView)
            toBottomPx(composerView, navigationController?.getSystemBars()?.bottom ?: 0)

            toStart(hintsSectionView)
            toEnd(hintsSectionView)
            bottomToTop(hintsSectionView, composerView, HINTS_SPACING.toFloat())
        }

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
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        vm.isActive = true
        vm.checkAccountChanged()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        vm.isActive = false
    }

    override fun onDestroy() {
        super.onDestroy()
        vm.onDestroy()
        context.unregisterReceiver(timezoneReceiver)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.Background.color)
        val bgColor = WColor.Background.color
        val bgColor80 = bgColor.colorWithAlpha(204)
        val bgColor90 = bgColor.colorWithAlpha(230)
        bottomGradientView.background = GradientShaderDrawable(
            intArrayOf(bgColor90 and 0x00FFFFFF, bgColor80, bgColor90),
            floatArrayOf(0f, 0.1f, 1f)
        )
        composerView.updateTheme()
        hintsSectionView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updateLayout()
    }

    private var hasAppliedInitialLayout = false

    private fun updateLayout() {
        val ime = window?.imeInsets?.bottom ?: 0
        val nav = navigationController?.getSystemBars()?.bottom ?: 0
        val targetBottom = maxOf(ime, nav)

        if (targetBottom != currentBottom) {
            val fromBottom = currentBottom
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
                    applyBottom(value)
                }
                start()
            }
        } else {
            applyBottom(targetBottom)
        }
    }

    private fun applyBottom(bottom: Int) {
        view.setConstraints {
            toBottomPx(composerView, bottom)
        }
        updateGradientHeight(animated = false)

        val topPadding =
            (navigationController?.getSystemBars()?.top ?: 0) + (navigationBar?.height ?: 0)
        val hintsExtra = if (hintsSectionView.isEnabled) {
            HINTS_SECTION.dp.roundToInt() + HINTS_SPACING.dp + 16.dp
        } else 0
        val bottomPadding = composerView.height + bottom + hintsExtra
        val paddingChanged = chatRecyclerView.paddingTop != topPadding ||
            chatRecyclerView.paddingBottom != bottomPadding
        if (paddingChanged)
            chatRecyclerView.setPadding(0, topPadding, 0, bottomPadding)
    }

    private fun updateGradientHeight(animated: Boolean) {
        val lp = bottomGradientView.layoutParams ?: return
        val showHints = hintsSectionView.isEnabled
        val hintsExtra = if (showHints) {
            HINTS_SECTION.dp.roundToInt() + HINTS_SPACING.dp
        } else 0
        val targetHeight = composerView.height + currentBottom + hintsExtra + GRADIENT_EXTRA.dp

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

    private fun animateHintsPadding(showHints: Boolean) {
        val topPadding =
            (navigationController?.getSystemBars()?.top ?: 0) + (navigationBar?.height ?: 0)
        val hintsExtra = if (showHints) {
            HINTS_SECTION.dp.roundToInt() + HINTS_SPACING.dp + 16.dp
        } else 0
        val targetBottom = composerView.height + currentBottom + hintsExtra
        val currentPaddingBottom = chatRecyclerView.paddingBottom

        if (targetBottom == currentPaddingBottom) return

        hintsPaddingAnimator?.cancel()
        hintsPaddingAnimator = ValueAnimator.ofInt(currentPaddingBottom, targetBottom).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                val value = animator.animatedValue as Int
                chatRecyclerView.setPadding(0, topPadding, 0, value)
            }
            start()
        }
    }

    private fun sendMessage(text: String) {
        vm.sendMessage(text)
    }

    private fun presentMoreMenu() {
        val items = mutableListOf<WMenuPopup.Item>()

        if (DEBUG_MODE || EnvironmentStore.isBeta) {
            val currentType = vm.processorType
            val types =
                AgentVM.ProcessorType.entries.filter { it != currentType && (DEBUG_MODE || it != AgentVM.ProcessorType.MOCK) }
            for (type in types) {
                val label = when (type) {
                    AgentVM.ProcessorType.MOCK -> "Switch to Mock"
                    AgentVM.ProcessorType.REAL -> "Switch to Real"
                }
                items.add(WMenuPopup.Item(null, label) {
                    vm.setProcessor(type)
                })
            }
        }

        items.add(
            WMenuPopup.Item(
                WMenuPopup.Item.Config.Item(
                    icon = WMenuPopup.Item.Config.Icon(
                        icon = org.mytonwallet.app_air.icons.R.drawable.ic_remove,
                        tintColor = null
                    ),
                    title = "Clear Chat",
                    titleColor = WColor.Red.color
                )
            ) {
                clearChat()
            })

        WMenuPopup.present(
            moreButton,
            items,
            positioning = WMenuPopup.Positioning.ALIGNED
        )
    }

    private fun clearChat() {
        vm.clearChat()
        animateFromIndex = -1
        timelineItems = emptyList()
        rvAdapter.reloadData()
    }

    // AgentVM.Delegate

    override fun onMessagesLoaded(messages: List<AgentMessage>) {
        timelineItems = buildTimelineItems(messages)
        rvAdapter.reloadData()
        scrollToBottom()
    }

    override fun onMessageAdded(message: AgentMessage) {
        if (animateFromIndex < 0) {
            animateFromIndex = timelineItems.size
            chatRecyclerView.doOnNextLayout {
                animateFromIndex = -1
            }
        }
        timelineItems = buildTimelineItems(vm.messages)
        rvAdapter.reloadData()
        scrollToBottom()
    }

    override fun onStreamingUpdate(messageId: String, text: String) {
        onStreamEvent(messageId)
    }

    override fun onStreamingFinished(messageId: String) {
        onStreamEvent(messageId)
    }

    private fun onStreamEvent(messageId: String) {
        timelineItems = buildTimelineItems(vm.messages)
        if (!updateVisibleCell(messageId)) {
            rvAdapter.reloadData()
        }
        if (isOnBottom) {
            scrollToBottom()
        }
    }

    private fun updateVisibleCell(messageId: String): Boolean {
        val idx = timelineItems.indexOfFirst {
            it is AgentTimelineItem.Message && it.message.id == messageId
        }
        if (idx < 0) return false

        val holder = chatRecyclerView.findViewHolderForAdapterPosition(idx)
        if (holder is WCell.Holder) {
            val message = (timelineItems[idx] as AgentTimelineItem.Message).message
            (holder.cell as? AgentMessageCell)?.configure(message, chatRecyclerView.width)
            return true
        }
        return false
    }

    private fun scrollToBottom() {
        if (isUserScrolling)
            return
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

    private fun onCopyPopupVisibilityChanged(visible: Boolean, bubbleView: View?) {
        isPopupVisible = visible
        chatRecyclerView.suppressLayout(visible)
        if (visible && bubbleView != null) {
            if (viewsOverlap(bubbleView, topReversedCornerView)) {
                topReversedCornerView?.fadeOut()
            }
            if (viewsOverlap(bubbleView, bottomReversedCornerView)) {
                bottomReversedCornerView?.fadeOut()
            }
            if (viewsOverlap(bubbleView, navigationBar?.titleLabel)) {
                navigationBar?.titleLabel?.fadeOut()
            }
            if (viewsOverlap(bubbleView, moreButton)) {
                moreButton.fadeOut()
            }
            val tabBarController = navigationController?.tabBarController
            if (viewsOverlap(bubbleView, tabBarController?.bottomCornerView)) {
                tabBarController?.hideTabBar()
            }
            if (viewsOverlap(bubbleView, hintsSectionView)) {
                hintsSectionView.fadeOut()
            }
            if (viewsOverlap(bubbleView, composerView)) {
                composerView.fadeOut()
            }
            if (viewsOverlap(bubbleView, bottomGradientView)) {
                bottomGradientView.fadeOut()
            }
        } else {
            topReversedCornerView?.fadeIn()
            bottomReversedCornerView?.fadeIn()
            navigationBar?.titleLabel?.fadeIn()
            moreButton.fadeIn()
            navigationController?.tabBarController?.showTabBar()
            composerView.fadeIn()
            bottomGradientView.fadeIn()
            if (hintsSectionView.isEnabled) {
                hintsSectionView.fadeIn()
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
        timelineItems = buildTimelineItems(vm.messages)
        rvAdapter.reloadData()
    }

    override fun onHintsUpdated(hints: List<AgentHint>) {
        val shouldShow = hints.isNotEmpty()
        if (shouldShow) {
            hintsSectionView.configure(hints)
        }
        composerView.setHintsAvailable(vm.hasHints)
        composerView.setHintsActive(shouldShow)

        val wasShowing = hintsSectionView.isEnabled
        if (wasShowing == shouldShow) return

        hintsSectionView.isEnabled = shouldShow

        hintsSectionView.animate().cancel()
        hintsSectionView.animate()
            .alpha(if (shouldShow) 1f else 0f)
            .translationY(if (shouldShow) 0f else hintsHiddenTranslationY)
            .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
            .setInterpolator(AccelerateDecelerateInterpolator())
            .start()

        animateHintsPadding(shouldShow)
        updateGradientHeight(animated = true)
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
            if (lastDate == null || message.date.time - lastDate.time > DATE_HEADER_GAP_MS) {
                items.add(AgentTimelineItem.DateHeader(message.date))
            }
            lastDate = message.date
            items.add(AgentTimelineItem.Message(message))
        }
        return items
    }

    // WRecyclerViewDataSource

    override fun recyclerViewNumberOfSections(rv: RecyclerView): Int = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int =
        timelineItems.size

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath): WCell.Type {
        return when (timelineItems[indexPath.row]) {
            is AgentTimelineItem.DateHeader -> DATE_CELL
            is AgentTimelineItem.Message -> {
                val msg = (timelineItems[indexPath.row] as AgentTimelineItem.Message).message
                when (msg.role) {
                    AgentMessageRole.SYSTEM -> SYSTEM_CELL
                    else -> MESSAGE_CELL
                }
            }
        }
    }

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return when (cellType) {
            DATE_CELL -> AgentDateHeaderCell(context)
            SYSTEM_CELL -> AgentSystemMessageCell(context)
            else -> AgentMessageCell(context)
        }
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

            is AgentTimelineItem.Message -> {
                when (val cell = cellHolder.cell) {
                    is AgentMessageCell -> {
                        cell.onOpenUrl = { url -> openInAppBrowser(url) }
                        cell.onPopupVisibilityChanged = { visible, bubbleView ->
                            onCopyPopupVisibilityChanged(visible, bubbleView)
                        }
                        cell.configure(item.message, rv.width, animate)
                    }

                    is AgentSystemMessageCell -> cell.configure(item.message)
                }
            }
        }
    }
}
