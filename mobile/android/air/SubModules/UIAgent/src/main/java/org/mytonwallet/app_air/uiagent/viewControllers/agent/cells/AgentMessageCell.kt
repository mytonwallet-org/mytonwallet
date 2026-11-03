package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.animation.AnimatorSet
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Path
import android.graphics.Rect
import android.text.SpannableStringBuilder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.animation.doOnEnd
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.accessibility.AccessibilityViewCommand
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import kotlin.math.max
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.AgentTextLinks
import org.mytonwallet.app_air.uiagent.agentV2.buildAgentV2MessageBlocks
import org.mytonwallet.app_air.uiagent.agentV2.getAgentAnalyzingRequestText
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentAnswerFeedback
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentDeeplink
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_BUBBLE_TAIL_WIDTH
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DAMPING
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DELAY_MS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AGENT_TAIL_REVEAL_DURATION_MS
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentBubbleDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentFeedbackPillView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentRichMessageView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentTypingIndicatorView
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.StreamingRevealLabel
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.commonViews.toast.ToastManager
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.getLocationInWindow
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.frameAsPath
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.DeeplinkOpenSource
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

private const val MYTONWALLET_SCHEME_PREFIX = "mytonwallet://"
private const val MTW_SCHEME_PREFIX = "mtw://"
private const val MESSAGE_HORIZONTAL_PADDING_DP = 36
private const val RICH_MESSAGE_HORIZONTAL_GUTTER_DP = 40

// The rating pill overlaps the answer's top edge and reaches past its end, as a thought bubble over it, where
// Telegram's reactions bar is
private const val FEEDBACK_PILL_OVERLAP_DP = 16
private const val FEEDBACK_PILL_OVERHANG_DP = 24

private const val TEXT_SIZE = 17f
private const val LINE_HEIGHT = 22f
private const val MIN_BUBBLE_WIDTH = 44
private const val MIN_BUBBLE_HEIGHT = 40

// Half the 12 dp between rows
private const val ROW_MARGIN = 6f

// The tail's tip keeps this far from the screen's edge, the body 8 dp farther, and the text 14 dp into the body
private const val TAIL_TIP_INSET = 10f
private const val BUBBLE_TEXT_INSET = 14
private const val TAIL_SIDE_TEXT_INSET = BUBBLE_TEXT_INSET + AGENT_BUBBLE_TAIL_WIDTH

// The action buttons under an answer: Demibold 16/20, 3 dp under the bubble and each other
private const val ACTION_TEXT_SIZE = 16f
private const val ACTION_LINE_HEIGHT = 20f
private const val ACTION_GAP = 3

// How close a bubble may come to the side opposite its sender's
private const val OUTGOING_OPPOSITE_INSET = 50f
private const val INCOMING_OPPOSITE_INSET = 56f

@SuppressLint("ViewConstructor")
class AgentMessageCell internal constructor(
    context: Context,
    private val textCache: AgentMessageTextCache
) : WCell(
    context,
    LayoutParams(MATCH_PARENT, WRAP_CONTENT)
) {
    companion object {
        private val pendingDeeplinkAnimationIds = mutableSetOf<String>()

        // Answers whose status has come in once; scrolled back into view, the status is simply there
        private val revealedTypingMessageIds = LinkedHashSet<String>()
        private const val REVEALED_TYPING_LIMIT = 64
    }

    private val contentContainer = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }

    // A tap or a long press opens the message's menu, as in Telegram; a tap on a link keeps to the link
    private val bubbleContainer = WFrameLayout(context)
    val skeletonRevealView: View get() = bubbleContainer
    private var bubbleDrawable: AgentBubbleDrawable? = null
    private var tailAnimator: ValueAnimator? = null
    private val messageLabel = StreamingRevealLabel(context).apply {
        id = UIComponentsR.id.agent_message_text
        setStyle(adaptiveFontSize(TEXT_SIZE))
        setLineHeight(LINE_HEIGHT)
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        useCustomEmoji = true
        movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
    }
    private val richMessageView = AgentRichMessageView(context).apply {
        visibility = GONE
    }
    private val typingIndicator = AgentTypingIndicatorView(context).apply {
        id = UIComponentsR.id.agent_typing_indicator
        visibility = GONE
    }
    private val deeplinkContainer = LinearLayout(context).apply {
        id = UIComponentsR.id.agent_message_actions
        orientation = LinearLayout.VERTICAL
    }
    private val copyLongClickListener = OnLongClickListener { source ->
        val link = (source as? TextView)?.let(menuTouch::linkAt)
        if (link != null) {
            requestLinkMenu(source, link, menuTouch.take(bubbleContainer))
            true
        } else if (isCopyable) {
            requestCopyMenu(menuTouch.take(bubbleContainer))
            true
        } else {
            false
        }
    }
    private val copyClickListener = OnClickListener { view ->
        val isOnLink = (view as? TextView)?.let(menuTouch::isOnLink) == true
        if (isCopyable && !isOnLink && canOpenMenuOnTap()) {
            requestCopyMenu(menuTouch.take(bubbleContainer))
        }
    }

    private val menuTouch = AgentMenuTouch()

    /** Whether a tap may open the menu now; the chat says no to a tap that stops its scroll */
    var canOpenMenuOnTap: () -> Boolean = { true }

    /** How the chat opens the menu, which may wait for the keyboard to go */
    var menuPresenter: AgentMenuPresenter? = null

    /** Rows where the menu leaves the bubble undimmed */
    var menuRows: AgentMenuRows = { getAgentListRows(this) }

    init {
        bubbleContainer.addView(messageLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        bubbleContainer.addView(
            richMessageView,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        contentContainer.addView(
            bubbleContainer,
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
        )
        contentContainer.addView(
            deeplinkContainer,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        addView(contentContainer, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(typingIndicator, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        bubbleContainer.setOnLongClickListener(copyLongClickListener)
        bubbleContainer.setMessageMenuTapListener(copyClickListener)
        messageLabel.setOnLongClickListener(copyLongClickListener)
        messageLabel.setMessageMenuTapListener(copyClickListener)
        messageLabel.onRevealFinished = {
            if (pendingRichMessageId == currentMessage?.id) {
                showRichMessage(animate = true)
            } else {
                notifyContentSettled()
            }
        }
        messageLabel.onSizeTransitionFrame = {
            onSizeTransitionFrame?.invoke(height)
        }
    }

    var onOpenUrl: ((String) -> Unit)? = null
    var onAction: ((String) -> Unit)? = null
    var onReportProblem: (() -> Unit)? = null
    var onEdit: (() -> Unit)? = null
    var canEditMessage: () -> Boolean = { false }
    var onRegenerate: (() -> Unit)? = null
    var canRegenerateMessage: () -> Boolean = { false }
    var canReportProblem: () -> Boolean = { false }

    /** Sets the rating of this answer, or withdraws it with null */
    var onRate: ((AgentAnswerFeedback?) -> Unit)? = null
    var onPopupVisibilityChanged: ((visible: Boolean) -> Unit)? = null

    var onCopied: (() -> Unit)? = null
    var onSizeTransitionFrame: ((previousHeight: Int) -> Unit)? = null
    var onInsertAnimationStarted: ((targetHeight: Int) -> Unit)? = null
    var onInsertAnimationFinished: (() -> Unit)? = null

    // Fires after message content and its controls finish their reveal
    var onContentSettled: (() -> Unit)? = null
    val isContentSettling: Boolean
        get() = isInsertAnimationPending || insertAnimation != null ||
            messageLabel.isRevealAnimating || deeplinkAnimator != null ||
            pendingRichMessageId != null || richTransitionAnimator?.isRunning == true ||
            typingCrossfadeAnimator?.isRunning == true

    private fun notifyContentSettled() {
        if (isContentSettling) return
        val callback = onContentSettled
        onContentSettled = null
        callback?.invoke()
    }

    private var insertAnimation: SpringAnimation? = null
    private var insertAnimationOnFinished: (() -> Unit)? = null
    private var isInsertAnimationPending = false
    private var insertAnimationTargetHeight = 0
    internal val layoutTargetHeight: Int
        get() = insertAnimationTargetHeight.takeIf { it > 0 } ?: height
    private var isStreamingCell = false
    private var renderedBubbleShape: Pair<Boolean, Boolean>? = null
    private var currentMessage: AgentMessage? = null
    private var isOutgoingCell = false
    private var renderedDeeplinks: List<AgentDeeplink> = emptyList()
    private var renderedDeeplinkTint = 0
    private var renderedDeeplinkMaxWidth = 0
    private var deeplinkAnimator: AnimatorSet? = null
    private var pendingRichMessageId: String? = null
    private var richTransitionAnimator: ValueAnimator? = null
    private var typingCrossfadeAnimator: ValueAnimator? = null
    private var isRenderingEnabled = true
    private var richContentWidth = 0
    private var renderedRichKey: RichRenderKey? = null
    private var shownTextKey: AgentMessageTextCache.TextKey? = null

    private data class RichRenderKey(
        val messageId: String,
        val blocks: List<MarkdownParser.Block>,
        val contentWidth: Int,
        val codeColor: Int,
        val textColor: Int,
        val separatorColor: Int,
        val detectsUrls: Boolean
    )

    private val isCopyable: Boolean
        get() {
            val msg = currentMessage ?: return false
            return msg.hasText && !isStreamingCell
        }

    fun setRenderingActive(active: Boolean) {
        isRenderingEnabled = active
        messageLabel.setRenderingActive(active)
        typingIndicator.setRenderingActive(active)
        updateRenderingAnimations()
    }

    private fun updateRenderingAnimations() {
        val active = isRenderingEnabled && isAttachedToWindow
        if (active) {
            insertAnimation?.start()
            scheduleInsertAnimation()
        } else {
            // Retain the spring's value and velocity until rendering resumes
            insertAnimation?.cancel()
        }
        for (animator in arrayOf(
            typingCrossfadeAnimator,
            richTransitionAnimator,
            deeplinkAnimator
        )) {
            if (active) animator?.resume() else animator?.pause()
        }
    }

    /** [hasFollowupsBelow]: suggestions hang from the bubble, which then has no tail */
    fun configure(
        message: AgentMessage,
        recyclerWidth: Int,
        publishesAnswerLinks: Boolean,
        shouldAnimate: Boolean = false,
        hasFollowupsBelow: Boolean = false
    ) {
        val previousMessageId = currentMessage?.id
        if (previousMessageId != message.id) {
            onContentSettled = null
            insertAnimationTargetHeight = 0
            cancelTypingCrossfade()
            resetRichMessagePresentation()
        }
        currentMessage = message
        val isOutgoing = message.role == AgentMessageRole.USER
        isOutgoingCell = isOutgoing
        // The role id sits on the cell, which stays visible when an answer has
        // no bubble, and marks an answer that is still streaming apart.
        id = when {
            isOutgoing -> UIComponentsR.id.agent_message_user
            message.isStreaming -> UIComponentsR.id.agent_message_streaming
            else -> UIComponentsR.id.agent_message_assistant
        }
        val detectsUrls = isOutgoing || !publishesAnswerLinks
        val showTyping = message.isStreaming && !message.hasText
        val wasStreaming = isStreamingCell
        val shouldAnimateInsert = shouldAnimate && !wasStreaming
        isInsertAnimationPending = shouldAnimateInsert
        isStreamingCell = message.isStreaming
        bubbleContainer.isHapticFeedbackEnabled = isCopyable
        // TalkBack offers the message's menu as "More actions"
        ViewCompat.replaceAccessibilityAction(
            bubbleContainer,
            AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_LONG_CLICK,
            LocaleController.getString("More actions").takeIf { isCopyable },
            if (isCopyable) {
                AccessibilityViewCommand { _, _ ->
                    requestCopyMenu(touch = null)
                    true
                }
            } else {
                null
            }
        )
        val hasDeeplinks = message.deeplinks.isNotEmpty()
        val wasShowingTypingForSameMessage = previousMessageId == message.id &&
            typingIndicator.isVisible && typingCrossfadeAnimator == null
        if (message.isStreaming) {
            pendingDeeplinkAnimationIds.add(message.id)
        }
        val animateDeeplinks = hasDeeplinks && !message.isStreaming &&
            pendingDeeplinkAnimationIds.contains(message.id)
        if (!message.isStreaming && !hasDeeplinks) {
            pendingDeeplinkAnimationIds.remove(message.id)
        }
        val showDeeplinks = hasDeeplinks && !message.isStreaming

        if (showTyping) {
            cancelTypingCrossfade()
            messageLabel.visibility = GONE
            typingIndicator.visibility = VISIBLE
            typingIndicator.setStatus(
                message.activityText ?: getAgentAnalyzingRequestText(),
                isAnimated = previousMessageId == message.id
            )
            if (revealedTypingMessageIds.add(message.id)) {
                if (revealedTypingMessageIds.size > REVEALED_TYPING_LIMIT) {
                    revealedTypingMessageIds.remove(revealedTypingMessageIds.first())
                }
                typingIndicator.revealStatus()
            }
            bubbleContainer.alpha = 0f
        } else {
            messageLabel.visibility = VISIBLE
            if (wasShowingTypingForSameMessage) {
                crossfadeFromTypingIndicator()
            } else if (typingCrossfadeAnimator == null) {
                typingIndicator.visibility = GONE
                bubbleContainer.alpha = 1f
            }
        }
        val maxBubbleWidth = recyclerWidth - 15f.dp.roundToInt()
        // As wide as the bubble may be between its margins, so the text wraps where the bubble ends
        val oppositeInset = if (isOutgoing) OUTGOING_OPPOSITE_INSET else INCOMING_OPPOSITE_INSET
        val standardMessageMaxWidth =
            (recyclerWidth - (TAIL_TIP_INSET + oppositeInset).dp.roundToInt()).coerceAtLeast(1)
        val richBlocks = if (
            message.role == AgentMessageRole.ASSISTANT &&
            (!message.isStreaming || message.tableReferences.isNotEmpty())
        ) {
            richBlocksFor(message)
        } else {
            null
        }
        val messageMaxWidth = if (richBlocks != null) {
            (recyclerWidth - RICH_MESSAGE_HORIZONTAL_GUTTER_DP.dp).coerceAtLeast(1)
        } else {
            standardMessageMaxWidth
        }

        updateBubbleBackground(
            isOutgoing = isOutgoing,
            hasActions = !isOutgoing && showDeeplinks,
            hasTail = !hasFollowupsBelow,
            isSameMessage = previousMessageId == message.id
        )
        if (isOutgoing) {
            messageLabel.setTextColor(WColor.TextOnTint.color)
            messageLabel.setPaddingDpLocalized(BUBBLE_TEXT_INSET, 10, TAIL_SIDE_TEXT_INSET, 10)
            messageLabel.maxWidth = standardMessageMaxWidth
            deeplinkContainer.visibility = GONE

            setConstraints {
                constrainedWidth(contentContainer.id, true)
                toTop(contentContainer, ROW_MARGIN)
                toBottom(contentContainer, ROW_MARGIN)
                toEnd(contentContainer, TAIL_TIP_INSET)
                toStart(contentContainer, OUTGOING_OPPOSITE_INSET)
                setHorizontalBias(contentContainer.id, 1f)
            }
        } else {
            messageLabel.setTextColor(WColor.PrimaryText.color)
            messageLabel.setPaddingDpLocalized(TAIL_SIDE_TEXT_INSET, 10, BUBBLE_TEXT_INSET, 10)
            messageLabel.maxWidth = messageMaxWidth

            setupDeeplinks(
                if (showDeeplinks) message.deeplinks else emptyList(),
                maxBubbleWidth,
                animateDeeplinks
            )

            setConstraints {
                constrainedWidth(contentContainer.id, true)
                toTop(contentContainer, ROW_MARGIN)
                toBottom(contentContainer, ROW_MARGIN)
                toStart(contentContainer, TAIL_TIP_INSET)
                toEnd(
                    contentContainer,
                    if (richBlocks != null) 30f else INCOMING_OPPOSITE_INSET
                )
                setHorizontalBias(contentContainer.id, 0f)
                constrainedWidth(typingIndicator.id, true)
                toTop(typingIndicator, ROW_MARGIN)
                // Its icon and text line up with the bubbles' text
                toStart(typingIndicator, TAIL_TIP_INSET + AGENT_BUBBLE_TAIL_WIDTH)
                toEnd(typingIndicator, 10f)
                setHorizontalBias(typingIndicator.id, 0f)
            }
        }

        if (!showTyping) {
            val codeColor =
                if (isOutgoing) {
                    WColor.TextOnTint.color.colorWithAlpha(
                        204
                    )
                } else {
                    WColor.SecondaryText.color
                }
            val linkColor = if (isOutgoing) WColor.TextOnTint.color.colorWithAlpha(204) else null
            if (richBlocks == null || message.tableReferences.isEmpty()) {
                val source = message.formatText()
                val textKey = if (message.isStreaming) {
                    null
                } else {
                    AgentMessageTextCache.TextKey(
                        message.id,
                        source,
                        codeColor,
                        linkColor,
                        detectsUrls,
                        messageLabel.textSize
                    )
                }
                // The same finished text keeps its layout
                if (textKey == null || textKey != shownTextKey) {
                    val text =
                        makeMessageText(message, source, textKey, codeColor, linkColor, detectsUrls)
                    messageLabel.setTextWithReveal(
                        text,
                        isStreaming = message.isStreaming && !isOutgoing && richBlocks == null,
                        key = message.id
                    )
                    shownTextKey = textKey
                }
            } else {
                messageLabel.finishReveal(message.id)
            }

            if (richBlocks == null) {
                showPlainMessage()
            } else {
                richContentWidth =
                    (messageMaxWidth - MESSAGE_HORIZONTAL_PADDING_DP.dp).coerceAtLeast(1)
                val renderKey = RichRenderKey(
                    messageId = message.id,
                    blocks = richBlocks,
                    contentWidth = richContentWidth,
                    codeColor = codeColor,
                    textColor = WColor.PrimaryText.color,
                    separatorColor = WColor.Separator.color,
                    detectsUrls = detectsUrls
                )
                val hasRichRenderChanged = renderedRichKey != renderKey
                if (hasRichRenderChanged) {
                    cancelRichTransition()
                    richMessageView.configure(
                        richBlocks,
                        richContentWidth,
                        codeColor,
                        onOpenUrl,
                        detectsUrls,
                        copyLongClickListener,
                        copyClickListener
                    )
                    renderedRichKey = renderKey
                }
                if (messageLabel.isRevealAnimating && message.tableReferences.isEmpty()) {
                    pendingRichMessageId = message.id
                } else if (richTransitionAnimator == null) {
                    showRichMessage(animate = false)
                }
            }
        }

        bubbleContainer.isVisible = message.hasVisibleBubble
        bubbleContainer.minimumHeight = MIN_BUBBLE_HEIGHT.dp
        bubbleContainer.minimumWidth = MIN_BUBBLE_WIDTH.dp
        // A very short question sits in the middle of its bubble
        val labelGravity = if (isOutgoing) Gravity.CENTER_HORIZONTAL else Gravity.START
        (messageLabel.layoutParams as FrameLayout.LayoutParams).let { labelParams ->
            if (labelParams.gravity != labelGravity) {
                labelParams.gravity = labelGravity
                messageLabel.layoutParams = labelParams
            }
        }

        if (shouldAnimateInsert) {
            setInsertAppearance(alpha = 0f, scale = 0.8f)
            updateLayoutParams { height = 1 }
            scheduleInsertAnimation()
        } else {
            finishInsertAnimation()
            setInsertAppearance(alpha = 1f, scale = 1f)
            updateLayoutParams { height = WRAP_CONTENT }
            if (onInsertAnimationStarted != null) {
                notifyInsertAnimationStarted(measureExpandedHeight())
            }
            notifyInsertAnimationFinished()
        }
    }

    /** Keeps the bubble's drawable across rebinds of a message, so its tail can grow back */
    private fun updateBubbleBackground(
        isOutgoing: Boolean,
        hasActions: Boolean,
        hasTail: Boolean,
        isSameMessage: Boolean
    ) {
        val current = bubbleDrawable
        val canReuse = current != null && isSameMessage &&
            renderedBubbleShape == (isOutgoing to hasActions)
        if (!canReuse) {
            tailAnimator?.cancel()
            tailAnimator = null
            bubbleDrawable =
                AgentBubbleDrawable(isOutgoing, hasActions, isTailless = !hasTail).also {
                    bubbleContainer.background = it
                }
            renderedBubbleShape = isOutgoing to hasActions
            return
        }
        val drawable = checkNotNull(current)
        drawable.setBubbleColor(
            if (isOutgoing) WColor.Tint.color else agentIncomingBubbleColor
        )
        val target = if (hasTail) 1f else 0f
        if (drawable.tailProgress == target && tailAnimator == null) return
        tailAnimator?.cancel()
        tailAnimator = null
        if (!hasTail || !isAttachedToWindow || !WGlobalStorage.getAreAnimationsActive()) {
            drawable.tailProgress = target
            return
        }
        // As the suggestions go, the tail grows back out of the corner
        tailAnimator = ValueAnimator.ofFloat(drawable.tailProgress, 1f).apply {
            duration = AGENT_TAIL_REVEAL_DURATION_MS
            startDelay = AGENT_TAIL_REVEAL_DELAY_MS
            interpolator = WInterpolator.spring(dampingRatio = AGENT_TAIL_REVEAL_DAMPING)
            addUpdateListener { drawable.tailProgress = it.animatedValue as Float }
            doOnEnd { if (tailAnimator === this) tailAnimator = null }
            start()
        }
    }

    private fun setInsertAppearance(alpha: Float, scale: Float) {
        for (view in arrayOf(contentContainer, typingIndicator)) {
            if (view !== typingIndicator || typingCrossfadeAnimator == null) view.alpha = alpha
            view.scaleX = scale
            view.scaleY = scale
        }
    }

    private fun crossfadeFromTypingIndicator() {
        if (!WGlobalStorage.getAreAnimationsActive() || !isAttachedToWindow) {
            typingIndicator.visibility = GONE
            bubbleContainer.alpha = 1f
            return
        }
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener {
                val progress = it.animatedValue as Float
                bubbleContainer.alpha = progress
                typingIndicator.alpha = 1f - progress
            }
        }
        typingCrossfadeAnimator = animator
        animator.doOnEnd {
            if (typingCrossfadeAnimator !== animator) return@doOnEnd
            typingCrossfadeAnimator = null
            finishTypingCrossfade()
            notifyContentSettled()
        }
        animator.start()
        updateRenderingAnimations()
    }

    private fun cancelTypingCrossfade() {
        val animator = typingCrossfadeAnimator ?: return
        typingCrossfadeAnimator = null
        animator.cancel()
        finishTypingCrossfade()
    }

    private fun finishTypingCrossfade() {
        typingIndicator.visibility = GONE
        typingIndicator.alpha = 1f
        bubbleContainer.alpha = 1f
    }

    private fun showPlainMessage() {
        pendingRichMessageId = null
        cancelRichTransition()
        richMessageView.visibility = GONE
        richMessageView.alpha = 1f
        messageLabel.alpha = 1f
        if (!typingIndicator.isVisible) messageLabel.visibility = VISIBLE
        bubbleContainer.updateLayoutParams<LinearLayout.LayoutParams> {
            width = WRAP_CONTENT
            height = WRAP_CONTENT
        }
        renderedRichKey = null
    }

    private fun resetRichMessagePresentation() {
        showPlainMessage()
        richMessageView.removeAllViews()
        richContentWidth = 0
    }

    private fun richBlocksFor(message: AgentMessage): List<MarkdownParser.Block>? {
        val key = AgentMessageTextCache.BlocksKey(
            message.id,
            message.text,
            message.answerTables,
            message.tableReferences,
            message.links
        )
        return textCache.getBlocks(key) {
            buildAgentV2MessageBlocks(key.source, key.tables, key.references, key.links)
                .takeIf { blocks -> blocks.any { it is MarkdownParser.Block.Table } }
        }
    }

    // Each label gets its own copy because it adds emoji to it
    private fun makeMessageText(
        message: AgentMessage,
        source: String,
        key: AgentMessageTextCache.TextKey?,
        codeColor: Int,
        linkColor: Int?,
        detectsUrls: Boolean
    ): CharSequence {
        fun parse() = MarkdownParser.parse(
            source,
            codeColor,
            linkColor,
            onOpenUrl,
            detectsUrls,
            textSize = messageLabel.textSize,
            isStreaming = message.isStreaming && message.role != AgentMessageRole.USER
        )
        if (key == null) return parse()
        return SpannableStringBuilder(textCache.getText(key, ::parse))
    }

    private fun showRichMessage(animate: Boolean) {
        pendingRichMessageId = null
        val messageId = currentMessage?.id
        if (messageId == null || renderedRichKey?.messageId != messageId) {
            notifyContentSettled()
            return
        }
        cancelRichTransition()

        val maximumWidth = richContentWidth + richMessageView.paddingLeft +
            richMessageView.paddingRight
        richMessageView.measure(
            MeasureSpec.makeMeasureSpec(maximumWidth, MeasureSpec.AT_MOST),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val targetWidth = richMessageView.measuredWidth
        val targetHeight = maxOf(richMessageView.measuredHeight, bubbleContainer.minimumHeight)
        val shouldAnimate = animate && WGlobalStorage.getAreAnimationsActive() &&
            bubbleContainer.width > 0 && bubbleContainer.height > 0

        if (!shouldAnimate) {
            val previousHeight = height
            richMessageView.visibility = VISIBLE
            richMessageView.alpha = 1f
            messageLabel.visibility = GONE
            messageLabel.alpha = 1f
            bubbleContainer.updateLayoutParams<LinearLayout.LayoutParams> {
                width = WRAP_CONTENT
                height = WRAP_CONTENT
            }
            onSizeTransitionFrame?.invoke(previousHeight)
            notifyContentSettled()
            return
        }

        val startWidth = bubbleContainer.width
        val startHeight = bubbleContainer.height
        richMessageView.visibility = VISIBLE
        richMessageView.alpha = 0f
        messageLabel.visibility = VISIBLE
        messageLabel.alpha = 1f
        bubbleContainer.updateLayoutParams<LinearLayout.LayoutParams> {
            width = startWidth
            height = startHeight
        }

        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { valueAnimator ->
                val previousHeight = this@AgentMessageCell.height
                val progress = valueAnimator.animatedValue as Float
                richMessageView.alpha = progress
                messageLabel.alpha = 1f - progress
                bubbleContainer.updateLayoutParams<LinearLayout.LayoutParams> {
                    width = lerp(startWidth.toFloat(), targetWidth.toFloat(), progress).toInt()
                    height = lerp(startHeight.toFloat(), targetHeight.toFloat(), progress).toInt()
                }
                onSizeTransitionFrame?.invoke(previousHeight)
            }
        }
        richTransitionAnimator = animator
        animator.doOnEnd {
            if (richTransitionAnimator !== animator) return@doOnEnd
            richTransitionAnimator = null
            richMessageView.alpha = 1f
            messageLabel.visibility = GONE
            messageLabel.alpha = 1f
            bubbleContainer.updateLayoutParams<LinearLayout.LayoutParams> {
                width = WRAP_CONTENT
                height = WRAP_CONTENT
            }
            notifyContentSettled()
        }
        animator.start()
        updateRenderingAnimations()
    }

    private fun cancelRichTransition() {
        val animator = richTransitionAnimator ?: return
        richTransitionAnimator = null
        animator.cancel()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateRenderingAnimations()
        if (renderedRichKey != null && !isStreamingCell &&
            !messageLabel.isRevealAnimating && pendingRichMessageId == null &&
            richTransitionAnimator == null
        ) {
            showRichMessage(animate = false)
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        deeplinkAnimator?.pause()
        cancelRichTransition()
        cancelTypingCrossfade()
        isInsertAnimationPending = false
        finishInsertAnimation()
        setInsertAppearance(alpha = 1f, scale = 1f)
        updateLayoutParams { height = WRAP_CONTENT }
        richMessageView.alpha = 1f
        messageLabel.alpha = 1f
    }

    private fun notifyInsertAnimationStarted(targetHeight: Int) {
        val callback = onInsertAnimationStarted
        onInsertAnimationStarted = null
        callback?.invoke(targetHeight)
    }

    private fun notifyInsertAnimationFinished() {
        val callback = onInsertAnimationFinished
        onInsertAnimationFinished = null
        callback?.invoke()
    }

    private fun normalizeAgentUrl(url: String): String {
        // Server may emit deeplinks under the wrong scheme; rewrite to the active app scheme.
        return when {
            url.startsWith(MYTONWALLET_SCHEME_PREFIX) ->
                "$APP_SCHEME://" + url.removePrefix(MYTONWALLET_SCHEME_PREFIX)

            APP_SCHEME != "mtw" && url.startsWith(MTW_SCHEME_PREFIX) ->
                "$APP_SCHEME://" + url.removePrefix(MTW_SCHEME_PREFIX)

            else -> url
        }
    }

    private fun setupDeeplinks(deeplinks: List<AgentDeeplink>, maxWidth: Int, animate: Boolean) {
        if (deeplinks.isEmpty()) {
            cancelDeeplinkAnimation()
            renderedDeeplinks = emptyList()
            deeplinkContainer.removeAllViews()
            deeplinkContainer.visibility = GONE
            return
        }
        val accentColor = WColor.Tint.color
        if (deeplinks == renderedDeeplinks && accentColor == renderedDeeplinkTint &&
            maxWidth == renderedDeeplinkMaxWidth
        ) {
            deeplinkContainer.visibility = VISIBLE
            return
        }
        renderedDeeplinks = deeplinks
        renderedDeeplinkTint = accentColor
        renderedDeeplinkMaxWidth = maxWidth
        cancelDeeplinkAnimation()
        deeplinkContainer.removeAllViews()
        deeplinkContainer.visibility = VISIBLE
        deeplinkContainer.updateLayoutParams<LinearLayout.LayoutParams> {
            marginStart = AGENT_BUBBLE_TAIL_WIDTH.dp
        }
        val shouldAnimate = animate && WGlobalStorage.getAreAnimationsActive()
        if (shouldAnimate) {
            setDeeplinkClipping(enabled = false)
        } else if (animate) {
            currentMessage?.id?.let { pendingDeeplinkAnimationIds.remove(it) }
        }
        val labelMaxWidth = maxWidth - 34.dp
        val labelAnimators = mutableListOf<ValueAnimator>()

        for ((index, deeplink) in deeplinks.withIndex()) {
            val isLast = index == deeplinks.size - 1
            val topRadius = 8f.dp
            val bottomRadius = if (isLast) 16f.dp else 8f.dp

            val accentColor = WColor.Tint.color

            val label = WLabel(context).apply {
                id = UIComponentsR.id.agent_action_button
                setStyle(ACTION_TEXT_SIZE, WFont.Medium)
                setLineHeight(ACTION_LINE_HEIGHT)
                text = deeplink.title
                setTextColor(accentColor)
                gravity = Gravity.CENTER
                setPadding(16.dp, 10.dp, 16.dp, 10.dp)
                setMaxWidth(labelMaxWidth)
                isSingleLine = false

                val bgColor = (accentColor and 0x00FFFFFF) or 0x1A000000
                background = WRippleDrawable.create(
                    topRadius,
                    topRadius,
                    bottomRadius,
                    bottomRadius
                ).apply {
                    backgroundColor = bgColor
                    rippleColor = (accentColor and 0x00FFFFFF) or 0x33000000
                }
                isClickable = true

                setOnClickListener {
                    val actionId = deeplink.actionId
                    val url = deeplink.url
                    when {
                        actionId != null -> onAction?.invoke(actionId)

                        url != null -> WalletCore.notifyEvent(
                            WalletEvent.OpenUrl(
                                normalizeAgentUrl(url),
                                source = DeeplinkOpenSource.AGENT
                            )
                        )
                    }
                }
            }
            val lp = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            lp.topMargin = ACTION_GAP.dp
            deeplinkContainer.addView(label, lp)

            if (shouldAnimate) {
                label.alpha = 0f
                label.translationY = 8f.dp
                labelAnimators.add(
                    ValueAnimator.ofFloat(0f, 1f).apply {
                        duration = AnimationConstants.VERY_QUICK_ANIMATION
                        startDelay = AnimationConstants.VERY_QUICK_ANIMATION + index * 50L
                        interpolator = AccelerateDecelerateInterpolator()
                        addUpdateListener {
                            val progress = it.animatedValue as Float
                            label.alpha = progress
                            label.translationY = 8f.dp * (1f - progress)
                        }
                    }
                )
            }
        }

        if (shouldAnimate) {
            animateDeeplinkExpansion(maxWidth, labelAnimators)
        }
    }

    private fun cancelDeeplinkAnimation() {
        val animator = deeplinkAnimator ?: return
        deeplinkAnimator = null
        animator.cancel()
        setDeeplinkClipping(enabled = true)
        deeplinkContainer.updateLayoutParams { height = WRAP_CONTENT }
    }

    private fun setDeeplinkClipping(enabled: Boolean) {
        deeplinkContainer.clipChildren = enabled
        deeplinkContainer.clipToPadding = enabled
        contentContainer.clipChildren = enabled
        contentContainer.clipToPadding = enabled
        clipChildren = enabled
        clipToPadding = enabled
    }

    private fun animateDeeplinkExpansion(maxWidth: Int, labelAnimators: List<ValueAnimator>) {
        deeplinkContainer.measure(
            MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val targetHeight = deeplinkContainer.measuredHeight
        deeplinkContainer.updateLayoutParams { height = 0 }
        val expansionAnimator = ValueAnimator.ofInt(0, targetHeight).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                deeplinkContainer.updateLayoutParams { height = animator.animatedValue as Int }
            }
            doOnEnd {
                deeplinkContainer.updateLayoutParams { height = WRAP_CONTENT }
            }
        }
        val animatedMessageId = currentMessage?.id
        val animator = AnimatorSet().apply {
            playTogether(labelAnimators + expansionAnimator)
            doOnEnd {
                if (deeplinkAnimator !== this) return@doOnEnd
                deeplinkAnimator = null
                setDeeplinkClipping(enabled = true)
                animatedMessageId?.let { pendingDeeplinkAnimationIds.remove(it) }
                notifyContentSettled()
            }
        }
        deeplinkAnimator = animator
        animator.start()
        updateRenderingAnimations()
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        menuTouch.track(this, event)
        return super.dispatchTouchEvent(event)
    }

    private fun requestCopyMenu(touch: Vec2i?) {
        val messageId = currentMessage?.id ?: return
        presentAgentMenu(
            menuPresenter,
            bubbleContainer,
            touch,
            isStillShown = { isAttachedToWindow && currentMessage?.id == messageId },
            open = ::showCopyMenu
        )
    }

    private fun requestLinkMenu(source: View, url: String, touch: Vec2i?) {
        val label = source as? TextView ?: return
        val messageId = currentMessage?.id ?: return
        presentAgentMenu(
            menuPresenter,
            source,
            touch,
            isStillShown = { isAttachedToWindow && currentMessage?.id == messageId }
        ) { anchor ->
            AgentLinkMenu.present(
                source = label,
                url = url,
                touch = anchor,
                items = listOf(
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_world_30,
                        LocaleController.getString("Open")
                    ) {
                        onOpenUrl?.invoke(url)
                    },
                    WMenuPopup.Item(
                        org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                        LocaleController.getString("Copy Link")
                    ) {
                        if (ClipboardHelpers.copyToClipboard(context, "Link", url)) {
                            ToastManager.show(
                                ToastManager.Toast(text = LocaleController.getString("Link Copied"))
                            )
                        }
                    }
                ),
                bubbleColor = {
                    if (isOutgoingCell) WColor.Tint.color else agentIncomingBubbleColor
                },
                isStillShown = { isAttachedToWindow && currentMessage?.id == messageId },
                onVisibilityChanged = { onPopupVisibilityChanged?.invoke(it) }
            )
        }
    }

    /** Opens the message's menu from the finger at [touch], a window point, as Telegram does; null opens it at the bubble */
    private fun showCopyMenu(touch: Vec2i?) {
        val message = currentMessage ?: return
        val dateHeader = buildAgentMessageMenuHeader(context, message.date)
        val canRate = !isOutgoingCell && !isStreamingCell && message.isComplete &&
            message.sdkMessageId != null && onRate != null
        lateinit var popup: INavigationPopup
        val feedbackPill = if (canRate) {
            AgentFeedbackPillView(
                context,
                message.feedback,
                pointsLeft = layoutDirection != LAYOUT_DIRECTION_RTL
            ) { feedback ->
                onRate?.invoke(feedback)
                popup.dismiss()
            }.apply { setDisplayProgress(0f) }
        } else {
            null
        }
        val menuItems = listOfNotNull(
            dateHeader,
            WMenuPopup.Item(
                org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                LocaleController.getString("Copy")
            ) {
                val text = currentMessage?.formatText()?.let(AgentTextLinks::copyText)
                if (text != null && ClipboardHelpers.copyToClipboard(
                        context,
                        "Message",
                        text
                    )
                ) {
                    Haptics.play(this@AgentMessageCell, HapticType.LIGHT_TAP)
                    onCopied?.invoke()
                }
            },
            WMenuPopup.Item(
                org.mytonwallet.app_air.icons.R.drawable.ic_pen,
                LocaleController.getString("Edit")
            ) {
                onEdit?.invoke()
            }.takeIf { isOutgoingCell && canEditMessage() },
            WMenuPopup.Item(
                org.mytonwallet.app_air.icons.R.drawable.ic_regenerate,
                LocaleController.getString("Regenerate")
            ) {
                onRegenerate?.invoke()
            }.takeIf { !isOutgoingCell && canRegenerateMessage() },
            WMenuPopup.Item(
                org.mytonwallet.app_air.icons.R.drawable.ic_flag_30,
                LocaleController.getString("Report a Problem")
            ) {
                onReportProblem?.invoke()
            }.takeIf { !isOutgoingCell && !isStreamingCell && canReportProblem() }
        )
        val rows = menuRows()
        val pillFrame = feedbackPill?.let { computeFeedbackPillFrame(it, rows.first) }
        onPopupVisibilityChanged?.invoke(true)
        popup = WMenuPopup.present(
            bubbleContainer,
            menuItems,
            positioning = WMenuPopup.Positioning.BELOW,
            backdropStyle = WMenuPopup.BackdropStyle.Dimmed,
            windowBackgroundStyle = buildAgentMenuBackdrop(buildBubbleCutoutPath(), rows),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false) },
            onDidDismiss = { (feedbackPill?.parent as? ViewGroup)?.removeView(feedbackPill) },
            displayProgressListener = feedbackPill?.let { pill -> pill::setDisplayProgress },
            placement = buildAgentMenuPlacement(this, bubbleContainer, touch, avoid = pillFrame)
        )
        if (feedbackPill != null && pillFrame != null) showFeedbackPill(feedbackPill, pillFrame)
    }

    /**
     * Where the rating pill goes, in the window: over the answer's top edge at its end, or over the top of what the
     * header leaves of a taller answer, from window row [visibleTop]. The frame takes in the pill's tail under it.
     */
    private fun computeFeedbackPillFrame(pill: AgentFeedbackPillView, visibleTop: Int): Rect {
        val area = getAgentPopupArea()
        val bubbleLocation = bubbleContainer.getLocationInWindow()
        val left = if (layoutDirection == LAYOUT_DIRECTION_RTL) {
            bubbleLocation.x - FEEDBACK_PILL_OVERHANG_DP.dp
        } else {
            bubbleLocation.x + bubbleContainer.width + FEEDBACK_PILL_OVERHANG_DP.dp -
                pill.bodyWidth
        }.coerceAtMost(area.right - pill.bodyWidth).coerceAtLeast(area.left)
        val bubbleTop = max(bubbleLocation.y, visibleTop)
        val top = max(bubbleTop + FEEDBACK_PILL_OVERLAP_DP.dp - pill.bodyHeight, area.top)
        return Rect(left, top, left + pill.bodyWidth, top + pill.tailBottom)
    }

    /** Places the rating pill at [frame], a window rect, above the open menu */
    private fun showFeedbackPill(pill: AgentFeedbackPillView, frame: Rect) {
        val host = PopupHelpers.popupHost ?: return
        val hostLocation = host.getLocationInWindow()
        host.addView(
            pill,
            FrameLayout.LayoutParams(
                WRAP_CONTENT,
                WRAP_CONTENT,
                Gravity.TOP or Gravity.LEFT
            ).apply {
                leftMargin = frame.left - hostLocation.x - host.paddingLeft
                topMargin = frame.top - hostLocation.y - host.paddingTop
            }
        )
    }

    private fun buildBubbleCutoutPath(): Path =
        (bubbleContainer.background as? AgentBubbleDrawable)?.buildCutoutPath(bubbleContainer)
            ?: bubbleContainer.frameAsPath(roundRadius = 21f.dp)

    private fun scheduleInsertAnimation() {
        if (!isInsertAnimationPending || !isRenderingEnabled || !isAttachedToWindow) return
        doOnPreDraw {
            if (isInsertAnimationPending && isRenderingEnabled) startInsertAnimation()
        }
    }

    private fun startInsertAnimation() {
        finishInsertAnimation()

        val targetHeight = measureExpandedHeight()
        insertAnimationTargetHeight = targetHeight
        notifyInsertAnimationStarted(targetHeight)
        insertAnimationOnFinished = onInsertAnimationFinished
        onInsertAnimationFinished = null
        val startHeight = (targetHeight * 0.3f).toInt().coerceAtLeast(1)
        updateLayoutParams { height = startHeight }

        insertAnimation = SpringAnimation(FloatValueHolder(startHeight.toFloat())).apply {
            setStartValue(startHeight.toFloat())
            spring = SpringForce(targetHeight.toFloat()).apply {
                stiffness = 500f
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            addUpdateListener { _, value, _ ->
                updateLayoutParams { height = value.toInt() }
                val appearStart = targetHeight * 0.7f
                val fraction =
                    ((value - appearStart) / (targetHeight - appearStart)).coerceIn(0f, 1f)
                setInsertAppearance(lerp(0f, 1f, fraction), lerp(0.8f, 1f, fraction))
            }
            addEndListener { _, canceled, _, _ ->
                if (!canceled) finishInsertAnimation()
            }
            start()
        }
        isInsertAnimationPending = false
    }

    private fun finishInsertAnimation() {
        val animation = insertAnimation ?: return
        insertAnimation = null
        animation.cancel()
        setInsertAppearance(alpha = 1f, scale = 1f)
        updateLayoutParams { height = WRAP_CONTENT }
        insertAnimationTargetHeight = 0
        val onFinished = insertAnimationOnFinished
        insertAnimationOnFinished = null
        onFinished?.invoke()
        notifyContentSettled()
    }

    private fun measureExpandedHeight(): Int {
        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        return measuredHeight
    }
}
