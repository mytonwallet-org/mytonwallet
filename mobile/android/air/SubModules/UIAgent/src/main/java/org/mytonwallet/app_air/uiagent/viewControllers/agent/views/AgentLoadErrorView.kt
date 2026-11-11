package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

private const val RETRY_GAP = 12
private const val RETRY_MIN_HEIGHT = 44

@SuppressLint("ViewConstructor")
internal class AgentLoadErrorView(context: Context) :
    LinearLayout(context),
    WThemedView {
    private val label = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER
    }
    private val retryButton = WLabel(context).apply {
        setStyle(17f, WFont.Medium)
        text = LocaleController.getString("Retry")
        gravity = Gravity.CENTER
        minHeight = RETRY_MIN_HEIGHT.dp
        isFocusable = true
        accessibilityDelegate = object : View.AccessibilityDelegate() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfo
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                info.className = Button::class.java.name
            }
        }
    }

    var onRetry: (() -> Unit)? = null

    init {
        id = generateViewId()
        orientation = VERTICAL
        gravity = Gravity.CENTER
        isGone = true
        addView(label, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            retryButton,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = RETRY_GAP.dp }
        )
        retryButton.setOnClickListener { onRetry?.invoke() }
        updateTheme()
    }

    /** Shows [text] with Retry, or hides the view for null */
    fun setError(text: String?) = show(text, hasRetry = true)

    /** Shows [text] without Retry, or hides the view for null */
    fun setMessage(text: String?) = show(text, hasRetry = false)

    private fun show(text: String?, hasRetry: Boolean) {
        isGone = text == null
        if (text != null) label.text = text
        retryButton.isGone = !hasRetry
    }

    override fun updateTheme() {
        label.setTextColor(WColor.SecondaryText)
        retryButton.setTextColor(WColor.Tint)
    }
}
