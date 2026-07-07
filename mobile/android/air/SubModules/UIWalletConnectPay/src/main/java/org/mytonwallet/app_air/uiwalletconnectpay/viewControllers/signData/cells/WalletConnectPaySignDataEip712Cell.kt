package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.views.Eip712ObjectView
import org.mytonwallet.app_air.walletcore.moshi.MSignDataPayload.SignDataPayloadEip712.TypeField

@SuppressLint("ViewConstructor")
class WalletConnectPaySignDataEip712Cell(context: Context) : WCell(
    context,
    android.view.ViewGroup.LayoutParams(
        LayoutParams.MATCH_PARENT,
        WRAP_CONTENT
    )
), WThemedView {

    private var topRadius = 0f
    private var bottomRadius = 0f
    private var objectView: View? = null

    override fun updateTheme() {
        setBackgroundColor(WColor.Background.color, topRadius, bottomRadius)
    }

    fun configure(
        obj: Map<String, Any?>,
        typeName: String,
        types: Map<String, List<TypeField>>,
        topRadius: Float,
        bottomRadius: Float,
    ) {
        this.topRadius = topRadius
        this.bottomRadius = bottomRadius
        objectView?.let { removeView(it) }
        val view = Eip712ObjectView(context, obj, typeName, types).apply {
            id = generateViewId()
        }
        objectView = view
        addView(view, LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(view, 14f)
            toBottom(view, 14f)
            toCenterX(view, 16f)
        }
        updateTheme()
    }
}
