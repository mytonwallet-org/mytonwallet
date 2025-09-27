package org.mytonwallet.app_air.uiwidgets.configurations.priceWidget

import android.content.Context
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uiwidgets.configurations.WidgetConfigurationVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

class PriceWidgetConfigurationVC(
    context: Context,
    override val appWidgetId: Int,
    override val onResult: (ok: Boolean) -> Unit
) :
    WidgetConfigurationVC(context) {

    val continueButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Continue")
        setOnClickListener {
            onResult(true)
        }
    }

    override fun setupViews() {
        super.setupViews()

        title = LocaleController.getString("Customize Widget")
        setupNavBar(true)

        view.addView(continueButton)
        view.setConstraints {
            toCenterX(continueButton, 32f)
            toBottomPx(
                continueButton,
                navigationController?.getSystemBars()?.bottom ?: 0
            )
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
    }

}
