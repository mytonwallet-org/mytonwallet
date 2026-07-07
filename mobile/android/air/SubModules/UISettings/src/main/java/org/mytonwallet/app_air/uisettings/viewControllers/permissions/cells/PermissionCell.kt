package org.mytonwallet.app_air.uisettings.viewControllers.permissions.cells

import android.content.Context
import android.text.TextUtils
import android.util.TypedValue
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatTextView
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class PermissionCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, WRAP_CONTENT)), WThemedView {

    private val lastItemRadius = (ViewConstants.BLOCK_RADIUS - 1.5f).dp

    private val imageView = WCustomImageView(context).apply {
        layoutParams = LayoutParams(40.dp, 40.dp)
        defaultRounding = Content.Rounding.Radius(20f.dp)
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(adaptiveFontSize(), WFont.Medium)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        maxLines = 1
    }

    private val subtitleLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val amountLabel = AppCompatTextView(context).apply {
        id = generateViewId()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setLineHeight(TypedValue.COMPLEX_UNIT_SP, 16f)
        includeFontPadding = false
        ellipsize = TextUtils.TruncateAt.END
        typeface = WFont.Medium.typeface
        maxLines = 1
    }

    private val mainView = WView(context, LayoutParams(MATCH_PARENT, 60.dp)).apply {
        addView(imageView)
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
        addView(amountLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toCenterY(imageView)
            toStart(imageView, 12f)
            // Title/subtitle are a vertically-centered pair, independent of the
            // (optionally hidden) icon.
            toTop(titleLabel, 10f)
            startToEnd(titleLabel, imageView, 12f)
            endToStart(titleLabel, amountLabel, 12f)
            topToBottom(subtitleLabel, titleLabel, 2f)
            startToEnd(subtitleLabel, imageView, 12f)
            endToStart(subtitleLabel, amountLabel, 12f)
            toCenterY(amountLabel)
            toEnd(amountLabel, 16f)
        }
    }

    private var isFirst = false
    private var isLast = false
    private var onTap: (() -> Unit)? = null

    init {
        addView(mainView)
        setConstraints {
            allEdges(mainView)
        }
        updateTheme()
    }

    override fun updateTheme() {
        mainView.setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.TOOLBAR_RADIUS.dp else 0f,
            if (isLast) lastItemRadius else 0f
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
        amountLabel.setTextColor(WColor.SecondaryText.color)
    }

    private fun applyTextStartConstraints(hasImage: Boolean) {
        mainView.setConstraints {
            if (hasImage) {
                startToEnd(titleLabel, imageView, 12f)
                startToEnd(subtitleLabel, imageView, 12f)
            } else {
                toStart(titleLabel, 16f)
                toStart(subtitleLabel, 16f)
            }
        }
    }

    fun configure(
        iconUrl: String?,
        title: String,
        subtitle: String,
        amount: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: (() -> Unit)?
    ) {
        this.isFirst = isFirst
        this.isLast = isLast
        this.onTap = onTap
        val hasImage = iconUrl != null
        if (hasImage) {
            imageView.visibility = VISIBLE
            imageView.set(Content(image = Content.Image.Url(iconUrl!!)))
        } else {
            imageView.clear()
            imageView.visibility = GONE
        }
        applyTextStartConstraints(hasImage)
        titleLabel.text = title
        subtitleLabel.text = subtitle
        amountLabel.visibility = if (amount != null) VISIBLE else GONE
        amountLabel.text = amount ?: ""
        mainView.setOnClickListener(
            if (onTap != null) {
                { onTap.invoke() }
            } else null
        )
        mainView.isClickable = onTap != null
        updateTheme()
    }
}
