package org.mytonwallet.app_air.uisettings.viewControllers.settings.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlin.math.roundToInt

interface ISettingsItemCell {
    fun configure(
        item: SettingsItem,
        subtitle: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    )
}

@SuppressLint("ViewConstructor")
class SettingsItemCell(
    context: Context,
    textLeadingMargin: Float = 64f,
    private val baseContentHeight: Float = BASE_CONTENT_HEIGHT
) : WCell(context),
    ISettingsItemCell, WThemedView {

    companion object {
        private const val BASE_CONTENT_HEIGHT = 50f
        const val SIMPLE_ROW_HEIGHT = 50f

        fun contentHeightForItem(
            baseContentHeight: Float = BASE_CONTENT_HEIGHT,
            isSubtitled: Boolean,
        ): Int {
            return (
                baseContentHeight +
                    (if (isSubtitled) 10 else 0)
                ).dp.roundToInt()
        }

        fun cellHeightForItem(
            baseContentHeight: Float = BASE_CONTENT_HEIGHT,
            isSubtitled: Boolean,
            isLast: Boolean,
        ): Int {
            return contentHeightForItem(baseContentHeight, isSubtitled) +
                (if (isLast) ViewConstants.GAP.dp else 0)
        }
    }

    private var isFirst = false
    private var isLast = false

    val iconView: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(16f)
            setSingleLine()
            setTextColor(WColor.PrimaryText)
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    private val subtitleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(13f)
            setSingleLine()
            setTextColor(WColor.SecondaryText)
            ellipsize = TextUtils.TruncateAt.END
        }
    }

    private val titleView: LinearLayout by lazy {
        LinearLayout(context).apply {
            id = generateViewId()
            orientation = LinearLayout.VERTICAL
            addView(titleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitleLabel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 1.dp
            })
        }
    }

    private val valueLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl
    }

    private val contentView = WView(context).apply {
        addView(iconView, LayoutParams(28.dp, 28.dp))
        addView(titleView, LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        addView(valueLabel)

        setConstraints {
            toStart(iconView, 18f)
            toCenterY(iconView)
            toStart(titleView, textLeadingMargin)
            toCenterY(titleView, 16f)
            endToStart(titleView, valueLabel, 8f)
            toEnd(valueLabel, 20f)
            toCenterY(valueLabel, 16f)
        }
    }

    init {
        super.setupViews()

        addView(contentView, LayoutParams(MATCH_PARENT, baseContentHeight.dp.roundToInt()))
        setConstraints {
            toTop(contentView)
            toCenterX(contentView)
        }

        updateTheme()
    }

    override fun configure(
        item: SettingsItem,
        subtitle: String?,
        isFirst: Boolean,
        isLast: Boolean,
        onTap: () -> Unit
    ) {
        this.isFirst = isFirst
        this.isLast = isLast

        if (item.icon != null)
            iconView.setImageDrawable(ContextCompat.getDrawable(context, item.icon)?.apply {
                if (item.hasTintColor)
                    setTint(WColor.SecondaryText.color)
            })
        else {
            iconView.setImageDrawable(null)
        }
        titleLabel.text = item.title
        valueLabel.text = item.value
        subtitleLabel.text = subtitle
        subtitleLabel.isGone = subtitle.isNullOrEmpty()

        contentView.layoutParams.height =
            contentHeightForItem(baseContentHeight, !subtitle.isNullOrEmpty())
        layoutParams.height =
            cellHeightForItem(baseContentHeight, !subtitle.isNullOrEmpty(), isLast)

        setOnClickListener {
            onTap()
        }

        updateTheme()
    }

    override fun updateTheme() {
        contentView.setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )
        contentView.addRippleEffect(
            WColor.SecondaryBackground.color,
            if (isFirst) ViewConstants.BLOCK_RADIUS.dp else 0f.dp,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f.dp
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        valueLabel.setTextColor(WColor.SecondaryText.color)
    }
}
