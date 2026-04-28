package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.Toast
import androidx.core.view.doOnPreDraw
import androidx.core.view.updateLayoutParams
import androidx.dynamicanimation.animation.FloatValueHolder
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentDeeplink
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessageRole
import org.mytonwallet.app_air.uiagent.viewControllers.agent.MarkdownParser
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.AgentOutgoingBubbleDrawable
import org.mytonwallet.app_air.uiagent.viewControllers.agent.views.TypingIndicatorView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcontext.utils.AnimUtils.Companion.lerp
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class AgentMessageCell(context: Context) : WCell(
    context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)
) {
    private val contentContainer = LinearLayout(context).apply {
        id = generateViewId()
        orientation = LinearLayout.VERTICAL
    }
    private val bubbleContainer = WFrameLayout(context)
    private val messageLabel = WLabel(context).apply {
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
    }

    var onOpenUrl: ((String) -> Unit)? = null
    var onPopupVisibilityChanged: ((visible: Boolean, bubbleView: View?) -> Unit)? = null

    private var insertAnimation: SpringAnimation? = null
    private var isStreamingCell = false
    private var currentMessage: AgentMessage? = null
    private var isOutgoingCell = false

    private val isCopyable: Boolean
        get() {
            val msg = currentMessage ?: return false
            return msg.text.isNotEmpty() && !isStreamingCell
        }

    fun configure(message: AgentMessage, recyclerWidth: Int, animate: Boolean = false) {
        currentMessage = message
        val isOutgoing = message.role == AgentMessageRole.USER
        isOutgoingCell = isOutgoing
        val showTyping = message.isStreaming && message.text.isEmpty()
        val wasStreaming = isStreamingCell
        isStreamingCell = message.isStreaming
        bubbleContainer.isHapticFeedbackEnabled = isCopyable
        val hasDeeplinks = message.deeplinks.isNotEmpty()

        if (showTyping) {
            messageLabel.visibility = GONE
            typingIndicator.visibility = VISIBLE
            typingIndicator.setPadding(20.dp, 0, 20.dp, 0)
        } else {
            messageLabel.visibility = VISIBLE
            typingIndicator.visibility = GONE
            val codeColor =
                if (isOutgoing) WColor.TextOnTint.color.colorWithAlpha(204) else WColor.SecondaryText.color
            val linkColor = if (isOutgoing) WColor.TextOnTint.color.colorWithAlpha(204) else null
            messageLabel.text = MarkdownParser.parse(message.text, codeColor, linkColor, onOpenUrl)
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
            if (hasDeeplinks) {
                bg.cornerRadii = floatArrayOf(
                    21f.dp, 21f.dp,
                    21f.dp, 21f.dp,
                    8f.dp, 8f.dp,
                    8f.dp, 8f.dp
                )
            } else {
                bg.cornerRadius = 21f.dp
            }
            bubbleContainer.background = bg
            messageLabel.setTextColor(WColor.PrimaryText.color)
            messageLabel.setPaddingDpLocalized(20, 10, 14, 10)
            messageLabel.maxWidth = maxBubbleWidth - 34.dp

            setupDeeplinks(message.deeplinks, maxBubbleWidth)

            setConstraints {
                constrainedWidth(contentContainer.id, true)
                toTop(contentContainer, 4f)
                toBottom(contentContainer, 4f)
                toStart(contentContainer, 10f)
                toEnd(contentContainer, 72f)
                setHorizontalBias(contentContainer.id, 0f)
            }
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
        }
    }

    private fun setupDeeplinks(deeplinks: List<AgentDeeplink>, maxWidth: Int) {
        deeplinkContainer.removeAllViews()
        if (deeplinks.isEmpty()) {
            deeplinkContainer.visibility = GONE
            return
        }
        deeplinkContainer.visibility = VISIBLE
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
                    topRadius, topRadius, bottomRadius, bottomRadius
                ).apply {
                    backgroundColor = bgColor
                    rippleColor = (accentColor and 0x00FFFFFF) or 0x33000000
                }
                isClickable = true

                setOnClickListener {
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(deeplink.url))
                }
            }
            val lp = LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            lp.topMargin = 1.dp
            deeplinkContainer.addView(label, lp)
        }
    }

    private fun showCopyMenu() {
        onPopupVisibilityChanged?.invoke(true, bubbleContainer)
        WMenuPopup.present(
            bubbleContainer,
            listOf(
                WMenuPopup.Item(
                    org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                    LocaleController.getString("Copy Text"),
                ) {
                    val clipboard =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("Message", currentMessage?.text ?: return@Item)
                    clipboard.setPrimaryClip(clip)
                    Haptics.play(context, HapticType.LIGHT_TAP)
                    Toast.makeText(
                        context,
                        LocaleController.getString("Message Copied"),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            ),
            positioning = WMenuPopup.Positioning.BELOW,
            yOffset = (-16).dp,
            centerHorizontally = true,
            windowBackgroundStyle = buildBubbleCutoutStyle(),
            onWillDismiss = { onPopupVisibilityChanged?.invoke(false, null) },
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

        measure(
            MeasureSpec.makeMeasureSpec((parent as? View)?.width ?: width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)
        )
        val targetHeight = measuredHeight
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
            }
            start()
        }
    }
}
