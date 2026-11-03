package org.mytonwallet.app_air.uiinappbrowser

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.ComposeShader
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Shader.TileMode.CLAMP
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.MotionEvent
import android.view.PixelCopy
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import android.view.animation.DecelerateInterpolator
import android.widget.Button
import android.widget.ImageView
import android.widget.OverScroller
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.animation.doOnEnd
import androidx.core.graphics.ColorUtils
import androidx.core.graphics.createBitmap
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat.AccessibilityActionCompat
import androidx.customview.widget.ExploreByTouchHelper
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import me.everything.android.ui.overscroll.OverScrollCalculationHelper
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uiinappbrowser.views.TitleSnapshot
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class MinimizedBrowserTabsVC(context: Context) : WViewController(context) {

    @Suppress("PropertyName")
    override val TAG = "MinimizedBrowserTabs"

    override val coversMinimizedBrowser = true
    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false
    override val isSwipeBackAllowed = false

    private val backgroundView = AppCompatImageView(context).apply {
        id = View.generateViewId()
        scaleType = ImageView.ScaleType.FIT_XY
        alpha = 0f
    }

    private val tabsView = TabsView(context).apply {
        id = View.generateViewId()
    }

    override fun setupViews() {
        super.setupViews()
        view.setBackgroundColor(Color.TRANSPARENT)
        view.addView(backgroundView, MATCH_PARENT, MATCH_PARENT)
        view.addView(tabsView, MATCH_PARENT, MATCH_PARENT)
        view.setConstraints {
            allEdges(backgroundView)
            allEdges(tabsView)
        }
        tabsView.loadTabs()
        view.post { captureBackground { tabsView.animateOpen(true) } }
    }

    override fun onBackPressed(): Boolean {
        tabsView.close()
        return false
    }

    private fun captureBackground(onReady: () -> Unit) {
        val window = window
        val windowView = window?.windowView
        if (window == null || windowView == null || windowView.width <= 0 ||
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O
        ) {
            onReady()
            return
        }
        val bitmap = createBitmap(
            max(1, windowView.width / BLUR_DOWNSCALE),
            max(1, windowView.height / BLUR_DOWNSCALE)
        )
        PixelCopy.request(
            window.window,
            bitmap,
            { result ->
                if (result == PixelCopy.SUCCESS) applyBackground(bitmap) else bitmap.recycle()
                onReady()
            },
            Handler(Looper.getMainLooper())
        )
    }

    private fun applyBackground(bitmap: Bitmap) {
        backgroundView.setImageBitmap(bitmap)
        backgroundView.colorFilter = ColorMatrixColorFilter(
            ColorMatrix().apply { setSaturation(if (ThemeManager.isDark) 1.08f else 1.25f) }
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            backgroundView.setRenderEffect(
                RenderEffect.createBlurEffect(14f.dp, 14f.dp, Shader.TileMode.CLAMP)
            )
        }
    }

    private fun finish(then: (() -> Unit)? = null) {
        if (isDestroyed) return
        val window = window ?: return
        window.dismissNav(navigationController, animated = false)
        then?.invoke()
    }

    private inner class TabPreview(val browser: InAppBrowserVC) {
        val title: String = browser.tabTitle
        val preview: Bitmap? = browser.tabPreview
        val icon: Bitmap? = browser.tabIcon
        val barColor: Int = browser.tabBarColor
        val barHeight: Float = browser.tabBarHeight.toFloat()
        val header: Bitmap? = browser.tabHeader
        val headerActions: Bitmap? = browser.tabHeaderActions
        val titleSnapshot: TitleSnapshot? = browser.tabTitleSnapshot
        val previewShader = preview?.let { BitmapShader(it, CLAMP, CLAMP) }
        val headerShader = header?.let { BitmapShader(it, CLAMP, CLAMP) }
        val headerActionsShader = headerActions?.let { BitmapShader(it, CLAMP, CLAMP) }
        val aspectRatio: Float? = preview?.let {
            val headerHeight = header?.let { h -> h.height * it.width / h.width.toFloat() }
                ?: barHeight
            it.width / (headerHeight + it.height)
        }
        var titleShader: Shader? = null
        var titleShaderVisible = -1f
        val barIsDark: Boolean = browser.tabBarIsDark
            ?: (ColorUtils.calculateLuminance(barColor) < .5)
        val clickBounds = RectF()
        var dismissedBounds: RectF? = null
        val matrix = Matrix()
        val inverse = Matrix()
        val src = FloatArray(8)
        val dst = FloatArray(8)

        var position = 0f
        var targetPosition = 0f
        var removed = false
        var dismissProgress = 0f
        var pressProgress = 0f
        private var pressAnimator: ValueAnimator? = null
        var pressed = false
            set(value) {
                if (field == value) return
                field = value
                pressAnimator?.cancel()
                pressAnimator = ValueAnimator.ofFloat(pressProgress, if (value) 1f else 0f).apply {
                    duration = 120
                    interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                    addUpdateListener {
                        pressProgress = it.animatedValue as Float
                        tabsView.invalidate()
                    }
                    start()
                }
            }
        var visible = false
        private var dismissAnimator: ValueAnimator? = null

        fun cancelDismissAnimator() {
            dismissAnimator?.cancel()
            dismissAnimator = null
        }

        fun animateDismiss(to: Float, velocity: Float = 0f, onEnd: (() -> Unit)? = null) {
            cancelDismissAnimator()
            val remaining = abs(to - dismissProgress) * tabsView.width
            val speed = abs(velocity)
            dismissAnimator = ValueAnimator.ofFloat(dismissProgress, to).apply {
                if (speed > 0f && remaining > 0f) {
                    // Starts at the release speed.
                    val seconds = (2f * remaining / speed).coerceIn(.12f, .32f)
                    val slope = (speed * seconds / remaining).coerceAtMost(2f)
                    duration = (seconds * 1000).toLong()
                    interpolator = TimeInterpolator { t -> slope * t + (1f - slope) * t * t }
                } else {
                    duration = if (abs(to) < .1f) 285 else 320
                    interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                }
                addUpdateListener {
                    dismissProgress = it.animatedValue as Float
                    tabsView.invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        dismissProgress = to
                        onEnd?.invoke()
                        tabsView.invalidate()
                    }
                })
                start()
            }
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class TabsView(context: Context) : View(context) {
        private val tabs = ArrayList<TabPreview>()
        private var count = 0f

        private var openProgress = 0f
        private var isOpen = false
        private var openAnimator: ValueAnimator? = null

        private var openingTab: TabPreview? = null
        private var openingProgress = 0f
        private var openingTabScroll = 0f
        private val openingFrame = RectF()
        private var openingRadius = 0f
        private var openingTopInset = 0f
        private var isOpeningCentered = false

        private val scroller = OverScroller(context)
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private val maximumVelocity = ViewConfiguration.get(context).scaledMaximumFlingVelocity
        private val minimumVelocity = ViewConfiguration.get(context).scaledMinimumFlingVelocity
        private var velocityTracker: VelocityTracker? = null
        private var offset = 0f
        private var scrollAnimator: ValueAnimator? = null
        private var endOverscroll = 0f
        private var endOverscrollAnimator: ValueAnimator? = null
        private var layoutAnimator: ValueAnimator? = null

        private val rect = RectF()
        private val rect2 = RectF()
        private val tabBounds = RectF()
        private val cardInset = RectF()
        private var cardRadius = 0f
        private var clipScaleY = 1f
        private var clipPivotY = 0f
        private val partPath = Path()
        private val partRect = RectF()
        private val partRadii = FloatArray(8)
        private val shaderMatrix = Matrix()
        private val closePath = Path().apply {
            moveTo(0f, 0f)
            lineTo(12f.dp, 12f.dp)
            moveTo(12f.dp, 0f)
            lineTo(0f, 12f.dp)
        }

        private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val cardShadow by lazy {
            CardShadow(CARD_RADIUS.dp, CARD_RADIUS.dp, 30f.dp, bakeScale = .5f)
        }
        private val headerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val headerShadow by lazy {
            CardShadow(CARD_RADIUS.dp, 0f, HEADER_SHADOW_BLUR.dp, bakeScale = 1f)
        }
        private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val shaderPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            strokeCap = Paint.Cap.ROUND
            strokeWidth = 2f.dp
        }
        private val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 17f.dp
            typeface = WFont.Medium.typeface
        }
        private val gradientPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val gradient = RadialGradient(
            0f,
            0f,
            255f,
            intArrayOf(0x00000000, 0x30000000),
            floatArrayOf(.5f, 1f),
            Shader.TileMode.CLAMP
        )
        private val gradientMatrix = Matrix()

        private val closeAllText = LocaleController.getString("Close All")
        private val closeAllPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 14f.dp
            typeface = WFont.Medium.typeface
            color = Color.WHITE
        }
        private val closeAllBackgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val closeAllBounds = RectF()
        private var closeAllPressed = false

        private val barTitleSize = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP,
            22f,
            context.resources.displayMetrics
        )

        private val statusBarHeight get() = window?.systemBars?.top ?: 0
        private val paddingTopPx get() = statusBarHeight + (40 + 55).dp.toFloat()
        private val navigationBarHeight get() = window?.systemBars?.bottom ?: 0
        private val paddingBottomPx get() = navigationBarHeight + 68f.dp

        fun loadTabs() {
            tabs.clear()
            val navigations = window?.minimizedBrowser?.navigations.orEmpty()
            navigations.asReversed().forEach { nav ->
                (nav.viewControllers.firstOrNull() as? InAppBrowserVC)?.let {
                    tabs.add(TabPreview(it))
                }
            }
            updateTargetPositions(animated = false)
            offset = scrollMax()
        }

        private fun aliveTabs() = tabs.filter { !it.removed }

        private fun updateTargetPositions(animated: Boolean) {
            val alive = aliveTabs()
            alive.forEachIndexed { i, tab -> tab.targetPosition = (alive.size - 1 - i).toFloat() }
            val targetCount = alive.size.toFloat()
            layoutAnimator?.cancel()
            if (!animated) {
                alive.forEach { it.position = it.targetPosition }
                count = targetCount
                invalidate()
                return
            }
            val fromPositions = alive.map { it.position }
            val fromCount = count
            layoutAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 320
                interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                addUpdateListener {
                    val f = it.animatedValue as Float
                    alive.forEachIndexed { i, tab ->
                        tab.position = lerp(fromPositions[i], tab.targetPosition, f)
                    }
                    count = lerp(fromCount, targetCount, f)
                    invalidate()
                }
                start()
            }
        }

        private val scrollStep get() = 200f.dp * min(1f, 3f * cardSpacing(scrollWindow()))
        private fun scrollWindow() = scrollWindow(count)
        private fun scrollWindow(count: Float): Float {
            val travel = cardTravel(count)
            val maxWindow = max(3f, 1f + travel * FRONT_SCROLL / MIN_CARD_GAP.dp)
            return min(count, maxWindow)
        }

        // Front card stays put; the rest tighten.
        private fun cardSpacing(window: Float) = when {
            window <= 0f -> 0f
            window <= 3f -> 1f / window
            else -> FRONT_SCROLL / (window - 1f)
        }

        private fun frontTop(count: Float) = paddingTopPx + 6f.dp * min(5f, max(0f, count - 1))

        // Fits the front card's tilted bottom (and its corners) above the bottom padding.
        private fun cardHeight(viewHeight: Float, frontScroll: Float, count: Float) = min(
            viewHeight * .75f,
            (1f - frontScroll) * (viewHeight - paddingBottomPx - frontTop(count)) /
                (CARD_TILTED_HEIGHT - .26f * frontScroll)
        )

        private fun cardTravel(count: Float): Float {
            val viewHeight = (if (height > 0) height else resources.displayMetrics.heightPixels)
                .toFloat()
            val bottom = viewHeight - paddingBottomPx -
                cardHeight(viewHeight, FRONT_SCROLL, count) * .26f
            return bottom - paddingTopPx
        }
        private fun scrollMin(count: Float = this.count) =
            -scrollWindow(count) / 3f * count.coerceIn(0f, 1f)
        private fun scrollMax(count: Float = this.count) =
            max(scrollMin(count), count - scrollWindow(count))

        fun animateOpen(open: Boolean, onEnd: (() -> Unit)? = null) {
            isOpen = open
            openAnimator?.cancel()
            openAnimator = ValueAnimator.ofFloat(openProgress, if (open) 1f else 0f).apply {
                duration = 320
                interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                addUpdateListener {
                    openProgress = it.animatedValue as Float
                    if (openingTab == null) backgroundView.alpha = openProgress
                    invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        if (open) accessibility.invalidateRoot()
                        onEnd?.invoke()
                    }
                })
                start()
            }
        }

        fun close() {
            if (!isOpen || openingTab != null) return
            animateOpen(false) { finish() }
        }

        private fun openTab(tab: TabPreview) {
            if (openingTab != null) return
            val nav = tab.browser.navigationController ?: return
            val window = this@MinimizedBrowserTabsVC.window ?: return
            openingTab = tab
            openingFrame.set(window.minimizedBrowser.maximizedFrame(nav))
            openingRadius = window.minimizedBrowser.windowRadius(nav)
            isOpeningCentered = nav.isCenteredWindow
            if (isOpeningCentered) {
                openingTopInset = 0f
            } else {
                openingTopInset = statusBarHeight.toFloat()
                window.forceStatusBarLight = tab.browser.tabBarIsDark
            }
            openingTabScroll =
                ((count - 1 - tab.position) - max(scrollMin(), offset)) *
                cardSpacing(scrollWindow())
            animateOpen(false)
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 300
                interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                addUpdateListener {
                    openingProgress = it.animatedValue as Float
                    if (isOpeningCentered) backgroundView.alpha = 1f - openingProgress
                    invalidate()
                }
                addListener(object : AnimatorListenerAdapter() {
                    override fun onAnimationEnd(animation: Animator) {
                        val presenter = this@MinimizedBrowserTabsVC.window?.minimizedBrowser
                        finish {
                            presenter?.maximize(animated = false, nav = nav)
                            tab.browser.revealCorners()
                        }
                    }
                })
                start()
            }
        }

        private fun removeTab(tab: TabPreview, dismissTo: Float, velocity: Float = 0f) {
            if (tab.removed) return
            tab.removed = true
            tab.dismissedBounds = RectF(tab.clickBounds)
            tab.browser.navigationController?.let {
                window?.minimizedBrowser?.dismissMinimized(animated = false, nav = it)
            }
            tab.animateDismiss(dismissTo, velocity) {
                tabs.remove(tab)
                invalidate()
                accessibility.invalidateRoot()
            }
            updateTargetPositions(animated = true)
            val finalCount = aliveTabs().size.toFloat()
            scrollTo(offset.coerceIn(scrollMin(finalCount), scrollMax(finalCount)))
            if (aliveTabs().isEmpty()) close()
        }

        private fun closeAll() {
            window?.minimizedBrowser?.dismissAll()
            tabs.forEach { it.removed = true }
            close()
        }

        private fun scrollTo(target: Float) {
            scrollAnimator?.cancel()
            scrollAnimator = ValueAnimator.ofFloat(offset, target).apply {
                duration = 250
                interpolator = CubicBezierInterpolator.EASE_OUT_QUINT
                addUpdateListener {
                    offset = it.animatedValue as Float
                    invalidate()
                }
                doOnEnd { accessibility.invalidateRoot() }
                start()
            }
        }

        private fun bounceBackEndOverscroll() {
            endOverscrollAnimator?.cancel()
            endOverscrollAnimator = ValueAnimator.ofFloat(endOverscroll, 0f).apply {
                duration = (endOverscroll / 10f).toLong().coerceIn(100L, 400L)
                interpolator = DecelerateInterpolator()
                addUpdateListener {
                    endOverscroll = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }

        override fun computeScroll() {
            if (scroller.computeScrollOffset()) {
                offset = scroller.currY / scrollStep
                postInvalidateOnAnimation()
            }
        }

        private fun pillBounds(out: RectF, depth: Float) {
            if (window?.minimizedBrowser?.frontBounds(out) != true) {
                val bottom = height - navigationBarHeight
                out.set(10f.dp, bottom - 60f.dp, width - 10f.dp, bottom - 12f.dp)
            }
            val d = depth.coerceIn(0f, 1f)
            out.offset(0f, -d * 8f.dp)
            val s = 1f - .05f * d
            val cx = out.centerX()
            val cy = out.centerY()
            val halfWidth = out.width() * s / 2f
            val halfHeight = out.height() * s / 2f
            out.set(cx - halfWidth, cy - halfHeight, cx + halfWidth, cy + halfHeight)
        }

        private fun lerpRect(from: RectF, to: RectF, t: Float, out: RectF) {
            out.set(
                lerp(from.left, to.left, t),
                lerp(from.top, to.top, t),
                lerp(from.right, to.right, t),
                lerp(from.bottom, to.bottom, t)
            )
        }

        override fun onDraw(canvas: Canvas) {
            if (openProgress <= 0f && openingProgress <= 0f) return
            if (isOpeningCentered) {
                canvas.drawColor(
                    ColorUtils.setAlphaComponent(Color.BLACK, (DIM_ALPHA * openingProgress).toInt())
                )
            }
            val thisWidth = width.toFloat()
            val thisHeight = height.toFloat()

            val paddingTop = paddingTopPx
            val cx = thisWidth / 2f
            val window = scrollWindow()
            val spacing = cardSpacing(window)
            val frontScroll = (count - 1 - scrollMax()) * spacing
            val cardHeight = cardHeight(thisHeight, frontScroll, count)
            val overscroll = if (window <= 0f) {
                0f
            } else {
                ((scrollMin() - offset) / (window * .15f) * .2f).coerceIn(0f, 1f)
            }
            val open = lerp(0f, 1f - overscroll, openProgress)
            val maxCardWidth = thisWidth * .95f
            fun cardAspectRatio(tab: TabPreview) = tab.aspectRatio ?: (thisWidth / thisHeight)
            // Width-capped cards are shorter, so the stack tightens to keep them overlapping.
            val stackScale = tabs.minOfOrNull {
                val scale = min(1f, maxCardWidth / (cardHeight * cardAspectRatio(it)))
                if (it.removed) lerp(scale, 1f, abs(it.dismissProgress)) else scale
            } ?: 1f
            val stackCenter = (paddingTop + thisHeight - paddingBottomPx) / 2f

            val opening = openingTab
            // Keep stack order: front cards slide away, the tapped card grows in place.
            for (tab in tabs) {
                val isOpening = tab === opening
                val isInFront = opening != null && !isOpening && tab.position < opening.position
                val tabOpen = if (isOpening || isInFront) 1f else open
                val openingT = if (isOpening) openingProgress else 0f
                val position = count - 1 - tab.position
                val scroll = if (isOpening) {
                    openingTabScroll
                } else {
                    (position - max(scrollMin(), offset)) * spacing
                }
                val top = paddingTop + 6f.dp * min(5f, position)
                val bottom = thisHeight - paddingBottomPx - cardHeight * .26f
                val y = stackCenter +
                    (top + (bottom - top) * scroll - endOverscroll - stackCenter) * stackScale
                val aspectRatio = cardAspectRatio(tab)
                val cardWidth = min(cardHeight * aspectRatio, maxCardWidth)
                rect2.set(cx - cardWidth / 2f, y, cx + cardWidth / 2f, y + cardWidth / aspectRatio)

                if (isOpening) {
                    rect.set(openingFrame)
                    lerpRect(rect2, rect, openingT, rect2)
                } else if (isInFront) {
                    rect2.offset(0f, openingProgress * (thisHeight - rect2.top))
                } else {
                    pillBounds(rect, tab.position)
                    lerpRect(rect, rect2, open, rect2)
                }
                tab.dismissedBounds?.let { rect2.set(it) }
                tab.visible = isOpening || (rect2.top <= thisHeight && rect2.bottom >= 0)
                if (!tab.visible) continue

                tab.clickBounds.set(rect2)
                canvas.save()
                val perspective = tabOpen * (1f - openingT)
                tab.src[0] = rect2.left
                tab.src[1] = rect2.top
                tab.src[2] = rect2.right
                tab.src[3] = rect2.top
                tab.src[4] = rect2.right
                tab.src[5] = rect2.bottom
                tab.src[6] = rect2.left
                tab.src[7] = rect2.bottom
                tab.dst[0] = rect2.left
                tab.dst[1] = rect2.top
                tab.dst[2] = rect2.right
                tab.dst[3] = rect2.top
                tab.dst[4] = rect2.centerX() + rect2.width() / 2f * lerp(1f, .83f, perspective)
                tab.dst[5] = rect2.top + rect2.height() * lerp(1f, CARD_TILTED_HEIGHT, perspective)
                tab.dst[6] = rect2.centerX() - rect2.width() / 2f * lerp(1f, .83f, perspective)
                tab.dst[7] = tab.dst[5]
                tab.matrix.setPolyToPoly(tab.src, 0, tab.dst, 0, 4)
                tab.matrix.invert(tab.inverse)
                canvas.concat(tab.matrix)

                // Fade over the real minimized bar beneath.
                val alpha = if (isOpening || isInFront) {
                    1f
                } else {
                    (openProgress / CARD_FADE_RANGE).coerceIn(0f, 1f)
                }
                val contentAlpha = lerp(
                    (position - count + 2).coerceIn(0f, 1f),
                    1f,
                    ((tabOpen - .1f) / .8f).coerceIn(0f, 1f)
                )
                val fill = if (isOpening) 1f else perspective
                drawTab(canvas, tab, rect2, alpha, perspective, fill, openingT, contentAlpha)
                canvas.restore()
            }

            drawCloseAll(canvas, thisWidth, paddingTop)
        }

        private fun drawTab(
            canvas: Canvas,
            tab: TabPreview,
            bounds: RectF,
            alphaIn: Float,
            expandProgress: Float,
            fill: Float,
            openingProgress: Float,
            contentAlpha: Float
        ) {
            val alpha = alphaIn * (1f - ((abs(tab.dismissProgress) - .3f) / .7f)).coerceIn(0f, 1f)
            if (alpha <= 0f) return
            val tabScaleY = lerp(1f, 1.3f, expandProgress * (1f - openingProgress))
            val tabTranslateY = openingProgress * openingTopInset
            canvas.save()
            canvas.translate(tab.dismissProgress * width, 0f)
            if (tab.pressProgress > 0f) {
                val scale = 1f - .02f * tab.pressProgress
                canvas.scale(scale, scale, bounds.centerX(), bounds.centerY())
            }

            val r = lerp(CARD_RADIUS.dp, openingRadius, openingProgress)
            cardShadow.draw(
                canvas,
                bounds.left,
                bounds.top,
                bounds.right,
                bounds.bottom,
                10f.dp,
                0x20 * alpha * expandProgress * (1f - openingProgress)
            )
            rect.set(bounds)
            rect.inset(1f, 1f)
            cardInset.set(rect)
            cardRadius = r
            clipScaleY = 1f
            clipPivotY = 0f

            // Hides the screenshot's transparent corners.
            backgroundPaint.color = tab.barColor
            backgroundPaint.alpha = (255 * alpha * fill).toInt()
            canvas.drawRoundRect(rect, r, r, backgroundPaint)

            val preview = tab.preview
            val previewShader = tab.previewShader
            if (preview != null && previewShader != null) {
                val previewTop =
                    bounds.top + headerHeight(tab, bounds, tabScaleY, openingProgress) +
                        tabTranslateY
                val stretch = lerp(1f, 1.25f, expandProgress * (1f - openingProgress))
                val s = bounds.width() / preview.width
                shaderMatrix.setScale(s, s * stretch)
                shaderMatrix.postTranslate(bounds.left, previewTop)
                previewShader.setLocalMatrix(shaderMatrix)
                drawClipped(
                    canvas,
                    bounds.left,
                    previewTop,
                    bounds.right,
                    previewTop + preview.height * s * stretch,
                    previewShader,
                    (255 * alpha * fill).toInt()
                )
            }

            gradientPaint.alpha = (255 * alpha * expandProgress * (1f - openingProgress)).toInt()
            gradientMatrix.reset()
            val gradientScale = bounds.height() / 255f
            gradientMatrix.postScale(gradientScale, gradientScale)
            gradientMatrix.postTranslate(bounds.centerX(), bounds.top)
            gradient.setLocalMatrix(gradientMatrix)
            gradientPaint.shader = gradient
            canvas.drawRoundRect(rect, r, r, gradientPaint)

            tabBounds.set(bounds)
            tabBounds.bottom = tabBounds.top +
                min(bounds.height(), headerHeight(tab, bounds, 1f, openingProgress))
            tabBounds.offset(0f, tabTranslateY)
            canvas.save()
            canvas.scale(1f, tabScaleY, tabBounds.centerX(), tabBounds.top)
            clipScaleY = tabScaleY
            clipPivotY = tabBounds.top
            drawHeader(
                canvas,
                tab,
                tabBounds,
                tabTranslateY,
                r,
                alpha * alpha,
                contentAlpha,
                max(fill, expandProgress),
                openingProgress
            )
            canvas.restore()
            canvas.restore()
        }

        private fun clipToCard(
            left: Float,
            top: Float,
            right: Float,
            bottom: Float,
            topRadius: Float = 0f,
            bottomRadius: Float = 0f
        ): Boolean {
            val cardTop = clipPivotY + (cardInset.top - clipPivotY) / clipScaleY
            val cardBottom = clipPivotY + (cardInset.bottom - clipPivotY) / clipScaleY
            partRect.set(
                max(left, cardInset.left),
                max(top, cardTop),
                min(right, cardInset.right),
                min(bottom, cardBottom)
            )
            if (partRect.width() <= 0f || partRect.height() <= 0f) return false
            val radiusY = cardRadius / clipScaleY
            val topCut = partRect.top < cardTop + radiusY
            val bottomCut = partRect.bottom > cardBottom - radiusY
            val topX = max(if (topCut) cardRadius else 0f, topRadius)
            val topY = max(if (topCut) radiusY else 0f, topRadius)
            val bottomX = max(if (bottomCut) cardRadius else 0f, bottomRadius)
            val bottomY = max(if (bottomCut) radiusY else 0f, bottomRadius)
            partRadii[0] = topX
            partRadii[1] = topY
            partRadii[2] = topX
            partRadii[3] = topY
            partRadii[4] = bottomX
            partRadii[5] = bottomY
            partRadii[6] = bottomX
            partRadii[7] = bottomY
            partPath.rewind()
            partPath.addRoundRect(partRect, partRadii, Path.Direction.CW)
            return true
        }

        private fun drawClipped(
            canvas: Canvas,
            left: Float,
            top: Float,
            right: Float,
            bottom: Float,
            shader: Shader,
            alpha: Int
        ) {
            if (alpha <= 0 || !clipToCard(left, top, right, bottom)) return
            shaderPaint.shader = shader
            shaderPaint.alpha = alpha
            canvas.drawPath(partPath, shaderPaint)
        }

        private fun headerHeight(
            tab: TabPreview,
            bounds: RectF,
            scaleY: Float,
            openingProgress: Float
        ): Float {
            val header = tab.header
            if (header != null) return header.height * bounds.width() / header.width * scaleY
            return lerp(HEADER_HEIGHT.dp * scaleY, tab.barHeight, openingProgress)
        }

        private fun drawHeader(
            canvas: Canvas,
            tab: TabPreview,
            bounds: RectF,
            extendUp: Float,
            r: Float,
            alpha: Float,
            contentAlpha: Float,
            expandProgress: Float,
            openingProgress: Float
        ) {
            headerPaint.color = if (tab.header != null) {
                tab.barColor
            } else {
                ColorUtils.blendARGB(WColor.Background.color, tab.barColor, expandProgress)
            }
            headerPaint.alpha = (255 * alpha).toInt()
            if (clipToCard(
                    bounds.left,
                    bounds.top - extendUp,
                    bounds.right,
                    bounds.bottom,
                    r,
                    lerp(r, 0f, expandProgress)
                )
            ) {
                canvas.save()
                canvas.clipRect(
                    cardInset.left,
                    clipPivotY + (cardInset.top - clipPivotY) / clipScaleY,
                    cardInset.right,
                    clipPivotY + (cardInset.bottom - clipPivotY) / clipScaleY
                )
                headerShadow.draw(
                    canvas,
                    bounds.left,
                    bounds.top - extendUp,
                    bounds.right,
                    bounds.bottom,
                    1f.dp,
                    0x10 * alpha
                )
                canvas.restore()
                canvas.drawPath(partPath, headerPaint)
            }

            val header = tab.header
            val headerShader = tab.headerShader
            if (header != null && headerShader != null) {
                rect.set(0f, 0f, header.width.toFloat(), header.height.toFloat())
                shaderMatrix.setRectToRect(rect, bounds, Matrix.ScaleToFit.FILL)
                headerShader.setLocalMatrix(shaderMatrix)
                val contentAlphaInt = (255 * alpha * contentAlpha).toInt()
                drawClipped(
                    canvas,
                    bounds.left,
                    bounds.top,
                    bounds.right,
                    bounds.bottom,
                    headerShader,
                    contentAlphaInt
                )
                val actionsShader = tab.headerActionsShader
                if (actionsShader != null && openingProgress > 0f) {
                    actionsShader.setLocalMatrix(shaderMatrix)
                    drawClipped(
                        canvas,
                        bounds.left,
                        bounds.top,
                        bounds.right,
                        bounds.bottom,
                        actionsShader,
                        (contentAlphaInt * openingProgress).toInt()
                    )
                }
                tab.titleSnapshot?.let { title ->
                    drawTitleSnapshot(
                        canvas,
                        tab,
                        title,
                        header,
                        bounds,
                        openingProgress,
                        contentAlphaInt
                    )
                }
                return
            }

            val barTextColor = if (tab.barIsDark) Color.WHITE else Color.BLACK
            val textColor =
                ColorUtils.blendARGB(WColor.PrimaryText.color, barTextColor, expandProgress)
            iconPaint.color = textColor
            iconPaint.alpha = (255 * alpha * contentAlpha).toInt()
            canvas.save()
            canvas.translate(
                bounds.left + lerp(18f.dp, BAR_CLOSE_CENTER.dp.toFloat() - 6f.dp, openingProgress),
                bounds.centerY() - 6f.dp
            )
            canvas.drawPath(closePath, iconPaint)
            canvas.restore()

            var leftPadding = 0f
            tab.icon?.let { icon ->
                val size = 24f.dp
                rect.set(
                    bounds.left + 56f.dp,
                    bounds.centerY() - size / 2f,
                    bounds.left + 56f.dp + size,
                    bounds.centerY() + size / 2f
                )
                bitmapPaint.alpha = (255 * alpha * contentAlpha * (1f - openingProgress)).toInt()
                canvas.drawBitmap(icon, null, rect, bitmapPaint)
                leftPadding = size + 4f.dp
            }

            titlePaint.color = textColor
            titlePaint.alpha = (255 * alpha * contentAlpha).toInt()
            titlePaint.textSize = lerp(17f.dp, barTitleSize, openingProgress)
            val maxWidth = bounds.width() - 100f.dp - leftPadding
            if (maxWidth <= 0f) return
            val title =
                TextUtils.ellipsize(tab.title, titlePaint, maxWidth, TextUtils.TruncateAt.END)
            val baseline = bounds.centerY() - (titlePaint.descent() + titlePaint.ascent()) / 2f
            canvas.drawText(
                title,
                0,
                title.length,
                bounds.left +
                    lerp(60f.dp + leftPadding, BAR_TITLE_START.dp.toFloat(), openingProgress),
                baseline,
                titlePaint
            )
        }

        // Fills the card, narrowing to the bar's title width as it opens.
        private fun drawTitleSnapshot(
            canvas: Canvas,
            tab: TabPreview,
            title: TitleSnapshot,
            header: Bitmap,
            bounds: RectF,
            openingProgress: Float,
            alpha: Int
        ) {
            val scaleX = bounds.width() / header.width
            val scaleY = bounds.height() / header.height
            val bitmap = title.bitmap
            val visible = lerp(title.filledWidth, title.width, openingProgress)
                .coerceAtMost(bitmap.width.toFloat())
            if (visible <= 0f || alpha <= 0) return
            val isRtl = LocaleController.isRTL
            val from = if (isRtl) bitmap.width - visible else 0f
            val to = from + visible
            if (tab.titleShaderVisible != visible) {
                tab.titleShaderVisible = visible
                val bitmapShader = BitmapShader(bitmap, CLAMP, CLAMP)
                tab.titleShader = if (title.textWidth > visible) {
                    val length = min(title.fadeLength, visible / 2f)
                    val fade = LinearGradient(
                        if (isRtl) from + length else to - length,
                        0f,
                        if (isRtl) from else to,
                        0f,
                        Color.BLACK,
                        Color.TRANSPARENT,
                        CLAMP
                    )
                    ComposeShader(bitmapShader, fade, PorterDuff.Mode.DST_IN)
                } else {
                    bitmapShader
                }
            }
            canvas.save()
            val left = if (isRtl) title.left + title.width - bitmap.width else title.left
            canvas.translate(bounds.left + left * scaleX, bounds.top + title.top * scaleY)
            canvas.scale(scaleX, scaleY)
            shaderPaint.shader = tab.titleShader
            shaderPaint.alpha = alpha
            canvas.drawRect(from, 0f, to, bitmap.height.toFloat(), shaderPaint)
            canvas.restore()
        }

        private fun drawCloseAll(canvas: Canvas, thisWidth: Float, paddingTop: Float) {
            if (openProgress <= 0f) return
            val buttonWidth = closeAllPaint.measureText(closeAllText) + 24f.dp
            val centerY = paddingTop - (75 + 20).dp / 2f
            closeAllBounds.set(
                (thisWidth - buttonWidth) / 2f,
                centerY - 14f.dp,
                (thisWidth + buttonWidth) / 2f,
                centerY + 14f.dp
            )
            val dark = ThemeManager.isDark
            val color = when {
                dark && closeAllPressed -> 0x33ffffff
                dark -> 0x20ffffff
                closeAllPressed -> 0x44000000
                else -> 0x2e000000
            }
            closeAllBackgroundPaint.color = multiplyAlpha(color, openProgress)
            canvas.drawRoundRect(closeAllBounds, 64f.dp, 64f.dp, closeAllBackgroundPaint)
            closeAllPaint.alpha = (255 * openProgress).toInt()
            val baseline = centerY - (closeAllPaint.descent() + closeAllPaint.ascent()) / 2f
            canvas.drawText(closeAllText, closeAllBounds.left + 12f.dp, baseline, closeAllPaint)
        }

        private var pressTab: TabPreview? = null
        private var pressTabClose = false
        private var isTapCandidate = false
        private val showPress = Runnable {
            pressTab?.let {
                it.pressed = true
                invalidate()
            }
        }
        private var startX = 0f
        private var startY = 0f
        private var lastY = 0f
        private var startTime = 0L
        private var verticallyScrolling = false
        private var horizontallySwiping = false

        private val touchPoint = FloatArray(2)

        private fun toCard(tab: TabPreview, x: Float, y: Float): FloatArray {
            touchPoint[0] = x
            touchPoint[1] = y
            tab.inverse.mapPoints(touchPoint)
            return touchPoint
        }

        private fun tabAt(x: Float, y: Float): TabPreview? {
            if (openProgress < 1f || openingTab != null) return null
            for (i in tabs.indices.reversed()) {
                val tab = tabs[i]
                if (tab.removed || abs(tab.dismissProgress) >= .4f) continue
                val (cardX, cardY) = toCard(tab, x, y)
                if (tab.clickBounds.contains(cardX, cardY)) return tab
            }
            return null
        }

        private fun isOnClose(tab: TabPreview, x: Float, y: Float): Boolean {
            val bounds = tab.clickBounds
            val (cardX, cardY) = toCard(tab, x, y)
            val fromEdge = if (LocaleController.isRTL) bounds.right - cardX else cardX - bounds.left
            return fromEdge < 50f.dp && cardY - bounds.top < (HEADER_HEIGHT * 1.3f).dp
        }

        private val accessibility = TabsAccessibility().also {
            ViewCompat.setAccessibilityDelegate(this, it)
        }

        override fun dispatchHoverEvent(event: MotionEvent): Boolean =
            accessibility.dispatchHoverEvent(event) || super.dispatchHoverEvent(event)

        override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
            super.onInitializeAccessibilityNodeInfo(info)
            if (offset > scrollMin()) info.addAction(AccessibilityAction.ACTION_SCROLL_BACKWARD)
            if (offset < scrollMax()) info.addAction(AccessibilityAction.ACTION_SCROLL_FORWARD)
        }

        override fun performAccessibilityAction(action: Int, arguments: Bundle?): Boolean {
            when (action) {
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD ->
                    scrollTo(max(scrollMin(), offset - 1f))

                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD ->
                    scrollTo(min(scrollMax(), offset + 1f))

                else -> return super.performAccessibilityAction(action, arguments)
            }
            return true
        }

        private inner class TabsAccessibility : ExploreByTouchHelper(this) {
            private val bounds = RectF()

            override fun getVirtualViewAt(x: Float, y: Float): Int {
                if (openProgress < 1f || openingTab != null) return INVALID_ID
                if (closeAllBounds.contains(x, y)) return CLOSE_ALL_ID
                val tab = tabAt(x, y) ?: return INVALID_ID
                return tabs.indexOf(tab) + 1
            }

            override fun getVisibleVirtualViews(virtualViewIds: MutableList<Int>) {
                if (openProgress < 1f || openingTab != null) return
                virtualViewIds.add(CLOSE_ALL_ID)
                tabs.forEachIndexed { i, tab ->
                    if (!tab.removed && tab.visible) virtualViewIds.add(i + 1)
                }
            }

            override fun onPopulateNodeForVirtualView(id: Int, node: AccessibilityNodeInfoCompat) {
                node.className = Button::class.java.name
                node.addAction(AccessibilityNodeInfoCompat.ACTION_CLICK)
                if (id == CLOSE_ALL_ID) {
                    node.text = closeAllText
                    bounds.set(closeAllBounds)
                } else {
                    val tab = tabs.getOrNull(id - 1)
                    node.text = tab?.title.orEmpty()
                    node.addAction(
                        AccessibilityActionCompat(
                            AccessibilityNodeInfoCompat.ACTION_DISMISS,
                            LocaleController.getString("Close")
                        )
                    )
                    tab?.matrix?.mapRect(bounds, tab.clickBounds) ?: bounds.setEmpty()
                }
                if (bounds.isEmpty) bounds.set(0f, 0f, 1f, 1f)
                node.setBoundsInParent(
                    Rect(
                        bounds.left.toInt(),
                        bounds.top.toInt(),
                        bounds.right.toInt(),
                        bounds.bottom.toInt()
                    )
                )
            }

            override fun onPerformActionForVirtualView(
                id: Int,
                action: Int,
                arguments: Bundle?
            ): Boolean {
                if (id == CLOSE_ALL_ID) {
                    if (action != AccessibilityNodeInfoCompat.ACTION_CLICK) return false
                    closeAll()
                    return true
                }
                val tab = tabs.getOrNull(id - 1)?.takeIf { !it.removed } ?: return false
                when (action) {
                    AccessibilityNodeInfoCompat.ACTION_CLICK -> openTab(tab)

                    AccessibilityNodeInfoCompat.ACTION_DISMISS ->
                        removeTab(tab, if (LocaleController.isRTL) 1f else -1f)

                    else -> return false
                }
                return true
            }
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (openProgress <= 0f || openingTab != null) return true
            val tracker = velocityTracker ?: VelocityTracker.obtain().also { velocityTracker = it }
            tracker.addMovement(event)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startTime = System.currentTimeMillis()
                    startX = event.x
                    startY = event.y
                    lastY = event.y
                    closeAllPressed = closeAllBounds.contains(event.x, event.y)
                    pressTab = if (closeAllPressed) null else tabAt(event.x, event.y)
                    verticallyScrolling = false
                    horizontallySwiping = false
                    pressTabClose = false
                    pressTab?.let { tab ->
                        tab.cancelDismissAnimator()
                        pressTabClose = isOnClose(tab, event.x, event.y)
                        isTapCandidate = !pressTabClose
                        if (isTapCandidate) {
                            postDelayed(showPress, ViewConfiguration.getTapTimeout().toLong())
                        }
                    }
                    if (!scroller.isFinished) scroller.abortAnimation()
                    scrollAnimator?.cancel()
                    invalidate()
                }

                MotionEvent.ACTION_MOVE -> {
                    val tab = pressTab
                    if (tab != null) {
                        if (!horizontallySwiping && !verticallyScrolling) {
                            if (abs(event.x - startX) > touchSlop) {
                                horizontallySwiping = true
                            } else if (abs(event.y - startY) > touchSlop) {
                                verticallyScrolling = true
                            }
                        }
                        if (horizontallySwiping || verticallyScrolling) {
                            removeCallbacks(showPress)
                            tab.pressed = false
                            pressTabClose = false
                            isTapCandidate = false
                        }
                        if (horizontallySwiping) {
                            tab.dismissProgress = (event.x - startX) / width
                        } else if (verticallyScrolling) {
                            var deltaY = event.y - lastY
                            val maxPx = scrollMax() * scrollStep
                            val targetPx = offset * scrollStep - deltaY
                            if (endOverscroll > 0f || targetPx > maxPx) {
                                endOverscrollAnimator?.cancel()
                                val pushed = if (endOverscroll > 0f) -deltaY else targetPx - maxPx
                                val x = OverScrollCalculationHelper.findXFromY(
                                    endOverscroll.toDouble()
                                ) + pushed
                                if (x <= 0) {
                                    endOverscroll = 0f
                                    offset = ((maxPx + x.toFloat()) / scrollStep)
                                        .coerceIn(scrollMin(), scrollMax())
                                } else {
                                    endOverscroll =
                                        OverScrollCalculationHelper.calculateY(x).toFloat()
                                    offset = scrollMax()
                                }
                            } else {
                                if (offset < scrollMin()) {
                                    deltaY *= 1f - .5f * (scrollMin() - offset).coerceIn(0f, 1f)
                                }
                                offset = ((offset * scrollStep - deltaY) / scrollStep)
                                    .coerceIn(
                                        scrollMin() - max(1.4f, scrollWindow() * .47f),
                                        scrollMax()
                                    )
                            }
                        }
                        invalidate()
                    }
                    if (closeAllPressed && !closeAllBounds.contains(event.x, event.y)) {
                        closeAllPressed = false
                        invalidate()
                    }
                    lastY = event.y
                }

                MotionEvent.ACTION_UP -> {
                    val tab = pressTab
                    if (tab != null) {
                        tracker.computeCurrentVelocity(1000, maximumVelocity.toFloat())
                        val velocityX = tracker.xVelocity
                        val isFling = horizontallySwiping &&
                            abs(velocityX) > DISMISS_FLING_VELOCITY.dp &&
                            velocityX * tab.dismissProgress > 0f
                        if (abs(tab.dismissProgress) > .4f || isFling) {
                            removeTab(tab, if (tab.dismissProgress < 0) -1f else 1f, velocityX)
                        } else if (pressTabClose && isOnClose(tab, event.x, event.y)) {
                            removeTab(tab, if (LocaleController.isRTL) 1f else -1f)
                        } else {
                            tab.animateDismiss(0f)
                            if (isTapCandidate) {
                                openTab(tab)
                            } else if (verticallyScrolling) {
                                settleScroll(tracker)
                            }
                        }
                        tab.pressed = false
                    } else if (closeAllPressed) {
                        closeAll()
                    } else if (hypot(event.x - startX, event.y - startY) <= touchSlop &&
                        System.currentTimeMillis() - startTime <=
                        ViewConfiguration.getTapTimeout() * 1.2f
                    ) {
                        close()
                    }
                    resetTouch()
                }

                MotionEvent.ACTION_CANCEL -> {
                    if (endOverscroll > 0f) bounceBackEndOverscroll()
                    pressTab?.let {
                        it.animateDismiss(0f)
                        it.pressed = false
                    }
                    resetTouch()
                }
            }
            return true
        }

        private fun settleScroll(tracker: VelocityTracker) {
            when {
                endOverscroll > 0f -> bounceBackEndOverscroll()

                offset < scrollMin() - scrollWindow() * .15f -> close()

                offset < scrollMin() -> scrollTo(scrollMin())

                else -> {
                    tracker.computeCurrentVelocity(1000, maximumVelocity.toFloat())
                    val velocityY = tracker.yVelocity
                    if (abs(velocityY) > minimumVelocity) {
                        scroller.fling(
                            0,
                            (offset * scrollStep).toInt(),
                            0,
                            -velocityY.toInt(),
                            0,
                            0,
                            (scrollMin() * scrollStep).toInt(),
                            (scrollMax() * scrollStep).toInt(),
                            0,
                            (.1f * scrollStep).toInt()
                        )
                        postInvalidateOnAnimation()
                    }
                }
            }
        }

        private fun resetTouch() {
            removeCallbacks(showPress)
            pressTab = null
            pressTabClose = false
            isTapCandidate = false
            closeAllPressed = false
            velocityTracker?.recycle()
            velocityTracker = null
            invalidate()
        }
    }
}

private fun lerp(a: Float, b: Float, t: Float) = a + (b - a) * t

private fun multiplyAlpha(color: Int, multiplier: Float): Int {
    val alpha = (Color.alpha(color) * multiplier.coerceIn(0f, 1f)).toInt()
    return (color and 0x00FFFFFF) or (alpha shl 24)
}

private const val HEADER_HEIGHT = 50

private const val CARD_FADE_RANGE = .35f
private const val CARD_TILTED_HEIGHT = .6f
private const val FRONT_SCROLL = 2f / 3f
private const val MIN_CARD_GAP = 64
private const val DISMISS_FLING_VELOCITY = 500
private const val DIM_ALPHA = 76
private const val CLOSE_ALL_ID = 0

// InAppBrowserTopBarView layout.
private const val BAR_CLOSE_CENTER = 36
private const val BAR_TITLE_START = 64
private const val BLUR_DOWNSCALE = 8

private class CardShadow(
    topRadius: Float,
    bottomRadius: Float,
    blurRadius: Float,
    bakeScale: Float
) {
    private val extent = ceil(3f * (blurRadius * 0.57735f + 0.5f))
    private val slice = 2f * extent + max(topRadius, bottomRadius)
    private val bitmap: Bitmap
    private val verts = FloatArray(32)
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)

    init {
        val size = 3f * slice
        val pixels = ceil(size * bakeScale).toInt()
        bitmap = createBitmap(pixels, pixels)
        val canvas = Canvas(bitmap)
        canvas.scale(pixels / size, pixels / size)
        // An opaque shadow color would take the paint's zero alpha.
        val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0
            setShadowLayer(blurRadius, 0f, 0f, 0xFE000000.toInt())
        }
        val radii = floatArrayOf(
            topRadius,
            topRadius,
            topRadius,
            topRadius,
            bottomRadius,
            bottomRadius,
            bottomRadius,
            bottomRadius
        )
        val shape = Path().apply {
            addRoundRect(
                RectF(extent, extent, size - extent, size - extent),
                radii,
                Path.Direction.CW
            )
        }
        canvas.drawPath(shape, shadowPaint)
    }

    fun draw(
        canvas: Canvas,
        shapeLeft: Float,
        shapeTop: Float,
        shapeRight: Float,
        shapeBottom: Float,
        dy: Float,
        alpha: Float
    ) {
        val alphaInt = alpha.toInt()
        if (alphaInt <= 0) return
        val left = shapeLeft - extent
        val top = shapeTop + dy - extent
        val right = shapeRight + extent
        val bottom = shapeBottom + dy + extent
        val sliceX = min(slice, (right - left) / 2f)
        val sliceY = min(slice, (bottom - top) / 2f)
        for (row in 0..3) {
            val y = when (row) {
                0 -> top
                1 -> top + sliceY
                2 -> bottom - sliceY
                else -> bottom
            }
            for (column in 0..3) {
                val i = (row * 4 + column) * 2
                verts[i] = when (column) {
                    0 -> left
                    1 -> left + sliceX
                    2 -> right - sliceX
                    else -> right
                }
                verts[i + 1] = y
            }
        }
        paint.alpha = alphaInt
        canvas.drawBitmapMesh(bitmap, 3, 3, verts, 0, null, 0, paint)
    }
}

private const val CARD_RADIUS = 18f
private const val HEADER_SHADOW_BLUR = 2.33f
