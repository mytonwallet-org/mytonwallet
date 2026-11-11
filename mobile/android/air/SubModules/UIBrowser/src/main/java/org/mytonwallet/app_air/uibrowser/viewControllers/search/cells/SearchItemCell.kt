package org.mytonwallet.app_air.uibrowser.viewControllers.search.cells

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.view.isGone
import org.mytonwallet.app_air.uicomponents.R as UIComponentsR
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.adaptiveFontSize
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class SearchItemCell(
    context: Context,
    iconRes: Int = org.mytonwallet.app_air.icons.R.drawable.ic_search_24,
    private val iconColor: WColor = WColor.SecondaryText,
    private val onTap: (keyword: String) -> Unit
) : WCell(context, LayoutParams(MATCH_PARENT, 50.dp)),
    WThemedView {

    private val iconDrawable: Drawable? =
        AppCompatResources.getDrawable(
            context,
            iconRes
        )?.mutate()?.apply {
            setTint(iconColor.color)
        }

    private val iconImageView: AppCompatImageView by lazy {
        AppCompatImageView(context).apply {
            id = generateViewId()
            setImageDrawable(iconDrawable)
        }
    }

    private val titleLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(adaptiveFontSize(), WFont.Regular)
            setSingleLine()
            ellipsize = TextUtils.TruncateAt.END
            setTextColor(WColor.PrimaryText)
        }
    }

    override fun setupViews() {
        super.setupViews()
        id = UIComponentsR.id.search_item_row
        addView(iconImageView, LayoutParams(24.dp, 24.dp))
        addView(titleLabel, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toStart(iconImageView, 16f)
            toCenterY(iconImageView)
            setHorizontalBias(titleLabel.id, 0f)
            toStart(titleLabel, 56f)
            toEnd(titleLabel, 16f)
            toCenterY(titleLabel)
        }

        setOnClickListener {
            onTap(keyword)
        }

        updateTheme()
    }

    var keyword = ""
    var isLastItem = false
    private var hasOpaqueBackground = true
    fun configure(keyword: String, isLastItem: Boolean, hasOpaqueBackground: Boolean = true) {
        this.keyword = keyword
        this.isLastItem = isLastItem
        this.hasOpaqueBackground = hasOpaqueBackground
        titleLabel.text = keyword
        updateTheme()
    }

    override fun updateTheme() {
        iconDrawable?.setTint(iconColor.color)
        setBackgroundColor(
            if (hasOpaqueBackground) WColor.Background.color else WColor.Transparent.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
        addRippleEffect(
            WColor.BackgroundRipple.color,
            0f,
            if (isLastItem) ViewConstants.BLOCK_RADIUS.dp else 0f
        )
    }
}
