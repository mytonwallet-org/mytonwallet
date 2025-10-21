package org.mytonwallet.app_air.uicomponents.commonViews

import android.content.Context
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.solidColorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MAccount
import kotlin.math.roundToInt

class WalletTypeView(context: Context) : FrameLayout(context) {

    private var eyeDrawable: Drawable? = null
    private var eyeImageView: AppCompatImageView? = null
    private var viewLabel: WLabel? = null
    private var viewTagView: LinearLayout? = null

    private var hardwareDrawable: Drawable? = null
    private var hardwareTagView: AppCompatImageView? = null

    init {
        id = generateViewId()
    }

    fun configure(account: MAccount?) {
        val account = account ?: run {
            isGone = true
            return
        }
        if (account.isViewOnly) {
            configureViewTagView()
            return
        }
        if (account.isHardware) {
            configureHardwareTagView()
            return
        }
        isGone = true
    }

    private var color = WColor.White.color
    fun setColor(newColor: Int) {
        color = newColor
        eyeDrawable?.setTint(newColor)
        viewLabel?.setTextColor(newColor)
        hardwareDrawable?.setTint(newColor)
        if (viewTagView?.isVisible == true) {
            setBackgroundColor(color.solidColorWithAlpha(41), 10f.dp)
        }
    }

    private fun configureViewTagView() {
        isGone = false
        hardwareTagView?.isGone = true
        if (viewTagView == null) {
            eyeDrawable = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye
            )?.apply {
                setTint(color)
            }
            eyeImageView = AppCompatImageView(context).apply {
                setImageDrawable(eyeDrawable)
            }
            viewLabel = WLabel(context).apply {
                text = LocaleController.getString("View")
                setStyle(12f, WFont.SemiBold)
                setTextColor(color)
                setPaddingLocalized(2.dp, 0, 0, 0)
            }
            viewTagView = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                addView(eyeImageView)
                addView(viewLabel)
                setPadding(4.5f.dp.roundToInt(), 0, 4.5f.dp.roundToInt(), 0)
            }
            addView(viewTagView, LayoutParams(LayoutParams.WRAP_CONTENT, 20.dp))
        } else {
            viewTagView?.isGone = false
        }
        setBackgroundColor(color.solidColorWithAlpha(41), 10f.dp)
    }

    private fun configureHardwareTagView() {
        isGone = false
        viewTagView?.isGone = true
        if (hardwareTagView == null) {
            hardwareDrawable = ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_ledger
            )?.apply {
                setTint(color)
            }
            hardwareTagView = AppCompatImageView(context).apply {
                setImageDrawable(hardwareDrawable)
            }
            addView(
                hardwareTagView, LayoutParams(
                    LayoutParams.WRAP_CONTENT,
                    LayoutParams.WRAP_CONTENT
                )
            )
        } else {
            hardwareTagView?.isGone = false
        }
        background = null
    }
}
