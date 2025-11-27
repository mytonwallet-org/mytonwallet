package org.mytonwallet.app_air.uicomponents.widgets

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.Drawable
import androidx.core.net.toUri
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.drawee.generic.GenericDraweeHierarchyBuilder
import com.facebook.drawee.generic.RoundingParams
import com.facebook.drawee.interfaces.DraweeController
import com.facebook.drawee.view.SimpleDraweeView
import com.facebook.imagepipeline.request.ImageRequestBuilder
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color


@Deprecated("use WCustomImageView (or AppCompatImageView for simple cases)")
@SuppressLint("ViewConstructor")
class WImageView(
    context: Context,
    private var cornerRadius: Int = 0,
    private var bWidth: Int = 0,
    private var bColor: Int? = null,
    private val circleRadius: Boolean = false
) :
    SimpleDraweeView(context), WThemedView {

    var isInitialized = false

    init {
        id = generateViewId()
        updateTheme()
        isInitialized = true
    }

    fun loadUrl(imageUrl: String) {
        hierarchy.actualImageScaleType =
            com.facebook.drawee.drawable.ScalingUtils.ScaleType.CENTER_CROP
        val imageRequest = ImageRequestBuilder.newBuilderWithSource(imageUrl.toUri())
            .build()
        val draweeController: DraweeController = Fresco.newDraweeControllerBuilder()
            .setImageRequest(imageRequest)
            .build()
        setController(draweeController)
    }

    fun loadRes(resId: Int) {
        hierarchy.actualImageScaleType =
            com.facebook.drawee.drawable.ScalingUtils.ScaleType.CENTER_CROP
        val imageRequest =
            ImageRequestBuilder.newBuilderWithResourceId(resId)
                .build()
        val draweeController: DraweeController = Fresco.newDraweeControllerBuilder()
            .setImageRequest(imageRequest)
            .build()
        setController(draweeController)
    }

    fun crossFadeImage(newDrawable: Drawable) {
        val fadeOut = ObjectAnimator.ofFloat(this, "alpha", 1f, 0f)
        fadeOut.duration = if (drawable == null) 0 else AnimationConstants.VERY_QUICK_ANIMATION / 2
        val fadeIn = ObjectAnimator.ofFloat(this, "alpha", 0f, 1f)
        fadeIn.duration = AnimationConstants.VERY_QUICK_ANIMATION / 2

        fadeOut.addListener(object : AnimatorListenerAdapter() {
            override fun onAnimationEnd(animation: Animator) {
                setImageDrawable(newDrawable)
                fadeIn.start()
            }
        })
        fadeOut.start()
    }

    override fun updateTheme() {
        if (!isInitialized || bWidth > 0) {
            if (cornerRadius > 0 || circleRadius || bWidth > 0) {
                val roundingParams = if (circleRadius) {
                    RoundingParams.asCircle()
                } else {
                    RoundingParams.fromCornersRadius(cornerRadius.toFloat())
                }
                roundingParams.apply {
                    if (bWidth > 0) {
                        setBorder(bColor ?: WColor.Background.color, bWidth.toFloat())
                    }
                }
                setHierarchy(
                    GenericDraweeHierarchyBuilder(resources)
                        .setRoundingParams(roundingParams)
                        .build()
                )
            }
        }
    }
}
