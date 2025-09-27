package org.mytonwallet.app_air.uiwidgets.configurations

import android.content.Context
import org.mytonwallet.app_air.uicomponents.base.WViewController

abstract class WidgetConfigurationVC(
    context: Context
) : WViewController(context) {

    abstract val appWidgetId: Int
    abstract val onResult: (ok: Boolean) -> Unit

}
