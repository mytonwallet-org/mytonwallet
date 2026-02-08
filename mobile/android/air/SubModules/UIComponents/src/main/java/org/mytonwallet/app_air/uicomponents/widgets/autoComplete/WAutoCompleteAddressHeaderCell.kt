package org.mytonwallet.app_air.uicomponents.widgets.autoComplete

import android.annotation.SuppressLint
import android.content.Context
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell.TopRounding
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

@SuppressLint("ViewConstructor")
class WAutoCompleteAddressHeaderCell(context: Context) :
    WCell(context, LayoutParams(MATCH_PARENT, 40.dp)),
    IAutoCompleteAddressItemCell, WThemedView {

    private val label: HeaderCell by lazy {
        HeaderCell(context, 20f).apply {
            titleLabel.setStyle(14f, WFont.DemiBold)
        }
    }

    init {
        super.setupViews()

        addView(label, LayoutParams(MATCH_PARENT, 40.dp))
        setConstraints {
            toStart(label)
            toEnd(label)
            toTop(label)
        }

        updateTheme()
    }

    override fun configure(
        item: AutoCompleteAddressItem,
        isLast: Boolean,
        onTap: () -> Unit,
        onLongClick: (() -> Unit)?
    ) {
        label.configure(
            title = item.title,
            titleColor = WColor.Tint,
            topRounding = TopRounding.FIRST_ITEM
        )
        updateTheme()
    }

    override fun updateTheme() {
        label.updateTheme()
    }
}
