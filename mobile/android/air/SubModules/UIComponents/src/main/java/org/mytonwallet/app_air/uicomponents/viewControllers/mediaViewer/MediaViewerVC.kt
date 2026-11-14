package org.mytonwallet.app_air.uicomponents.viewControllers.mediaViewer

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.AnimatorSet
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Rect
import android.graphics.RectF
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.doOnLayout
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import androidx.core.view.updateLayoutParams
import com.facebook.drawee.drawable.ScalingUtils
import com.facebook.drawee.generic.RoundingParams
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.CubicBezierInterpolator
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.image.WZoomableImageView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setOnMenuClickListener
import org.mytonwallet.app_air.uicomponents.widgets.zoomable.DefaultZoomableController
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

// Telegram's side zones: an eighth of the viewer's width on each side, up to 135 px
private const val EDGE_TAP_MAX_PX = 135
private const val EDGE_TAP_WIDTH_DIVISOR = 8f

/** How wide each side's tap zone is in a viewer [width] px wide */
internal fun mediaViewerEdgeTapSide(width: Float): Float =
    min(EDGE_TAP_MAX_PX.toFloat(), width / EDGE_TAP_WIDTH_DIVISOR)

/**
 * Whether a tap at [x] lies in a side zone of a viewer [width] px wide. As in Telegram, a tap there pages, or shows or
 * hides the bars, as soon as the finger lifts and never makes half of a double tap: only outside them does a double
 * tap zoom.
 */
internal fun isMediaViewerEdgeTap(x: Float, width: Float): Boolean {
    val side = mediaViewerEdgeTapSide(width)
    return x < side || x > width - side
}

/** [caption] takes the text size in px. Without [menuItems] there is no ⋮ button. */
class MediaViewerItem(
    val url: String,
    val date: (() -> String?)? = null,
    val caption: ((textSize: Float) -> CharSequence)? = null,
    val accessibilityLabel: String? = null,
    val menuItems: ((host: View) -> List<WMenuPopup.Item>)? = null
)

/** Telegram-style photo viewer: flies from the list, pages, zooms and swipes away, with chrome a tap toggles. */
@SuppressLint("ViewConstructor")
class MediaViewerVC(
    context: Context,
    private val items: List<MediaViewerItem>,
    startIndex: Int,
    private val findSource: (index: Int) -> Source?
) : WViewController(context) {
    /** [visibleRows]: window rows where the list is uncovered; elsewhere the picture flies under the bars. */
    class Source(
        val image: View,
        val topCornerRadius: Float,
        val aspectRatio: Float?,
        val visibleRows: IntRange,
        val bottomCornerRadius: Float = 0f
    )

    private class Place(val frame: RectF, val visibleTop: Float, val visibleBottom: Float)

    @Suppress("PropertyName")
    override val TAG = "MediaViewerVC"

    override val shouldDisplayTopBar = false
    override val shouldDisplayBottomBar = false

    private val urls = items.map { it.url }
    private var index = startIndex.coerceIn(0, urls.lastIndex)
    private val background = View(context).apply {
        setBackgroundColor(Color.BLACK)
        alpha = 0f
    }

    // Before, at and after the index; they swap as the viewer pages
    private val pages = Array(PAGE_COUNT) { makePage() }
    private val flyer = WCustomImageView(context).apply {
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
        isVisible = false
    }
    private val flyerFrame = RectF()
    private val flyerClip = Rect()
    private val layout = ViewerLayout(context)
    private var pageOffset = 0f
    private var dragOffset = 0f
    private var motion: ValueAnimator? = null
    private var hiddenSource: View? = null
    private var isClosing = false

    private val pressedEdges = MediaViewerPressedEdges(context)
    private val actionBar = MediaViewerActionBar(context).apply {
        backButton.setOnClickListener { close() }
        menuButton.setOnMenuClickListener { showMenu() }
    }
    private val caption = MediaViewerCaptionView(context)

    private val navigationScrim = View(context).apply { setBackgroundColor(CHROME_SCRIM_COLOR) }
    private val chrome = FrameLayout(context)
    private var isChromeShown = true
    private var chromeAnimator: AnimatorSet? = null
    private var restoresStatusBar = false
    private var ownsSystemBars = false
    private val turnActionIds = HashMap<View, List<Int>>()

    override fun setupViews() {
        super.setupViews()
        layout.addView(background, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        pages.forEach { layout.addView(it, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)) }
        layout.addView(pressedEdges, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        layout.addView(flyer, FrameLayout.LayoutParams(0, 0))
        chrome.addView(caption, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        chrome.addView(
            navigationScrim,
            FrameLayout.LayoutParams(MATCH_PARENT, 0, Gravity.BOTTOM)
        )
        chrome.addView(actionBar, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        chrome.alpha = 0f
        layout.addView(chrome, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        view.addView(layout, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        bindPages()
        bindChrome(direction = 0)
        insetsUpdated()
        setUpAccessibility()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        takeSystemBars()
    }

    // A sheet over the viewer leaves without another viewWillAppear
    override fun viewDidEnterForeground() {
        super.viewDidEnterForeground()
        takeSystemBars()
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        releaseSystemBars()
    }

    // The window can dismiss the viewer without close()
    override fun onDestroy() {
        motion?.cancel()
        chromeAnimator?.cancel()
        restoreSource()
        releaseSystemBars()
        super.onDestroy()
    }

    private fun takeSystemBars() {
        if (isClosing || isDestroyed) return
        ownsSystemBars = true
        window?.forceStatusBarLight = true
        window?.forceBottomBarLight = true
        setStatusBarHidden(!isChromeShown)
    }

    private fun releaseSystemBars() {
        setStatusBarHidden(false)
        if (!ownsSystemBars) return
        ownsSystemBars = false
        window?.forceStatusBarLight = null
        window?.forceBottomBarLight = null
    }

    private fun setUpAccessibility() {
        actionBar.backButton.contentDescription = LocaleController.getString("Close")
        actionBar.menuButton.contentDescription = LocaleController.getString("More actions")
        listOf<View>(background, pressedEdges, flyer, navigationScrim).forEach {
            it.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        }
        updatePageAccessibility()
    }

    private fun updatePageAccessibility() {
        pages.forEach { page ->
            turnActionIds.remove(page)?.forEach { ViewCompat.removeAccessibilityAction(page, it) }
            if (page === centerPage) {
                page.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
                page.isFocusable = true
                page.contentDescription =
                    mediaViewerDescription(
                        index + 1,
                        items.size,
                        items[index].accessibilityLabel
                    )
                val turns = MediaViewerTurn.available(index, items.size)
                turnActionIds[page] = turns.map { turn ->
                    val title = LocaleController.getString(turn.titleKey)
                    ViewCompat.addAccessibilityAction(page, title) { _, _ ->
                        if (hasPage(turn.step) && !isClosing) switchTo(turn.step)
                        true
                    }
                }
            } else {
                page.importantForAccessibility = HIDDEN_FOR_ACCESSIBILITY
                page.contentDescription = null
            }
        }
    }

    private fun focusPictureForAccessibility() {
        if (!isAccessibilityEnabled()) return
        val page = centerPage
        page.post { page.performAccessibilityAction(ACCESSIBILITY_FOCUS, null) }
    }

    private fun isAccessibilityEnabled(): Boolean {
        val service = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
        return (service as? AccessibilityManager)?.isEnabled == true
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bars = navigationController?.getSystemBars() ?: return
        val isRtl = LocaleController.isRTL
        val start = if (isRtl) bars.right else bars.left
        val end = if (isRtl) bars.left else bars.right
        actionBar.setInsets(bars.top, start, end)
        chrome.setPadding(bars.left, 0, bars.right, 0)
        val barBottom = bars.top + actionBar.contentHeight
        caption.updateLayoutParams<FrameLayout.LayoutParams> {
            topMargin = barBottom
            bottomMargin = bars.bottom
        }
        navigationScrim.updateLayoutParams { height = bars.bottom }
    }

    fun open() {
        layout.doOnLayout { animateOpening() }
    }

    override fun onBackPressed(): Boolean {
        close()
        return false
    }

    // Telegram's photo viewer: zooms up to 3x, and a pinch past either limit goes on, slowed, until it springs back
    private fun makePage() = WZoomableImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(0f)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Transparent)
        (zoomableController as DefaultZoomableController).apply {
            maxScaleFactor = MAX_ZOOM
            isOverzoomEnabled = true
        }
    }

    private val centerPage get() = pages[1]

    // Only a page given another picture reloads
    private fun bindPages() {
        pages.forEachIndexed { slot, page ->
            val url = urls.getOrNull(index + slot - 1)
            page.isVisible = url != null
            if (page.tag == url) return@forEachIndexed
            page.tag = url
            if (url != null) {
                page.set(Content.ofUrl(url).copy(scaleType = ScalingUtils.ScaleType.FIT_CENTER))
            } else {
                page.clear()
            }
        }
        placePages()
    }

    private fun placePages() {
        val step = layout.width + PAGE_GAP.dp
        pages.forEachIndexed { slot, page ->
            page.translationX = (slot - 1) * step + pageOffset
            page.translationY = if (slot == 1) dragOffset else 0f
        }
    }

    private fun updateDragFade() {
        val fadeDistance = layout.width / DRAG_FADE_WIDTH_DIVISOR
        val fade = if (fadeDistance > 0f) min(abs(dragOffset), fadeDistance) / fadeDistance else 0f
        background.alpha = max(DRAG_MIN_BACKGROUND_ALPHA, 1f - fade)
    }

    private val isCenterZoomed: Boolean
        get() = centerPage.zoomableController.scaleFactor > 1f

    private fun hasPage(step: Int) = urls.getOrNull(index + step) != null

    private val edgeTapSide: Float
        get() = mediaViewerEdgeTapSide(layout.width.toFloat())

    private fun onTap(x: Float, y: Float) {
        if (isClosing || motion?.isRunning == true) return
        val bars = navigationController?.getSystemBars()
        val pagingTop = (bars?.top ?: 0) + actionBar.contentHeight + EDGE_TAP_TOP_GAP.dp
        if (y > pagingTop) {
            val side = edgeTapSide
            when {
                x < side && hasPage(-1) -> return switchTo(-1)
                x > layout.width - side && hasPage(1) -> return switchTo(1)
            }
        }
        setChromeShown(!isChromeShown, animated = true)
    }

    private fun pressEdge(x: Float) {
        if (pressedEdges.isAnyPressed) return
        val side = edgeTapSide
        when {
            x < side && hasPage(-1) -> pressedEdges.press(0)
            x > layout.width - side && hasPage(1) -> pressedEdges.press(1)
        }
    }

    private fun switchTo(step: Int) {
        index += step
        when (step) {
            1 -> {
                val first = pages[0]
                pages[0] = pages[1]
                pages[1] = pages[2]
                pages[2] = first
            }

            -1 -> {
                val last = pages[2]
                pages[2] = pages[1]
                pages[1] = pages[0]
                pages[0] = last
            }
        }
        pages.forEach { if (it.isVisible && it !== centerPage) it.resetZoom() }
        pageOffset = 0f
        bindPages()
        bindChrome(direction = step)
        updatePageAccessibility()
        focusPictureForAccessibility()
        hideSource()
    }

    /** [direction]: 1 to the next picture, -1 to the previous one, 0 at once. */
    private fun bindChrome(direction: Int) {
        val item = items[index]
        val (title, subtitle) = mediaViewerTitles(index + 1, items.size, item.date?.invoke())
        actionBar.setTitle(title, direction)
        actionBar.setSubtitle(subtitle, direction)
        actionBar.menuButton.isInvisible = item.menuItems == null
        caption.setText(item.caption?.invoke(caption.textView.textSize))
        if (direction != 0) {
            caption.textView.alpha = 0f
            caption.textView.animate().alpha(1f).setDuration(CAPTION_FADE_MS).start()
        }
    }

    // Telegram's viewer menu: dark over the dark viewer in either theme, opening over the button from its top corner
    private fun showMenu() {
        val menuItems = items[index].menuItems?.invoke(view) ?: return
        WMenuPopup.present(
            actionBar.menuButton,
            menuItems,
            positioning = WMenuPopup.Positioning.ALIGNED,
            isAlignedToEnd = true,
            themeIsDark = true
        )
    }

    private fun setChromeShown(show: Boolean, animated: Boolean) {
        if (show == isChromeShown) return
        isChromeShown = show
        chromeAnimator?.cancel()
        setStatusBarHidden(!show)
        val offset = CHROME_SLIDE.dp.toFloat()
        val alpha = if (show) 1f else 0f
        if (show) {
            actionBar.isVisible = true
            caption.isVisible = caption.hasText
        }
        val targets = listOf(
            Triple(actionBar, -offset, true),
            Triple(caption, offset, true),
            Triple(navigationScrim, 0f, false)
        )
        if (!animated || !WGlobalStorage.getAreAnimationsActive()) {
            targets.forEach { (view, hiddenY, slides) ->
                view.alpha = alpha
                if (slides) view.translationY = if (show) 0f else hiddenY
            }
            if (!show) hideChromeViews()
            return
        }
        chromeAnimator = AnimatorSet().apply {
            playTogether(
                targets.flatMap { (view, hiddenY, slides) ->
                    listOfNotNull(
                        ObjectAnimator.ofFloat(view, View.ALPHA, alpha),
                        if (slides) {
                            val y = if (show) 0f else hiddenY
                            ObjectAnimator.ofFloat(view, View.TRANSLATION_Y, y)
                        } else {
                            null
                        }
                    )
                }
            )
            duration = CHROME_TOGGLE_MS
            addListener(object : AnimatorListenerAdapter() {
                private var isCanceled = false

                override fun onAnimationCancel(animation: Animator) {
                    isCanceled = true
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (chromeAnimator === animation) chromeAnimator = null
                    if (!isCanceled && !show) hideChromeViews()
                }
            })
            start()
        }
    }

    // Hidden chrome takes no touches
    private fun hideChromeViews() {
        actionBar.visibility = View.INVISIBLE
        caption.visibility = View.INVISIBLE
    }

    // The window keeps its insets while the status bar is away, so nothing under the viewer moves
    private fun setStatusBarHidden(isHidden: Boolean) {
        val activity = window ?: return
        if (!isHidden && !restoresStatusBar) return
        restoresStatusBar = isHidden
        val controller = WindowInsetsControllerCompat(activity.window, activity.window.decorView)
        if (isHidden) {
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.statusBars())
        } else {
            controller.show(WindowInsetsCompat.Type.statusBars())
        }
    }

    private fun finishPaging(velocity: Float) {
        val width = layout.width.toFloat()
        val step = width + PAGE_GAP.dp
        val target = when {
            (pageOffset < -width / PAGE_THRESHOLD_DIVISOR || velocity < -PAGE_FLING_VELOCITY.dp) &&
                hasPage(1) -> 1

            (pageOffset > width / PAGE_THRESHOLD_DIVISOR || velocity > PAGE_FLING_VELOCITY.dp) &&
                hasPage(-1) -> -1

            else -> 0
        }
        animate(pageOffset, -target * step) { value ->
            pageOffset = value
            placePages()
        }.onEnd { if (target != 0) switchTo(target) }
    }

    private fun finishDragDown() {
        if (abs(dragOffset) > layout.height / CLOSE_DRAG_DIVISOR) {
            close()
            return
        }
        animate(dragOffset, 0f) { value ->
            dragOffset = value
            placePages()
            updateDragFade()
        }
    }

    private fun animateOpening() {
        val source = findSource(index)
        val place = source?.let(::placeOf)
        if (source == null || place == null || !WGlobalStorage.getAreAnimationsActive()) {
            background.alpha = 1f
            chrome.alpha = 1f
            hideSource()
            focusPictureForAccessibility()
            return
        }
        val target = fitFrame(source.aspectRatio ?: (place.frame.width() / place.frame.height()))
        hideSource()
        centerPage.alpha = 0f
        showFlyer(source.topCornerRadius)
        animate(0f, 1f) { fraction ->
            background.alpha = fraction
            chrome.alpha = fraction
            placeFlyer(place, target, fraction, source)
        }.onEnd {
            centerPage.alpha = 1f
            flyer.isVisible = false
            focusPictureForAccessibility()
        }
    }

    private fun close() {
        if (isClosing) return
        isClosing = true
        motion?.cancel()
        if (isCenterZoomed) centerPage.resetZoom()
        setStatusBarHidden(false)
        val source = findSource(index)
        val place = source?.let(::placeOf)
        val startAlpha = background.alpha
        val startChromeAlpha = chrome.alpha
        if (source == null || place == null || !WGlobalStorage.getAreAnimationsActive()) {
            animate(0f, 1f) { fraction ->
                background.alpha = startAlpha * (1f - fraction)
                chrome.alpha = startChromeAlpha * (1f - fraction)
                centerPage.alpha = 1f - fraction
                val scale = 1f - (1f - CLOSE_SCALE) * fraction
                centerPage.scaleX = scale
                centerPage.scaleY = scale
            }.onEnd { dismiss() }
            return
        }
        val start = fitFrame(source.aspectRatio ?: (place.frame.width() / place.frame.height()))
        start.offset(pageOffset, dragOffset)
        pages.forEach { it.alpha = 0f }
        showFlyer(0f)
        animate(1f, 0f) { fraction ->
            background.alpha = startAlpha * fraction
            chrome.alpha = startChromeAlpha * fraction
            placeFlyer(place, start, fraction, source)
        }.onEnd { dismiss() }
    }

    private fun dismiss() {
        val listPicture = hiddenSource?.takeIf { isAccessibilityEnabled() }
        restoreSource()
        releaseSystemBars()
        window?.dismissLastNav(animated = false)
        listPicture?.post {
            listPicture.performAccessibilityAction(ACCESSIBILITY_FOCUS, null)
        }
    }

    private fun showFlyer(cornerRadius: Float) {
        flyer.set(Content.ofUrl(urls[index]).copy(rounding = Content.Rounding.Radius(cornerRadius)))
        flyer.isVisible = true
    }

    private fun placeFlyer(place: Place, target: RectF, fraction: Float, origin: Source) {
        val source = place.frame
        val left = lerp(source.left, target.left, fraction)
        val top = lerp(source.top, target.top, fraction)
        val right = lerp(source.right, target.right, fraction)
        val bottom = lerp(source.bottom, target.bottom, fraction)
        flyerFrame.set(left, top, right, bottom)
        layoutFlyer()
        val visibleTop = place.visibleTop
        val visibleBottom = lerp(place.visibleBottom, layout.height.toFloat(), fraction)
        flyerClip.set(
            0,
            (visibleTop - top).roundToInt().coerceAtLeast(0),
            (right - left).roundToInt(),
            (visibleBottom - top).roundToInt().coerceAtMost((bottom - top).roundToInt())
        )
        flyer.clipBounds = flyerClip
        val topRadius = origin.topCornerRadius * (1f - fraction)
        val bottomRadius = origin.bottomCornerRadius * (1f - fraction)
        flyer.hierarchy.roundingParams =
            RoundingParams.fromCornersRadii(topRadius, topRadius, bottomRadius, bottomRadius)
    }

    private fun layoutFlyer() {
        flyer.layout(
            flyerFrame.left.toInt(),
            flyerFrame.top.toInt(),
            flyerFrame.right.toInt(),
            flyerFrame.bottom.toInt()
        )
    }

    private fun placeOf(source: Source): Place? {
        val image = source.image
        if (!image.isAttachedToWindow || image.width == 0 || image.height == 0) return null
        val imageLocation = IntArray(2)
        val layoutLocation = IntArray(2)
        image.getLocationInWindow(imageLocation)
        layout.getLocationInWindow(layoutLocation)
        val left = (imageLocation[0] - layoutLocation[0]).toFloat()
        val top = (imageLocation[1] - layoutLocation[1]).toFloat()
        val frame = RectF(left, top, left + image.width, top + image.height)
        val visibleTop = (source.visibleRows.first - layoutLocation[1]).toFloat()
        val visibleBottom = (source.visibleRows.last + 1 - layoutLocation[1]).toFloat()
        if (frame.bottom <= visibleTop || frame.top >= visibleBottom) return null
        return Place(frame, visibleTop, visibleBottom)
    }

    private fun fitFrame(aspectRatio: Float): RectF {
        val width = layout.width.toFloat()
        val height = layout.height.toFloat()
        val fittedWidth = min(width, height * aspectRatio)
        val fittedHeight = fittedWidth / aspectRatio
        val left = (width - fittedWidth) / 2f
        val top = (height - fittedHeight) / 2f
        return RectF(left, top, left + fittedWidth, top + fittedHeight)
    }

    /** Hides the list's picture only between its bars; what shows under them stays for the backdrop to cover. */
    private fun hideSource() {
        val source = findSource(index)
        val image = source?.image
        if (image === hiddenSource) return
        restoreSource()
        if (source == null || image == null) return
        hideBetweenBars(image, source.visibleRows)
        hiddenSource = image
    }

    private fun hideBetweenBars(image: View, visibleRows: IntRange) {
        val location = IntArray(2).also(image::getLocationInWindow)
        val top = location[1]
        val bottom = top + image.height
        val keptRows = when {
            bottom <= visibleRows.first || top > visibleRows.last -> 0 until image.height
            top < visibleRows.first -> 0 until visibleRows.first - top
            bottom > visibleRows.last + 1 -> visibleRows.last + 1 - top until image.height
            else -> IntRange.EMPTY
        }
        if (keptRows.isEmpty()) {
            image.alpha = 0f
        } else {
            image.clipBounds = Rect(0, keptRows.first, image.width, keptRows.last + 1)
        }
    }

    private fun restoreSource() {
        hiddenSource?.let {
            it.alpha = 1f
            it.clipBounds = null
        }
        hiddenSource = null
    }

    private fun animate(from: Float, to: Float, onFrame: (Float) -> Unit): ValueAnimator {
        motion?.cancel()
        return ValueAnimator.ofFloat(from, to).apply {
            duration = if (WGlobalStorage.getAreAnimationsActive()) MOTION_DURATION_MS else 0L
            interpolator = CubicBezierInterpolator.DEFAULT
            addUpdateListener { onFrame(it.animatedValue as Float) }
            motion = this
            start()
        }
    }

    private fun ValueAnimator.onEnd(action: () -> Unit) {
        addListener(object : AnimatorListenerAdapter() {
            private var isCanceled = false

            override fun onAnimationCancel(animation: Animator) {
                isCanceled = true
            }

            override fun onAnimationEnd(animation: Animator) {
                if (motion === animation) motion = null
                if (!isCanceled) action()
            }
        })
    }

    private fun lerp(from: Float, to: Float, fraction: Float) = from + (to - from) * fraction

    @SuppressLint("ViewConstructor")
    private inner class ViewerLayout(context: Context) : FrameLayout(context) {
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var startX = 0f
        private var startY = 0f
        private var mode = Mode.NONE
        private var hasSecondFinger = false
        private var velocityTracker: VelocityTracker? = null

        // A touch starting on the bar's buttons or the caption's text is theirs
        private var isTouchOnChrome = false

        // A touch starting in a side zone is a tap there until it moves, lasts or a second finger comes
        private var isEdgeTouch = false
        private var isEdgeTapCancelled = false
        private var edgeTapX = 0f
        private var edgeTapY = 0f
        private val gestures = GestureDetector(
            context,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    onTap(e.x, e.y)
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    // A double tap zooms rather than pages, so the edge it lands on isn't shaded
                    pressedEdges.release()
                    if (!isClosing && motion?.isRunning != true) {
                        val pageEvent = MotionEvent.obtain(e)
                        pageEvent.offsetLocation(-centerPage.x, -centerPage.y)
                        centerPage.doubleTapped(pageEvent)
                        pageEvent.recycle()
                    }
                    return true
                }
            }
        )

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            placePages()
        }

        override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
            super.onLayout(changed, left, top, right, bottom)
            if (flyer.isVisible) layoutFlyer()
        }

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (isClosing) return true
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    isTouchOnChrome = isChromeAt(event.x, event.y)
                    isEdgeTouch = !isTouchOnChrome &&
                        isMediaViewerEdgeTap(event.x, width.toFloat())
                    isEdgeTapCancelled = false
                    edgeTapX = event.x
                    edgeTapY = event.y
                    if (!isTouchOnChrome) pressEdge(event.x)
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> pressedEdges.release()
            }
            // The page takes each touch first. Its zoom stops any zoom animation as a finger comes down, so a double
            // tap, recognised on its second finger down, zooms only after the page has had that touch.
            val isHandled = super.dispatchTouchEvent(event)
            if (isEdgeTouch) {
                trackEdgeTap(event)
            } else if (!isTouchOnChrome) {
                gestures.onTouchEvent(event)
            }
            return isHandled
        }

        // A tap in a side zone pages, or shows or hides the bars, as the finger lifts, as in Telegram, without waiting
        // to see whether a second tap follows, so quick taps there page once each
        private fun trackEdgeTap(event: MotionEvent) {
            when (event.actionMasked) {
                MotionEvent.ACTION_MOVE -> {
                    val travel = hypot(event.x - edgeTapX, event.y - edgeTapY)
                    if (travel > touchSlop) isEdgeTapCancelled = true
                }

                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_CANCEL -> {
                    isEdgeTapCancelled = true
                }

                MotionEvent.ACTION_UP -> {
                    val heldMs = event.eventTime - event.downTime
                    val isHeld = heldMs > ViewConfiguration.getLongPressTimeout()
                    if (!isEdgeTapCancelled && !isHeld) onTap(event.x, event.y)
                }
            }
        }

        private fun isChromeAt(x: Float, y: Float): Boolean {
            if (!isChromeShown) return false
            if (y < actionBar.bottom) return true
            if (!caption.hasText) return false
            return y >= caption.top + caption.bandTop && x >= caption.left && x < caption.right
        }

        override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
            if (isTouchOnChrome) return false
            trackVelocity(event)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    mode = Mode.NONE
                    hasSecondFinger = false
                }

                MotionEvent.ACTION_POINTER_DOWN -> hasSecondFinger = true

                MotionEvent.ACTION_MOVE -> return detectMode(event)
            }
            return false
        }

        private fun detectMode(event: MotionEvent): Boolean {
            if (mode != Mode.NONE) return true
            if (hasSecondFinger || isCenterZoomed || motion?.isRunning == true) return false
            val dx = abs(event.x - startX)
            val dy = abs(event.y - startY)
            if (dy >= DRAG_START.dp && dy / 2f > dx) {
                mode = Mode.DRAG
                startY = event.y
                setChromeShown(false, animated = true)
            } else if (dx > touchSlop && dy + PAGING_SLACK.dp < dx) {
                mode = Mode.PAGING
                startX = event.x
            }
            if (mode != Mode.NONE) pressedEdges.release()
            return mode != Mode.NONE
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            trackVelocity(event)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    mode = Mode.NONE
                    hasSecondFinger = false
                }

                MotionEvent.ACTION_POINTER_DOWN -> hasSecondFinger = true

                MotionEvent.ACTION_MOVE -> when (mode) {
                    Mode.DRAG -> {
                        dragOffset = event.y - startY
                        placePages()
                        updateDragFade()
                    }

                    Mode.PAGING -> {
                        val dx = event.x - startX
                        val isPastEnd = (dx < 0 && !hasPage(1)) || (dx > 0 && !hasPage(-1))
                        pageOffset = if (isPastEnd) dx / EDGE_RESISTANCE else dx
                        placePages()
                    }

                    Mode.NONE -> detectMode(event)
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val tracker = velocityTracker
                    tracker?.computeCurrentVelocity(VELOCITY_UNITS)
                    when (mode) {
                        Mode.DRAG -> finishDragDown()
                        Mode.PAGING -> finishPaging(tracker?.xVelocity ?: 0f)
                        Mode.NONE -> Unit
                    }
                    mode = Mode.NONE
                    velocityTracker?.recycle()
                    velocityTracker = null
                }
            }
            return true
        }

        private fun trackVelocity(event: MotionEvent) {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                velocityTracker?.recycle()
                velocityTracker = VelocityTracker.obtain()
            }
            velocityTracker?.addMovement(event)
        }
    }

    private enum class Mode { NONE, DRAG, PAGING }

    companion object {
        private const val PAGE_COUNT = 3
        private const val MAX_ZOOM = 3f
        private const val PAGE_GAP = 30
        private const val EDGE_TAP_TOP_GAP = 40
        private const val CHROME_SCRIM_COLOR = 0x7F000000
        private const val CHROME_SLIDE = 24
        private const val CHROME_TOGGLE_MS = 200L
        private const val CAPTION_FADE_MS = 220L
        private const val HIDDEN_FOR_ACCESSIBILITY =
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        private const val ACCESSIBILITY_FOCUS = AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS
        private const val PAGE_THRESHOLD_DIVISOR = 3f
        private const val PAGE_FLING_VELOCITY = 650
        private const val EDGE_RESISTANCE = 3f
        private const val DRAG_START = 30
        private const val PAGING_SLACK = 12
        private const val CLOSE_DRAG_DIVISOR = 6f
        private const val DRAG_FADE_WIDTH_DIVISOR = 4f
        private const val DRAG_MIN_BACKGROUND_ALPHA = 0.5f
        private const val CLOSE_SCALE = 0.9f
        private const val MOTION_DURATION_MS = 250L
        private const val VELOCITY_UNITS = 1000

        fun present(
            window: WWindow,
            items: List<MediaViewerItem>,
            startIndex: Int,
            findSource: (index: Int) -> Source?
        ) {
            if (items.isEmpty()) return
            val viewer = MediaViewerVC(window, items, startIndex, findSource)
            val navigation = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.Overlay
                )
            )
            navigation.setRoot(viewer)
            // Reading the picture's place needs the window to have placed the viewer
            window.present(navigation, animated = false, onCompletion = viewer::open)
        }
    }
}
