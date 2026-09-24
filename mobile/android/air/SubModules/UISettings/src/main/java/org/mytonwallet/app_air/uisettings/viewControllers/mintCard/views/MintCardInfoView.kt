package org.mytonwallet.app_air.uisettings.viewControllers.mintCard.views

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.walletcore.models.MCardInfo

@SuppressLint("ViewConstructor")
class MintCardInfoView(context: Context) : LinearLayout(context) {

    private val typeLabel = WLabel(context).apply {
        setStyle(20f, WFont.Medium)
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
    }

    private val availabilityView = MintCardAvailabilityView(context)

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(typeLabel, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(
            availabilityView,
            LayoutParams(MATCH_PARENT, 36.dp).apply { topMargin = 17.dp }
        )
    }

    fun setupBlur(rootView: ViewGroup) {
        availabilityView.setupBlur(rootView)
    }

    fun configure(title: String, cardInfo: MCardInfo?, isComingSoon: Boolean) {
        typeLabel.text = title
        val showsCountdown = cardInfo?.mintStartsAtMillis != null
        val availabilityParams = availabilityView.layoutParams as LayoutParams
        availabilityParams.topMargin = if (showsCountdown) 5.dp else 17.dp
        availabilityView.layoutParams = availabilityParams
        setPadding(0, 0, 0, if (showsCountdown) 28.dp else 16.dp)
        availabilityView.configure(cardInfo, isComingSoon)
    }
}
