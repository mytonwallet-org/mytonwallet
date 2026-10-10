package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.animation.ValueAnimator
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.text.InputFilter
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
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
import androidx.core.view.doOnNextLayout
import androidx.core.view.doOnPreDraw
import androidx.core.view.isGone
import androidx.core.view.setPadding
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import java.util.Date
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uiagent.agentV2.agentUnavailableText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentDateHeaderCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentHintsCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.cells.AgentSystemMessageCell
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentComposerView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentConsentView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.drawable.GradientShaderDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WEditText
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialogButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.moshi.agentV2.AgentV2EntryPoint

class AgentVC(
    context: Context,
    initialPrompt: String? = null,
    initialPinnedMessageId: String? = null,
    initialEntryPoint: AgentV2EntryPoint = AgentV2EntryPoint()
) : WViewController(context),
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
        private const val KEYBOARD_GAP = 12
        private const val HINTS_SETTLE_FALLBACK_MS = 3000L
        private const val INCOMING_MESSAGE_DELAY_MS = 250L
        private const val HISTORY_LOAD_THRESHOLD = 5
        private const val PROBLEM_REPORT_COMMENT_LINES = 4
        private const val PROBLEM_REPORT_COMMENT_MAX_LENGTH = 1000
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
    private var hasAppeared = false
    private var isPreparingAppearance = false
    private var initialPromptAwaitingInsertion = initialPrompt?.takeIf {
        initialPinnedMessageId.isNullOrBlank() && it.isNotBlank()
    }
    private val pendingPrompts = AgentPromptQueue().apply {
        initialPromptAwaitingInsertion?.let {
            enqueue(it, initialEntryPoint, shouldWaitForAppearance = true)
        }
    }
    private var requestedPinnedMessageId = initialPinnedMessageId?.takeIf { it.isNotBlank() }
    private var shouldJumpToRequestedMessage = requestedPinnedMessageId != null
    private var timelineItems = listOf<AgentTimelineItem>()
    private var animateFromIndex = -1
    private var gradientHeightAnimator: ValueAnimator? = null
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

    private val chatRecyclerView: WRecyclerView = object : WRecyclerView(this) {
        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (isEditFading || editPresentation != null) return true
            return super.dispatchTouchEvent(event)
        }
    }.apply {
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
                            ?.let { it in 0..HISTORY_LOAD_THRESHOLD } == true
                    ) {
                        viewport.shareScrollPosition()
                        vm.loadOlderMessages()
                    }
                }
                updateBlurViews(recyclerView)
                viewport.shareScrollPosition()
            }
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

    private val viewport: AgentTimelineViewport by lazy {
        AgentTimelineViewport(object : AgentTimelineViewport.Host {
            override fun onMessagePinned(messageId: String) {
                editPresentation?.takeIf { it.outgoingMessageId == messageId }?.hasPinned = true
                finishEditPresentation(messageId)
            }

            override val recyclerView get() = chatRecyclerView
            override val timelineItems get() = this@AgentVC.timelineItems
            override val scrollPosition get() = vm.scrollPosition
            override val topPadding get() = chatTopPadding()
            override val isPopupVisible get() = this@AgentVC.isPopupVisible
            override val dismissingHintsIndex
                get() = dismissingHints?.let {
                    timelineItems.indexOf(it)
                }
                    ?: -1

            override fun baseBottomPadding(bottom: Int) =
                composerView.height + bottom + composerBottomOffset.dp + BOTTOM_OFFSET.dp

            override fun publishScrollPosition(position: AgentVM.ScrollPosition) =
                vm.updateScrollPosition(this@AgentVC, position)

            override fun presentationMessageId(messageId: String) = timelineItems
                .filterIsInstance<AgentTimelineItem.Message>()
                .firstOrNull { it.message.id == messageId }?.message?.id
                ?: vm.messages.firstOrNull { it.matchesMessageId(messageId) }?.id

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

    private val bottomGradientView = View(context).apply {
        id = View.generateViewId()
    }
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
    private var editingMessageId: String? = null

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

    private val consentView by lazy {
        AgentConsentView(context).apply {
            isGone = true
            onAllow = {
                showError(null)
                vm.acceptConsent()
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
        composerView.onHeightChanged = {
            updateLayout()
        }

        view.addView(contentContainer, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(consentView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

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
        isPreparingAppearance = true
        vm.setActive(this, true)
        updateVisibleHintsAvailability()
        when {
            initialPromptAwaitingInsertion != null -> viewport.showInitialPromptAtBottom()
            requestedPinnedMessageId != null -> prepareRequestedMessageForAppearance()
            else -> viewport.restoreSharedScrollPosition()
        }
    }

    override fun viewDidAppear() {
        super.viewDidAppear()
        hasAppeared = true
        isPreparingAppearance = false
        if (showRequestedMessageIfAvailable() || requestedPinnedMessageId != null) return
        viewport.restorePendingPosition()
        if (initialPromptAwaitingInsertion != null) viewport.showInitialPromptAtBottom()
        submitPendingPrompts()
    }

    override fun viewWillDisappear() {
        hasAppeared = false
        isPreparingAppearance = false
        viewport.shareScrollPosition()
        super.viewWillDisappear()
        vm.setActive(this, false)
    }

    override fun onDestroy() {
        pendingPrompts.clear()
        viewport.shareScrollPosition()
        cancelHintsSettleFallback()
        editPresentation = null
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
        viewport.dispose()
        gradientHeightAnimator?.cancel()
        context.unregisterReceiver(timezoneReceiver)
        super.onDestroy()
        editFadeAnimator?.cancel()
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
            bottomGradientView.background = GradientShaderDrawable(
                intArrayOf(bgColor.colorWithAlpha(0), bgColor.colorWithAlpha(229)),
                floatArrayOf(0f, 1f)
            )
        } else {
            bottomGradientView.isGone = true
        }
        composerView.updateTheme()
        consentView.updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        contentContainer.setPaddingLocalized(
            additionalTabletPadding + systemBarStartInset,
            0,
            systemBarEndInset,
            0
        )
        consentView.updateInsets(chatTopPadding(), viewport.currentBottom)
        topReversedCornerView?.setSideInsets(
            systemBarStartInset.toFloat(),
            systemBarEndInset.toFloat()
        )
        updateLayout()
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

    private fun chatTopPadding(): Int =
        (navigationController?.getSystemBars()?.top ?: 0) + (navigationBar?.height ?: 0)

    private fun updateLayout() {
        val ime = navigationController?.imeInsetBottom ?: 0
        val nav = navigationController?.getSystemBars()?.bottom ?: 0
        val aboveKeyboard = if (ime > 0) {
            ime + KEYBOARD_GAP.dp - composerView.inputBottomInset - composerBottomOffset.dp
        } else {
            0
        }
        viewport.updateLayout(maxOf(aboveKeyboard, nav), ime, nav)
    }

    private fun updateGradientHeight(animated: Boolean) {
        val lp = bottomGradientView.layoutParams ?: return
        val targetHeight = composerView.height + viewport.currentBottom + GRADIENT_EXTRA.dp

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
        val accepted = vm.sendMessage(text, entryPoint)
        if (accepted) view.hideKeyboard()
        return accepted
    }

    private fun sendFollowup(messageId: String, followupId: String) {
        if (vm.sendFollowup(messageId, followupId)) view.hideKeyboard()
    }

    fun submitPrompt(text: String, entryPoint: AgentV2EntryPoint = AgentV2EntryPoint()) {
        if (text.isBlank()) return
        pendingPrompts.enqueue(text, entryPoint)
        submitPendingPrompts()
    }

    override fun onMessageAcceptanceChanged() {
        if (!isSessionReleased) submitPendingPrompts()
    }

    private fun submitPendingPrompts() {
        if (agentState == AgentVM.State.CLEARING || isSessionReleased) return
        pendingPrompts.submit(hasAppeared, vm::sendMessage)
    }

    fun showMessage(messageId: String) {
        if (messageId.isBlank()) return
        initialPromptAwaitingInsertion = null
        pendingPrompts.clear()
        shouldJumpToRequestedMessage = false
        requestedPinnedMessageId = messageId
        if (!hasAppeared || showRequestedMessageIfAvailable()) return
        if (agentState == AgentVM.State.READY) loadRequestedMessage(messageId)
    }

    private fun presentMoreMenu() {
        val items = mutableListOf<WMenuPopup.Item>()

        if (agentState == AgentVM.State.ERROR) {
            items.add(
                WMenuPopup.Item(null, LocaleController.getString("Retry")) {
                    vm.retry()
                }
            )
        }

        if (vm.canReportProblem) {
            items.add(
                WMenuPopup.Item(
                    org.mytonwallet.app_air.icons.R.drawable.ic_flag_30,
                    LocaleController.getString("Report a Problem")
                ) {
                    presentProblemReportForm(null)
                }
            )
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
            positioning = WMenuPopup.Positioning.ALIGNED,
            backdropStyle = WMenuPopup.BackdropStyle.Transparent
        )
    }

    private fun clearChat() {
        editingMessageId = null
        vm.clearChat()
    }

    /** Opens the report form; after a failed send it opens again with the [failedComment] the user wrote */
    private fun presentProblemReportForm(presentationId: String?, failedComment: String? = null) {
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

    override fun onStateChanged(state: AgentVM.State) {
        agentState = state
        val showsConsent = state == AgentVM.State.CONSENT_REQUIRED ||
            state == AgentVM.State.ACCEPTING_CONSENT
        contentContainer.isGone = showsConsent
        consentView.isGone = !showsConsent
        consentView.setLoading(state == AgentVM.State.ACCEPTING_CONSENT)
        if (state == AgentVM.State.ACCEPTING_CONSENT) consentView.showError(null)
        val isClearing = state == AgentVM.State.CLEARING
        composerView.setSubmissionEnabled(
            !isClearing && editFadeAnimator == null && regeneratingMessageId == null
        )
        moreButton.isGone = showsConsent || isClearing

        if (state != AgentVM.State.READY) return
        val messageId = requestedPinnedMessageId ?: return
        if (viewport.timelineIndexOf(messageId) >= 0) {
            if (hasAppeared) showRequestedMessageIfAvailable()
            return
        }
        loadRequestedMessage(messageId)
    }

    private fun loadRequestedMessage(messageId: String) {
        vm.loadMessageHistoryUntil(messageId) { found ->
            if (requestedPinnedMessageId != messageId) return@loadMessageHistoryUntil
            if (found) {
                if (hasAppeared) {
                    showRequestedMessageIfAvailable()
                } else if (isPreparingAppearance) {
                    prepareRequestedMessageForAppearance()
                }
            } else {
                restoreAfterMissingRequestedMessage()
            }
        }
    }

    private fun restoreAfterMissingRequestedMessage() {
        requestedPinnedMessageId = null
        shouldJumpToRequestedMessage = false
        if (!viewport.restoreSharedScrollPosition()) viewport.scrollToBottom()
    }

    override fun onMessagesLoaded(messages: List<AgentMessage>) {
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
        timelineItems = buildTimelineItems(messages)
        rvAdapter.reloadData()
        when {
            initialPromptAwaitingInsertion != null -> viewport.showInitialPromptAtBottom()

            requestedPinnedMessageId != null -> {
                if (hasAppeared) {
                    showRequestedMessageIfAvailable()
                } else if (isPreparingAppearance) {
                    prepareRequestedMessageForAppearance()
                }
            }

            !viewport.restoreSharedScrollPosition() -> viewport.scrollToBottom()
        }
    }

    override fun onMessagesTruncated(removedMessages: List<AgentMessage>) {
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
        if (vm.messages.firstOrNull { it.matchesMessageId(messageId) }?.text?.trim() ==
            text.trim()
        ) {
            return true
        }
        val latestUserMessage = vm.messages.lastOrNull { it.role == AgentMessageRole.USER }
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
            if (!isDestroyed && vm.messages.any { it.matchesMessageId(messageId) }) {
                editingMessageId = messageId
                composerView.setDraftText(text)
            }
        }) { rows ->
            editPresentation = EditPresentation(
                vm.messages.dropWhile { it.id != latestUserMessage.id },
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
        if (!vm.canRegenerateMessage(messageId) || editFadeAnimator != null) return
        val messageIndex = vm.messages.indexOfFirst { it.matchesMessageId(messageId) }
        vm.messages.take(messageIndex).lastOrNull { it.role == AgentMessageRole.USER }?.let {
            viewport.requestMessagePin(it.id, preservePadding = true)
        }
        val index = viewport.timelineIndexOf(messageId)
        if (index < 0 || !WGlobalStorage.getAreAnimationsActive()) {
            vm.regenerateMessage(messageId)
            return
        }
        chatRecyclerView.stopScroll()
        fadeMessagesFrom(index) { rows ->
            regeneratingMessageId = messageId
            rows.forEach { it.visibility = View.INVISIBLE }
            if (!vm.regenerateMessage(messageId)) {
                regeneratingMessageId = null
                rows.forEach { it.visibility = View.VISIBLE }
            }
        }
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
                composerView.setSubmissionEnabled(
                    agentState != AgentVM.State.CLEARING && regeneratingMessageId == null
                )
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
            val oldItems = timelineItems
            val top = layoutManager.findViewByPosition(viewport.timelineIndexOf(messageId))?.top
            editPresentation = null
            dismissingHints = null
            dismissingHintsAnchorId = null
            cancelHintsSettleFallback()
            animateFromIndex = -1
            val newItems = buildTimelineItems(vm.messages)
            val diff = DiffUtil.calculateDiff(
                object : DiffUtil.Callback() {
                    override fun getOldListSize() = oldItems.size
                    override fun getNewListSize() = newItems.size

                    override fun areItemsTheSame(oldPosition: Int, newPosition: Int): Boolean {
                        val old = oldItems[oldPosition]
                        val new = newItems[newPosition]
                        return when {
                            old is AgentTimelineItem.Message && new is AgentTimelineItem.Message ->
                                old.message.id == new.message.id

                            old is AgentTimelineItem.DateHeader &&
                                new is AgentTimelineItem.DateHeader -> old.date == new.date

                            else -> old == new
                        }
                    }

                    override fun areContentsTheSame(oldPosition: Int, newPosition: Int) =
                        oldItems[oldPosition] == newItems[newPosition]
                },
                false
            )
            timelineItems = newItems
            diff.dispatchUpdatesTo(WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0))
            val index = viewport.timelineIndexOf(messageId)
            if (index >= 0 && top != null) {
                layoutManager.scrollToPositionWithOffset(index, top - chatRecyclerView.paddingTop)
            }
            pendingIncomingReveals[messageId]?.let(::schedulePendingIncomingReveal)
            chatRecyclerView.doOnNextLayout { viewport.shareScrollPosition() }
        }
    }

    override fun onMessagesPrepended(messages: List<AgentMessage>) {
        animateFromIndex = -1
        timelineItems = buildTimelineItems(messages)
        rvAdapter.reloadData()
        viewport.restoreSharedScrollPosition()
        chatRecyclerView.doOnNextLayout {
            viewport.restorePendingPosition()
        }
    }

    private fun prepareRequestedMessageForAppearance() {
        if (!shouldJumpToRequestedMessage) return
        val messageId = requestedPinnedMessageId ?: return
        val index = viewport.timelineIndexOf(messageId)
        if (index < 0) return
        val layoutManager = chatRecyclerView.layoutManager as? LinearLayoutManager ?: return

        layoutManager.stackFromEnd = false
        layoutManager.scrollToPositionWithOffset(index, -viewport.pinnedTopOffset)
        if (chatRecyclerView.isLaidOut) {
            showRequestedMessageIfAvailable()
            return
        }

        chatRecyclerView.doOnNextLayout {
            if (isPreparingAppearance && requestedPinnedMessageId == messageId) {
                showRequestedMessageIfAvailable()
            }
        }
    }

    private fun showRequestedMessageIfAvailable(): Boolean {
        val requestedMessageId = requestedPinnedMessageId ?: return false
        val messageId = viewport.presentationMessageId(requestedMessageId) ?: return false

        val animated =
            !shouldJumpToRequestedMessage && WGlobalStorage.getAreAnimationsActive()
        shouldJumpToRequestedMessage = false
        requestedPinnedMessageId = null
        viewport.requestMessagePin(messageId)
        if (animated) {
            chatRecyclerView.post {
                evaluateRequestedMessage(messageId, animated)
            }
        } else {
            evaluateRequestedMessage(messageId, animated)
        }
        return true
    }

    private fun evaluateRequestedMessage(messageId: String, animated: Boolean) {
        if (viewport.pendingPinMessageId == messageId) {
            viewport.evaluatePinning(messageId, animated = animated)
        }
        syncTopBlurAfterLayout()
    }

    override fun onMessageAdded(message: AgentMessage, animated: Boolean) {
        if (message.role == AgentMessageRole.ASSISTANT && regeneratingMessageId != null) {
            regeneratingMessageId = null
            composerView.setSubmissionEnabled(
                agentState != AgentVM.State.CLEARING && editFadeAnimator == null
            )
        }
        if (!animated) {
            animateFromIndex = -1
            pendingHintsReveal = false
            cancelHintsSettleFallback()
            rebuildTimeline()
            return
        }
        if (message.role == AgentMessageRole.USER &&
            message.text == initialPromptAwaitingInsertion
        ) {
            initialPromptAwaitingInsertion = null
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
        timelineItems = buildTimelineItems(vm.messages)
        when {
            removedIndex >= 0 && oldItems.size == timelineItems.size + 1 -> {
                WRecyclerViewAdapter.OffsetUpdateCallback(rvAdapter, 0)
                    .onRemoved(removedIndex, 1)
            }

            oldItems != timelineItems -> rvAdapter.reloadData()
        }
    }

    override fun onStreamingUpdate(messageId: String) {
        onStreamEvent(messageId)
    }

    override fun onStreamingFinished(messageId: String) {
        onStreamEvent(messageId)
    }

    override fun onFollowupsChanged(messageId: String, animated: Boolean) {
        if (hiddenIncomingMessageIds.contains(messageId)) return
        val index = viewport.timelineIndexOf(messageId)
        if (index < 0) return
        val message = vm.messages.firstOrNull { it.id == messageId } ?: return
        timelineItems = timelineItems.toMutableList().apply {
            set(index, AgentTimelineItem.Message(message))
        }
        if (vm.visibleFollowups(messageId).isNotEmpty()) {
            onStreamEvent(messageId)
        } else if (!updateVisibleCell(messageId)) {
            rvAdapter.notifyItemChanged(index)
        }
        updateVisibleHintsAvailability()
    }

    private fun updateVisibleHintsAvailability() {
        for (index in 0 until chatRecyclerView.childCount) {
            val cell = chatRecyclerView.getChildAt(index) as? AgentHintsCell ?: continue
            val item = timelineItems.getOrNull(chatRecyclerView.getChildAdapterPosition(cell))
                as? AgentTimelineItem.Hints ?: continue
            cell.setCardsEnabled(item.followupMessageId == null || vm.canSendFollowup)
        }
    }

    override fun onOutgoingMessageFailed(messageId: String) {
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
        } else if (hadHints && newItems.lastOrNull() is AgentTimelineItem.Hints &&
            newItems.lastOrNull() != previousHints
        ) {
            rvAdapter.notifyItemChanged(newItems.size - 1)
        }
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
            cell.onContentSettled = { appendDueHints(messageId) }
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
        var newItems = buildTimelineItems(vm.messages)
        if (newItems.lastOrNull() is AgentTimelineItem.Hints) {
            newItems = newItems.dropLast(1)
        }
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
        val pinMessageId = viewport.deferredPinMessageId.takeIf { it == outgoingMessageId }
        chatRecyclerView.doOnNextLayout {
            animateFromIndex = -1
            if (pinMessageId != null && viewport.pendingPinMessageId == pinMessageId) {
                viewport.clearDeferredPin()
                viewport.evaluatePinning(pinMessageId)
            } else if (viewport.pinnedMessageId != null) {
                viewport.syncPinnedPadding()
            }
            if (buildTimelineItems(vm.messages).lastOrNull() is AgentTimelineItem.Hints) {
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
        val canonical = buildTimelineItems(vm.messages)
        if (canonical.lastOrNull() !is AgentTimelineItem.Hints) return
        timelineItems = canonical
        scheduleHintsReveal()
        insertHintsItem()
        viewport.refreshIsOnBottom()
        if (viewport.isOnBottom) viewport.scrollToBottom()
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
        viewport.preserveCollapsingHintsSpace(delta, hintsIdx, dismissingHintsAnchorId != null)
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
            viewport.refreshIsOnBottom()
            if (viewport.isOnBottom) viewport.scrollToBottom()
        }
    }

    private fun updateVisibleCell(messageId: String): Boolean {
        val idx = viewport.timelineIndexOf(messageId)
        if (idx < 0) return false

        val holder = chatRecyclerView.findViewHolderForAdapterPosition(idx)
        if (holder is WCell.Holder) {
            val message = (timelineItems[idx] as AgentTimelineItem.Message).message
            val cell = holder.cell as? AgentMessageCell ?: return false
            cell.configure(message, chatRecyclerView.width, vm.publishesAnswerLinks)
            return true
        }
        return false
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

    override fun onHintsUpdated(hints: List<AgentHint>) {
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
            viewport.refreshIsOnBottom()
            if (viewport.isOnBottom) viewport.scrollToBottom()
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

    override fun onError() {
        if (agentState == AgentVM.State.CONSENT_REQUIRED ||
            agentState == AgentVM.State.ACCEPTING_CONSENT
        ) {
            consentView.showError(agentUnavailableText())
        }
    }

    override fun onActionUnavailable() {
        Toast.makeText(
            context,
            LocaleController.getString("This action is no longer available."),
            Toast.LENGTH_SHORT
        ).show()
    }

    override fun onOpenDapp(site: MExploreSite) {
        val w = window ?: return
        val url = site.url ?: return
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
                navigationController?.tabBarController,
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

        val presentationMessages = editPresentation?.let { presentation ->
            val index = messages.indexOfFirst { it.id == presentation.outgoingMessageId }
            if (index < 0) {
                messages
            } else {
                messages.take(index) + presentation.removedMessages + messages.drop(index)
            }
        } ?: messages
        for (message in presentationMessages) {
            if (!message.hasVisibleContent ||
                hiddenIncomingMessageIds.contains(message.id)
            ) {
                continue
            }
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
        val followupOwner = messages.findFollowupOwner()
        val followups = followupOwner?.followups.orEmpty()
        if (followups.isNotEmpty() && followupOwner?.isStreaming == false &&
            !hiddenIncomingMessageIds.contains(followupOwner.id)
        ) {
            items.add(
                AgentTimelineItem.Hints(
                    followups.map { AgentHint(it.id, it.text, "", it.text) },
                    followupMessageId = followupOwner.id
                )
            )
        } else {
            val hints = vm.visibleHints
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
                (cellHolder.cell as AgentDateHeaderCell).configure(item.date, animate)
            }

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
                        shouldShowEmptyStateIcon = vm.messages.isEmpty(),
                        animate = pendingHintsReveal
                    )
                    setCardsEnabled(item.followupMessageId == null || vm.canSendFollowup)
                }
            }

            is AgentTimelineItem.Message -> {
                when (val cell = cellHolder.cell) {
                    is AgentMessageCell -> {
                        val messageId = item.message.id
                        val tracksIncomingReveal =
                            pendingIncomingReveals.containsKey(messageId)
                        val tracksPin = messageId == viewport.pendingPinMessageId
                        cell.onOpenUrl = { url -> openAnswerLink(url) }
                        cell.onAction = { actionId -> vm.performAction(messageId, actionId) }
                        cell.onReportProblem = { presentProblemReportForm(messageId) }
                        cell.canReportProblem = { vm.canReportProblem }
                        cell.canEditMessage = { vm.canEditMessage(messageId) }
                        cell.canRegenerateMessage = { vm.canRegenerateMessage(messageId) }
                        cell.onRegenerate = { regenerateMessage(messageId) }
                        cell.onEdit = {
                            if (vm.canEditMessage(messageId)) {
                                composerView.setDraftText(item.message.text)
                                editingMessageId = messageId
                            }
                        }
                        cell.onPopupVisibilityChanged = { visible, bubbleView ->
                            onCopyPopupVisibilityChanged(visible, bubbleView)
                        }
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
                            vm.publishesAnswerLinks,
                            animate
                        )
                    }

                    is AgentSystemMessageCell -> cell.configure(item.message)
                }
            }
        }
    }
}
