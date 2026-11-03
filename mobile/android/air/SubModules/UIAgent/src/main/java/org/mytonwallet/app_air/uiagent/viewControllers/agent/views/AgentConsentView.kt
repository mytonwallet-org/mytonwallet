package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.graphics.Outline
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ConsentCopy
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentChatBackgroundColor
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

class AgentConsentView(context: Context) : WView(context) {
    var onAllow: (() -> Unit)? = null

    private val copy = agentV2ConsentCopy()

    private var topInset = 0
    private var bottomInset = 0

    private val spinningTop = AgentSpinningTopView(context, speed = 0.5f).apply {
        id = View.generateViewId()
        isTouchInteractive = true
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    private val titleLabel = WLabel(context).apply {
        gravity = Gravity.CENTER
        setStyle(30f, WFont.Bold)
        text = LocaleController.getString("Agent")
    }
    private val subtitleLabel = WLabel(context).apply {
        gravity = Gravity.CENTER
        setStyle(16f)
        setLineHeight(22f)
        text = copy.subtitle
    }
    private val featureLabels = copy.features.map { feature ->
        WLabel(context).apply {
            setStyle(16f)
            setLineHeight(22f)
            text = "•  $feature"
        }
    }
    private val disclosureTitleLabel = WLabel(context).apply {
        id = UIComponentsR.id.agent_consent_disclosure_title
        setStyle(14f, WFont.Medium)
        text = copy.disclosureTitle
    }
    private val disclosureLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        text = copy.disclosure
    }
    private val searchDisclosureLabel = WLabel(context).apply {
        setStyle(13f)
        setLineHeight(18f)
        movementMethod = LinkMovementMethod.getInstance()
        text = SpannableStringBuilder(copy.searchDisclosure).apply {
            append(" ")
            val start = length
            append(LocaleController.getString("Learn more"))
            setSpan(
                WClickableSpan(context.getString(BaseR.string.app_privacy_policy_url)) { url ->
                    WalletCore.notifyEvent(
                        WalletEvent.OpenUrlWithConfig(
                            InAppBrowserConfig(
                                url,
                                injectDappConnect = false,
                                injectDarkModeStyles = true,
                                title = LocaleController.getString("Privacy Policy")
                            )
                        )
                    )
                },
                start,
                length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
    }
    private val errorLabel = WLabel(context).apply {
        id = UIComponentsR.id.agent_consent_error
        gravity = Gravity.CENTER
        setStyle(14f)
        isGone = true
    }
    private val disclosureContainer = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        setPadding(16.dp, 16.dp, 16.dp, 16.dp)
        addView(disclosureTitleLabel, matchWidth())
        addView(disclosureLabel, matchWidth(topMargin = 8.dp))
        addView(searchDisclosureLabel, matchWidth(topMargin = 12.dp))
    }
    private val contentLayout = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(24.dp, 28.dp, 24.dp, 28.dp)
        addView(spinningTop, LinearLayout.LayoutParams(74.dp, 74.dp))
        addView(titleLabel, matchWidth(topMargin = 14.dp))
        addView(subtitleLabel, matchWidth(topMargin = 12.dp))
        featureLabels.forEachIndexed { index, label ->
            addView(label, matchWidth(topMargin = if (index == 0) 32.dp else 18.dp))
        }
        addView(disclosureContainer, matchWidth(topMargin = 28.dp))
        addView(errorLabel, matchWidth(topMargin = 16.dp))
    }
    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        isFillViewport = true
        isVerticalScrollBarEnabled = false
        clipToPadding = false
        addView(
            contentLayout,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }
    private val bottomReversedCornerView = ReversedCornerViewUpsideDown(context, scrollView)
    private val allowButton = WButton(context, WButton.Type.PRIMARY).apply {
        id = UIComponentsR.id.agent_consent_allow
        text = copy.allowButton
        setOnClickListener { onAllow?.invoke() }
    }

    init {
        addView(scrollView, ConstraintLayout.LayoutParams(0, 0))
        addView(
            bottomReversedCornerView,
            ConstraintLayout.LayoutParams(0, bottomReversedCornerViewHeight())
        )
        addView(allowButton, ConstraintLayout.LayoutParams(0, BUTTON_HEIGHT.dp))
        setConstraints {
            allEdges(scrollView)

            toStart(bottomReversedCornerView)
            toEnd(bottomReversedCornerView)
            toBottom(bottomReversedCornerView)

            toStart(allowButton, BUTTON_MARGIN.toFloat())
            toEnd(allowButton, BUTTON_MARGIN.toFloat())
        }
        applyInsets()
        updateTheme()
    }

    fun setLoading(isLoading: Boolean) {
        allowButton.isLoading = isLoading
    }

    fun showError(message: String?) {
        errorLabel.text = message
        errorLabel.isGone = message.isNullOrBlank()
    }

    private var bottomCornerRadius = 0f

    private fun setBottomCornerRadius(radius: Float) {
        if (bottomCornerRadius == radius) return
        bottomCornerRadius = radius
        outlineProvider = if (radius > 0f) {
            object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    outline.setRoundRect(0, -radius.roundToInt(), view.width, view.height, radius)
                }
            }
        } else {
            ViewOutlineProvider.BACKGROUND
        }
        clipToOutline = radius > 0f
    }

    /** [endsAboveBottomBar]: rounds its own end, since the bar would blur it. */
    fun updateInsets(top: Int, bottom: Int, endsAboveBottomBar: Boolean = false) {
        setBottomCornerRadius(if (endsAboveBottomBar) ViewConstants.TOOLBAR_RADIUS.dp else 0f)
        val contentBottom = if (endsAboveBottomBar) 0 else bottom
        if (topInset == top && bottomInset == contentBottom) return
        topInset = top
        bottomInset = contentBottom
        applyInsets()
    }

    private fun applyInsets() {
        scrollView.setPadding(
            0,
            topInset,
            0,
            bottomInset + BUTTON_SPACE.dp + ViewConstants.BLOCK_RADIUS.dp.roundToInt()
        )
        bottomReversedCornerView.updateLayoutParams {
            height = bottomReversedCornerViewHeight()
        }
        setConstraints {
            toBottomPx(allowButton, bottomInset + BUTTON_MARGIN.dp)
        }
    }

    private fun bottomReversedCornerViewHeight(): Int =
        bottomInset + BUTTON_SPACE.dp + ViewConstants.BLOCK_RADIUS.dp.roundToInt()

    fun updateTheme() {
        setBackgroundColor(agentChatBackgroundColor)
        titleLabel.setTextColor(WColor.PrimaryText)
        subtitleLabel.setTextColor(WColor.SecondaryText)
        featureLabels.forEach { it.setTextColor(WColor.PrimaryText) }
        disclosureTitleLabel.setTextColor(WColor.PrimaryText)
        disclosureLabel.setTextColor(WColor.SecondaryText)
        searchDisclosureLabel.setTextColor(WColor.SecondaryText)
        errorLabel.setTextColor(WColor.Error)
        disclosureContainer.setBackgroundColor(
            agentIncomingBubbleColor,
            ViewConstants.BLOCK_RADIUS.dp
        )
        bottomReversedCornerView.setBlurOverlayColor(agentChatBackgroundColor)
        bottomReversedCornerView.updateTheme()
        allowButton.updateTheme()
    }

    private companion object {
        const val BUTTON_HEIGHT = 50
        const val BUTTON_MARGIN = 16
        const val BUTTON_SPACE = BUTTON_HEIGHT + BUTTON_MARGIN * 2

        fun matchWidth(topMargin: Int = 0) = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            this.topMargin = topMargin
        }
    }
}
