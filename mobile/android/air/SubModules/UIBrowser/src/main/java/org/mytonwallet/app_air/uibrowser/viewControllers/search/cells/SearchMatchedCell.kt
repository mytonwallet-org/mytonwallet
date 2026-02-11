package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.net.toUri
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.timeAgo
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import java.util.Date

@SuppressLint("ViewConstructor")
class SearchMatchedCell(
    context: Context,
    private val onTap: (site: MExploreHistory.VisitedSite) -> Unit
) :
    WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView {

    private val logoImageView: WCustomImageView by lazy {
        WCustomImageView(context).apply {
            defaultRounding = Content.Rounding.Radius(6f.dp)
            defaultPlaceholder =
                Content.Placeholder.Color(WColor.Transparent)
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f, WFont.SemiBold)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.PrimaryText)
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(12f, WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.SecondaryText)
        }
    }

    override fun setupViews() {
        super.setupViews()
        addView(logoImageView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(logoImageView, 18f)
            toCenterY(logoImageView)
            toStart(titleLabel, 56f)
            toTop(titleLabel, 9.5f)
            toEnd(titleLabel, 12f)
            toStart(subtitleLabel, 56f)
            topToBottom(subtitleLabel, titleLabel, 1f)
            toEnd(subtitleLabel, 12f)
        }

        setOnClickListener {
            site?.let {
                onTap(it)
            }
        }
    }

    var site: MExploreHistory.VisitedSite? = null

    @SuppressLint("SetTextI18n")
    fun configure(site: MExploreHistory.VisitedSite) {
        this.site = site

        logoImageView.set(Content.ofUrl(site.favicon))
        titleLabel.text = site.title
        subtitleLabel.text =
            site.url.toUri().host + " · " + Date(site.visitDate).timeAgo("\$visited_ago")

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.PrimaryText.color.colorWithAlpha(15),
            ViewConstants.BLOCK_RADIUS.dp
        )
        addRippleEffect(
            WColor.BackgroundRipple.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

}
