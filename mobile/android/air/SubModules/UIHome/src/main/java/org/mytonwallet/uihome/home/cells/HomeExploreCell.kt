package org.mytonwallet.uihome.home.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatImageView
import org.mytonwallet.app_air.icons.R as IconsR
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.PerpsAvailability

@SuppressLint("ViewConstructor")
class HomeExploreCell(
    context: Context,
    private val onMarketTap: () -> Unit,
    private val onFuturesTap: () -> Unit,
    private val onAppsTap: () -> Unit
) : WCell(context, LayoutParams(MATCH_PARENT, HEIGHT.dp)),
    WThemedView {

    companion object {
        private const val TITLE_HEIGHT = 40
        private const val ROW_HEIGHT = 60
        private val ROW_COUNT = if (PerpsAvailability.isAvailable()) 3 else 2
        val HEIGHT = TITLE_HEIGHT + ROW_COUNT * ROW_HEIGHT
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(14f, WFont.Medium)
        text = LocaleController.getString("Explore")
    }

    private val rows = listOfNotNull(
        Row(
            context,
            IconsR.drawable.ic_explore_market,
            LocaleController.getString("Market"),
            LocaleController.getString("\$perps_explore_market"),
            onMarketTap
        ),
        if (PerpsAvailability.isAvailable()) {
            Row(
                context,
                IconsR.drawable.ic_explore_futures,
                LocaleController.getString("Futures"),
                LocaleController.getString("\$perps_explore_futures"),
                onFuturesTap
            )
        } else {
            null
        },
        Row(
            context,
            IconsR.drawable.ic_explore_apps,
            LocaleController.getString("Apps"),
            LocaleController.getString("\$perps_explore_apps"),
            onAppsTap
        )
    )

    override fun setupViews() {
        super.setupViews()
        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        rows.forEach { addView(it, LayoutParams(MATCH_PARENT, ROW_HEIGHT.dp)) }
        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            rows.forEachIndexed { index, row ->
                toTop(row, (TITLE_HEIGHT + index * ROW_HEIGHT).toFloat())
                toCenterX(row)
            }
        }
        updateTheme()
    }

    private var appliedRadius: Float? = null
    private var appliedBackgroundColor: Int? = null

    override fun updateTheme() {
        val radius = ViewConstants.BLOCK_RADIUS.dp
        val backgroundColor = WColor.Background.color
        if (appliedRadius != radius || appliedBackgroundColor != backgroundColor) {
            appliedRadius = radius
            appliedBackgroundColor = backgroundColor
            setBackgroundColor(backgroundColor, radius, true)
        }
        titleLabel.setTextColor(WColor.Tint.color)
        rows.forEach { it.updateTheme() }
    }

    @SuppressLint("ViewConstructor")
    private class Row(
        context: Context,
        iconRes: Int,
        title: String,
        subtitle: String,
        onTap: () -> Unit
    ) : WView(context),
        WThemedView {

        private val ripple = WRippleDrawable.create(0f)

        private val iconView = AppCompatImageView(context).apply {
            id = generateViewId()
            setImageResource(iconRes)
        }

        private val titleLabel = WLabel(context).apply {
            setStyle(adaptiveFontSize())
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            text = title
        }

        private val subtitleLabel = WLabel(context).apply {
            setStyle(14f)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            text = subtitle
        }

        init {
            background = ripple
            addView(iconView, LayoutParams(28.dp, 28.dp))
            addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
            addView(subtitleLabel, LayoutParams(0, WRAP_CONTENT))
            setConstraints {
                toStart(iconView, 18f)
                toCenterY(iconView)
                startToEnd(titleLabel, iconView, 18f)
                toEnd(titleLabel, 20f)
                startToEnd(subtitleLabel, iconView, 18f)
                toEnd(subtitleLabel, 20f)
                toTop(titleLabel, 9f)
                toBottom(subtitleLabel, 9f)
            }
            setOnClickListener { onTap() }
        }

        override fun updateTheme() {
            ripple.rippleColor = WColor.BackgroundRipple.color
            titleLabel.setTextColor(WColor.PrimaryText.color)
            subtitleLabel.setTextColor(WColor.SecondaryText.color)
        }
    }
}
