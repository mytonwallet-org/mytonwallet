package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.BitmapDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import androidx.core.animation.doOnEnd
import androidx.core.view.AccessibilityDelegateCompat
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.drawToBitmap
import androidx.core.view.isVisible
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class SearchSelectorHeaderCell(context: Context) :
    WCell(context),
    WThemedView {

    enum class Mode(val titleKey: String) {
        RECENT("\$universal_search_recent"),
        SUGGEST("Suggest"),
        TRENDING("Trending")
    }

    private var topRounding = HeaderCell.TopRounding.ZERO
    private var selectedMode = Mode.RECENT
    private var alternativeMode = Mode.TRENDING
    private var showsSelector = false
    private var accessoryText: String? = null
    private var selectorFade: ValueAnimator? = null

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
        setTextColor(WColor.Tint)
    }

    private val recentLabel = selectorLabel("")
    private val separatorLabel = selectorLabel(" · ").apply {
        isClickable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val alternativeLabel = selectorLabel("")

    private val selectorView = LinearLayout(context).apply {
        id = View.generateViewId()
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(recentLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(separatorLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(alternativeLabel, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
    }

    var onModeSelected: ((Mode) -> Unit)? = null

    override fun setupViews() {
        super.setupViews()

        layoutParams.apply {
            height = 40.dp
        }
        addView(
            titleLabel,
            LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                constrainedWidth = true
            }
        )
        addView(selectorView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            setHorizontalBias(titleLabel.id, 0f)
            toStart(titleLabel, 20f)
            endToStart(titleLabel, selectorView, 12f)
            toTop(titleLabel, 16f)
            toEnd(selectorView, 20f)
            centerYToCenterY(selectorView, titleLabel)
        }

        recentLabel.setOnClickListener { onModeSelected?.invoke(Mode.RECENT) }
        alternativeLabel.setOnClickListener { onModeSelected?.invoke(alternativeMode) }
        updateTheme()
    }

    fun configure(
        title: String,
        showsSelector: Boolean,
        selectedMode: Mode,
        alternativeMode: Mode,
        topRounding: HeaderCell.TopRounding,
        accessoryText: String? = null,
        animated: Boolean = false,
        onModeSelected: (Mode) -> Unit
    ) {
        val isSwitching = animated && showsSelector && this.showsSelector &&
            alternativeMode == this.alternativeMode && selectedMode != this.selectedMode &&
            selectorView.isLaidOut && selectorView.width > 0 && selectorView.height > 0 &&
            isAttachedToWindow && WGlobalStorage.getAreAnimationsActive()
        finishSelectorFade()
        if (isSwitching) fadeOutSelector()
        this.selectedMode = selectedMode
        this.alternativeMode = alternativeMode
        this.topRounding = topRounding
        this.showsSelector = showsSelector
        this.accessoryText = accessoryText?.takeIf { !showsSelector }
        this.onModeSelected = onModeSelected
        titleLabel.text = title
        recentLabel.text = this.accessoryText ?: LocaleController.getString(Mode.RECENT.titleKey)
        recentLabel.isClickable = showsSelector && selectedMode != Mode.RECENT
        recentLabel.importantForAccessibility = if (showsSelector && !recentLabel.isClickable) {
            IMPORTANT_FOR_ACCESSIBILITY_NO
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_YES
        }
        alternativeLabel.text = LocaleController.getString(alternativeMode.titleKey)
        alternativeLabel.isClickable = showsSelector && selectedMode != alternativeMode
        alternativeLabel.importantForAccessibility = if (alternativeLabel.isClickable) {
            IMPORTANT_FOR_ACCESSIBILITY_YES
        } else {
            IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        separatorLabel.isVisible = showsSelector
        alternativeLabel.isVisible = showsSelector
        selectorView.isVisible = showsSelector || this.accessoryText != null
        updateTheme()
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        finishSelectorFade()
    }

    private fun fadeOutSelector() {
        val snapshot = BitmapDrawable(resources, selectorView.drawToBitmap()).apply {
            setBounds(selectorView.left, selectorView.top, selectorView.right, selectorView.bottom)
        }
        overlay.add(snapshot)
        selectorView.alpha = 0f
        selectorFade = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = SELECTOR_FADE_MS
            addUpdateListener {
                val fraction = it.animatedValue as Float
                selectorView.alpha = fraction
                snapshot.alpha = ((1f - fraction) * 255).roundToInt()
            }
            doOnEnd {
                overlay.remove(snapshot)
                selectorView.alpha = 1f
            }
            start()
        }
    }

    private fun finishSelectorFade() {
        selectorFade?.end()
        selectorFade = null
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            when (topRounding) {
                HeaderCell.TopRounding.FIRST_ITEM -> ViewConstants.TOOLBAR_RADIUS.dp
                HeaderCell.TopRounding.NORMAL -> ViewConstants.BLOCK_RADIUS.dp
                HeaderCell.TopRounding.ZERO -> 0f
            },
            0f
        )
        titleLabel.updateTheme()
        val isRecentSelected = showsSelector && selectedMode == Mode.RECENT
        recentLabel.setStyle(14f, if (isRecentSelected) WFont.Medium else WFont.Regular)
        recentLabel.setTextColor(
            if (isRecentSelected || !showsSelector) WColor.SecondaryText else WColor.Tint
        )
        separatorLabel.setStyle(14f, WFont.Regular)
        separatorLabel.setTextColor(WColor.SecondaryText)
        alternativeLabel.setStyle(
            14f,
            if (selectedMode == alternativeMode) WFont.Medium else WFont.Regular
        )
        alternativeLabel.setTextColor(
            if (selectedMode == alternativeMode) WColor.SecondaryText else WColor.Tint
        )
    }

    private fun selectorLabel(title: String) = SelectorLabel(context).apply {
        text = title
        setStyle(14f, WFont.Regular)
        setSingleLine()
        ViewCompat.setAccessibilityDelegate(this, selectorButtonAccessibility)
    }

    private companion object {
        const val SELECTOR_FADE_MS = 250L
        const val PRESSED_ALPHA = 0.45f

        val selectorButtonAccessibility = object : AccessibilityDelegateCompat() {
            override fun onInitializeAccessibilityNodeInfo(
                host: View,
                info: AccessibilityNodeInfoCompat
            ) {
                super.onInitializeAccessibilityNodeInfo(host, info)
                if (!host.isClickable) return
                info.className = Button::class.java.name
                info.hintText =
                    LocaleController.getString("\$universal_search_switch_section_contents")
            }
        }
    }

    private class SelectorLabel(context: Context) : WLabel(context) {
        override fun setPressed(pressed: Boolean) {
            super.setPressed(pressed)
            alpha = if (pressed && isClickable) PRESSED_ALPHA else 1f
        }
    }
}
