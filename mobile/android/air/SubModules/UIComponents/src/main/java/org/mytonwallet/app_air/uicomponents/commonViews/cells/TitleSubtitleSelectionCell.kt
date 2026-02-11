package org.mytonwallet.app_air.uicomponents.commonViews.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class TitleSubtitleSelectionCell(
    context: Context
) : WCell(context, LayoutParams(MATCH_PARENT, 60.dp)), WThemedView {

    private val selectionImageView: AppCompatImageView by lazy {
        val img = AppCompatImageView(context)
        img.id = generateViewId()
        img
    }

    private val titleLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl
    }

    private val subtitleLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(13f)
        lbl
    }

    override fun setupViews() {
        super.setupViews()

        addView(selectionImageView, LayoutParams(40.dp, 40.dp))
        addView(titleLabel)
        addView(subtitleLabel)
        setConstraints {
            toCenterY(selectionImageView)
            toStart(selectionImageView, 12f)
            toTop(titleLabel, 7.75f)
            toStart(titleLabel, 64f)
            toTop(subtitleLabel, 31.75f)
            toStart(subtitleLabel, 64f)
        }

        setOnClickListener {
            onClick()
        }
    }

    override fun updateTheme() {
        setBackgroundColor(
            WColor.Background.color,
            if (isFirst) ViewConstants.TOOLBAR_RADIUS.dp else 0f,
            if (isLast) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(WColor.SecondaryBackground.color)
        selectionImageView.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                if (isSelected) R.drawable.ic_radio_fill else R.drawable.ic_radio
            )?.apply {
                setTint(if (isSelected) WColor.Tint.color else WColor.Separator.color)
            }
        )
        titleLabel.setTextColor(WColor.PrimaryText.color)
        subtitleLabel.setTextColor(WColor.SecondaryText.color)
    }

    private var isSelected = true
    private var isFirst = false
    private var isLast = false
    private lateinit var onClick: () -> Unit

    fun configure(
        title: String,
        subtitle: String,
        isSelected: Boolean,
        isFirst: Boolean,
        isLast: Boolean,
        onClick: () -> Unit
    ) {
        this.isSelected = isSelected
        this.isFirst = isFirst
        this.isLast = isLast
        updateTheme()
        titleLabel.text = title
        subtitleLabel.text = subtitle
        this.onClick = onClick
    }

}
