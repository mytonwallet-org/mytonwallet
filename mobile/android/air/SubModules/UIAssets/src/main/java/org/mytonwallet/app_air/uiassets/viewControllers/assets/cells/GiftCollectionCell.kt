package org.mytonwallet.app_air.uiassets.viewControllers.assets.cells

import android.content.Context
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor

class GiftCollectionCell(context: Context) :
    WCell(context, ViewGroup.LayoutParams(MATCH_PARENT, 88.dp)), WThemedView {
    private val title = WLabel(context).apply { setStyle(17f, WFont.Medium) }
    private val subtitle = WLabel(context).apply { setStyle(14f) }

    init {
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(16.dp, 12.dp, 16.dp, 12.dp)
            addView(title, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(subtitle, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        addView(content, ViewGroup.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        updateTheme()
    }

    fun configure(name: String, detail: String, onOpen: (() -> Unit)?) {
        updateTheme()
        title.text = name
        subtitle.text = detail
        contentDescription = "$name, $detail"
        setOnClickListener(if (onOpen == null) null else android.view.View.OnClickListener { onOpen() })
        isClickable = onOpen != null
        isFocusable = onOpen != null
    }

    override fun updateTheme() {
        title.setTextColor(WColor.PrimaryText)
        subtitle.setTextColor(WColor.SecondaryText)
    }
}
