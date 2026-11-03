package org.mytonwallet.app_air.uicomponents.base

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.graphics.Color
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewOutlineProvider
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.DecelerateInterpolator
import androidx.constraintlayout.widget.ConstraintLayout
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.glass.GlassProviders
import org.mytonwallet.app_air.uicomponents.glass.WGlassView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator

class MinimizedBrowserPresenter(private val host: Host) {
    interface Host {
        val container: ViewGroup
        val availableHeight: Int
        val bottomInset: Int
        val horizontalSpan: IntRange
        val animationsEnabled: Boolean
        fun canMinimize(nav: WNavigationController): Boolean
        fun maximizedFrame(nav: WNavigationController, minimizedHeight: Int): RectF
        fun detach(nav: WNavigationController)
        fun attach(nav: WNavigationController, animated: Boolean)
        fun destroy(nav: WNavigationController)
        fun render()
    }

    private class Entry(
        val nav: WNavigationController,
        val onMaximizeProgress: (progress: Float) -> Unit,
        val onStateChanged: () -> Unit
    ) {
        var shadow: WGlassView? = null
    }

    private class Slot(
        val x: Float,
        val y: Float,
        val width: Int,
        val scale: Float,
        val alpha: Float
    )

    private var isDisposed = false
    private var animator: ValueAnimator? = null
    private var transition: Any? = null
    private val context get() = host.container.context

    private val entries = ArrayList<Entry>()
    private var isResting = false
    private var cornerRadius = 0f

    var height = 0f
        private set

    private fun setHeight(value: Float) {
        if (height == value) return
        height = value
        host.render()
    }

    val hasNavigation get() = entries.isNotEmpty()
    val count get() = entries.size

    val navigations: List<WNavigationController>
        get() = entries.asReversed().map { it.nav }

    fun hosts(nav: WNavigationController) = entries.any { it.nav === nav }

    fun isFront(nav: WNavigationController) = entries.lastOrNull()?.nav === nav

    fun frontBounds(out: RectF): Boolean {
        val nav = entries.lastOrNull()?.nav ?: return false
        val left = nav.left + nav.translationX
        val top = nav.top + nav.translationY
        out.set(left, top, left + nav.layoutParams.width, top + nav.layoutParams.height)
        return true
    }

    val occupiedHeight: Int
        get() = if (entries.isEmpty()) 0 else host.bottomInset + height.roundToInt()

    fun updateTheme() {
        entries.forEach {
            it.nav.updateTheme()
            it.shadow?.updateTheme()
        }
    }

    fun bringToFront() {
        entries.forEach {
            it.shadow?.bringToFront()
            it.nav.bringToFront()
        }
    }

    fun dispose() {
        if (isDisposed) return
        dismissAll()
        isDisposed = true
    }

    private fun cancelTransition() {
        transition = null
        val previous = animator
        animator = null
        previous?.removeAllListeners()
        previous?.removeAllUpdateListeners()
        previous?.cancel()
    }

    private fun settle() {
        var remaining = 4
        while (remaining-- > 0) {
            animator?.end() ?: return
        }
    }

    private fun animate(
        animated: Boolean,
        duration: Long,
        interpolator: TimeInterpolator,
        update: (Float) -> Unit,
        onStart: () -> Unit = {},
        complete: () -> Unit = {}
    ) {
        cancelTransition()
        val next = Any()
        transition = next
        onStart()
        if (transition !== next) return
        if (!animated) {
            update(1f)
            if (transition === next) {
                transition = null
                complete()
            }
            return
        }
        val nextAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            this.interpolator = interpolator
            addUpdateListener {
                if (transition === next) update(it.animatedFraction)
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (transition !== next) return
                    transition = null
                    animator = null
                    complete()
                }
            })
        }
        animator = nextAnimator
        nextAnimator.start()
    }

    private fun minimizedY(): Float =
        (host.availableHeight - host.bottomInset - MINIMIZED_HEIGHT.dp - 4.dp).toFloat()

    private fun minimizedWidth(): Int {
        val span = host.horizontalSpan
        return min(span.last + 1 - span.first - 20.dp, MINIMIZED_MAX_WIDTH.dp)
    }

    private fun minimizedX(): Float {
        val span = host.horizontalSpan
        return span.first + (span.last + 1 - span.first - minimizedWidth()) / 2f
    }

    private fun restingHeight(count: Int): Float = when {
        count == 0 -> 0f
        count == 1 -> (MINIMIZED_HEIGHT + 8).dp.toFloat()
        else -> (MINIMIZED_HEIGHT + 8 + STACK_PEEK).dp.toFloat()
    }

    private fun slot(depth: Int): Slot {
        val visibleDepth = min(depth, 1)
        return Slot(
            x = minimizedX(),
            y = minimizedY() - visibleDepth * STACK_PEEK.dp,
            width = minimizedWidth(),
            scale = 1f - visibleDepth * (1f - BACK_SCALE),
            alpha = if (depth <= 1) 1f else 0f
        )
    }

    private fun currentSlot(entry: Entry) = Slot(
        entry.nav.translationX,
        entry.nav.translationY,
        entry.nav.layoutParams.width,
        entry.nav.scaleX,
        entry.nav.alpha
    )

    private fun applySlot(entry: Entry, from: Slot, to: Slot, fraction: Float) {
        val nav = entry.nav
        val alpha = from.alpha + (to.alpha - from.alpha) * fraction
        val width = from.width + ((to.width - from.width) * fraction).roundToInt()
        if (nav.layoutParams.width != width) {
            nav.layoutParams = nav.layoutParams.apply { this.width = width }
        }
        nav.translationX = from.x + (to.x - from.x) * fraction
        nav.translationY = from.y + (to.y - from.y) * fraction
        val scale = from.scale + (to.scale - from.scale) * fraction
        nav.pivotX = width / 2f
        nav.pivotY = nav.layoutParams.height / 2f
        nav.scaleX = scale
        nav.scaleY = scale
        nav.alpha = alpha
        nav.visibility = if (alpha > 0f) View.VISIBLE else View.INVISIBLE
        applyShadow(entry, alpha, nav.layoutParams.width, nav.layoutParams.height, cornerRadius)
    }

    private fun createShadow(): WGlassView = WGlassView(context).also {
        it.alpha = 0f
        it.glassPadding = WGlassView.GLASS_PADDING_DP.dp
        it.setProvider(GlassProviders.shadowOnly())
        host.container.addView(it, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private fun applyShadow(entry: Entry, alpha: Float, width: Int, height: Int, radius: Float) {
        val nav = entry.nav
        val shadow = entry.shadow
        if (shadow == null) {
            nav.elevation = alpha * 1.5f.dp
            return
        }
        val scale = nav.scaleX
        val scaledWidth = width * scale
        val scaledHeight = height * scale
        val l = nav.left + nav.translationX + (width - scaledWidth) / 2f
        val t = nav.top + nav.translationY + (height - scaledHeight) / 2f
        shadow.alpha = alpha
        shadow.setTargetRect(l, t, l + scaledWidth, t + scaledHeight, radius * scale)
    }

    private fun release(entry: Entry, restore: Boolean, animated: Boolean = false) {
        if (!entries.remove(entry)) return
        entry.shadow?.let { host.container.removeView(it) }
        entry.shadow = null
        entry.nav.elevation = 0f
        if (entries.isEmpty()) {
            height = 0f
            isResting = false
        }
        host.render()
        if (restore) {
            entry.nav.clipToOutline = false
            entry.nav.outlineProvider = ViewOutlineProvider.BACKGROUND
            host.container.removeView(entry.nav)
            host.attach(entry.nav, animated)
        } else {
            host.destroy(entry.nav)
        }
    }

    private fun notifyStateChanged() {
        entries.toList().forEach { it.onStateChanged() }
    }

    private fun finishStackChange() {
        isResting = entries.isNotEmpty()
        notifyStateChanged()
        relayout()
    }

    fun stackChanged() {
        if (isDisposed || !isResting) return
        notifyStateChanged()
        relayout()
    }

    fun relayout() = relayout(driver = null)

    fun follow(driver: ValueAnimator) = relayout(driver)

    fun snapToRest() {
        if (isDisposed || !isResting || entries.isEmpty() || transition != null) return
        val stack = entries.toList()
        stack.forEachIndexed { i, entry ->
            val slot = slot(stack.size - 1 - i)
            applySlot(entry, slot, slot, 1f)
        }
    }

    private fun relayout(driver: ValueAnimator?) {
        if (isDisposed || !isResting || entries.isEmpty()) return
        if (driver == null && transition != null) return
        val stack = entries.toList()
        val from = stack.map(::currentSlot)
        val to = stack.indices.map { slot(stack.size - 1 - it) }
        val startHeight = height
        val targetHeight = restingHeight(stack.size)
        val settled = abs(startHeight - targetHeight) < 0.5f && from.indices.all {
            abs(from[it].x - to[it].x) < 0.5f &&
                from[it].width == to[it].width &&
                abs(from[it].y - to[it].y) < 0.5f &&
                abs(from[it].scale - to[it].scale) < 0.001f &&
                abs(from[it].alpha - to[it].alpha) < 0.01f
        }
        if (settled) return
        val update = { fraction: Float ->
            if (startHeight != targetHeight) {
                height = startHeight + (targetHeight - startHeight) * fraction
                host.render()
            }
            stack.forEachIndexed { i, entry -> applySlot(entry, from[i], to[i], fraction) }
        }
        if (driver != null) {
            followDriver(driver, update)
        } else {
            animate(
                host.animationsEnabled,
                AnimationConstants.VERY_VERY_QUICK_ANIMATION,
                AccelerateDecelerateInterpolator(),
                update = update,
                complete = { relayout() }
            )
        }
        host.render()
    }

    private fun followDriver(driver: ValueAnimator, update: (Float) -> Unit) {
        cancelTransition()
        val next = Any()
        transition = next
        val interpolator = WInterpolator.emphasized
        val updateListener = ValueAnimator.AnimatorUpdateListener {
            if (transition !== next || it.duration <= 0) return@AnimatorUpdateListener
            val progress = (it.currentPlayTime.toFloat() / it.duration).coerceIn(0f, 1f)
            update(interpolator.getInterpolation(progress))
        }
        driver.addUpdateListener(updateListener)
        // Owners may clear listeners on cancel.
        driver.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationCancel(animation: Animator) = finish()
            override fun onAnimationEnd(animation: Animator) = finish()

            private fun finish() {
                driver.removeUpdateListener(updateListener)
                driver.removeListener(this)
                if (transition !== next) return
                transition = null
                relayout()
            }
        })
    }

    fun containerResized() {
        if (isDisposed || entries.isEmpty()) return
        settle()
        cancelTransition()
        if (isResting) {
            relayout()
            return
        }
        val stack = entries.toList()
        stack.forEachIndexed { i, entry ->
            val slot = slot(stack.size - 1 - i)
            applySlot(entry, slot, slot, 1f)
        }
    }

    // Runs while the browser still covers the screen.
    fun prepareMinimize(nav: WNavigationController) {
        if (isDisposed || !host.canMinimize(nav)) return
        settle()
        isResting = false
        setHeight(restingHeight(entries.size + 1))
    }

    fun cancelMinimize() {
        if (isDisposed || isResting || transition != null) return
        setHeight(restingHeight(entries.size))
        finishStackChange()
    }

    fun minimize(
        nav: WNavigationController,
        onProgress: (progress: Float) -> Unit,
        onMaximizeProgress: (progress: Float) -> Unit,
        onStateChanged: () -> Unit
    ) {
        if (isDisposed || !host.canMinimize(nav)) {
            onMaximizeProgress(1f)
            cancelMinimize()
            return
        }
        settle()
        val initialX = nav.translationX
        val initialY = nav.translationY
        val initialRadius = windowRadius(nav)
        val others = entries.toList()
        val othersFrom = others.map(::currentSlot)
        val othersTo = others.indices.map { slot(others.size - it) }
        val entry = Entry(nav, onMaximizeProgress, onStateChanged)
        entries.add(entry)
        isResting = false
        host.detach(nav)
        entry.shadow = createShadow()
        host.container.addView(nav)
        val initialHeight = nav.height
        val finalHeight = MINIMIZED_HEIGHT.dp
        val initialWidth = nav.width
        val finalWidth = minimizedWidth()
        val finalTranslationX = minimizedX()
        val finalY = minimizedY()
        height = restingHeight(entries.size)
        host.render()

        fun onUpdate(animatedFraction: Float) {
            nav.translationY = initialY + (finalY - initialY) * animatedFraction
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            nav.layoutParams = nav.layoutParams.apply {
                height = animatedHeight
                width = animatedWidth
            }
            nav.translationX = initialX + (finalTranslationX - initialX) * animatedFraction
            val radius = initialRadius + (24.dp - initialRadius) * animatedFraction
            cornerRadius = radius
            nav.setBackgroundColor(Color.TRANSPARENT, radius, true)
            applyShadow(entry, animatedFraction, animatedWidth, animatedHeight, radius)
            others.forEachIndexed { i, other ->
                applySlot(other, othersFrom[i], othersTo[i], animatedFraction)
            }
        }

        animate(
            host.animationsEnabled,
            AnimationConstants.VERY_VERY_QUICK_ANIMATION,
            AccelerateDecelerateInterpolator(),
            update = { fraction ->
                onUpdate(fraction)
                onProgress(fraction)
            },
            complete = ::finishStackChange
        )
    }

    fun maximize(animated: Boolean, nav: WNavigationController? = null) {
        if (isDisposed) return
        settle()
        val entry = entryFor(nav) ?: return
        isResting = false
        if (entries.last() !== entry) {
            entries.remove(entry)
            entries.add(entry)
            bringToFront()
            applySlot(entry, currentSlot(entry), slot(0), 1f)
        }
        val others = entries.filter { it !== entry }
        val othersFrom = others.map(::currentSlot)
        val othersTo = others.indices.map { slot(others.size - 1 - it) }
        val target = entry.nav
        val frame = maximizedFrame(target)
        val initialHeight = target.height
        val finalHeight = frame.height().roundToInt()
        val initialWidth = target.width
        val finalWidth = frame.width().roundToInt()
        val initialY = target.y
        val initialAlpha = target.alpha
        val initialRadius = cornerRadius
        val finalRadius = windowRadius(target)
        val initialTranslationX = target.translationX

        fun onUpdate(animatedFraction: Float) {
            target.translationY = initialY + (frame.top - initialY) * animatedFraction
            val animatedHeight = finalHeight +
                ((initialHeight - finalHeight) * (1 - animatedFraction)).roundToInt()
            val animatedWidth = finalWidth +
                ((initialWidth - finalWidth) * (1 - animatedFraction)).roundToInt()
            target.layoutParams = target.layoutParams.apply {
                height = animatedHeight
                width = animatedWidth
            }
            target.translationX =
                initialTranslationX + (frame.left - initialTranslationX) * animatedFraction
            target.alpha = initialAlpha + (1 - initialAlpha) * animatedFraction
            val radius = initialRadius + (finalRadius - initialRadius) * animatedFraction
            target.setBackgroundColor(Color.TRANSPARENT, radius, radius > 0f)
            applyShadow(entry, 1f - animatedFraction, animatedWidth, animatedHeight, radius)
            others.forEachIndexed { i, other ->
                applySlot(other, othersFrom[i], othersTo[i], animatedFraction)
            }
        }

        animate(
            animated,
            AnimationConstants.VERY_VERY_QUICK_ANIMATION,
            AccelerateDecelerateInterpolator(),
            update = { fraction ->
                onUpdate(fraction)
                entry.onMaximizeProgress(fraction)
            },
            onStart = { entry.onMaximizeProgress(0f) },
            complete = {
                height = restingHeight(others.size)
                release(entry, restore = true, animated = animated)
                finishStackChange()
            }
        )
    }

    fun maximizeAll() {
        if (isDisposed) return
        settle()
        entries.toList().forEach { maximize(animated = false, nav = it.nav) }
    }

    fun dismissMinimized(animated: Boolean, nav: WNavigationController? = null) {
        if (isDisposed) return
        settle()
        val entry = entryFor(nav) ?: return
        isResting = false
        val others = entries.filter { it !== entry }
        val othersFrom = others.map(::currentSlot)
        val othersTo = others.indices.map { slot(others.size - 1 - it) }
        val startStackHeight = height
        val finalStackHeight = restingHeight(others.size)
        val initialAlpha = entry.nav.alpha

        fun onUpdate(animatedFraction: Float) {
            setHeight(startStackHeight + (finalStackHeight - startStackHeight) * animatedFraction)
            val fadedAlpha = initialAlpha * (1 - animatedFraction)
            entry.nav.alpha = fadedAlpha
            entry.shadow?.alpha = fadedAlpha
            others.forEachIndexed { i, other ->
                applySlot(other, othersFrom[i], othersTo[i], animatedFraction)
            }
        }

        animate(
            animated,
            AnimationConstants.VERY_QUICK_ANIMATION,
            DecelerateInterpolator(),
            update = ::onUpdate,
            complete = {
                release(entry, restore = false)
                finishStackChange()
            }
        )
    }

    fun dismissAll() {
        if (isDisposed) return
        settle()
        cancelTransition()
        isResting = false
        entries.toList().forEach { release(it, restore = false) }
    }

    // Frame a minimized nav reopens into, once it leaves the stack.
    fun maximizedFrame(nav: WNavigationController): RectF {
        val others = entries.count { it.nav !== nav }
        val remainingHeight =
            if (others == 0) 0 else host.bottomInset + restingHeight(others).roundToInt()
        return host.maximizedFrame(nav, remainingHeight)
    }

    fun windowRadius(nav: WNavigationController) =
        if (nav.isCenteredWindow) ViewConstants.BLOCK_RADIUS.dp else 0f

    private fun entryFor(nav: WNavigationController?): Entry? =
        if (nav == null) entries.lastOrNull() else entries.firstOrNull { it.nav === nav }
}

private const val MINIMIZED_HEIGHT = 48
private const val MINIMIZED_MAX_WIDTH = 480
private const val STACK_PEEK = 8
private const val BACK_SCALE = 0.95f
