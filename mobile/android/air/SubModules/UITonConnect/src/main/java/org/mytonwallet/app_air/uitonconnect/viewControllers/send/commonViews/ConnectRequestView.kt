package org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnLayout
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.moshi.ApiDapp

class ConnectRequestView(context: Context) : WView(context), WThemedView, SkeletonContainer {
    companion object {
        private const val SKELETON_RADIUS = 12f
        private const val IMAGE_SKELETON_RADIUS = 20f
    }

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(20f.dp)
        defaultPlaceholder = Content.Placeholder.Color(WColor.Background)
    }

    private val imageSkeletonView = WBaseView(context).apply {
        visibility = GONE
    }

    private val titleTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 28f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val titleSkeletonView = WBaseView(context).apply {
        visibility = GONE
    }

    private val linkTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 22f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        maxLines = 1
    }

    private val linkSkeletonView = WBaseView(context).apply {
        visibility = GONE
    }

    private val infoTextView = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 20f)
        ellipsize = TextUtils.TruncateAt.END
        gravity = Gravity.CENTER
        typeface = WFont.Regular.typeface
        maxWidth = 300.dp
        letterSpacing = -0.02f
    }

    private val skeletonView = SkeletonView(context)

    override fun setupViews() {
        setPaddingDp(20, 0, 20, 24)

        // Add skeleton views
        addView(imageSkeletonView, LayoutParams(80.dp, 80.dp))
        addView(titleSkeletonView, LayoutParams(180.dp, 28.dp))
        addView(linkSkeletonView, LayoutParams(120.dp, 24.dp))

        addView(imageView, LayoutParams(80.dp, 80.dp))
        addView(titleTextView, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(linkTextView, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(infoTextView, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        addView(skeletonView, LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT))

        setConstraints {
            toCenterX(imageSkeletonView)
            toTop(imageSkeletonView)

            topToBottom(titleSkeletonView, imageSkeletonView, 23f)
            toCenterX(titleSkeletonView)

            topToBottom(linkSkeletonView, titleSkeletonView, 7f)
            toCenterX(linkSkeletonView)

            toCenterX(imageView)
            toTop(imageView)

            topToBottom(titleTextView, imageView, 21f)
            toStart(titleTextView)
            toEnd(titleTextView)

            topToBottom(linkTextView, titleTextView, 9f)
            toStart(linkTextView)
            toEnd(linkTextView)

            topToBottom(infoTextView, linkTextView, 10f)
            toCenterX(infoTextView)

            allEdges(skeletonView)
        }

        updateTheme()
    }

    fun configure(dApp: ApiDapp?) {
        infoTextView.text = LocaleController.getString("Connected apps can only see your wallet address and will not be able to move your assets without permission.")
        dApp?.let {
            if (isShowingSkeleton) {
                hideSkeleton()
            }
            titleTextView.text = LocaleController.getFormattedString("Connect to %1$@?", listOf(dApp.name ?: "dApp"))
            linkTextView.text = dApp.host
            dApp.iconUrl?.let { iconUrl ->
                imageView.set(Content.ofUrl(iconUrl))
            } ?: run {
                imageView.clear()
            }
        } ?: run {
            showSkeleton()
        }
    }

    override fun updateTheme() {
        titleTextView.setTextColor(WColor.PrimaryText.color)
        linkTextView.setTextColor(WColor.Tint.color)
        infoTextView.setTextColor(WColor.PrimaryText.color)

        val skeletonColor = WColor.SecondaryBackground.color
        imageSkeletonView.setBackgroundColor(skeletonColor, IMAGE_SKELETON_RADIUS.dp)
        titleSkeletonView.setBackgroundColor(skeletonColor, SKELETON_RADIUS.dp)
        linkSkeletonView.setBackgroundColor(skeletonColor, SKELETON_RADIUS.dp)
    }

    var isShowingSkeleton = false
        private set

    fun showSkeleton() {
        if (isShowingSkeleton) return
        isShowingSkeleton = true

        imageView.visibility = INVISIBLE
        titleTextView.visibility = INVISIBLE
        linkTextView.visibility = INVISIBLE

        imageSkeletonView.visibility = VISIBLE
        titleSkeletonView.visibility = VISIBLE
        linkSkeletonView.visibility = VISIBLE

        val skeletonViews = listOf(imageSkeletonView, titleSkeletonView, linkSkeletonView)
        val radiusMap = hashMapOf(
            0 to IMAGE_SKELETON_RADIUS,
            1 to SKELETON_RADIUS,
            2 to SKELETON_RADIUS
        )
        skeletonView.doOnLayout {
            skeletonView.applyMask(skeletonViews, radiusMap)
            skeletonView.startAnimating()
        }
    }

    private fun hideSkeleton() {
        if (!isShowingSkeleton) return
        isShowingSkeleton = false

        skeletonView.stopAnimating()

        titleSkeletonView.fadeOut(onCompletion = {
            titleSkeletonView.visibility = GONE
        })
        linkSkeletonView.fadeOut(onCompletion = {
            linkSkeletonView.visibility = GONE
        })

        imageView.visibility = VISIBLE
        titleTextView.visibility = VISIBLE
        linkTextView.visibility = VISIBLE
        imageView.alpha = 0f
        imageView.fadeIn()
        titleTextView.alpha = 0f
        titleTextView.fadeIn()
        linkTextView.alpha = 0f
        linkTextView.fadeIn()
    }

    override fun getChildViewMap(): HashMap<View, Float> {
        return hashMapOf(
            imageSkeletonView to IMAGE_SKELETON_RADIUS,
            titleSkeletonView to SKELETON_RADIUS,
            linkSkeletonView to SKELETON_RADIUS
        )
    }
}
