package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.View
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.utils.Vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.vec2i
import org.mytonwallet.app_air.walletbasecontext.utils.x
import org.mytonwallet.app_air.walletbasecontext.utils.y
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class HighlightOverlayView(
    context: Context,
    private val holeRect: RectF?,
    private val cornerRadius: Float,
    private val topReversedCornerView: ReversedCornerView?,
    private val bottomReversedCornerView: ReversedCornerViewUpsideDown?,
) : View(context) {

    init {
        id = generateViewId()
        setLayerType(LAYER_TYPE_SOFTWARE, null)
    }

    private val dimPaint = Paint().apply {
        color = Color.BLACK.colorWithAlpha(76)
    }

    private val clearPaint = Paint().apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
    }
    private val holePath = Path()
    private val exclusionPath = Path()
    private val cornerCutoutPath = Path()
    private val viewLocation: Vec2i = vec2i()
    private val thisLocation: Vec2i = vec2i()
    private val viewRect = RectF()
    private val cutoutRect = RectF()
    private val radiiTop = floatArrayOf(
        ViewConstants.TOOLBAR_RADIUS.dp, ViewConstants.TOOLBAR_RADIUS.dp,
        ViewConstants.TOOLBAR_RADIUS.dp, ViewConstants.TOOLBAR_RADIUS.dp,
        0f, 0f,
        0f, 0f
    )
    private val radiiBottom = floatArrayOf(
        0f, 0f,
        0f, 0f,
        ViewConstants.TOOLBAR_RADIUS.dp, ViewConstants.TOOLBAR_RADIUS.dp,
        ViewConstants.TOOLBAR_RADIUS.dp, ViewConstants.TOOLBAR_RADIUS.dp
    )

    override fun onDraw(canvas: Canvas) {
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), dimPaint)
        val holeRect = holeRect ?: return

        holePath.reset()
        holePath.addRoundRect(holeRect, cornerRadius, cornerRadius, Path.Direction.CW)
        exclusionPath.reset()

        handleCornerCutout(topReversedCornerView, isTop = true)
        handleCornerCutout(bottomReversedCornerView, isTop = false)

        if (!exclusionPath.isEmpty) {
            holePath.op(exclusionPath, Path.Op.DIFFERENCE)
        }

        canvas.drawPath(holePath, clearPaint)
    }

    private fun handleCornerCutout(view: BaseReversedCornerView?, isTop: Boolean) {
        if (view?.isVisible != true || view.width <= 0 || view.height <= 0) return

        view.getLocationInWindow(viewLocation)
        getLocationInWindow(thisLocation)

        val left = (viewLocation.x - thisLocation.x).toFloat()
        val top = (viewLocation.y - thisLocation.y).toFloat()
        val width = view.width.toFloat()
        val height = view.height.toFloat()
        val radius = ViewConstants.TOOLBAR_RADIUS.dp
        val padding = view.horizontalPadding

        viewRect.set(left, top, left + width, top + height)

        if (!RectF.intersects(holeRect!!, viewRect)) return

        cornerCutoutPath.reset()
        cornerCutoutPath.addRect(viewRect, Path.Direction.CW)

        val cutoutTop = if (isTop) top + height - radius else top
        val cutoutBottom = if (isTop) top + height else top + radius
        val radii = if (isTop) radiiTop else radiiBottom

        cutoutRect.set(
            left + padding,
            cutoutTop,
            left + width - padding,
            cutoutBottom
        )

        val cutoutPath = Path().apply {
            addRoundRect(cutoutRect, radii, Path.Direction.CCW)
        }

        cornerCutoutPath.op(cutoutPath, Path.Op.DIFFERENCE)
        exclusionPath.op(cornerCutoutPath, Path.Op.UNION)
    }
}
