package org.mytonwallet.app_air.uiagent.viewControllers.agent.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uiagent.viewControllers.agent.AgentMessage
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

/** A centered note between messages: an account change, or a failure that may offer a "Retry" link */
@SuppressLint("ViewConstructor")
class AgentSystemMessageCell(context: Context) :
    WCell(
        context,
        LayoutParams(MATCH_PARENT, WRAP_CONTENT)
    ),
    WThemedView {
    private val label = WLabel(context).apply {
        id = UIComponentsR.id.agent_message_system
        gravity = Gravity.CENTER
        isSingleLine = false
        useCustomEmoji = true
    }

    private var message: AgentMessage? = null
    private var onRetry: (() -> Unit)? = null
    private var isFailureStyle: Boolean? = null

    init {
        addView(label)
    }

    /** [onRetry] adds the link to a failure */
    fun configure(message: AgentMessage, onRetry: (() -> Unit)? = null) {
        this.message = message
        this.onRetry = onRetry.takeIf { message.isFailure }
        applyStyle(message.isFailure)
        updateTheme()
    }

    private fun applyStyle(isFailure: Boolean) {
        if (isFailureStyle == isFailure) return
        isFailureStyle = isFailure
        label.setStyle(TEXT_SIZE, WFont.Medium)
        if (isFailure) {
            // Figma's failure line: a 28 dp row with its text 12 dp below the row's top
            label.setLineHeight(FAILURE_LINE_HEIGHT)
            label.maxLines = FAILURE_MAX_LINES
        } else {
            label.setLineSpacing(0f, 1f)
            label.maxLines = NOTE_MAX_LINES
        }
        setConstraints {
            toTop(label, if (isFailure) FAILURE_TOP else NOTE_VERTICAL)
            toBottom(label, if (isFailure) 0f else NOTE_VERTICAL)
            toStart(label, if (isFailure) FAILURE_HORIZONTAL else NOTE_HORIZONTAL)
            toEnd(label, if (isFailure) FAILURE_HORIZONTAL else NOTE_HORIZONTAL)
        }
    }

    override fun updateTheme() {
        label.setTextColor(WColor.SecondaryText.color)
        val message = message ?: return
        val onRetry = onRetry
        if (onRetry == null) {
            label.movementMethod = null
            label.text = message.text
            return
        }
        val retryText = LocaleController.getString("Retry")
        val text = SpannableStringBuilder(message.text).append(' ')
        val start = text.length
        text.append(retryText)
        text.setSpan(
            WClickableSpan(retryText, WColor.Tint.color) { onRetry() },
            start,
            text.length,
            Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
        )
        label.movementMethod = ExtraHitLinkMovementMethod(RETRY_HIT_SLOP.dp, RETRY_HIT_SLOP.dp)
        label.text = text
    }

    private companion object {
        const val TEXT_SIZE = 11f
        const val NOTE_MAX_LINES = 2
        const val NOTE_VERTICAL = 4f
        const val NOTE_HORIZONTAL = 40f
        const val FAILURE_LINE_HEIGHT = 16f
        const val FAILURE_MAX_LINES = 4
        const val FAILURE_TOP = 12f
        const val FAILURE_HORIZONTAL = 20f
        const val RETRY_HIT_SLOP = 8
    }
}
