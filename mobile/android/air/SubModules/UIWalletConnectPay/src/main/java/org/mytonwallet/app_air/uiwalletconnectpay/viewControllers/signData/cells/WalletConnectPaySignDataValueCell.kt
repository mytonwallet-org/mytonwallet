package org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.cells

import android.annotation.SuppressLint
import android.content.Context
import android.text.method.LinkMovementMethod
import android.view.Gravity
import android.widget.Toast
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color

@SuppressLint("ViewConstructor")
class WalletConnectPaySignDataValueCell(context: Context) : WCell(
    context,
    android.view.ViewGroup.LayoutParams(
        LayoutParams.MATCH_PARENT,
        LayoutParams.WRAP_CONTENT
    )
), WThemedView {

    private var topRadius = 0f
    private var bottomRadius = 0f
    private var copyLabel: String = ""

    private val textLabel = WLabel(context).apply {
        id = generateViewId()
        setStyle(16f, WFont.Medium)
        setLineHeight(22f)
        gravity = Gravity.START
        setTextIsSelectable(true)
        movementMethod = LinkMovementMethod.getInstance()
    }

    override fun setupViews() {
        super.setupViews()
        addView(textLabel, LayoutParams(0, LayoutParams.WRAP_CONTENT))
        setConstraints {
            toTop(textLabel, 12f)
            toBottom(textLabel, 12f)
            toCenterX(textLabel, 16f)
        }
        setOnLongClickListener {
            if (ClipboardHelpers.copyToClipboard(context, copyLabel, textLabel.text)) {
                Toast.makeText(
                    context,
                    LocaleController.getString("Data Copied"),
                    Toast.LENGTH_SHORT
                ).show()
            }
            true
        }
        updateTheme()
    }

    override fun updateTheme() {
        textLabel.setTextColor(WColor.PrimaryText.color)
        setBackgroundColor(WColor.Background.color, topRadius, bottomRadius)
    }

    fun configure(text: CharSequence, copyLabel: String, topRadius: Float, bottomRadius: Float) {
        this.copyLabel = copyLabel
        this.topRadius = topRadius
        this.bottomRadius = bottomRadius
        textLabel.text = text
        updateTheme()
    }
}
