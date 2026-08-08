package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import androidx.core.animation.doOnEnd
import androidx.core.view.doOnPreDraw
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentDeeplink
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentOutgoingBubbleDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.StreamingRevealLabel
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.TypingIndicatorView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.APP_SCHEME
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent

private const val MYTONWALLET_SCHEME_PREFIX = "mytonwallet://"
private const val MTW_SCHEME_PREFIX = "mtw://"

@SuppressLint("ViewConstructor")
class AgentMessageCell(context: Context) :
    WCell(
        context,
        LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    ) {
    companion object {
        private val pendingDeeplinkAnimationIds = mutableSetOf<String>()
    }

    private val contentContainer = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }
    private val bubbleContainer = WFrameLayout(context)
    private val messageLabel = StreamingRevealLabel(context).apply {
        setStyle(adaptiveFontSize())
        isSingleLine = false
        maxLines = Int.MAX_VALUE
        ellipsize = null
        useCustomEmoji = true
        movementMethod = ExtraHitLinkMovementMethod(2.dp, 2.dp)
    }
    private val typingIndicator = TypingIndicatorView(context)
    private val deeplinkContainer = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }

    init {
        bubbleContainer.addView(messageLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        bubbleContainer.addView(
            typingIndicator,
            FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.CENTER
            }
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
        val longClickListener = OnLongClickListener {
            if (isCopyable) {
                showCopyMenu()
                true
            } else {
                false
            }
        }
        bubbleContainer.setOnLongClickListener(longClickListener)
        messageLabel.setOnLongClickListener(longClickListener)
        messageLabel.onRevealFinished = { notifyContentSettled() }
        messageLabel.onSizeTransitionFrame = {
            onSizeTransitionFrame?.invoke(height)
        }
    }

    var onOpenUrl: ((String) -> Unit)? = null
    var onPopupVisibilityChanged: ((visible: Boolean, bubbleView: View?) -> Unit)? = null
    var onSizeTransitionFrame: ((previousHeight: Int) -> Unit)? = null
    var onInsertAnimationStarted: ((targetHeight: Int) -> Unit)? = null
    var onInsertAnimationFinished: (() -> Unit)? = null

    // Fires once the text reveal and the deeplink appearance have both finished playing.
    var onContentSettled: (() -> Unit)? = null
    private var deeplinksAnimating = false

    val isContentSettling: Boolean
        get() = messageLabel.isRevealAnimating || deeplinksAnimating

    private fun notifyContentSettled() {
        if (isContentSettling) return
        val callback = onContentSettled
        onContentSettled = null
        callback?.invoke()
    }

    private var insertAnimation: SpringAnimation? = null
    private var insertAnimationTargetHeight = 0
    internal val layoutTargetHeight: Int
        get() = insertAnimationTargetHeight.takeIf { it > 0 } ?: height
    private var isStreamingCell = false
    private var currentMessage: AgentMessage? = null
    private var isOutgoingCell = false
    private var renderedDeeplinks: List<AgentDeeplink> = emptyList()
    private var renderedDeeplinkTint = 0
    private var renderedDeeplinkMaxWidth = 0
    private var deeplinkExpandAnimator: ValueAnimator? = null

    private val isCopyable: Boolean
        get() {
            val msg = currentMessage ?: return false
            return msg.text.isNotEmpty() && !isStreamingCell
        }

    fun configure(message: AgentMessage, recyclerWidth: Int, animate: Boolean = false) {
        val previousMessageId = currentMessage?.id
        if (previousMessageId != message.id) {
            onContentSettled = null
            deeplinksAnimating = false
            insertAnimationTargetHeight = 0
        }
        currentMessage = message
        val isOutgoing = message.role == AgentMessageRole.USER
        isOutgoingCell = isOutgoing
        val showTyping = message.isStreaming && message.text.isEmpty()
        val wasStreaming = isStreamingCell
        isStreamingCell = message.isStreaming
        bubbleContainer.isHapticFeedbackEnabled = isCopyable
        val hasDeeplinks = message.deeplinks.isNotEmpty()
        val wasShowingTypingForSameMessage =
            previousMessageId == message.id && typingIndicator.isVisible
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
            messageLabel.visibility = GONE
            typingIndicator.visibility = VISIBLE
            typingIndicator.setPadding(20.dp, 0, 20.dp, 0)
        } else {
            messageLabel.visibility = VISIBLE
            typingIndicator.visibility = GONE
        }
        val maxBubbleWidth = (recyclerWidth * 0.8f).toInt()

        if (isOutgoing) {
            bubbleContainer.background = AgentOutgoingBubbleDrawable()
            messageLabel.setTextColor(WColor.TextOnTint.color)
            messageLabel.setPaddingDpLocalized(14, 10, 20, 10)
            messageLabel.maxWidth = maxBubbleWidth - 34.dp
            deeplinkContainer.visibility = GONE

            setConstraints {
                constrainedWidth(contentContainer.id, true)
                toTop(contentContainer, 4f)
                toBottom(contentContainer, 4f)
                toEnd(contentContainer, 10f)
                toStart(contentContainer, 72f)
                setHorizontalBias(contentContainer.id, 1f)
            }
        } else {
            val bg = GradientDrawable()
            bg.setColor(WColor.SecondaryBackground.color)
            if (showDeeplinks) {
                bg.cornerRadii = floatArrayOf(
                    21f.dp,
                    21f.dp,
                    21f.dp,
                    21f.dp,
                    8f.dp,
                    8f.dp,
                    8f.dp,
                    8f.dp
                )
            } else {
                bg.cornerRadius = 21f.dp
            }
            bubbleContainer.background = bg
            messageLabel.setTextColor(WColor.PrimaryText.color)
            messageLabel.setPaddingDpLocalized(20, 10, 14, 10)
            messageLabel.maxWidth = maxBubbleWidth - 34.dp

            setupDeeplinks(
                if (showDeeplinks) message.deeplinks else emptyList(),
                maxBubbleWidth,
                animateDeeplinks
            )

            setConstraints {
                constrainedWidth(contentContainer.id, true)
                toTop(contentContainer, 4f)
                toBottom(contentContainer, 4f)
                toStart(contentContainer, 10f)
                toEnd(contentContainer, 72f)
                setHorizontalBias(contentContainer.id, 0f)
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
            // When the typing indicator is replaced by the first chunk, morph the bubble from
            // its current size instead of snapping to the empty reveal size.
            val transitionFrom = if (wasShowingTypingForSameMessage && message.isStreaming) {
                Pair(
                    (bubbleContainer.width - messageLabel.paddingLeft - messageLabel.paddingRight)
                        .coerceAtLeast(0).toFloat(),
                    (bubbleContainer.height - messageLabel.paddingTop - messageLabel.paddingBottom)
                        .coerceAtLeast(0).toFloat()
                )
            } else {
                null
            }
            messageLabel.setTextWithReveal(
                MarkdownParser.parse(message.text, codeColor, linkColor, onOpenUrl),
                isStreaming = message.isStreaming,
                key = message.id,
                transitionFromContentSize = transitionFrom
            )
        }

        bubbleContainer.minimumHeight = 40.dp

        if (animate && !wasStreaming) {
            contentContainer.alpha = 0f
            contentContainer.scaleX = 0.8f
            contentContainer.scaleY = 0.8f
            updateLayoutParams { height = 1 }
            doOnPreDraw { startInsertAnimation() }
        } else {
            insertAnimation?.cancel()
            contentContainer.alpha = 1f
            contentContainer.scaleX = 1f
            contentContainer.scaleY = 1f
            updateLayoutParams { height = WRAP_CONTENT }
            if (onInsertAnimationStarted != null) {
                notifyInsertAnimationStarted(measureExpandedHeight())
            }
            notifyInsertAnimationFinished()
        }
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
            renderedDeeplinks = emptyList()
            deeplinkContainer.removeAllViews()
            deeplinkContainer.visibility = GONE
            deeplinksAnimating = false
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
        deeplinkExpandAnimator?.cancel()
        deeplinkExpandAnimator = null
        setDeeplinkClipping(enabled = true)
        deeplinkContainer.updateLayoutParams { height = WRAP_CONTENT }
        deeplinkContainer.removeAllViews()
        deeplinkContainer.visibility = VISIBLE
        val shouldAnimate = animate && WGlobalStorage.getAreAnimationsActive()
        if (shouldAnimate) {
            setDeeplinkClipping(enabled = false)
        } else if (animate) {
            currentMessage?.id?.let { pendingDeeplinkAnimationIds.remove(it) }
        }
        val labelMaxWidth = maxWidth - 34.dp

        for ((index, deeplink) in deeplinks.withIndex()) {
            val isLast = index == deeplinks.size - 1
            val topRadius = 8f.dp
            val bottomRadius = if (isLast) 16f.dp else 8f.dp

            val accentColor = WColor.Tint.color

            val label = WLabel(context).apply {
                setStyle(17f)
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
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(normalizeAgentUrl(deeplink.url)))
                }
            }
            val lp = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            lp.topMargin = 1.dp
            deeplinkContainer.addView(label, lp)

            if (shouldAnimate) {
                deeplinksAnimating = true
                label.alpha = 0f
                label.translationY = 8f.dp
                label.animate()
                    .alpha(1f)
                    .translationY(0f)
                    .setDuration(AnimationConstants.VERY_QUICK_ANIMATION)
                    .setStartDelay(AnimationConstants.VERY_QUICK_ANIMATION + index * 50L)
                    .setInterpolator(AccelerateDecelerateInterpolator())
                    .apply {
                        if (isLast) {
                            val animatedMessageId = currentMessage?.id
                            withEndAction {
                                setDeeplinkClipping(enabled = true)
                                animatedMessageId?.let {
                                    pendingDeeplinkAnimationIds.remove(it)
                                }
                                deeplinksAnimating = false
                                notifyContentSettled()
                            }
                        }
                    }
                    .start()
            }
        }

        if (shouldAnimate) {
            animateDeeplinkExpansion(maxWidth)
        }
    }

    private fun setDeeplinkClipping(enabled: Boolean) {
        deeplinkContainer.clipChildren = enabled
        deeplinkContainer.clipToPadding = enabled
        contentContainer.clipChildren = enabled
        contentContainer.clipToPadding = enabled
        clipChildren = enabled
        clipToPadding = enabled
    }

    private fun animateDeeplinkExpansion(maxWidth: Int) {
        deeplinkContainer.measure(
            MeasureSpec.makeMeasureSpec(maxWidth, MeasureSpec.AT_MOST),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val targetHeight = deeplinkContainer.measuredHeight
        if (targetHeight <= 0) return
        deeplinkContainer.updateLayoutParams { height = 0 }
        deeplinkExpandAnimator = ValueAnimator.ofInt(0, targetHeight).apply {
            duration = AnimationConstants.VERY_QUICK_ANIMATION
            interpolator = AccelerateDecelerateInterpolator()
            addUpdateListener { animator ->
                deeplinkContainer.updateLayoutParams { height = animator.animatedValue as Int }
            }
            doOnEnd {
                deeplinkContainer.updateLayoutParams { height = WRAP_CONTENT }
                deeplinkExpandAnimator = null
            }
            start()
        }
    }

    private fun showCopyMenu() {
        onPopupVisibilityChanged?.invoke(true, bubbleContainer)
        WMenuPopup.present(
            bubbleContainer,
            listOf(
                WMenuPopup.Item(
                    org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                    LocaleController.getString("Copy Text")
                ) {
                    val text = currentMessage?.text
                    if (text != null && ClipboardHelpers.copyToClipboard(
                            context,
                            "Message",
                            text
                        )
                    ) {
                        Haptics.play(context, HapticType.LIGHT_TAP)
                        Toast.makeText(
                            context,
                            LocaleController.getString("Message Copied"),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }
            ),
            positioning = WMenuPopup.Positioning.BELOW,
            yOffset = (-16).dp,
            centerHorizontally = true,
            windowBackgroundStyle = buildBubbleCutoutStyle(),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false, null) }
        )
    }

    private fun buildBubbleCutoutStyle(): WMenuPopup.BackgroundStyle {
        if (isOutgoingCell) {
            val drawable = bubbleContainer.background as? AgentOutgoingBubbleDrawable
            if (drawable != null) {
                return WMenuPopup.BackgroundStyle.Cutout(drawable.buildCutoutPath(bubbleContainer))
            }
        }
        return WMenuPopup.BackgroundStyle.Cutout.fromView(bubbleContainer, roundRadius = 21f.dp)
    }

    private fun startInsertAnimation() {
        insertAnimation?.cancel()

        val targetHeight = measureExpandedHeight()
        insertAnimationTargetHeight = targetHeight
        notifyInsertAnimationStarted(targetHeight)
        val onFinished = onInsertAnimationFinished
        onInsertAnimationFinished = null
        val startHeight = (targetHeight * 0.3f).toInt().coerceAtLeast(1)
        updateLayoutParams { height = startHeight }

        insertAnimation = SpringAnimation(FloatValueHolder()).apply {
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
                contentContainer.alpha = lerp(0f, 1f, fraction)
                contentContainer.scaleX = lerp(0.8f, 1f, fraction)
                contentContainer.scaleY = contentContainer.scaleX
            }
            addEndListener { _, _, _, _ ->
                contentContainer.alpha = 1f
                contentContainer.scaleX = 1f
                contentContainer.scaleY = 1f
                updateLayoutParams { height = WRAP_CONTENT }
                insertAnimation = null
                insertAnimationTargetHeight = 0
                onFinished?.invoke()
            }
            start()
        }
    }

    private fun measureExpandedHeight(): Int {
        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        return measuredHeight
    }
}
