package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.GONE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.core.graphics.withSave
import androidx.core.view.children
import androidx.core.view.updateLayoutParams
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.WCutoutDrawable
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.PillShadowView
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.JSWebViewBridge

class WNavigationPopup(
    private val initialPopupView: WMenuPopupView,
    private val popupWidth: Int,
    private val windowBackgroundStyle: WMenuPopup.BackgroundStyle,
    private val backdropStyle: WMenuPopup.BackdropStyle,
    private val usePillShadow: Boolean = false
) : INavigationPopup {

    companion object {
        private const val BACKDROP_BLUR_RADIUS = 14f
        private const val BACKGROUND_SCALE = 0.9f
        private const val BACKGROUND_SCRIM_ALPHA = 0.1f
    }

    private val popupHost: WPopupHost? get() = PopupHelpers.popupHost

    private val roundRadius: Float = 20f.dp
    private val transitionXOffset: Float = 48f.dp

    private val isBlurSupported: Boolean
        get() = WGlobalStorage.isBlurEnabled()
    private val shouldUseTransparentBackdrop: Boolean
        get() = backdropStyle is WMenuPopup.BackdropStyle.Transparent
    private val shouldUseDimBackdrop: Boolean
        get() = !shouldUseTransparentBackdrop
    private val shouldUseBlurBackdrop: Boolean
        get() = isBlurSupported && backdropStyle is WMenuPopup.BackdropStyle.BlurDimmed

    private inner class PopupSurfaceLayout(
        private val stableHeightProvider: () -> Int,
        private val fitToSafeBounds: Boolean
    ) : WFrameLayout(initialPopupView.context),
        WThemedView {

        var interceptChildTouches = false
        var dimProgress = 0f
            private set
        private val dimOverlay = View(initialPopupView.context).apply {
            setBackgroundColor(Color.BLACK)
            alpha = 0f
            isClickable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        private var isBlurAutoUpdateEnabled: Boolean? = null
        private var requestedTranslationX = 0f
        private var requestedTranslationY = 0f
        private var isPositionTransitioning = false

        val blurryBackground: WBlurryBackgroundView by lazy {
            WBlurryBackgroundView(initialPopupView.context, null, 25f)
        }

        init {
            if (isBlurSupported) {
                addView(blurryBackground, LayoutParams(0, 0))
                val blurRootView = popupHost?.windowView?.children
                    ?.lastOrNull { child ->
                        child is ViewGroup &&
                            child !is JSWebViewBridge &&
                            child !is WPopupHost
                    } as? ViewGroup

                blurRootView?.let { viewGroup ->
                    blurryBackground.setupWith(viewGroup)
                }
            }
            updateTheme()
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            val stableHeight = stableHeightProvider()
            if (isBlurSupported) {
                // with stable size blur works better while animation
                blurryBackground.measure(measuredWidth.exactly, stableHeight.exactly)
            }
            dimOverlay.measure(measuredWidth.exactly, stableHeight.exactly)
        }

        override fun onInterceptTouchEvent(ev: MotionEvent): Boolean =
            interceptChildTouches || super.onInterceptTouchEvent(ev)

        fun addContentView(view: View, params: FrameLayout.LayoutParams) {
            addView(view, params)
            if (dimOverlay.parent == null) {
                addView(dimOverlay, LayoutParams(0, 0))
            } else {
                dimOverlay.bringToFront()
            }
        }

        fun setRequestedPosition(x: Float, y: Float) {
            requestedTranslationX = x
            requestedTranslationY = y
            translationX = x
            translationY = y
        }

        fun getSafeTranslationY(height: Int): Float {
            val contentAreaBounds = popupHost?.getContentAreaBounds()
                ?: return requestedTranslationY
            val displayTop = top + requestedTranslationY
            val displayBottom = top + height + requestedTranslationY
            var dy = 0f
            if (displayTop < contentAreaBounds.top) {
                dy += contentAreaBounds.top - displayTop
            }
            if (displayBottom + dy > contentAreaBounds.bottom) {
                dy -= displayBottom + dy - contentAreaBounds.bottom
            }
            return requestedTranslationY + dy
        }

        fun beginPositionTransition() {
            isPositionTransitioning = true
        }

        fun finishPositionTransition(height: Int) {
            isPositionTransitioning = false
            translationY = getSafeTranslationY(height)
        }

        fun setDimProgress(progress: Float) {
            val nextProgress = progress.coerceIn(0f, 1f)
            if (dimProgress == nextProgress) return
            dimProgress = nextProgress
            dimOverlay.alpha = BACKGROUND_SCRIM_ALPHA * nextProgress
        }

        fun pauseBlurring() {
            if (isBlurSupported) {
                isBlurAutoUpdateEnabled = false
                blurryBackground.pauseBlurring()
            }
        }

        fun resumeBlurring() {
            if (isBlurSupported) {
                isBlurAutoUpdateEnabled = true
                blurryBackground.resumeBlurring()
            }
        }

        fun setTransitionBlurUpdateEnabled(enabled: Boolean) {
            if (!isBlurSupported || isBlurAutoUpdateEnabled == enabled) return
            isBlurAutoUpdateEnabled = enabled
            blurryBackground.setBlurAutoUpdate(enabled)
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            super.onLayout(changed, left, top, right, bottom)
            dimOverlay.layout(0, 0, measuredWidth, stableHeightProvider())
            if (!fitToSafeBounds) {
                return
            }
            val contentAreaBounds = popupHost?.getContentAreaBounds() ?: return
            if (!changed) {
                return
            }
            // Fit popup to safe bounds
            val displayLeft = left + requestedTranslationX
            val displayRight = right + requestedTranslationX

            var dx = 0f
            if (displayLeft < contentAreaBounds.left) {
                dx += (contentAreaBounds.left - displayLeft)
            }
            if (displayRight + dx > contentAreaBounds.right) {
                dx -= (displayRight + dx - contentAreaBounds.right)
            }

            translationX = requestedTranslationX + dx
            if (!isPositionTransitioning) {
                translationY = getSafeTranslationY(bottom - top)
            }
        }

        override fun updateTheme() {
            if (isBlurSupported) {
                blurryBackground.setOverlayColor(WColor.Background, 204)
            } else {
                setBackgroundColor(WColor.Background.color, roundRadius, true)
            }
            updateShadows()
        }

        private fun updateShadows() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                outlineAmbientShadowColor = WColor.PopupAmbientShadow.color
                outlineSpotShadowColor = WColor.PopupSpotShadow.color
            }
        }

        fun dispose() {
            pauseBlurring()
        }
    }

    private val contentContainerLayout = PopupSurfaceLayout(
        stableHeightProvider = {
            popupViews.maxOfOrNull { it.finalHeight } ?: initialPopupView.finalHeight
        },
        fitToSafeBounds = true
    ).apply {
        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        addContentView(initialPopupView, FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT))
        if (isBlurSupported) {
            setRoundedOutline(roundRadius)
        }
        setOnClickListener {
            if (expandedItemState != null) {
                handleOutsideTap()
            }
        }
    }

    private var windowBackgroundDrawable: Drawable? = null
    private var blurCutoutPath: Path? = null
    private val blurVisiblePath = Path()
    private val windowBlurBackground: WBlurryBackgroundView by lazy {
        WBlurryBackgroundView(initialPopupView.context, null, BACKDROP_BLUR_RADIUS)
    }
    private val blurBackdropContainer = object : WFrameLayout(initialPopupView.context) {
        override fun dispatchDraw(canvas: Canvas) {
            val cutoutPath = blurCutoutPath
            if (cutoutPath == null) {
                super.dispatchDraw(canvas)
                return
            }

            blurVisiblePath.reset()
            blurVisiblePath.addRect(
                0f,
                0f,
                width.toFloat(),
                height.toFloat(),
                Path.Direction.CW
            )
            if (!blurVisiblePath.op(cutoutPath, Path.Op.DIFFERENCE)) {
                super.dispatchDraw(canvas)
                return
            }

            canvas.withSave {
                clipPath(blurVisiblePath)
                super.dispatchDraw(this)
            }
        }
    }.apply {
        addView(windowBlurBackground, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }
    private var isBlurBackdropAttached = false

    private fun getBlurRootView(host: WPopupHost): ViewGroup? = host.windowView?.children
        ?.lastOrNull { child ->
            child is ViewGroup &&
                child !is JSWebViewBridge &&
                child !is WPopupHost
        } as? ViewGroup ?: (host.windowView as? ViewGroup)

    private fun configureBlurBackdrop() {
        windowBlurBackground.post {
            windowBlurBackground.setBlurEnabled(isBlurSupported)
            windowBlurBackground.setBlurRadius(BACKDROP_BLUR_RADIUS)
            windowBlurBackground.setOverlayColor(WColor.Background, 0)
            windowBlurBackground.resumeBlurring()
            windowBlurBackground.invalidate()
        }
    }

    private fun ensureBlurBackdropAttached(host: WPopupHost) {
        if (!shouldUseBlurBackdrop || isBlurBackdropAttached) {
            return
        }

        getBlurRootView(host)?.let { viewGroup ->
            windowBlurBackground.setupWith(viewGroup)
        }

        if (windowBlurBackground.parent is ViewGroup) {
            (windowBlurBackground.parent as ViewGroup).removeView(windowBlurBackground)
        }
        if (blurBackdropContainer.parent is ViewGroup) {
            (blurBackdropContainer.parent as ViewGroup).removeView(blurBackdropContainer)
        }
        if (windowBlurBackground.parent !== blurBackdropContainer) {
            blurBackdropContainer.addView(
                windowBlurBackground,
                FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
            )
        }

        host.addView(blurBackdropContainer, 0, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        isBlurBackdropAttached = true
    }

    private fun updateBackdropProgress(progress: Float) {
        if (shouldUseDimBackdrop) {
            windowBackgroundDrawable?.alpha = (255 * progress).roundToInt()
        } else {
            windowBackgroundDrawable?.alpha = 0
        }
        if (shouldUseBlurBackdrop && isBlurBackdropAttached) {
            blurBackdropContainer.alpha = progress
        }
    }

    private val rootContainerLayout: WFrameLayout = object :
        WFrameLayout(
            initialPopupView.context
        ),
        WThemedView {
        override fun updateTheme() {
            contentContainerLayout.updateTheme()
            expandedItemStates.forEach { it.surface.updateTheme() }
            popupViews.forEach { it.updateTheme() }
            if (shouldUseDimBackdrop) {
                (windowBackgroundDrawable as? WCutoutDrawable)?.color = WColor.PopupWindow.color
            }
            if (shouldUseBlurBackdrop) {
                configureBlurBackdrop()
            }
        }
    }.apply {
        val params = FrameLayout.LayoutParams(
            if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth,
            WRAP_CONTENT
        )
        params.gravity = Gravity.LEFT or Gravity.TOP
        if (windowBackgroundStyle is WMenuPopup.BackgroundStyle.Cutout) {
            blurCutoutPath = if (shouldUseBlurBackdrop) windowBackgroundStyle.cutoutPath else null
            if (shouldUseDimBackdrop) {
                background = WCutoutDrawable().apply {
                    color = WColor.PopupWindow.color
                    cutoutPath = windowBackgroundStyle.cutoutPath
                    windowBackgroundDrawable = this
                }
            } else {
                background = null
                windowBackgroundDrawable = null
            }
        } else {
            blurCutoutPath = null
            windowBackgroundDrawable = null
        }
        addView(contentContainerLayout, params)
        setOnClickListener { handleOutsideTap() }
    }

    private val popupViews = mutableListOf(initialPopupView)

    private inner class ExpandedItemState(
        val sourceView: WMenuPopupView,
        val sourceSurface: PopupSurfaceLayout,
        val backgroundSurfaces: List<PopupSurfaceLayout>,
        val originalScales: List<Pair<Float, Float>>,
        val originalDimProgress: Float,
        val nextView: WMenuPopupView,
        val surface: PopupSurfaceLayout,
        val shadow: PillShadowView?,
        val sourceY: Float,
        val targetY: Float,
        val sourceHeight: Int,
        val targetHeight: Int,
        val originalPivotX: Float,
        val originalPivotY: Float,
        val originalImportantForAccessibility: Int
    )

    private val expandedItemStates = mutableListOf<ExpandedItemState>()
    private val expandedItemState: ExpandedItemState?
        get() = expandedItemStates.lastOrNull()
    private var itemTransitionAnimator: ValueAnimator? = null
    private val itemTransitionInterpolator = AccelerateDecelerateInterpolator()
    private var isItemTransitioning = false
    private var isExpandedDismissing = false
    private var onDismissListener: (() -> Unit)? = null
    private var displayProgressListener: ((progress: Float) -> Unit)? = null
    private var isDismissed = false

    private fun lerp(start: Float, end: Float, progress: Float): Float =
        start + (end - start) * progress

    private fun setSurfaceHeight(surface: PopupSurfaceLayout, height: Int) {
        if (surface.isLaidOut) {
            surface.bottom = surface.top + height
            surface.invalidateOutline()
        } else {
            surface.updateLayoutParams {
                this.height = height
            }
        }
    }

    private fun pauseItemTransitionBlurs(activeSurface: PopupSurfaceLayout) {
        if (!isBlurSupported) return
        if (contentContainerLayout !== activeSurface) contentContainerLayout.pauseBlurring()
        expandedItemStates.forEach {
            if (it.surface !== activeSurface) it.surface.pauseBlurring()
        }
        activeSurface.resumeBlurring()
        if (isBlurBackdropAttached) windowBlurBackground.pauseBlurring()
    }

    private fun resumeItemTransitionBlurs() {
        if (!isBlurSupported || isDismissed) return
        contentContainerLayout.resumeBlurring()
        expandedItemStates.forEach { it.surface.resumeBlurring() }
        if (isBlurBackdropAttached) windowBlurBackground.resumeBlurring()
    }

    private fun shouldThrottleTransitionBlur(surface: PopupSurfaceLayout): Boolean =
        isBlurSupported && (surface.display?.refreshRate ?: 60f) > 75f

    private fun handleOutsideTap() {
        if (isItemTransitioning || isExpandedDismissing) {
            return
        }
        if (expandedItemState != null) {
            pop()
        } else {
            dismiss()
        }
    }

    init {
        initialPopupView.popupWindow = this
    }

    fun setOnDismissListener(listener: (() -> Unit)?) {
        onDismissListener = listener
    }

    fun setDisplayProgressListener(listener: ((progress: Float) -> Unit)?) {
        displayProgressListener = listener
    }

    private var pillShadow: PillShadowView? = null

    private fun attachPillShadowIfNeeded() {
        if (!usePillShadow || pillShadow != null) return
        pillShadow = PillShadowView.attachTo(contentContainerLayout, roundRadius)
        contentContainerLayout.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            pillShadow?.sync()
        }
    }

    fun showAtLocation(x: Int, y: Int, initialHeight: Int = 0, fromTop: Boolean = true) {
        val popupHost = this.popupHost ?: return
        ensureBlurBackdropAttached(popupHost)
        contentContainerLayout.apply {
            setRequestedPosition(
                x.toFloat() - popupHost.paddingLeft,
                y.toFloat() - popupHost.paddingTop
            )
            val elevationValue = if (usePillShadow) {
                0f
            } else if (!shouldUseDimBackdrop ||
                windowBackgroundStyle is WMenuPopup.BackgroundStyle.Transparent
            ) {
                4f
            } else {
                2f
            }
            elevation = elevationValue.dp
        }
        popupHost.addView(rootContainerLayout)
        attachPillShadowIfNeeded()
        if (shouldUseBlurBackdrop) {
            configureBlurBackdrop()
            blurBackdropContainer.alpha = 0f
        }
        updateBackdropProgress(0f)
        val interpolator = LinearInterpolator()
        initialPopupView.present(initialHeight, fromTop) { animationFraction ->
            val interpolated = interpolator.getInterpolation(animationFraction)
            updateBackdropProgress(interpolated)
            displayProgressListener?.invoke(animationFraction)
            pillShadow?.sync()
        }
        PopupHelpers.popupShown(this)
    }

    override fun push(
        nextPopupView: WMenuPopupView,
        animated: Boolean,
        onCompletion: (() -> Unit)?,
        transition: WMenuPopup.SubmenuTransition,
        sourceItemIndex: Int?
    ) {
        if (
            transition == WMenuPopup.SubmenuTransition.EXPAND_FROM_ITEM &&
            sourceItemIndex != null
        ) {
            pushFromItem(nextPopupView, sourceItemIndex, animated, onCompletion)
            return
        }

        val currentView = popupViews.last()
        currentView.lockView()

        nextPopupView.present(initialHeight = currentView.height, fromTop = true)
        nextPopupView.alpha = 0f
        nextPopupView.translationX = transitionXOffset
        nextPopupView.lockView()

        val layoutWidth =
            if (popupWidth == WRAP_CONTENT) contentContainerLayout.width else popupWidth
        contentContainerLayout.addContentView(
            nextPopupView,
            FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT)
        )
        popupViews.add(nextPopupView)
        val targetTranslationY =
            contentContainerLayout.getSafeTranslationY(nextPopupView.finalHeight)

        fun onEnd() {
            contentContainerLayout.finishPositionTransition(nextPopupView.finalHeight)
            currentView.visibility = GONE
            nextPopupView.alpha = 1f
            nextPopupView.translationX = 0f
            nextPopupView.unlockView()
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            contentContainerLayout.beginPositionTransition()
            animatorSet {
                together {
                    viewProperty(contentContainerLayout) {
                        translationY(targetTranslationY)
                        duration(AnimationConstants.NAV_PUSH)
                        interpolator(WInterpolator.emphasized)
                    }
                    viewProperty(nextPopupView) {
                        alpha(1f)
                        translationX(0f)
                        duration(AnimationConstants.NAV_PUSH)
                        interpolator(WInterpolator.emphasized)
                    }
                    viewProperty(currentView) {
                        alpha(0f)
                        translationX(-transitionXOffset)
                        duration(AnimationConstants.NAV_PUSH / 2)
                        interpolator(WInterpolator.emphasized)
                    }
                }
                onEnd { onEnd() }
            }.start()
        } else {
            onEnd()
        }
    }

    private fun pushFromItem(
        nextPopupView: WMenuPopupView,
        sourceItemIndex: Int,
        animated: Boolean,
        onCompletion: (() -> Unit)?
    ) {
        if (isItemTransitioning) {
            return
        }

        val currentView = popupViews.last()
        val parentState = expandedItemState
        val sourceSurface = parentState?.surface ?: contentContainerLayout
        val layoutWidth =
            if (popupWidth == WRAP_CONTENT) sourceSurface.width else popupWidth
        val sourceItemTop = currentView.getItemTop(sourceItemIndex)
        val sourceItemHeight = currentView.getItemHeight(sourceItemIndex)
        val firstItemHeight = currentView.getItemHeight(0)
        val desiredTargetY =
            sourceSurface.translationY + BACKGROUND_SCALE * firstItemHeight - 8f.dp
        val contentAreaBounds = popupHost?.getContentAreaBounds()
        val targetY = contentAreaBounds?.let { bounds ->
            val minY = bounds.top.toFloat()
            val maxY = (bounds.bottom - sourceItemHeight)
                .coerceAtLeast(bounds.top)
                .toFloat()
            desiredTargetY.coerceIn(minY, maxY)
        } ?: desiredTargetY
        contentAreaBounds?.let { bounds ->
            nextPopupView.limitHeight(
                (bounds.bottom - targetY).toInt().coerceAtLeast(sourceItemHeight)
            )
        }

        nextPopupView.prepareForExpandingPresentation()
        nextPopupView.lockView()
        currentView.lockView()

        val targetHeight = nextPopupView.finalHeight
        val sourceY = sourceSurface.translationY + sourceItemTop

        val foregroundSurface = PopupSurfaceLayout(
            stableHeightProvider = { targetHeight },
            fitToSafeBounds = false
        ).apply {
            translationX = sourceSurface.translationX
            translationY = sourceY
            elevation = if (usePillShadow) 0f else sourceSurface.elevation + 1f.dp
            addContentView(
                nextPopupView,
                FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT)
            )
            if (isBlurSupported) {
                setRoundedOutline(roundRadius)
            }
            setOnClickListener {
                if (interceptChildTouches) {
                    handleOutsideTap()
                }
            }
        }
        rootContainerLayout.addView(
            foregroundSurface,
            FrameLayout.LayoutParams(layoutWidth, sourceItemHeight).apply {
                gravity = Gravity.LEFT or Gravity.TOP
            }
        )
        val foregroundShadow = if (usePillShadow) {
            PillShadowView.attachTo(foregroundSurface, roundRadius)
        } else {
            null
        }
        foregroundSurface.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            foregroundShadow?.sync()
        }

        val backgroundSurfaces =
            listOf(contentContainerLayout) + expandedItemStates.map { it.surface }
        val state = ExpandedItemState(
            sourceView = currentView,
            sourceSurface = sourceSurface,
            backgroundSurfaces = backgroundSurfaces,
            originalScales = backgroundSurfaces.map { it.scaleX to it.scaleY },
            originalDimProgress = sourceSurface.dimProgress,
            nextView = nextPopupView,
            surface = foregroundSurface,
            shadow = foregroundShadow,
            sourceY = sourceY,
            targetY = targetY,
            sourceHeight = sourceItemHeight,
            targetHeight = targetHeight,
            originalPivotX = sourceSurface.pivotX,
            originalPivotY = sourceSurface.pivotY,
            originalImportantForAccessibility =
                sourceSurface.importantForAccessibility
        )
        expandedItemStates.add(state)
        popupViews.add(nextPopupView)

        sourceSurface.interceptChildTouches = true
        sourceSurface.importantForAccessibility =
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        sourceSurface.pivotX = sourceSurface.width / 2f
        sourceSurface.pivotY =
            contentContainerLayout.translationY - sourceSurface.translationY

        var throttleBlurUpdates = false
        var blurFrame = 0

        fun update(progress: Float) {
            if (throttleBlurUpdates) {
                foregroundSurface.setTransitionBlurUpdateEnabled(blurFrame++ % 2 == 0)
            }
            val easedProgress = itemTransitionInterpolator.getInterpolation(progress)
                .coerceIn(0f, 1f)
            state.backgroundSurfaces.forEachIndexed { index, surface ->
                val originalScale = state.originalScales[index]
                surface.scaleX = lerp(
                    originalScale.first,
                    originalScale.first * BACKGROUND_SCALE,
                    easedProgress
                )
                surface.scaleY = lerp(
                    originalScale.second,
                    originalScale.second * BACKGROUND_SCALE,
                    easedProgress
                )
            }
            sourceSurface.setDimProgress(
                lerp(state.originalDimProgress, 1f, easedProgress)
            )
            foregroundSurface.translationY = lerp(sourceY, targetY, easedProgress)
            setSurfaceHeight(
                foregroundSurface,
                lerp(
                    sourceItemHeight.toFloat(),
                    targetHeight.toFloat(),
                    easedProgress
                ).roundToInt()
            )
            nextPopupView.setExpandingPresentationProgress(
                easedProgress,
                updateAppearance = false
            )
            pillShadow?.sync()
            expandedItemStates.forEach { it.shadow?.sync() }
        }

        fun finish() {
            update(1f)
            foregroundSurface.layoutParams.height = targetHeight
            foregroundSurface.setTransitionBlurUpdateEnabled(true)
            nextPopupView.finishExpandingAppearanceAnimation()
            itemTransitionAnimator = null
            isItemTransitioning = false
            resumeItemTransitionBlurs()
            nextPopupView.unlockView()
            nextPopupView.prepareExpandingSubmenus()
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            isItemTransitioning = true
            val animator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = LinearInterpolator()
                addUpdateListener { update(it.animatedValue as Float) }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        finish()
                    }
                })
            }
            itemTransitionAnimator = animator
            foregroundSurface.postOnAnimation {
                if (itemTransitionAnimator !== animator) return@postOnAnimation
                pauseItemTransitionBlurs(foregroundSurface)
                throttleBlurUpdates = shouldThrottleTransitionBlur(foregroundSurface)
                nextPopupView.startExpandingAppearanceAnimation()
                animator.start()
            }
        } else {
            finish()
        }
    }

    private fun collapseExpandedItem(
        state: ExpandedItemState,
        animated: Boolean,
        onCompletion: (() -> Unit)?
    ) {
        if (isItemTransitioning || expandedItemState !== state) {
            return
        }

        state.nextView.lockView()
        state.nextView.resetExpandingPresentationScroll()

        var throttleBlurUpdates = false
        var blurFrame = 0

        fun update(progress: Float) {
            if (throttleBlurUpdates) {
                state.surface.setTransitionBlurUpdateEnabled(blurFrame++ % 2 == 0)
            }
            val easedProgress = itemTransitionInterpolator.getInterpolation(progress)
                .coerceIn(0f, 1f)
            state.backgroundSurfaces.forEachIndexed { index, surface ->
                val originalScale = state.originalScales[index]
                surface.scaleX = lerp(
                    originalScale.first,
                    originalScale.first * BACKGROUND_SCALE,
                    easedProgress
                )
                surface.scaleY = lerp(
                    originalScale.second,
                    originalScale.second * BACKGROUND_SCALE,
                    easedProgress
                )
            }
            state.sourceSurface.setDimProgress(
                lerp(state.originalDimProgress, 1f, easedProgress)
            )
            state.surface.translationY = lerp(state.sourceY, state.targetY, easedProgress)
            setSurfaceHeight(
                state.surface,
                lerp(
                    state.sourceHeight.toFloat(),
                    state.targetHeight.toFloat(),
                    easedProgress
                ).roundToInt()
            )
            state.nextView.setExpandingPresentationProgress(easedProgress)
            pillShadow?.sync()
            expandedItemStates.forEach { it.shadow?.sync() }
        }

        fun finish() {
            update(0f)
            state.sourceSurface.pivotX = state.originalPivotX
            state.sourceSurface.pivotY = state.originalPivotY
            state.sourceSurface.importantForAccessibility =
                state.originalImportantForAccessibility
            state.sourceSurface.interceptChildTouches = false
            state.surface.dispose()
            (state.shadow?.parent as? ViewGroup)?.removeView(state.shadow)
            rootContainerLayout.removeView(state.surface)
            popupViews.remove(state.nextView)
            expandedItemStates.removeAt(expandedItemStates.lastIndex)
            itemTransitionAnimator = null
            isItemTransitioning = false
            state.sourceView.unlockView()
            resumeItemTransitionBlurs()
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            isItemTransitioning = true
            pauseItemTransitionBlurs(state.surface)
            throttleBlurUpdates = shouldThrottleTransitionBlur(state.surface)
            itemTransitionAnimator = ValueAnimator.ofFloat(1f, 0f).apply {
                duration = AnimationConstants.VERY_QUICK_ANIMATION
                interpolator = LinearInterpolator()
                addUpdateListener { update(it.animatedValue as Float) }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        finish()
                    }
                })
                start()
            }
        } else {
            finish()
        }
    }

    override fun pop(animated: Boolean, onCompletion: (() -> Unit)?) {
        expandedItemState?.let {
            collapseExpandedItem(it, animated, onCompletion)
            return
        }
        if (popupViews.size <= 1) {
            dismiss()
            return
        }

        val currentView = popupViews.last()
        val previousView = popupViews[popupViews.size - 2]
        val targetTranslationY =
            contentContainerLayout.getSafeTranslationY(previousView.height)

        with(previousView) {
            unlockView()
            visibility = VISIBLE
            alpha = 0f
            translationX = -transitionXOffset
        }

        fun onEnd() {
            contentContainerLayout.finishPositionTransition(previousView.height)
            with(previousView) {
                alpha = 1f
                translationX = 0f
            }
            contentContainerLayout.removeView(currentView)
            popupViews.removeAt(popupViews.size - 1)
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            currentView.post {
                contentContainerLayout.beginPositionTransition()
                animatorSet {
                    together {
                        viewProperty(contentContainerLayout) {
                            translationY(targetTranslationY)
                            duration(AnimationConstants.NAV_POP)
                            interpolator(WInterpolator.emphasized)
                        }
                        viewProperty(currentView) {
                            alpha(0f)
                            translationX(transitionXOffset)
                            duration(AnimationConstants.NAV_POP / 2)
                            interpolator(WInterpolator.emphasized)
                        }
                        viewProperty(previousView) {
                            alpha(1f)
                            translationX(0f)
                            duration(AnimationConstants.NAV_POP)
                            interpolator(WInterpolator.emphasized)
                        }
                        intValues(contentContainerLayout.height, previousView.height) {
                            interpolator(AccelerateDecelerateInterpolator())
                            duration(AnimationConstants.NAV_POP)
                            onUpdate { animatedValue ->
                                contentContainerLayout.updateLayoutParams {
                                    height = animatedValue
                                }
                            }
                        }
                    }
                    onEnd { onEnd() }
                }.start()
            }
        } else {
            onEnd()
        }
    }

    override fun onBackPressed() {
        pop(animated = true)
    }

    private fun dismissExpandedItem(state: ExpandedItemState) {
        if (isExpandedDismissing) {
            return
        }
        isExpandedDismissing = true
        state.sourceView.lockView()
        state.nextView.lockView()
        state.nextView.notifyWillDismiss()
        PopupHelpers.popupDismissed(this)

        val surfaces = listOf(contentContainerLayout) + expandedItemStates.map { it.surface }
        val surfaceStates = surfaces.map { surface ->
            Triple(surface, surface.translationY, surface.alpha)
        }
        val interpolator = AccelerateDecelerateInterpolator()

        fun update(progress: Float) {
            val easedProgress = interpolator.getInterpolation(progress)
            surfaceStates.forEach { (surface, translationY, alpha) ->
                surface.alpha = lerp(alpha, 0f, easedProgress)
                surface.translationY = translationY - easedProgress * 8f.dp
            }
            val reversedProgress = 1f - progress
            updateBackdropProgress(reversedProgress)
            displayProgressListener?.invoke(reversedProgress)
            expandedItemStates.forEach { it.shadow?.sync() }
            pillShadow?.sync()
        }

        fun finish() {
            update(1f)
            expandedItemStates.forEach { it.surface.dispose() }
            removeFromParent()
        }

        if (WGlobalStorage.getAreAnimationsActive()) {
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = AnimationConstants.MENU_DISMISS
                addUpdateListener { update(it.animatedValue as Float) }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        finish()
                    }
                })
                start()
            }
        } else {
            finish()
        }
    }

    override fun dismiss() {
        if (isDismissed) {
            return
        }
        if (isItemTransitioning) {
            itemTransitionAnimator?.end()
        }
        expandedItemState?.let {
            dismissExpandedItem(it)
            return
        }
        popupViews.last().apply {
            PopupHelpers.popupDismissed(this@WNavigationPopup)
            if (isDismissed) {
                removeFromParent()
                return
            }
            lockView()
            val interpolator = LinearInterpolator()
            dismiss { animationFraction ->
                val reversed = 1 - animationFraction
                val reversedInterpolated = interpolator.getInterpolation(reversed)
                updateBackdropProgress(reversedInterpolated)
                displayProgressListener?.invoke(reversedInterpolated)
                pillShadow?.sync()
            }
            PopupHelpers.popupDismissed(this@WNavigationPopup)
        }
    }

    private fun removeFromParent() {
        if (isDismissed) {
            return
        }
        isDismissed = true
        PopupHelpers.popupDismissed(this@WNavigationPopup)

        (rootContainerLayout.parent as? ViewGroup)?.removeView(rootContainerLayout)
        if (isBlurBackdropAttached) {
            windowBlurBackground.pauseBlurring()
            (blurBackdropContainer.parent as? ViewGroup)?.removeView(blurBackdropContainer)
            isBlurBackdropAttached = false
        }
        onDismissListener?.invoke()
    }
}
