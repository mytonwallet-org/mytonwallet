package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import kotlin.math.min
import org.mytonwallet.app_air.uiagent.R
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ConsentCopy
import org.mytonwallet.app_air.uiagent.viewControllers.agent.agentIncomingBubbleColor
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.R as BaseR
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig

/**
 * What the Agent asks the user to allow, as the consent sheet shows it under its header: the three features, the data
 * the Agent gets and the Allow button under them. It sizes to its content up to [maxContentHeight], past which the text
 * scrolls over the button.
 */
@SuppressLint("ViewConstructor")
class AgentConsentView(context: Context) : LinearLayout(context) {
    var onAllow: (() -> Unit)? = null

    /** The most it grows to, in px; 0 lets it take whatever its parent gives */
    var maxContentHeight = 0
        set(value) {
            if (field == value) return
            field = value
            requestLayout()
        }

    private val copy = agentV2ConsentCopy()

    private val featureIcons = FEATURE_ICONS.map { icon ->
        ImageView(context).apply {
            setImageResource(icon)
            val inset = ((FEATURE_ICON_SIZE - FEATURE_SHAPE_SIZE) / 2).dp
            setPadding(inset, inset, inset, inset)
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
    }
    private val featureLabels = copy.features.map { feature ->
        WLabel(context).apply {
            setStyle(16f)
            setLineHeight(FEATURE_LINE_HEIGHT.toFloat())
            text = feature
        }
    }

    // Each icon is centred on all the lines of its text, 14 dp before it
    private val featureRows = featureIcons.zip(featureLabels) { icon, label ->
        LinearLayout(context).apply {
            id = View.generateViewId()
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(icon, LinearLayout.LayoutParams(FEATURE_ICON_SIZE.dp, FEATURE_ICON_SIZE.dp))
            addView(
                label,
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    marginStart = FEATURE_ICON_GAP.dp
                }
            )
        }
    }
    private val disclosureTitleLabel = WLabel(context).apply {
        id = UIComponentsR.id.agent_consent_disclosure_title
        setStyle(14f, WFont.Medium)
        text = copy.disclosureTitle
    }
    private val disclosureLabel = WLabel(context).apply {
        setStyle(DISCLOSURE_TEXT_SIZE)
        setLineHeight(DISCLOSURE_LINE_HEIGHT)
        text = copy.disclosure
    }
    private val searchDisclosureLabel = WLabel(context).apply {
        setStyle(DISCLOSURE_TEXT_SIZE)
        setLineHeight(DISCLOSURE_LINE_HEIGHT)
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
        setPadding(24.dp, CONTENT_TOP.dp, 24.dp, 0)
        featureRows.forEachIndexed { index, row ->
            addView(row, matchWidth(topMargin = if (index == 0) 0 else 18.dp))
        }
        addView(disclosureContainer, matchWidth(topMargin = 28.dp))
        addView(errorLabel, matchWidth(topMargin = 16.dp))
    }
    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        addView(
            contentLayout,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
    }
    private val allowButton = WButton(context, WButton.Type.PRIMARY).apply {
        id = UIComponentsR.id.agent_consent_allow
        text = copy.allowButton
        setOnClickListener { onAllow?.invoke() }
    }

    init {
        id = View.generateViewId()
        orientation = VERTICAL
        // The text takes what the button leaves, and shrinks to scroll once the content outgrows the sheet
        addView(scrollView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, 1f))
        addView(
            allowButton,
            LayoutParams(LayoutParams.MATCH_PARENT, BUTTON_HEIGHT.dp).apply {
                setMargins(BUTTON_MARGIN.dp, BUTTON_MARGIN.dp, BUTTON_MARGIN.dp, BUTTON_MARGIN.dp)
            }
        )
        updateTheme()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val limit = maxContentHeight
        if (limit <= 0) return super.onMeasure(widthMeasureSpec, heightMeasureSpec)
        val available = if (MeasureSpec.getMode(heightMeasureSpec) == MeasureSpec.UNSPECIFIED) {
            limit
        } else {
            min(limit, MeasureSpec.getSize(heightMeasureSpec))
        }
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(available, MeasureSpec.AT_MOST)
        )
    }

    /** The button keeps [bottom] px clear under it, for the system's navigation bar */
    fun setBottomInset(bottom: Int) {
        allowButton.updateLayoutParams<LayoutParams> { bottomMargin = BUTTON_MARGIN.dp + bottom }
    }

    fun setLoading(isLoading: Boolean) {
        allowButton.isLoading = isLoading
    }

    fun showError(message: String?) {
        errorLabel.text = message
        errorLabel.isGone = message.isNullOrBlank()
    }

    fun updateTheme() {
        featureLabels.forEach { it.setTextColor(WColor.PrimaryText) }
        featureIcons.forEach { it.setColorFilter(WColor.Tint.color) }
        disclosureTitleLabel.setTextColor(WColor.PrimaryText)
        disclosureLabel.setTextColor(WColor.SecondaryText)
        searchDisclosureLabel.setTextColor(WColor.SecondaryText)
        errorLabel.setTextColor(WColor.Error)
        disclosureContainer.setBackgroundColor(
            agentIncomingBubbleColor,
            ViewConstants.BLOCK_RADIUS.dp
        )
        allowButton.updateTheme()
    }

    private companion object {
        const val BUTTON_HEIGHT = 50
        const val BUTTON_MARGIN = 16

        // The features' room under the sheet's header
        const val CONTENT_TOP = 8
        const val FEATURE_ICON_SIZE = 28
        const val FEATURE_ICON_GAP = 14
        const val FEATURE_LINE_HEIGHT = 22

        // Each icon's viewport is the square around its shape: the shapes' longer sides share this length
        const val FEATURE_SHAPE_SIZE = 24

        const val DISCLOSURE_TEXT_SIZE = 12f

        // The lines keep their height in proportion to the text, 18 to 13
        const val DISCLOSURE_LINE_HEIGHT = DISCLOSURE_TEXT_SIZE * 18f / 13f

        // Answers, actions and the wallet's context, in the order of the copy's features
        val FEATURE_ICONS = listOf(
            R.drawable.ic_agent_consent_answers,
            R.drawable.ic_agent_consent_actions,
            R.drawable.ic_agent_consent_context
        )

        fun matchWidth(topMargin: Int = 0) = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply {
            this.topMargin = topMargin
        }
    }
}
