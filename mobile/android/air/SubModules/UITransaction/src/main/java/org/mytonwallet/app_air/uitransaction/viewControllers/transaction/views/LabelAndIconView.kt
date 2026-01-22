package org.mytonwallet.app_air.uitransaction.viewControllers.transaction.views

import android.content.Context
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView

class LabelAndIconView(context: Context) : WView(context) {

    val lbl = WLabel(context)
    val img = WCustomImageView(context).apply {
        chainSize = 10.dp
    }

    override fun setupViews() {
        super.setupViews()

        addView(lbl, LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        addView(img, LayoutParams(30.dp, 30.dp))

        setConstraints {
            toStart(lbl)
            toCenterY(lbl)
            startToEnd(img, lbl, 8f)
            toBottom(img, 6f)
            toEnd(img)
        }
    }

    fun configure(text: CharSequence, content: Content) {
        lbl.text = text
        img.set(content)
    }
}
