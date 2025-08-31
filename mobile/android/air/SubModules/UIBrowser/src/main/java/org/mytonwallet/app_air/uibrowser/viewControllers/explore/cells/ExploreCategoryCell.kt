package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.setPadding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.addRippleEffect
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.models.MExploreCategory
import org.mytonwallet.app_air.walletcore.models.MExploreSite
import org.mytonwallet.app_air.walletcore.stores.ConfigStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class ExploreCategoryCell(
    context: Context,
    cellWidth: Int,
    private val onSiteTap: (site: MExploreSite) -> Unit,
    private val onOpenCategoryTap: (category: MExploreCategory) -> Unit
) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val imagesPadding = 4

    private val img1 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(14f.dp)
        setPadding(imagesPadding.dp)
    }
    private val img2 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(14f.dp)
        setPadding(imagesPadding.dp)
    }
    private val img3 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(14f.dp)
        setPadding(imagesPadding.dp)
    }
    private val otherImg1 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(5.5f.dp)
    }
    private val otherImg2 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(5.5f.dp)
    }
    private val otherImg3 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(5.5f.dp)
    }
    private val otherImg4 = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(5.5f.dp)
    }
    private val imageSize = (cellWidth - 62.dp) / 2 + 2 * imagesPadding.dp

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

    override fun setupViews() {
        super.setupViews()

        addView(containerView, ViewGroup.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(titleLabel)
        setConstraints {
            toTop(containerView)
            toCenterX(containerView)
            setDimensionRatio(containerView.id, "1:1")
            topToBottom(titleLabel, containerView, 8f)
            toCenterX(titleLabel)
        }

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
    fun configure(category: MExploreCategory) {
        this.category = category

        titleLabel.text = category.name

        val sites = category.sites.filter {
            ConfigStore.isLimited != true || !it.canBeRestricted
        }

        if (sites.isNotEmpty()) img1.set(
            Content.ofUrl(
                sites.getOrNull(0)!!.icon ?: ""
            )
        ) else img1.clear()
        if (sites.size > 1) img2.set(
            Content.ofUrl(
                sites.getOrNull(1)!!.icon ?: ""
            )
        ) else img2.clear()
        if (sites.size > 2) img3.set(
            Content.ofUrl(
                sites.getOrNull(2)!!.icon ?: ""
            )
        ) else img3.clear()

        val otherImages = listOf(otherImg1, otherImg2, otherImg3, otherImg4)
        for (i in otherImages.indices) {
            val site = sites.getOrNull(i + 3)
            if (site != null) {
                otherImages[i].set(Content.ofUrl(site.icon!!))
            } else {
                otherImages[i].visibility = GONE
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        arrayOf(img1, img2, img3).forEach {
            it.setBackgroundColor(WColor.GroupedBackground.color)
            it.addRippleEffect(WColor.BackgroundRipple.color, 16f.dp)
        }
        containerView.setBackgroundColor(
            WColor.GroupedBackground.color,
            ViewConstants.STANDARD_ROUNDS.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }
}
