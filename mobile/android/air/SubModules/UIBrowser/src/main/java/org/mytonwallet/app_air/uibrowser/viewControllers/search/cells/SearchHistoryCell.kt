package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.content.res.AppCompatResources
import androidx.core.net.toUri
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.timeAgo
import org.mytonwallet.app_air.walletcore.models.MExploreHistory
import java.util.Date

@SuppressLint("ViewConstructor")
class SearchHistoryCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView {

    private val historyDrawable: Drawable? = AppCompatResources.getDrawable(
        context,
        org.mytonwallet.app_air.uicomponents.R.drawable.ic_history
    )

    private val historyImageView: WCustomImageView by lazy {
        WCustomImageView(context).apply {
            id = generateViewId()
            defaultRounding = Content.Rounding.Radius(6f.dp)
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
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
        addView(historyImageView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(historyImageView, 18f)
            toCenterY(historyImageView)
            toStart(titleLabel, 56f)
            toTop(titleLabel, 9.5f)
            toEnd(titleLabel, 12f)
            toStart(subtitleLabel, 56f)
            topToBottom(subtitleLabel, titleLabel, 1f)
            toEnd(subtitleLabel, 12f)
        }
    }

    var isLastItem = false

    @SuppressLint("SetTextI18n")
    fun configure(site: MExploreHistory.VisitedSite, isLastItem: Boolean, onTap: () -> Unit) {
        this.isLastItem = isLastItem
        setOnClickListener {
            onTap()
        }

        historyImageView.clear()
        historyImageView.set(Content.ofUrl(site.favicon))
        titleLabel.setStyle(16f, WFont.SemiBold)
        titleLabel.text = site.title
        subtitleLabel.text =
            "${site.url.toUri().host} · ${Date(site.visitDate).timeAgo("\$visited_ago")}"

        updateTheme()
    }

    @SuppressLint("SetTextI18n")
    fun configure(site: MExploreHistory.HistoryItem, isLastItem: Boolean, onTap: () -> Unit) {
        this.isLastItem = isLastItem
        setOnClickListener {
            onTap()
        }

        historyImageView.clear()
        historyImageView.setImageDrawable(historyDrawable)
        titleLabel.setStyle(16f, WFont.Regular)
        titleLabel.text = site.title
        subtitleLabel.text = site.visitDate?.let { visitDate -> Date(visitDate).timeAgo() }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.BackgroundRipple.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        historyDrawable?.setTint(WColor.SecondaryText.color)
    }

}
