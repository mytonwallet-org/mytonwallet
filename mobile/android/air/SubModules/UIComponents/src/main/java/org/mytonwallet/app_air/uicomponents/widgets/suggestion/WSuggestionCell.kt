package org.mytonwallet.app_air.uicomponents.widgets.suggestion

import android.content.Context
import android.graphics.Color
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class WSuggestionCell(context: Context) : WCell(context, LayoutParams(WRAP_CONTENT, MATCH_PARENT)),
    WThemedView {

    var onTap: ((text: String) -> Unit)? = null

    private val titleLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(15f)
        lbl.maxLines = 1
        lbl
    }

    init {
        setPadding(16.dp, 12.dp, 16.dp, 12.dp)

        addView(titleLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))

        setConstraints {
            allEdges(titleLabel)
        }

        setOnClickListener {
            onTap?.invoke(titleLabel.text.toString())
        }

        updateTheme()
    }

    override fun updateTheme() {
        setBackgroundColor(Color.TRANSPARENT)
        addRippleEffect(WColor.SecondaryBackground.color, 6f.dp)
        titleLabel.setTextColor(WColor.PrimaryText.color)
    }

    fun configure(
        text: String,
    ) {
        titleLabel.text = text
    }

}
