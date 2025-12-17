package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ceilToInt

class WordListItemView(
    context: Context,
) : WView(context), WThemedView {

    private val indexLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setLineSpacing(4f.dp, 1f)
        lbl.setStyle(17F)
        lbl
    }

    private val wordLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setLineSpacing(4f.dp, 1f)
        lbl.setStyle(17F, WFont.SemiBold)
        lbl.gravity = Gravity.LEFT
        lbl
    }

    fun setupViews(index: String, word: String) {
        addView(
            indexLabel,
            LayoutParams(indexLabel.paint.measureText("88.").ceilToInt(), WRAP_CONTENT)
        )
        addView(wordLabel, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        setConstraints {
            toTop(indexLabel)
            toStart(indexLabel)
            toTop(wordLabel)
            toEnd(wordLabel)
            startToEnd(wordLabel, indexLabel, 4F)
        }

        indexLabel.text = index
        wordLabel.text = word

        updateTheme()
    }

    override fun updateTheme() {
        indexLabel.setTextColor(WColor.SecondaryText.color)
        wordLabel.setTextColor(WColor.PrimaryText.color)
    }
}
