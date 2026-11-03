package org.mytonwallet.app_air.uicomponents.glass

import android.graphics.Canvas
import android.view.View

/**
 * A ViewGroup that lets [GlassRoot] draw its direct children into a blur capture.
 *
 * `ViewGroup.drawChild` is protected; routing through it (rather than `child.draw`) records a
 * reference to the child's RenderNode, so scrolling, translation and alpha changes reach the blur
 * without re-recording the capture.
 */
interface GlassCaptureHost {
    fun glassDrawBackground(canvas: Canvas) {}

    fun glassDrawChild(canvas: Canvas, child: View, drawingTime: Long): Boolean

    /** Draws what lies over the children, after them */
    fun glassDrawForeground(canvas: Canvas) {}

    /** The state of what the background and the foreground draw, which a capture has to record anew when it changes */
    fun glassDrawnStateHash(): Long = 0
}
