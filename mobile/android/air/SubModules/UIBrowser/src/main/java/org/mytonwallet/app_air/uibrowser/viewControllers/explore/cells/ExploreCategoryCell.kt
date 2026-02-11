package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.setPadding
import androidx.core.view.updateLayoutParams
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ExploreCategoryCell(
    context: Context,
    private val cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
    private val onOpenCategoryTap: (category: MExploreCategory) -> Unit
) :
    WCell(context, LayoutParams(WRAP_CONTENT, WRAP_CONTENT)), WThemedView {

    private val imagesPadding = 4

    private val img1Ripple = WRippleDrawable.create(18f.dp)
    private val img2Ripple = WRippleDrawable.create(18f.dp)
    private val img3Ripple = WRippleDrawable.create(18f.dp)

    private val img1 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(18f.dp)
        setPadding(imagesPadding.dp)
        background = img1Ripple
    }
    private val img2 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(18f.dp)
        setPadding(imagesPadding.dp)
        background = img2Ripple
    }
    private val img3 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(18f.dp)
        setPadding(imagesPadding.dp)
        background = img3Ripple
    }
    private val otherImg1 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(7f.dp)
    }
    private val otherImg2 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(7f.dp)
    }
    private val otherImg3 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(7f.dp)
    }
    private val otherImg4 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(7f.dp)
    }
    private val imageSize = (cellWidth - 54.dp) / 2 + 2 * imagesPadding.dp

    private val otherSitesView = WView(context).apply {
        val smallImageSize = ((imageSize - 2 * imagesPadding.dp - 12f.dp) / 2).roundToInt()
        addView(otherImg1, ViewGroup.LayoutParams(smallImageSize, smallImageSize))
        addView(otherImg2, ViewGroup.LayoutParams(smallImageSize, smallImageSize))
        addView(otherImg3, ViewGroup.LayoutParams(smallImageSize, smallImageSize))
        addView(otherImg4, ViewGroup.LayoutParams(smallImageSize, smallImageSize))
        setConstraints {
            toStart(otherImg1, 3.5f)
            toTop(otherImg1, 3.5f)
            startToEnd(otherImg2, otherImg1, 5f)
            toTop(otherImg2, 3.5f)
            startToStart(otherImg3, otherImg1)
            topToBottom(otherImg3, otherImg1, 5f)
            startToStart(otherImg4, otherImg2)
            topToTop(otherImg4, otherImg3)
        }
    }

    private val containerView = WView(context).apply {
        addView(img1, ViewGroup.LayoutParams(imageSize, imageSize))
        addView(img2, ViewGroup.LayoutParams(imageSize, imageSize))
        addView(img3, ViewGroup.LayoutParams(imageSize, imageSize))
        addView(otherSitesView, ViewGroup.LayoutParams(imageSize, imageSize))

        setConstraints {
            toStart(img1, 12f - imagesPadding)
            toTop(img1, 12f - imagesPadding)
            startToEnd(img2, img1, 14f - 2 * imagesPadding)
            toTop(img2, 12f - imagesPadding)
            startToStart(img3, img1)
            topToBottom(img3, img1, 14f - 2 * imagesPadding)
            startToStart(otherSitesView, img2, imagesPadding.toFloat())
            topToTop(otherSitesView, img3, imagesPadding.toFloat())
            toEnd(img2, 12f - imagesPadding)
            toBottom(img3, 12f - imagesPadding)
        }
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
    }

    private val outerContainerView = WView(context).apply {
        addView(containerView, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(titleLabel)
        setConstraints {
            toTop(containerView, 16f)
            toCenterX(containerView, 8f)
            setDimensionRatio(containerView.id, "1:1")
            topToBottom(titleLabel, containerView, 8f)
            toCenterX(titleLabel)
            toBottom(titleLabel, 4f)
        }
    }

    override fun setupViews() {
        super.setupViews()

        addView(outerContainerView, LayoutParams(MATCH_PARENT, MATCH_PARENT))

        val allImages = listOf(img1, img2, img3)
        for (i in allImages.indices) {
            allImages[i].setOnClickListener {
                allImages.getOrNull(i)
                category?.sites?.get(i)?.let {
                    onSiteTap(it)
                }
            }
        }
        otherSitesView.setOnClickListener {
            category?.let {
                onOpenCategoryTap(it)
            }
        }
    }

    private var category: MExploreCategory? = null
    private var isTopLeft: Boolean = false
    private var isTopRight: Boolean = false
    private var isBottomLeft: Boolean = false
    private var isBottomRight: Boolean = false
    fun configure(
        category: MExploreCategory?,
        isLeft: Boolean,
        isRight: Boolean,
        isTopLeft: Boolean,
        isTopRight: Boolean,
        isBottomLeft: Boolean,
        isBottomRight: Boolean
    ) {
        this.category = category
        this.isTopLeft = isTopLeft
        this.isTopRight = isTopRight
        this.isBottomLeft = isBottomLeft
        this.isBottomRight = isBottomRight

        setPadding(
            if (isLeft) ViewConstants.HORIZONTAL_PADDINGS.dp else 0,
            0,
            if (isRight) ViewConstants.HORIZONTAL_PADDINGS.dp else 0,
            0
        )
        outerContainerView.setPadding(
            if (isLeft) 8.dp else 0,
            0,
            if (isRight) 8.dp else 0,
            0,
        )
        updateLayoutParams {
            width =
                cellWidth +
                    paddingLeft + paddingRight +
                    outerContainerView.paddingLeft + outerContainerView.paddingRight
        }
        containerView.isInvisible = category == null
        titleLabel.isInvisible = category == null
        category?.let {
            titleLabel.text = category.name

            val sites = category.sites.filter {
                ConfigStore.isLimited != true || !it.canBeRestricted
            }

            if (sites.isNotEmpty()) img1.set(
                Content.ofUrl(
                    sites.getOrNull(0)!!.iconUrl ?: ""
                )
            ) else img1.clear()
            if (sites.size > 1) img2.set(
                Content.ofUrl(
                    sites.getOrNull(1)!!.iconUrl ?: ""
                )
            ) else img2.clear()
            if (sites.size > 2) img3.set(
                Content.ofUrl(
                    sites.getOrNull(2)!!.iconUrl ?: ""
                )
            ) else img3.clear()

            val otherImages = listOf(otherImg1, otherImg2, otherImg3, otherImg4)
            for (i in otherImages.indices) {
                val site = sites.getOrNull(i + 3)
                if (site != null) {
                    otherImages[i].set(Content.ofUrl(site.iconUrl!!))
                    otherImages[i].isGone = false
                } else {
                    otherImages[i].clear()
                    otherImages[i].isGone = true
                }
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        arrayOf(img1Ripple, img2Ripple, img3Ripple).forEach {
            it.backgroundColor = WColor.SecondaryBackground.color
            it.rippleColor = WColor.BackgroundRipple.color
        }
        containerView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            26f.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        outerContainerView.setBackgroundColor(
            WColor.Background.color,
            if (isTopLeft) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isTopRight) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isBottomRight) ViewConstants.BLOCK_RADIUS.dp else 0f,
            if (isBottomLeft) ViewConstants.BLOCK_RADIUS.dp else 0f,
        )
    }
}
