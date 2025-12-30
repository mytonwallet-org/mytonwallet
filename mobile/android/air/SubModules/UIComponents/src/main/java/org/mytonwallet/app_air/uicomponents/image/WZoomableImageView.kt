package org.mytonwallet.app_air.uicomponents.image

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.PointF
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.util.AttributeSet
import android.view.MotionEvent
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.content.ContextCompat
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.drawee.generic.GenericDraweeHierarchyBuilder
import com.facebook.drawee.generic.RoundingParams
import com.facebook.drawee.interfaces.DraweeController
import com.facebook.imagepipeline.request.ImageRequest
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.drawable.ContentGradientDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setRounding
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.zoomable.AbstractAnimatedZoomableController
import org.mytonwallet.app_air.uicomponents.widgets.zoomable.DefaultZoomableController
import org.mytonwallet.app_air.uicomponents.widgets.zoomable.ZoomableDraweeView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.gradientColors
import org.mytonwallet.app_air.walletcore.models.MToken

// TODO:: Merge with WCustomImageView
open class WZoomableImageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyle: Int = 0,
) : ZoomableDraweeView(context, attrs, defStyle), WThemedView {

    companion object {
        const val CHAIN_SIZE = 16
    }

    private var chainDrawable: Drawable? = null
    private var content: Content? = null
    private val path = Path()

    var defaultRounding: Content.Rounding = Content.Rounding.Round
    var defaultPlaceholder: Content.Placeholder = Content.Placeholder.Color(WColor.BackgroundRipple)
    var chainSize: Int = CHAIN_SIZE.dp
    var chainSizeGap: Float = 1.5f.dp

    init {
        id = generateViewId()
        isFocusable = false
        isClickable = false
    }

    fun doubleTapped(e: MotionEvent) {
        val zc = zoomableController as AbstractAnimatedZoomableController
        val vp = PointF(e.x, e.y)
        val ip = zc.mapViewToImage(vp)
        val maxScale = zc.maxScaleFactor
        val minScale = zc.minScaleFactor
        if (zc.scaleFactor < (maxScale + minScale) / 2) {
            zc.zoomToPoint(
                maxScale,
                ip,
                vp,
                DefaultZoomableController.LIMIT_ALL,
                AnimationConstants.VERY_QUICK_ANIMATION.toLong(),
                null
            )
        } else {
            zc.zoomToPoint(
                minScale,
                ip,
                vp,
                DefaultZoomableController.LIMIT_ALL,
                AnimationConstants.VERY_QUICK_ANIMATION.toLong(),
                null
            )
        }
    }

    fun resetZoom() {
        val zoomableController = (zoomableController as AbstractAnimatedZoomableController)
        val vp = PointF(x, y)
        val ip: PointF = zoomableController.mapViewToImage(vp)
        zoomableController.zoomToPoint(
            1f,
            ip,
            vp,
            DefaultZoomableController.LIMIT_ALL,
            AnimationConstants.VERY_QUICK_ANIMATION,
            null
        )
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)

        val chainRadius = chainSize / 2f

        path.reset()
        path.addRect(0f, 0f, measuredWidth.toFloat(), measuredHeight.toFloat(), Path.Direction.CW)
        path.addCircle(
            measuredWidth - chainRadius,
            measuredHeight - chainRadius,
            chainRadius + chainSizeGap,
            Path.Direction.CCW
        )
        path.close()
    }

    override fun onDraw(canvas: Canvas) {
        val needClip = chainDrawable != null && chainSize > 0
        if (needClip) {
            canvas.save()
            canvas.clipPath(path)
        }

        super.onDraw(canvas)
        if (needClip) {
            canvas.restore()
            chainDrawable?.let {
                it.setBounds(
                    measuredWidth - chainSize,
                    measuredHeight - chainSize,
                    measuredWidth,
                    measuredHeight
                )
                it.draw(canvas)
            }
        }
    }

    fun setAsset(token: MToken, showChain: Boolean = false) {
        set(Content.of(token, showChain), null)
    }

    fun set(content: Content, lowResUrl: String? = null) {
        this.hierarchy = buildHierarchy(content)
        this.controller = buildController(content, lowResUrl = lowResUrl)
        this.chainDrawable = if (content.subImageRes != 0)
            AppCompatResources.getDrawable(context, content.subImageRes)
        else null

        this.content = content
        invalidate()
    }

    fun clear() {
        controller = buildController(null, null)
        chainDrawable = null
        content = null
        setImageDrawable(null)
        invalidate()
    }

    override fun updateTheme() {
        val content = this.content ?: return
        val placeholder = getPlaceholderMode(content)
        if (placeholder is Content.Placeholder.Color || content.image is Content.Image.Gradient) {
            hierarchy = buildHierarchy(content)
        }
        invalidate()
    }

    /* Private */

    private fun buildController(content: Content?, lowResUrl: String?): DraweeController {
        return when (val image = content?.image) {
            is Content.Image.Empty,
            is Content.Image.Res,
            is Content.Image.Gradient,
            null -> Fresco.newDraweeControllerBuilder()
                .setOldController(controller)
                .setAutoPlayAnimations(true)
                .build()

            is Content.Image.Url -> Fresco.newDraweeControllerBuilder()
                .setOldController(controller)
                .setImageRequest(ImageRequest.fromUri(image.url))
                .setLowResImageRequest(ImageRequest.fromUri(lowResUrl))
                .build()
        }
    }

    private fun buildHierarchy(content: Content) = GenericDraweeHierarchyBuilder(resources).apply {
        setPlaceholderImage(getPlaceholderDrawable(content))
        setPlaceholderImageScaleType(content.scaleType)
        setActualImageScaleType(content.scaleType)
        setRoundingParams(getRoundingParams(content))
    }.build()

    private fun getRoundingMode(content: Content) =
        if (content.rounding !is Content.Rounding.Default)
            content.rounding else defaultRounding

    private fun getPlaceholderMode(content: Content) =
        if (content.placeholder !is Content.Placeholder.Default)
            content.placeholder else defaultPlaceholder

    private fun getRoundingParams(content: Content): RoundingParams {
        return when (val rounding = getRoundingMode(content)) {
            is Content.Rounding.Default -> throw IllegalArgumentException()
            is Content.Rounding.Round -> RoundingParams.asCircle()
            is Content.Rounding.Radius -> RoundingParams.fromCornersRadius(rounding.radius)
        }
    }

    private fun getPlaceholderDrawable(content: Content): Drawable? {
        return when (content.image) {
            is Content.Image.Res -> ContextCompat.getDrawable(context, content.image.res)
            is Content.Image.Gradient -> {
                val res = content.image.icon
                val drawable = if (res != 0) {
                    ContextCompat.getDrawable(context, res)?.apply {
                        setTint(Color.WHITE)
                    }
                } else null
                ContentGradientDrawable(
                    GradientDrawable.Orientation.TOP_BOTTOM,
                    content.image.key.gradientColors,
                    drawable
                ).apply {
                    setRounding(getRoundingMode(content))
                }
            }

            else -> when (val placeholder = getPlaceholderMode(content)) {
                is Content.Placeholder.Default -> throw IllegalArgumentException()
                is Content.Placeholder.Color -> ColorDrawable(placeholder.color.color)
            }
        }
    }
}
