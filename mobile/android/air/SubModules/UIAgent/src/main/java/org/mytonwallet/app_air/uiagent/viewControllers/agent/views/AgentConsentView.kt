package org.mytonwallet.app_air.uiagent.viewControllers.agent.views

import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.isGone
import androidx.core.view.updateLayoutParams
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uiagent.agentV2.agentV2ConsentCopy
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class AgentConsentView(context: Context) : WView(context) {
    var onAllow: (() -> Unit)? = null

    private val copy = agentV2ConsentCopy()

    private var topInset = 0
    private var bottomInset = 0

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
        setStyle(16f, WFont.Medium)
        text = copy.disclosureTitle
    }
    private val disclosureLabel = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        text = copy.disclosure
    }
    private val searchDisclosureLabel = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        text = copy.searchDisclosure
    }
    private val errorLabel = WLabel(context).apply {
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
        addView(titleLabel, matchWidth())
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

    fun updateInsets(top: Int, bottom: Int) {
        if (topInset == top && bottomInset == bottom) return
        topInset = top
        bottomInset = bottom
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
        setBackgroundColor(WColor.Background.color)
        titleLabel.setTextColor(WColor.PrimaryText)
        subtitleLabel.setTextColor(WColor.SecondaryText)
        featureLabels.forEach { it.setTextColor(WColor.PrimaryText) }
        disclosureTitleLabel.setTextColor(WColor.PrimaryText)
        disclosureLabel.setTextColor(WColor.SecondaryText)
        searchDisclosureLabel.setTextColor(WColor.SecondaryText)
        errorLabel.setTextColor(WColor.Error)
        disclosureContainer.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        bottomReversedCornerView.setBlurOverlayColor(WColor.Background.color)
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
