package org.mytonwallet.app_air.uibrowser.viewControllers.explore.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
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
            cellWidth
        )
    ),
    WThemedView {

    private val imageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(16f.dp)
        set(
            Content.ofUrl(
                site.extendedIcon.ifBlank { site.icon ?: "" }
            )
        )
    }

    private val thumbImageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(16f.dp)
        site.icon?.let {
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
        setStyle(12f, WFont.Medium)
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
        fadeSide = null,
        overrideBlurRadius = 30f
    ).apply {
        setupWith(this@ExploreTrendingItemCell)
        setOverlayColor(WColor.Black, 130)
    }

    private val openButtonRipple = WRippleDrawable.create(16f.dp)
    private val openButton = WLabel(context).apply {
        setStyle(16f, WFont.SemiBold)
        text =
            LocaleController.getString("Open")
        gravity = Gravity.CENTER
        background = openButtonRipple
        setOnClickListener {
            onSiteTap(site)
        }
    }

    private val bottomView = WView(context).apply {
        setBackgroundColor(Color.TRANSPARENT, 0f, 16f.dp, true)
        addView(bottomBlurView, ViewGroup.LayoutParams(0, 0))
        if (site.extendedIcon.isNotBlank()) {
            addView(thumbImageView, ViewGroup.LayoutParams(48.dp, 48.dp))
            addView(openButton, ViewGroup.LayoutParams(65.dp, 32.dp))
        }
        addView(textsContainerView, ViewGroup.LayoutParams(0, WRAP_CONTENT))

        setConstraints {
            allEdges(bottomBlurView)
            toStart(thumbImageView, 20f)
            toCenterY(thumbImageView)
            toCenterY(textsContainerView)
            toCenterX(textsContainerView)
            toStart(textsContainerView, if (site.extendedIcon.isNotBlank()) 78f else 8f)
            if (site.extendedIcon.isNotBlank()) {
                toEnd(openButton, 20f)
                toCenterY(openButton)
                endToStart(textsContainerView, openButton, 4f)
            } else {
                toEnd(textsContainerView, 8f)
            }
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
        addView(imageView, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        addView(bottomView, ViewGroup.LayoutParams(MATCH_PARENT, 60.dp))

        setConstraints {
            allEdges(imageView)
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
        openButton.setTextColor(WColor.White)
        openButtonRipple.apply {
            backgroundColor = Color.WHITE.colorWithAlpha(25)
            rippleColor = Color.WHITE.colorWithAlpha(50)
        }
        if (site.withBorder) {
            val border = GradientDrawable()
            border.setColor(WColor.Tint.color)
            border.setStroke(1, WColor.Tint.color)
            border.cornerRadius = 16f.dp
            contentView.background = border
        }
        if (site.badgeText.isNotBlank()) {
            badgeLabel.setBackgroundColor(WColor.Tint.color, 4f.dp, true)
            badgeLabel.setTextColor(WColor.TextOnTint.color)
        }
    }
}
