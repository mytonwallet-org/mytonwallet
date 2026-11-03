package org.mytonwallet.app_air.uiagent.viewControllers.agent

import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.PixelFormat
import android.graphics.drawable.Drawable
import android.os.Build
import android.view.View
import android.view.ViewTreeObserver
import java.lang.ref.WeakReference
import java.util.WeakHashMap
import kotlin.math.abs
import kotlin.math.roundToInt
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

/** An Agent screen whose header stays in place through a push or a pop to another one */
interface AgentHeaderHandoffScreen {
    /** The header's parts that differ between Agent screens, such as the title, which cross-fade in place */
    val headerHandoffContent: List<View>
}

/**
 * Keeps the header in place through a push or a pop between two Agent screens, such as from the News feed into a news
 * item's discussion: the screens' contents move as usual while both bars hold still over them, so the back button
 * stays where it is and only the parts that differ cross-fade. During an interactive pop the top bar stays opaque, and
 * the parts cross-fade on it as far as the screen has been swiped.
 */
internal object AgentHeaderHandoff {
    private const val MAX_WAITED_FRAMES = 8
    private val sessions = WeakHashMap<WNavigationController, Session>()

    /** Called by an Agent screen as it is about to appear or disappear */
    fun begin(screen: WViewController) {
        val navigationController = screen.navigationController ?: return
        // A detached stack draws nothing to hold, and its tree observer would never be called
        if (!navigationController.isAttachedToWindow) return
        if (!WGlobalStorage.getAreAnimationsActive()) return
        if (sessions[navigationController] != null) return
        val session = Session(navigationController)
        sessions[navigationController] = session
        session.start()
    }

    // A session ends with its stack leaving the window, so the static map never keeps a destroyed stack's screens
    private class Session(navigationController: WNavigationController) :
        ViewTreeObserver.OnPreDrawListener,
        View.OnAttachStateChangeListener {
        private val navigationController = WeakReference(navigationController)
        private var observer: ViewTreeObserver? = null
        private var top: WViewController? = null
        private var behind: WViewController? = null
        private var hasHeld = false
        private var waitedFrames = 0

        fun start() {
            val navigationController = navigationController.get() ?: return
            navigationController.addOnAttachStateChangeListener(this)
            observer = navigationController.viewTreeObserver.also { it.addOnPreDrawListener(this) }
            onPreDraw()
        }

        override fun onViewAttachedToWindow(view: View) {}

        override fun onViewDetachedFromWindow(view: View) = finish()

        override fun onPreDraw(): Boolean {
            val navigationController = navigationController.get()
            val stack = navigationController?.viewControllers
            val top = stack?.lastOrNull()
            val behind = stack?.getOrNull(stack.size - 2)
            if (top !== this.top || behind !== this.behind) {
                reset()
                this.top = top
                this.behind = behind
            }
            val isTransitioning = behind != null && behind.isViewConfigured &&
                behind.view.parent != null && behind.view.visibility == View.VISIBLE
            if (top !is AgentHeaderHandoffScreen || behind !is AgentHeaderHandoffScreen) {
                finish()
                return true
            }
            // A pop shows the screen behind just after it is told it appears
            if (!isTransitioning) {
                if (hasHeld || ++waitedFrames > MAX_WAITED_FRAMES) finish()
                return true
            }
            hasHeld = true
            hold(top, behind)
            return true
        }

        private fun hold(top: WViewController, behind: WViewController) {
            // The top screen slides; its bar stays
            val shift = -top.view.translationX
            listOfNotNull(top.navigationBar, top.topReversedCornerView).forEach {
                it.translationX = shift
            }
            // The screen behind grows into place; its bar keeps its size
            val scale = behind.view.scaleX.takeIf { it > 0f } ?: 1f
            listOfNotNull(behind.navigationBar, behind.topReversedCornerView).forEach {
                it.pivotX = behind.view.pivotX - it.left
                it.pivotY = behind.view.pivotY - it.top
                it.scaleX = 1 / scale
                it.scaleY = 1 / scale
            }
            // The top screen fades in over the one behind as it comes, and out as it goes
            val fade = 1 - top.view.alpha.coerceIn(0f, 1f)
            (behind as AgentHeaderHandoffScreen).headerHandoffContent.forEach {
                setFade(it, fade)
            }
            holdSwipedHeader(top, behind)
        }

        /**
         * A screen swiped away keeps its opaque bar over the one behind, so the parts that differ cross-fade on it as
         * far as the swipe has gone: its own fade out and those of the screen behind fade in over them
         */
        private fun holdSwipedHeader(top: WViewController, behind: WViewController) {
            val bar = top.navigationBar ?: return
            val width = top.view.width.takeIf { it > 0 } ?: return
            val progress = if (top.view.alpha >= 1f) {
                (abs(top.view.translationX) / width).coerceIn(0f, 1f)
            } else {
                0f
            }
            (top as AgentHeaderHandoffScreen).headerHandoffContent.forEach {
                setFade(it, 1 - progress)
            }
            val incoming = swipedContent ?: SwipedContent(bar).also {
                swipedContent = it
                bar.overlay.add(it)
            }
            incoming.update((behind as AgentHeaderHandoffScreen).headerHandoffContent, progress)
        }

        // The screen behind's differing parts, drawn on the swiped screen's bar where they lie
        private class SwipedContent(val bar: View) : Drawable() {
            private var views: List<View> = emptyList()
            private var progress = 0f
            private val barLocation = IntArray(2)
            private val viewLocation = IntArray(2)

            fun update(views: List<View>, progress: Float) {
                this.views = views
                this.progress = progress
                setBounds(0, 0, bar.width, bar.height)
                invalidateSelf()
            }

            override fun draw(canvas: Canvas) {
                if (progress <= 0f) return
                bar.getLocationInWindow(barLocation)
                for (view in views) {
                    if (!view.isShown || view.width == 0 || view.height == 0) continue
                    view.getLocationInWindow(viewLocation)
                    val count = canvas.save()
                    canvas.translate(
                        (viewLocation[0] - barLocation[0]).toFloat(),
                        (viewLocation[1] - barLocation[1]).toFloat()
                    )
                    canvas.saveLayerAlpha(
                        0f,
                        0f,
                        view.width.toFloat(),
                        view.height.toFloat(),
                        (progress * view.alpha * 255).roundToInt()
                    )
                    view.draw(canvas)
                    canvas.restoreToCount(count)
                }
            }

            override fun setAlpha(alpha: Int) {}

            override fun setColorFilter(colorFilter: ColorFilter?) {}

            @Deprecated("Deprecated in Java")
            override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
        }

        private var swipedContent: SwipedContent? = null

        private fun releaseSwipedContent() {
            val content = swipedContent ?: return
            swipedContent = null
            content.bar.overlay.remove(content)
        }

        // The fade multiplies the view's own alpha. Before API 29 the view's alpha carries it: the alpha it had is
        // kept, and taken anew when something else sets the view's alpha meanwhile, such as a button turning disabled.
        private class Fade(var original: Float, var written: Float)

        private val fades = WeakHashMap<View, Fade>()

        private fun setFade(view: View, fade: Float) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                view.transitionAlpha = fade
                return
            }
            val entry = fades.getOrPut(view) { Fade(view.alpha, view.alpha) }
            if (view.alpha != entry.written) entry.original = view.alpha
            entry.written = entry.original * fade
            view.alpha = entry.written
        }

        private fun clearFade(view: View) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                view.transitionAlpha = 1f
                return
            }
            val entry = fades.remove(view) ?: return
            // An alpha set by someone else since the last frame is the view's own
            if (view.alpha == entry.written) view.alpha = entry.original
        }

        private fun reset() {
            releaseSwipedContent()
            top?.takeIf { it.isViewConfigured }?.let { screen ->
                listOfNotNull(screen.navigationBar, screen.topReversedCornerView).forEach {
                    it.translationX = 0f
                }
                (screen as? AgentHeaderHandoffScreen)?.headerHandoffContent?.forEach(::clearFade)
            }
            behind?.takeIf { it.isViewConfigured }?.let { screen ->
                listOfNotNull(screen.navigationBar, screen.topReversedCornerView).forEach {
                    it.scaleX = 1f
                    it.scaleY = 1f
                }
                (screen as? AgentHeaderHandoffScreen)?.headerHandoffContent?.forEach(::clearFade)
            }
            top = null
            behind = null
        }

        private fun finish() {
            reset()
            observer?.takeIf { it.isAlive }?.removeOnPreDrawListener(this)
            observer = null
            navigationController.get()?.let {
                it.removeOnAttachStateChangeListener(this)
                sessions.remove(it)
            }
        }
    }
}
