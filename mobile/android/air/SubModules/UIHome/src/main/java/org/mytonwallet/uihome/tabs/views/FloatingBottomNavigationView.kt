package org.mytonwallet.uihome.tabs.views

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.content.res.AppCompatResources
import android.os.SystemClock
import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.uihome.R

@SuppressLint("ViewConstructor")
class FloatingBottomNavigationView(
    context: Context,
    private val blurRootView: ViewGroup? = null,
) : IBottomNavigationView(context) {

    companion object {
        private const val PILL_WIDTH = 328
        private const val PILL_HEIGHT = 56
        private const val PILL_HORIZONTAL_MARGIN = 4
        private const val ITEM_WIDTH = 80
        private const val ICON_SIZE = 24
        private const val LABEL_SIZE = 11f
        private const val INDICATOR_WIDTH = 80
        private const val INDICATOR_HEIGHT = 48
    }

    override var listener: Listener? = null

    private var selectedTab: Int = ID_HOME
    private var highlightedTab: Int = ID_HOME
    private var isEnabled = true

    private data class TabDef(
        val id: Int,
        val iconRes: Int,
        val filledIconRes: Int,
        val labelKey: String,
    )

    private data class TabItem(
        val container: TabItemView,
    )

    private data class HighlightSlot(
        val contentView: HighlightContentView,
        val rect: RectF = RectF(),
        val path: Path = Path(),
        var tabId: Int = ID_HOME,
        var centerX: Float = 0f,
        var scaleX: Float = 0f,
        var scaleY: Float = 1f,
        var alpha: Float = 1f,
        var isVisible: Boolean = false,
    )

    private val tabDefs = listOf(
        TabDef(ID_HOME, R.drawable.ic_home_thin, R.drawable.ic_home_filled, "Wallet"),
        TabDef(ID_AGENT, R.drawable.ic_agent_thin, R.drawable.ic_agent_filled, "Agent"),
        TabDef(ID_EXPLORE, R.drawable.ic_explore_thin, R.drawable.ic_explore_filled, "Explore"),
        TabDef(ID_SETTINGS, R.drawable.ic_settings_thin, R.drawable.ic_settings_filled, "Settings"),
    )

    private val tabs = linkedMapOf<Int, TabItem>()

    // Indicator: old and new highlights animate together in X while height stays fixed.
    private var indicatorAnimator: ValueAnimator? = null
    private val indicatorPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val outerPath = Path()

    private val pillW = PILL_WIDTH.dp
    private val pillH = PILL_HEIGHT.dp

    @SuppressLint("ViewConstructor")
    private inner class TabItemView(context: Context) : FrameLayout(context) {
        var outlineIcon: ImageView? = null
        var label: WLabel? = null

        fun updateThemeColors() {
            label?.setTextColor(WColor.PrimaryText.color)
            outlineIcon?.setColorFilter(WColor.PrimaryText.color)
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class HighlightContentView(context: Context) : FrameLayout(context) {
        private val iconView = ImageView(context).apply {
            id = generateViewId()
            scaleType = ImageView.ScaleType.CENTER
        }
        private val labelView = WLabel(context).apply {
            id = generateViewId()
            textSize = LABEL_SIZE
            letterSpacing = 0f
            typeface = WFont.SemiBold.typeface
            gravity = Gravity.CENTER
            setSingleLine(true)
            maxLines = 1
        }

        init {
            isClickable = false
            isFocusable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO

            addView(iconView, createIconLayoutParams())
            addView(labelView, createLabelLayoutParams())
            updateThemeColors()
        }

        fun bind(tab: TabDef) {
            iconView.setImageDrawable(AppCompatResources.getDrawable(context, tab.filledIconRes))
            labelView.text = LocaleController.getString(tab.labelKey)
            updateThemeColors()
        }

        fun updateThemeColors() {
            iconView.setColorFilter(tintColor)
            labelView.setTextColor(tintColor)
        }
    }

    private val activeHighlight = HighlightSlot(
        HighlightContentView(context).apply { visibility = INVISIBLE }
    )
    private val incomingHighlight = HighlightSlot(
        HighlightContentView(context).apply { visibility = INVISIBLE }
    )

    private val pillContainer = object : FrameLayout(context) {
        override fun dispatchDraw(canvas: Canvas) {
            if (!hasVisibleHighlight(activeHighlight) && !hasVisibleHighlight(incomingHighlight)) {
                super.dispatchDraw(canvas)
                return
            }

            updateHighlightRect(activeHighlight)
            updateHighlightRect(incomingHighlight)

            val drawingTime = SystemClock.uptimeMillis()
            blurView?.let { super.drawChild(canvas, it, drawingTime) } ?: run {
                canvas.drawColor(WColor.SearchFieldBackground.color)
            }

            drawHighlightBackground(canvas, activeHighlight)
            drawHighlightBackground(canvas, incomingHighlight)

            drawBaseTabs(canvas, drawingTime)
            drawHighlightContent(canvas, activeHighlight, drawingTime)
            drawHighlightContent(canvas, incomingHighlight, drawingTime)
        }

        private fun drawBaseTabs(canvas: Canvas, drawingTime: Long) {
            tabs.values.forEach { tab ->
                super.drawChild(canvas, tab.container, drawingTime)
            }
        }

        private fun drawHighlightBackground(canvas: Canvas, slot: HighlightSlot) {
            if (!hasVisibleHighlight(slot)) return
            val savedAlpha = indicatorPaint.alpha
            indicatorPaint.alpha = (savedAlpha * slot.alpha).toInt()
            val r = slot.rect.height() / 2f
            canvas.drawRoundRect(slot.rect, r, r, indicatorPaint)
            indicatorPaint.alpha = savedAlpha
        }

        private fun drawHighlightContent(canvas: Canvas, slot: HighlightSlot, drawingTime: Long) {
            if (!hasVisibleHighlight(slot)) return
            val alpha = (slot.alpha.coerceIn(0f, 1f) * 255).toInt()
            if (alpha <= 0) return
            val saved = canvas.saveLayerAlpha(
                slot.rect.left, slot.rect.top, slot.rect.right, slot.rect.bottom,
                alpha
            )
            super.drawChild(canvas, slot.contentView, drawingTime)
            canvas.restoreToCount(saved)
        }
    }.apply {
        id = generateViewId()
        setWillNotDraw(false)
        clipChildren = false
        clipToPadding = false
        clipToOutline = true
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, view.height / 2f)
            }
        }
    }

    private fun hasVisibleHighlight(slot: HighlightSlot): Boolean {
        return slot.isVisible && slot.scaleX > 0f
    }

    private fun updateHighlightRect(slot: HighlightSlot) {
        if (!hasVisibleHighlight(slot)) {
            slot.rect.setEmpty()
            slot.path.reset()
            return
        }

        val hHalf = INDICATOR_WIDTH.dp / 2f * slot.scaleX
        val cy = pillContainer.height / 2f
        val vHalf = INDICATOR_HEIGHT.dp / 2f * slot.scaleY
        slot.rect.set(slot.centerX - hHalf, cy - vHalf, slot.centerX + hHalf, cy + vHalf)

        val r = slot.rect.height() / 2f
        slot.path.reset()
        slot.path.addRoundRect(slot.rect, r, r, Path.Direction.CW)
    }

    private fun updatePaths() {
        outerPath.reset()
        outerPath.addRect(
            0f,
            0f,
            pillContainer.width.toFloat(),
            pillContainer.height.toFloat(),
            Path.Direction.CW
        )
        addHighlightHoleToOuterPath(activeHighlight)
        addHighlightHoleToOuterPath(incomingHighlight)
    }

    private fun addHighlightHoleToOuterPath(slot: HighlightSlot) {
        if (!hasVisibleHighlight(slot))
            return

        val r = slot.rect.height() / 2f
        outerPath.addRoundRect(slot.rect, r, r, Path.Direction.CCW)
    }

    private var blurView: WBlurryBackgroundView? = null
    private var pillShadowView: PillShadowView? = null
    private var isPlayingBlur = true

    init {
        id = generateViewId()
        clipChildren = false
        clipToPadding = false

        tabDefs.forEachIndexed { index, def ->
            val outlineIcon = ImageView(context).apply {
                this.id = generateViewId()
                setImageDrawable(AppCompatResources.getDrawable(context, def.iconRes))
                scaleType = ImageView.ScaleType.CENTER
            }
            val label = WLabel(context).apply {
                this.id = generateViewId()
                text = LocaleController.getString(def.labelKey)
                textSize = LABEL_SIZE
                letterSpacing = 0f
                typeface = WFont.SemiBold.typeface
                gravity = Gravity.CENTER
                setSingleLine(true)
                maxLines = 1
            }
            val item = TabItemView(context).apply {
                this.id = generateViewId()
                this.outlineIcon = outlineIcon
                this.label = label
                addView(outlineIcon, createIconLayoutParams())
                addView(label, createLabelLayoutParams())
                updateThemeColors()
                setOnClickListener {
                    if (!isEnabled) return@setOnClickListener
                    selectedItemId = def.id
                }
            }
            pillContainer.addView(
                item,
                LayoutParams(ITEM_WIDTH.dp, MATCH_PARENT).apply {
                    leftMargin = PILL_HORIZONTAL_MARGIN.dp + index * ITEM_WIDTH.dp
                })
            tabs[def.id] = TabItem(item)
        }

        pillContainer.addView(
            activeHighlight.contentView,
            LayoutParams(ITEM_WIDTH.dp, MATCH_PARENT)
        )
        pillContainer.addView(
            incomingHighlight.contentView,
            LayoutParams(ITEM_WIDTH.dp, MATCH_PARENT)
        )

        addView(pillContainer, LayoutParams(pillW, pillH, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
        pillShadowView = PillShadowView.attachTo(pillContainer, pillH / 2f)

        post {
            positionIndicatorInstant(selectedTab)
        }
        updateTheme()
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        super.onLayout(changed, l, t, r, b)
        if (changed) pillShadowView?.sync()
    }

    private fun createIconLayoutParams() = FrameLayout.LayoutParams(
        ICON_SIZE.dp,
        ICON_SIZE.dp,
        Gravity.CENTER_HORIZONTAL or Gravity.TOP
    ).apply {
        topMargin = 9.dp
    }

    private fun createLabelLayoutParams() = FrameLayout.LayoutParams(
        WRAP_CONTENT,
        WRAP_CONTENT,
        Gravity.CENTER_HORIZONTAL or Gravity.BOTTOM
    ).apply {
        bottomMargin = 7.dp
    }

    // ── Selection ─────────────────────────────────────────────────────────────

    override var selectedItemId: Int
        get() = selectedTab
        set(value) {
            val isReselect = selectedTab == value
            val tabSelected = listener?.onTabSelected(value, isReselect)
            if (tabSelected != false && !isReselect) {
                selectTab(value, animated = tabSelected == true)
            }
        }

    private fun selectTab(id: Int, animated: Boolean) {
        selectedTab = id
        if (animated) animateIndicatorTo(id) else positionIndicatorInstant(id)
    }

    private fun tabCenterX(id: Int): Float {
        val index = tabs.keys.indexOf(id)
        if (index < 0) return 0f
        return PILL_HORIZONTAL_MARGIN.dp + index * ITEM_WIDTH.dp + ITEM_WIDTH.dp / 2f
    }

    private fun tabLeftX(id: Int): Float {
        val index = tabs.keys.indexOf(id)
        if (index < 0) return 0f
        return (PILL_HORIZONTAL_MARGIN.dp + index * ITEM_WIDTH.dp).toFloat()
    }

    private fun positionIndicatorInstant(id: Int) {
        highlightedTab = id
        setSingleHighlight(activeHighlight, id, 1f)
        hideHighlight(incomingHighlight)
        resetThinIconAlphas(id)
        pillContainer.invalidate()
    }

    private fun resetThinIconAlphas(selectedId: Int) {
        tabs.forEach { (id, tab) ->
            tab.container.outlineIcon?.alpha = if (id == selectedId) 0f else 1f
        }
    }

    private fun setThinIconAlpha(id: Int, alpha: Float) {
        tabs[id]?.container?.outlineIcon?.alpha = alpha
    }

    private fun animateIndicatorTo(id: Int) {
        indicatorAnimator?.cancel()
        settleToMostVisibleHighlight()

        val previousTab = activeHighlight.tabId
        if (previousTab == id) {
            positionIndicatorInstant(id)
            return
        }

        bindHighlight(activeHighlight, previousTab, 1f)
        bindHighlight(incomingHighlight, id, 0f)

        indicatorAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            var wasCancelled = false
            duration = AnimationConstants.VERY_VERY_QUICK_ANIMATION
            interpolator = CubicBezierInterpolator.EASE_BOTH
            addUpdateListener {
                val progress = animatedValue as Float
                activeHighlight.scaleX = 0.7f + 0.3f * (1f - progress)
                activeHighlight.scaleY = activeHighlight.scaleX
                activeHighlight.alpha = 1 - progress
                incomingHighlight.scaleX = 0.7f + 0.3f * progress
                incomingHighlight.scaleY = incomingHighlight.scaleX
                incomingHighlight.alpha = progress
                setThinIconAlpha(previousTab, progress)
                setThinIconAlpha(id, 1f - progress)
                pillContainer.invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationCancel(animation: Animator) {
                    wasCancelled = true
                    indicatorAnimator = null
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (wasCancelled) return

                    highlightedTab = id
                    setSingleHighlight(activeHighlight, id, 1f)
                    hideHighlight(incomingHighlight)
                    resetThinIconAlphas(id)
                    indicatorAnimator = null
                    pillContainer.invalidate()
                }
            })
            start()
        }
    }

    // ── Appearance ────────────────────────────────────────────────────────────

    private var tintColor: Int = 0

    private fun bindHighlight(slot: HighlightSlot, id: Int, scaleX: Float) {
        val tab = tabDefs.firstOrNull { it.id == id } ?: return
        slot.tabId = id
        slot.centerX = tabCenterX(id)
        slot.scaleX = scaleX
        slot.scaleY = scaleX
        slot.alpha = scaleX
        slot.isVisible = true
        slot.contentView.bind(tab)
        slot.contentView.x = tabLeftX(id)
        slot.contentView.visibility = VISIBLE
    }

    private fun setSingleHighlight(slot: HighlightSlot, id: Int, scaleX: Float) {
        bindHighlight(slot, id, scaleX)
        // At full scale (resting state) always show fully
        if (scaleX == 1f) {
            slot.scaleY = 1f
            slot.alpha = 1f
        }
    }

    private fun hideHighlight(slot: HighlightSlot) {
        slot.isVisible = false
        slot.scaleX = 0.7f
        slot.scaleY = 0.7f
        slot.alpha = 0f
        slot.rect.setEmpty()
        slot.path.reset()
        slot.contentView.visibility = INVISIBLE
    }

    private fun settleToMostVisibleHighlight() {
        val activeVisible = hasVisibleHighlight(activeHighlight)
        val incomingVisible = hasVisibleHighlight(incomingHighlight)

        val settledId = when {
            incomingVisible && (!activeVisible || incomingHighlight.scaleX >= activeHighlight.scaleX) ->
                incomingHighlight.tabId

            activeVisible -> activeHighlight.tabId
            else -> highlightedTab
        }

        highlightedTab = settledId
        setSingleHighlight(activeHighlight, settledId, 1f)
        hideHighlight(incomingHighlight)
        resetThinIconAlphas(settledId)
    }

    override val isTinted = true
    private var _isDarkThemeApplied: Boolean? = null
    override fun updateTheme() {
        val darkModeChanged = ThemeManager.isDark != _isDarkThemeApplied
        _isDarkThemeApplied = ThemeManager.isDark

        val newTintColor = WColor.Tint.color
        val tintChanged = newTintColor != tintColor

        if (tintChanged || darkModeChanged) {
            this.tintColor = newTintColor
            indicatorPaint.color = tintColor.colorWithAlpha(20)
            tabs.values.forEach { it.container.updateThemeColors() }
            activeHighlight.contentView.updateThemeColors()
            incomingHighlight.contentView.updateThemeColors()
        }

        syncBlurView()

        if (darkModeChanged) {
            blurView?.updateTheme()
        }
    }

    private fun syncBlurView() {
        val blurEnabled = WGlobalStorage.isBlurEnabled() && blurRootView != null
        if (blurEnabled && blurView == null) {
            blurView = WBlurryBackgroundView(context, fadeSide = null).also {
                it.setupWith(blurRootView)
                it.setOverlayColor(WColor.SearchFieldBackground, 204)
            }
            pillContainer.addView(blurView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
            isPlayingBlur = true
        } else if (!blurEnabled && blurView != null) {
            pillContainer.removeView(blurView)
            blurView = null
            isPlayingBlur = false
        }
    }

    // ── Blur ──────────────────────────────────────────────────────────────────

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        resumeBlurring()
    }

    override fun pauseBlurring() {
        if (!isPlayingBlur) return
        isPlayingBlur = false
        blurView?.pauseBlurring()
    }

    override fun resumeBlurring() {
        if (isPlayingBlur) return
        isPlayingBlur = true
        blurView?.resumeBlurring()
    }

    override val pausedBlurViews: Boolean
        get() = !isPlayingBlur

    // ── Insets / size ─────────────────────────────────────────────────────────

    override fun insetsUpdated(bottomInset: Int) {
        pillContainer.translationY = ViewConstants.TOOLBAR_RADIUS.dp
        pillShadowView?.sync()
    }

    // ── Misc ──────────────────────────────────────────────────────────────────

    override fun setTabsEnabled(enabled: Boolean) {
        isEnabled = enabled
    }

    override fun getMinimizedWidth(): Int = PILL_WIDTH.dp

    override fun getSettingsItemView(): View? = tabs[ID_SETTINGS]?.container
}
