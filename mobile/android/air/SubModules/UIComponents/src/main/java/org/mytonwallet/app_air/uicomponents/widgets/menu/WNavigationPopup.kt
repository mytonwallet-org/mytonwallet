package org.mytonwallet.app_air.uicomponents.widgets.menu

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.GONE
import android.view.View.INVISIBLE
import android.view.View.VISIBLE
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewTreeObserver
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import androidx.core.graphics.withSave
import androidx.core.view.children
import androidx.core.view.doOnPreDraw
import androidx.core.view.updateLayoutParams
import kotlin.math.abs
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.drawable.WCutoutDrawable
import org.mytonwallet.app_air.uicomponents.extensions.animatorSet
import org.mytonwallet.app_air.uicomponents.extensions.captureHardwareImage
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.glass.GlassFlavor
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.helpers.PopupHelpers
import org.mytonwallet.app_air.uicomponents.widgets.INavigationPopup
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.setRoundedOutline
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.theme.colorForTheme
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcore.JSWebViewBridge

class WNavigationPopup(
    private val initialPopupView: WMenuPopupView,
    private val popupWidth: Int,
    private val windowBackgroundStyle: WMenuPopup.BackgroundStyle,
    private val backdropStyle: WMenuPopup.BackdropStyle,
    private val usePillShadow: Boolean = false,
    private val morphSource: View? = null
) : INavigationPopup {

    companion object {
        private const val BACKGROUND_SCALE = 0.9f
        private const val BACKGROUND_SCRIM_ALPHA = 0.1f
        private const val MORPH_SOURCE_FADE_END = 0.15f
        private val DRAG_SELECTION_ACTIVATION_DISTANCE = 4f.dp
    }

    private val popupHost: WPopupHost? get() = PopupHelpers.popupHost

    private val roundRadius: Float = 20f.dp

    // The menu's surface without blur, in the menu's theme
    private val surfaceColor: Int
        get() = WColor.Background.colorForTheme(initialPopupView.themeIsDark)
    private val transitionXOffset: Float = 48f.dp

    private val isBlurSupported: Boolean
        get() = WGlobalStorage.isBlurEnabled()

    // A menu in a fixed theme is solid, as Telegram's viewer's is: over a screen of another theme, its glass would let
    // that screen's lighter parts show through
    private val isSurfaceBlurred: Boolean
        get() = isBlurSupported && initialPopupView.themeIsDark == null
    private val shouldUseTransparentBackdrop: Boolean
        get() = backdropStyle is WMenuPopup.BackdropStyle.Transparent
    private val shouldUseDimBackdrop: Boolean
        get() = backdropStyle is WMenuPopup.BackdropStyle.BlurDimmed ||
            backdropStyle is WMenuPopup.BackdropStyle.Dimmed
    private val shouldUseBlurBackdrop: Boolean
        get() = isBlurSupported && (
            backdropStyle is WMenuPopup.BackdropStyle.BlurDimmed ||
                backdropStyle is WMenuPopup.BackdropStyle.PlainBlur
            )

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
        private var requestedTranslationX = 0f
        private var requestedTranslationY = 0f
        private var isPositionTransitioning = false
        private var surfaceRadius = roundRadius

        fun setMorphSize(width: Int, height: Int, radius: Float) {
            right = left + width
            bottom = top + height
            surfaceRadius = radius
            setRoundedOutline(radius)
            if (isSurfaceBlurred) {
                // Match the animated shadow outline without resizing the stable blur height
                blurryBackground.right = blurryBackground.left + width
                blurryBackground.setRadius(radius)
            } else {
                setBackgroundColor(surfaceColor, radius, true)
            }
            dimOverlay.right = dimOverlay.left + width
        }

        val blurryBackground: WGlassView by lazy {
            WGlassView(initialPopupView.context).apply {
                flavor = GlassFlavor.FROSTED
                liquidGlass = false
                setRadius(roundRadius)
                setProvider(GlassProviders.legacy(WColor.Background))
            }
        }

        init {
            if (isSurfaceBlurred) {
                addView(blurryBackground, LayoutParams(0, 0))
                val blurRootView = popupHost?.windowView?.children
                    ?.lastOrNull { child ->
                        child is ViewGroup &&
                            child !is JSWebViewBridge &&
                            child !is WPopupHost &&
                            !isMinimizedBrowser(child)
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
            if (isSurfaceBlurred) {
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
            if (isSurfaceBlurred) {
                blurryBackground.updateTheme()
            } else {
                setBackgroundColor(surfaceColor, surfaceRadius, true)
            }
            updateShadows()
        }

        private fun updateShadows() {
            WMenuPopup.applySurfaceShadowColors(this)
        }

        fun dispose() {}
    }

    private val contentContainerLayout = PopupSurfaceLayout(
        stableHeightProvider = {
            popupViews.maxOfOrNull { it.finalHeight } ?: initialPopupView.finalHeight
        },
        fitToSafeBounds = true
    ).apply {
        val layoutWidth = if (popupWidth == WRAP_CONTENT) WRAP_CONTENT else popupWidth
        addContentView(initialPopupView, FrameLayout.LayoutParams(layoutWidth, WRAP_CONTENT))
        if (isSurfaceBlurred) {
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
    private val windowBlurBackground: WGlassView by lazy {
        WGlassView(initialPopupView.context).apply {
            flavor = if (backdropStyle is WMenuPopup.BackdropStyle.PlainBlur) {
                GlassFlavor.FROSTED_PLAIN
            } else {
                GlassFlavor.FROSTED
            }
            liquidGlass = false
            setProvider(GlassProviders.plain(WColor.Background, 0f))
        }
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
                child !is WPopupHost &&
                !isMinimizedBrowser(child)
        } as? ViewGroup ?: (host.windowView as? ViewGroup)

    private fun isMinimizedBrowser(view: View) = view is WNavigationController &&
        view.window.hasMinimizedBrowser && view.window.minimizedBrowser.hosts(view)

    private fun configureBlurBackdrop() {
        windowBlurBackground.post {
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
            (windowBlurBackground.parent as? ViewGroup)?.removeView(windowBlurBackground)
        }
        if (blurBackdropContainer.parent is ViewGroup) {
            (blurBackdropContainer.parent as? ViewGroup)?.removeView(blurBackdropContainer)
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

    private var backdropProgress = 0f

    private fun updateBackdropProgress(progress: Float) {
        backdropProgress = progress
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
        override fun onDetachedFromWindow() {
            super.onDetachedFromWindow()
            if (morphSource != null) removeFromParent()
        }

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
        val cutoutStyle = if (morphSource == null) {
            windowBackgroundStyle as? WMenuPopup.BackgroundStyle.Cutout
        } else {
            null
        }
        blurCutoutPath = if (shouldUseBlurBackdrop) cutoutStyle?.cutoutPath else null
        if (shouldUseDimBackdrop && (morphSource != null || cutoutStyle != null)) {
            background = WCutoutDrawable().apply {
                color = WColor.PopupWindow.color
                cutoutPath = cutoutStyle?.cutoutPath
                lifted = cutoutStyle?.lifted
                windowBackgroundDrawable = this
            }
        } else {
            background = null
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
        val shadow: WGlassView?,
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

    private var morphAnimator: ValueAnimator? = null
    private var morphProgress = 0f
    private var isMorphDismissing = false
    private var sourceAlpha: Float? = null
    private var sourceSnapshot: Bitmap? = null
    private val sourceBounds = RectF()
    private val menuBounds = RectF()

    private var isPresented = false
    private var dragSelectionStartY: Float? = null
    private var dragSelectionView: WMenuPopupView? = null
    private var hasLastDragPoint = false
    private var lastDragX = 0f
    private var lastDragY = 0f
    private var hasPendingDragRelease = false
    private val canDragSelect: Boolean
        get() = isPresented && !isDismissed && !isMorphDismissing &&
            !isItemTransitioning && !isExpandedDismissing
    private val sourceLayoutBounds = Rect()
    private val hostLayoutBounds = Rect()
    private val hostContentBounds = Rect()
    private var geometryObserver: ViewTreeObserver? = null
    private var geometryListener: ViewTreeObserver.OnGlobalLayoutListener? = null
    private val snapshotPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val snapshotView = object : View(initialPopupView.context) {
        override fun onDraw(canvas: Canvas) {
            sourceSnapshot?.let { canvas.drawBitmap(it, 0f, 0f, snapshotPaint) }
        }
    }.apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        isClickable = false
    }
    private val sourceAttachListener = object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) {}

        override fun onViewDetachedFromWindow(view: View) {
            removeFromParent()
        }
    }

    private fun captureSource(source: View, onResult: (Bitmap?) -> Unit) {
        val parent = source.parent as? View
        if (source.width <= 0 || source.height <= 0 || parent == null) {
            onResult(null)
            return
        }
        val captureView = object : View(source.context) {
            override fun onDraw(canvas: Canvas) {
                canvas.withSave {
                    translate(-source.x + parent.scrollX, -source.y + parent.scrollY)
                    parent.draw(this)
                }
            }
        }
        captureView.layout(0, 0, source.width, source.height)
        captureView.captureHardwareImage(onResult)
    }

    private fun presentMorph(source: View, host: WPopupHost) {
        val location = IntArray(2)
        val hostLocation = IntArray(2)
        source.getLocationInWindow(location)
        host.getLocationInWindow(hostLocation)
        sourceBounds.set(
            (location[0] - hostLocation[0]).toFloat(),
            (location[1] - hostLocation[1]).toFloat(),
            (location[0] - hostLocation[0] + source.width).toFloat(),
            (location[1] - hostLocation[1] + source.height).toFloat()
        )
        source.getGlobalVisibleRect(sourceLayoutBounds)
        host.getGlobalVisibleRect(hostLayoutBounds)
        hostContentBounds.set(host.getContentAreaBounds())
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            val currentSourceBounds = Rect()
            val currentHostBounds = Rect()
            source.getGlobalVisibleRect(currentSourceBounds)
            host.getGlobalVisibleRect(currentHostBounds)
            if (currentSourceBounds != sourceLayoutBounds ||
                currentHostBounds != hostLayoutBounds ||
                host.getContentAreaBounds() != hostContentBounds
            ) {
                removeFromParent()
            }
        }
        geometryListener = listener
        geometryObserver = host.viewTreeObserver.also { it.addOnGlobalLayoutListener(listener) }
        initialPopupView.limitHeight(hostContentBounds.height())
        initialPopupView.prepareForExpandingPresentation()
        initialPopupView.alpha = 0f
        contentContainerLayout.alpha = 0f
        contentContainerLayout.interceptChildTouches = true
        source.addOnAttachStateChangeListener(sourceAttachListener)
        rootContainerLayout.addView(
            snapshotView,
            FrameLayout.LayoutParams(source.width, source.height).apply {
                // Morph positions use physical window coordinates in both layout directions
                gravity = Gravity.LEFT or Gravity.TOP
            }
        )
        snapshotView.visibility = INVISIBLE
        captureSource(source) { bitmap ->
            if (isDismissed || isMorphDismissing || !source.isAttachedToWindow) {
                bitmap?.recycle()
                if (!isDismissed) removeFromParent()
                return@captureSource
            }
            sourceSnapshot = bitmap
            rootContainerLayout.doOnPreDraw {
                if (isDismissed || isMorphDismissing || !source.isAttachedToWindow) {
                    if (!isDismissed) removeFromParent()
                    return@doOnPreDraw
                }
                menuBounds.set(
                    contentContainerLayout.x,
                    contentContainerLayout.y,
                    contentContainerLayout.x + contentContainerLayout.width,
                    contentContainerLayout.y + initialPopupView.finalHeight
                )
                sourceAlpha = source.alpha
                snapshotView.visibility = VISIBLE
                contentContainerLayout.beginPositionTransition()
                animateMorph(1f)
            }
            rootContainerLayout.invalidate()
        }
    }

    private fun updateMorph(progress: Float) {
        morphProgress = progress
        // Crossfade matching source outlines before changing the surface geometry
        val surfaceAlpha = (progress / MORPH_SOURCE_FADE_END).coerceIn(0f, 1f)
        val shapeProgress = (
            (progress - MORPH_SOURCE_FADE_END) / (1f - MORPH_SOURCE_FADE_END)
            ).coerceIn(0f, 1f)
        morphSource?.alpha = if (sourceSnapshot == null) {
            (sourceAlpha ?: 1f) * (1f - surfaceAlpha)
        } else {
            0f
        }
        val width = lerp(sourceBounds.width(), menuBounds.width(), shapeProgress).roundToInt()
        val height = lerp(sourceBounds.height(), menuBounds.height(), shapeProgress).roundToInt()
        val x = lerp(sourceBounds.left, menuBounds.left, shapeProgress)
        val y = lerp(sourceBounds.top, menuBounds.top, shapeProgress)
        val radius = lerp(sourceBounds.height() / 2f, roundRadius, shapeProgress)
        contentContainerLayout.apply {
            translationX = x
            translationY = y
            setMorphSize(width, height, radius)
            alpha = surfaceAlpha
        }
        initialPopupView.alpha = ((progress - MORPH_SOURCE_FADE_END) / 0.65f).coerceIn(0f, 1f)
        snapshotView.apply {
            translationX = x
            translationY = y
            right = left + width
            bottom = top + sourceBounds.height().roundToInt()
            setRoundedOutline(radius)
            alpha = 1f - surfaceAlpha
        }
        displayProgressListener?.invoke(progress)
    }

    private fun animateMorph(target: Float) {
        morphAnimator?.removeAllListeners()
        morphAnimator?.cancel()
        val start = morphProgress
        val startBackdrop = backdropProgress
        val backdropInterpolator = AccelerateDecelerateInterpolator()
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration =
                if (target ==
                    1f
                ) {
                    AnimationConstants.MENU_PRESENT
                } else {
                    AnimationConstants.MENU_DISMISS
                }
            interpolator = LinearInterpolator()
            addUpdateListener {
                val fraction = it.animatedFraction
                updateMorph(
                    lerp(start, target, WInterpolator.emphasized.getInterpolation(fraction))
                )
                updateBackdropProgress(
                    lerp(startBackdrop, target, backdropInterpolator.getInterpolation(fraction))
                )
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    morphAnimator = null
                    updateMorph(target)
                    updateBackdropProgress(target)
                    if (target == 0f) {
                        removeFromParent()
                    } else {
                        contentContainerLayout.interceptChildTouches = false
                        initialPopupView.prepareExpandingSubmenus()
                        finishPresentation()
                    }
                }
            })
        }
        morphAnimator = animator
        updateMorph(start)
        if (WGlobalStorage.getAreAnimationsActive()) animator.start() else animator.end()
    }

    private fun dismissMorph() {
        if (isMorphDismissing) return
        isMorphDismissing = true
        initialPopupView.notifyWillDismiss()
        contentContainerLayout.interceptChildTouches = true
        if (sourceAlpha == null || morphSource?.isAttachedToWindow != true) {
            removeFromParent()
            return
        }
        initialPopupView.resetExpandingPresentationScroll()
        animateMorph(0f)
    }

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

    fun beginDragSelection(startY: Float) {
        dragSelectionStartY = startY
    }

    fun updateDragSelection(x: Float, y: Float) {
        val startY = dragSelectionStartY ?: y.also { dragSelectionStartY = it }
        hasLastDragPoint = true
        lastDragX = x
        lastDragY = y
        if (!canDragSelect) return
        val isActivated = dragSelectionView != null
        if (!isActivated && abs(y - startY) <= DRAG_SELECTION_ACTIVATION_DISTANCE) return
        val popupView = popupViews.last()
        dragSelectionView?.takeIf { it !== popupView }?.endDragSelection(performAction = false)
        dragSelectionView = popupView
        popupView.updateDragSelection(x, y)
    }

    fun endDragSelection(performAction: Boolean) {
        if (performAction && !isPresented) {
            hasPendingDragRelease = true
            return
        }
        hasPendingDragRelease = false
        hasLastDragPoint = false
        dragSelectionStartY = null
        val popupView = dragSelectionView ?: return
        dragSelectionView = null
        val isCurrentPage = popupView === popupViews.last()
        popupView.endDragSelection(performAction && canDragSelect && isCurrentPage)
    }

    // Applies a drag made while the menu was opening
    private fun finishPresentation() {
        isPresented = true
        if (isDismissed || isMorphDismissing) return
        if (hasLastDragPoint) updateDragSelection(lastDragX, lastDragY)
        if (hasPendingDragRelease) endDragSelection(performAction = true)
    }

    fun setOnDismissListener(listener: (() -> Unit)?) {
        onDismissListener = listener
    }

    fun setDisplayProgressListener(listener: ((progress: Float) -> Unit)?) {
        displayProgressListener = listener
    }

    private var pillShadow: WGlassView? = null

    private fun attachPillShadowIfNeeded() {
        if (!usePillShadow || pillShadow != null) return
        pillShadow = WGlassView.attachTo(
            contentContainerLayout,
            roundRadius,
            GlassProviders.shadowOnly(),
            root = null
        )
    }

    fun showAtLocation(x: Int, y: Int, initialHeight: Int = 0, fromTop: Boolean = true) {
        val popupHost = this.popupHost ?: run {
            removeFromParent()
            return
        }
        ensureBlurBackdropAttached(popupHost)
        contentContainerLayout.apply {
            setRequestedPosition(
                x.toFloat() - popupHost.paddingLeft,
                y.toFloat() - popupHost.paddingTop
            )
            elevation = if (usePillShadow) {
                0f
            } else {
                WMenuPopup.surfaceElevation(
                    isOverDim = !shouldUseTransparentBackdrop &&
                        windowBackgroundStyle !is WMenuPopup.BackgroundStyle.Transparent
                )
            }
        }
        popupHost.addView(rootContainerLayout)
        attachPillShadowIfNeeded()
        if (shouldUseBlurBackdrop) {
            configureBlurBackdrop()
            blurBackdropContainer.alpha = 0f
        }
        updateBackdropProgress(0f)
        morphSource?.let { source ->
            presentMorph(source, popupHost)
            PopupHelpers.popupShown(this)
            return
        }
        val interpolator = LinearInterpolator()
        initialPopupView.present(
            initialHeight,
            fromTop,
            updateListener = { animationFraction ->
                val interpolated = interpolator.getInterpolation(animationFraction)
                updateBackdropProgress(interpolated)
                displayProgressListener?.invoke(animationFraction)
            },
            onPresented = ::finishPresentation
        )
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
            if (isSurfaceBlurred) {
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
            WGlassView.attachTo(
                foregroundSurface,
                roundRadius,
                GlassProviders.shadowOnly(),
                root = null
            )
        } else {
            null
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

        fun update(progress: Float) {
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
        }

        fun finish() {
            update(1f)
            foregroundSurface.layoutParams.height = targetHeight
            nextPopupView.finishExpandingAppearanceAnimation()
            itemTransitionAnimator = null
            isItemTransitioning = false
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

        fun update(progress: Float) {
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
            onCompletion?.invoke()
        }

        if (animated && WGlobalStorage.getAreAnimationsActive()) {
            isItemTransitioning = true
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
        if (morphSource != null) {
            dismissMorph()
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
            }
            PopupHelpers.popupDismissed(this@WNavigationPopup)
        }
    }

    private fun removeFromParent() {
        if (isDismissed) {
            return
        }
        isDismissed = true
        morphAnimator?.removeAllListeners()
        morphAnimator?.cancel()
        morphAnimator = null
        geometryListener?.let { listener ->
            geometryObserver?.takeIf { it.isAlive }?.removeOnGlobalLayoutListener(listener)
        }
        geometryListener = null
        geometryObserver = null
        morphSource?.removeOnAttachStateChangeListener(sourceAttachListener)
        sourceAlpha?.let { morphSource?.alpha = it }
        sourceAlpha = null
        sourceSnapshot?.let { snapshot ->
            sourceSnapshot = null
            snapshot.recycle()
        }
        PopupHelpers.popupDismissed(this@WNavigationPopup)

        (rootContainerLayout.parent as? ViewGroup)?.removeView(rootContainerLayout)
        if (isBlurBackdropAttached) {
            (blurBackdropContainer.parent as? ViewGroup)?.removeView(blurBackdropContainer)
            isBlurBackdropAttached = false
        }
        onDismissListener?.invoke()
    }
}
