package org.mytonwallet.app_air.uicomponents.commonViews.cardMotion

import android.content.Context
import android.graphics.Canvas
import android.graphics.Matrix
import android.view.MotionEvent
import org.mytonwallet.app_air.uicomponents.widgets.WView

/** Projects the live subtree while mapping child hit testing back to its plane. */
class CardPressSurfaceView(context: Context) : WView(context) {
    private val projection = Matrix()
    private val inverse = Matrix()
    private val values = FloatArray(9)

    init {
        // ViewGroup can bypass draw() for a container without its own background.
        setWillNotDraw(false)
    }

    internal fun updatePose(motion: CardPressMotion) {
        motion.writeProjection(
            width,
            height,
            resources.displayMetrics.density,
            values,
            width - paddingLeft - paddingRight
        )
        projection.setValues(values)
        projection.invert(inverse)
        invalidate()
    }

    override fun draw(canvas: Canvas) {
        val save = canvas.save()
        canvas.concat(projection)
        super.draw(canvas)
        canvas.restoreToCount(save)
    }

    fun mapHostPoint(x: Float, y: Float, out: FloatArray) {
        out[0] = x
        out[1] = y
        inverse.mapPoints(out)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (projection.isIdentity) return super.dispatchTouchEvent(event)
        val mapped = MotionEvent.obtain(event)
        return try {
            mapped.transform(inverse)
            super.dispatchTouchEvent(mapped)
        } finally {
            mapped.recycle()
        }
    }
}
