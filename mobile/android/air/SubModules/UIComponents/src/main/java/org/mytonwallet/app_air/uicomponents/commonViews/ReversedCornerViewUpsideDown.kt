package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.RectF
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage

@SuppressLint("ViewConstructor")
class ReversedCornerViewUpsideDown(
    context: Context,
    private var blurRootView: ViewGroup?,
) : BaseReversedCornerView(context), WThemedView {

    init {
        id = generateViewId()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            requestedFrameRate = REQUESTED_FRAME_RATE_CATEGORY_LOW
        }
    }

    private val backgroundView: View by lazy {
        View(context).apply {
            setBackgroundColor(WColor.SecondaryBackground.color)
        }
    }

    private val blurryBackgroundView =
        if (WGlobalStorage.isBlurEnabled()) blurRootView?.let {
            WBlurryBackgroundView(context, fadeSide = WBlurryBackgroundView.Side.TOP)
        } else null

    private val path = Path()
    private val cornerPath = Path()
    private val rectF = RectF()

    private var cornerRadius: Float = ViewConstants.TOOLBAR_RADIUS.dp

    private var radii: FloatArray =
        floatArrayOf(0f, 0f, 0f, 0f, cornerRadius, cornerRadius, cornerRadius, cornerRadius)

    private var showSeparator: Boolean = true
    var isPlaying = false
    private var lastWidth = -1
    private var lastHeight = -1

    fun setShowSeparator(visible: Boolean) {
        if (visible == showSeparator) return
        showSeparator = visible
        postInvalidateOnAnimation()
    }

    private var overlayColor: Int? = null
    fun setBlurOverlayColor(color: Int?) {
        overlayColor = color

        blurryBackgroundView?.setOverlayColor(color ?: Color.TRANSPARENT) ?: run {
            backgroundView.setBackgroundColor(color ?: WColor.SecondaryBackground.color)
        }
        postInvalidateOnAnimation()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        resumeBlurring()
    }

    override fun dispatchDraw(canvas: Canvas) {
        val width = width
        val height = height

        if (width <= 0 || height <= 0) return

        val wF = width.toFloat()
        val hF = height.toFloat()

        if (width != lastWidth || height != lastHeight) {
            lastWidth = width
            lastHeight = height
            pathDirty = true
        }

        if (pathDirty) {
            updatePath(wF, hF)
            pathDirty = false
        }

        drawChildrenClipped(canvas)
    }

    private fun updatePath(width: Float, height: Float) {
        path.reset()
        cornerPath.reset()
        path.moveTo(0f, 0f)
        path.lineTo(width, 0f)
        path.lineTo(width, height)
        path.lineTo(0f, height)
        path.close()

        rectF.set(
            horizontalPadding,
            0f,
            width - horizontalPadding,
            cornerRadius
        )
        cornerPath.addRoundRect(rectF, radii, Path.Direction.CCW)

        path.op(cornerPath, Path.Op.DIFFERENCE)
    }

    private fun drawChildrenClipped(canvas: Canvas) {
        canvas.save()
        canvas.clipPath(path)
        if (blurryBackgroundView?.parent != null) {
            blurryBackgroundView.draw(canvas)
        } else {
            backgroundView.draw(canvas)
        }
        canvas.restore()
    }

    override fun updateTheme() {
        val bgColor = overlayColor
            ?: WColor.SecondaryBackground.color
        if (blurryBackgroundView == null)
            backgroundView.setBackgroundColor(bgColor)

        blurryBackgroundView?.updateTheme()

        updateRadius()

        if (!isPlaying) {
            resumeBlurring()
            post { pauseBlurring() }
        } else {
            postInvalidateOnAnimation()
        }
    }

    private fun updateRadius() {
        if (cornerRadius == ViewConstants.TOOLBAR_RADIUS.dp)
            return
        cornerRadius = ViewConstants.TOOLBAR_RADIUS.dp
        radii = floatArrayOf(0f, 0f, 0f, 0f, cornerRadius, cornerRadius, cornerRadius, cornerRadius)
        pathDirty = true
    }

    fun pauseBlurring() {
        if (!isPlaying) return
        isPlaying = false
        blurryBackgroundView?.pauseBlurring()
        postInvalidateOnAnimation()
    }

    fun resumeBlurring() {
        if (isPlaying) return
        isPlaying = true

        blurryBackgroundView?.let {
            if (it.parent == null) {
                addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT))
                it.setupWith(blurRootView!!)
            }
            it.resumeBlurring()
        } ?: run {
            if (backgroundView.parent == null)
                addView(backgroundView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }

        postInvalidateOnAnimation()
    }
}
