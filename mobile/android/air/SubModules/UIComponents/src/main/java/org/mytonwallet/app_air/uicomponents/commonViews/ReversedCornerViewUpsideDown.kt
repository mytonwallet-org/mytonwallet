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
import org.mytonwallet.app_air.uicomponents.drawable.StickyBottomGradientDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha

@SuppressLint("ViewConstructor")
class ReversedCornerViewUpsideDown(
    context: Context,
    private var blurRootView: ViewGroup?,
    private val forceBlurView: Boolean = false,
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

    var isGradientMode: Boolean = !forceBlurView && WGlobalStorage.isGradientNavigationBarActive()
        private set

    val extraTopHeight: Int
        get() = if (isGradientMode) ViewConstants.ADDITIONAL_GRADIENT_HEIGHT.dp.toInt() else 0

    private var blurryBackgroundView: WBlurryBackgroundView? = null

    private val gradientView: View by lazy {
        View(context).apply {
            id = generateViewId()
        }
    }
    private var gradientDrawable: StickyBottomGradientDrawable? = null

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

        if (isGradientMode) {
            rebuildGradientDrawable()
        } else {
            blurryBackgroundView?.setOverlayColor(color ?: Color.TRANSPARENT) ?: run {
                backgroundView.setBackgroundColor(color ?: WColor.SecondaryBackground.color)
            }
        }
        postInvalidateOnAnimation()
    }

    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        resumeBlurring()
        if (configured)
            return
        updateTheme()
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

        if (isGradientMode) {
            super.dispatchDraw(canvas)
            return
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
        val blurryBackgroundView = blurryBackgroundView
        if (blurryBackgroundView?.parent != null) {
            blurryBackgroundView.draw(canvas)
        } else {
            backgroundView.draw(canvas)
        }
        canvas.restore()
    }

    private fun rebuildGradientDrawable() {
        val bgColor = overlayColor
            ?: if (ThemeManager.isDark) WColor.SecondaryBackground.color else WColor.Background.color
        val drawable = StickyBottomGradientDrawable(
            intArrayOf(
                bgColor.colorWithAlpha(0),
                bgColor
            )
        )
        drawable.setStops(floatArrayOf(0f, 1f))
        gradientDrawable = drawable
        gradientView.background = drawable
    }

    private fun attachGradientView() {
        if (gradientView.parent != null) return
        addView(gradientView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (gradientDrawable == null) rebuildGradientDrawable()
    }

    private fun detachGradientView() {
        if (gradientView.parent != null) {
            (gradientView.parent as ViewGroup).removeView(gradientView)
        }
    }

    private fun syncBlurView() {
        if (isGradientMode) {
            blurryBackgroundView?.let { blur ->
                blur.pauseBlurring()
                if (blur.parent != null) (blur.parent as ViewGroup).removeView(blur)
            }
            blurryBackgroundView = null
            if (backgroundView.parent != null)
                (backgroundView.parent as ViewGroup).removeView(backgroundView)
            attachGradientView()
            return
        }

        detachGradientView()

        val blurEnabled = WGlobalStorage.isBlurEnabled() && blurRootView != null
        if (blurEnabled && blurryBackgroundView == null) {
            blurryBackgroundView =
                WBlurryBackgroundView(context, fadeSide = WBlurryBackgroundView.Side.TOP)
            if (backgroundView.parent != null)
                (backgroundView.parent as ViewGroup).removeView(backgroundView)
            if (isPlaying) {
                isPlaying = false
                resumeBlurring()
            }
        } else if (!blurEnabled && blurryBackgroundView != null) {
            blurryBackgroundView?.let { blur ->
                blur.pauseBlurring()
                if (blur.parent != null) (blur.parent as ViewGroup).removeView(blur)
            }
            blurryBackgroundView = null
            if (backgroundView.parent == null)
                addView(backgroundView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        } else if (!blurEnabled && blurryBackgroundView == null) {
            if (backgroundView.parent == null)
                addView(backgroundView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    fun refreshModeFromSettings() {
        val next = !forceBlurView && WGlobalStorage.isGradientNavigationBarActive()
        if (next == isGradientMode)
            return
        isGradientMode = next
        clipChildren = !isGradientMode
        pathDirty = true
        return
    }

    override fun updateTheme() {
        refreshModeFromSettings()
        syncBlurView()

        if (isGradientMode) {
            rebuildGradientDrawable()
        } else {
            val bgColor = overlayColor ?: WColor.SecondaryBackground.color
            if (blurryBackgroundView == null)
                backgroundView.setBackgroundColor(bgColor)
            blurryBackgroundView?.updateTheme()
        }

        updateRadius()
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

        if (isGradientMode) {
            attachGradientView()
            postInvalidateOnAnimation()
            return
        }

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
