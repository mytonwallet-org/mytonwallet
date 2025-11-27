package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFadedEdgeView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MExploreSite

@SuppressLint("ViewConstructor")
class ExploreTrendingItemCell(
    context: Context,
    cellWidth: Int,
    val site: MExploreSite,
    private val onSiteTap: (site: MExploreSite) -> Unit,
) :
    WView(
        context,
        LayoutParams(
            if (site.extendedIcon.isNotBlank()) cellWidth * 2 else cellWidth,
            cellWidth + 12.dp
        )
    ),
    WThemedView {

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(22f.dp)
        set(
            Content.ofUrl(
                site.extendedIcon.ifBlank { site.iconUrl ?: "" }
            )
        )
    }

    private val imageViewContainer = FrameLayout(context).apply {
        id = generateViewId()
        addView(imageView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private val thumbImageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(12f.dp)
        site.iconUrl?.let {
            set(Content.ofUrl(it))
        }
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(15f, WFont.SemiBold)
        text = site.name
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.MARQUEE
        isHorizontalFadingEdgeEnabled = true
        isSelected = true
    }

    private val subtitleLabel = WLabel(context).apply {
        setStyle(13f, WFont.Medium)
        text = site.description
        maxLines = 2
        ellipsize = TextUtils.TruncateAt.END
    }

    private val textsContainerView = WView(context).apply {
        addView(titleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(titleLabel)
            topToBottom(subtitleLabel, titleLabel)
            toBottom(subtitleLabel, 1f)
        }
    }

    private val bottomBlurView = WBlurryBackgroundView(
        context,
        fadeSide = WBlurryBackgroundView.Side.TOP,
        overrideBlurRadius = 30f
    ).apply {
        setupWith(imageViewContainer)
        setOverlayColor(WColor.Transparent, 130)
    }

    private val bottomBlurContainerView = WFadedEdgeView(context).apply {
        id = generateViewId()
        addView(bottomBlurView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    private val bottomView = WView(context).apply {
        setBackgroundColor(Color.TRANSPARENT, 0f, 22f.dp, true)
        addView(bottomBlurContainerView, ViewGroup.LayoutParams(0, 0))
        if (site.extendedIcon.isNotBlank()) {
            addView(thumbImageView, ViewGroup.LayoutParams(48.dp, 48.dp))
        }
        addView(textsContainerView, ViewGroup.LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            allEdges(bottomBlurContainerView)
            toStart(thumbImageView, 16f)
            toCenterY(thumbImageView)
            toCenterY(textsContainerView)
            toCenterX(textsContainerView)
            toStart(textsContainerView, if (site.extendedIcon.isNotBlank()) 75f else 12f)
            toEnd(textsContainerView, 12f)
        }
    }

    private val badgeLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Medium)
            setPadding(2.dp, 0, 2.dp, 2)
            text = site.badgeText
        }
    }

    private val contentView = WView(context).apply {
        addView(imageViewContainer, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(bottomView, ViewGroup.LayoutParams(MATCH_PARENT, 80.dp))

        setConstraints {
            allEdges(imageViewContainer)
            toCenterX(bottomView)
            toBottom(bottomView)
        }
    }

    override fun setupViews() {
        super.setupViews()

        setPadding(10.dp, 0.dp, 0.dp, 16.dp)
        addView(contentView, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        if (site.withBorder) {
            contentView.setPadding(1.dp, 1.dp, 1.dp, 1.dp)
        }
        if (site.badgeText.isNotBlank())
            addView(badgeLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(contentView, 3f)
            toBottom(contentView)
            toStart(contentView)
            toEnd(contentView, 6f)
            if (site.badgeText.isNotBlank()) {
                toEnd(badgeLabel, 3f)
                toTop(badgeLabel, 0f)
            }
        }

        contentView.setOnClickListener {
            onSiteTap(site)
        }

        updateTheme()
    }

    override fun updateTheme() {
        titleLabel.setTextColor(Color.WHITE)
        subtitleLabel.setTextColor(Color.WHITE.colorWithAlpha(153))
        if (site.withBorder) {
            val border = GradientDrawable()
            border.setColor(WColor.Tint.color)
            border.setStroke(2, WColor.Tint.color)
            border.cornerRadius = 22f.dp
            contentView.background = border
        }
        if (site.badgeText.isNotBlank()) {
            badgeLabel.setBackgroundColor(WColor.Tint.color, 4f.dp, true)
            badgeLabel.setTextColor(WColor.TextOnTint.color)
        }
    }
}
