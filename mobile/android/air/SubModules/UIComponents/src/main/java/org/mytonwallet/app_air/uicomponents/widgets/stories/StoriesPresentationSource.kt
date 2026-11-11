package org.mytonwallet.app_air.uicomponents.widgets.stories

import android.graphics.Bitmap
import android.graphics.RectF
import android.view.View
import java.lang.ref.WeakReference
import org.mytonwallet.app_air.uicomponents.extensions.asImage

class StoriesPresentationSource(
    view: View,
    button: View,
    val buttonTitle: String,
    val buttonColor: Int,
    val buttonTextColor: Int,
    /** In pixels. */
    val buttonTextSize: Float,
    /** In pixels. */
    val cornerRadius: Float,
    private val prepareForPresentation: () -> Unit = {},
    private val isValid: () -> Boolean = { true }
) {
    private val viewRef = WeakReference(view)
    private val buttonRef = WeakReference(button)
    private var snapshot: Bitmap? = null
    private var isHidden = false

    internal class Anchor(val frame: RectF, val buttonFrame: RectF)

    internal fun resolve(container: View): Anchor? {
        val view = viewRef.get() ?: return null
        val button = buttonRef.get() ?: return null
        if (!isValid() || !view.isAttachedToWindow || !button.isAttachedToWindow ||
            view.windowToken != container.windowToken ||
            view.width == 0 || view.height == 0 || button.width == 0 || button.height == 0
        ) {
            return null
        }
        if (!isHidden) prepareForPresentation()
        val frame = frameIn(view, container)
        if (!RectF.intersects(
                frame,
                RectF(0f, 0f, container.width.toFloat(), container.height.toFloat())
            )
        ) {
            return null
        }
        return Anchor(frame, frameIn(button, container))
    }

    internal fun makeSnapshot(): Bitmap? {
        snapshot?.let { return it }
        val view = viewRef.get() ?: return null
        val button = buttonRef.get() ?: return null
        val buttonAlpha = button.alpha
        button.alpha = 0f
        return view.asImage().also {
            button.alpha = buttonAlpha
            snapshot = it
        }
    }

    internal fun hide() {
        isHidden = true
        viewRef.get()?.alpha = 0f
    }

    internal fun restore() {
        isHidden = false
        snapshot = null
        viewRef.get()?.alpha = 1f
    }

    private fun frameIn(view: View, container: View): RectF {
        val viewLocation = IntArray(2).also(view::getLocationInWindow)
        val containerLocation = IntArray(2).also(container::getLocationInWindow)
        val left = (viewLocation[0] - containerLocation[0]).toFloat()
        val top = (viewLocation[1] - containerLocation[1]).toFloat()
        return RectF(left, top, left + view.width * view.scaleX, top + view.height * view.scaleY)
    }
}
