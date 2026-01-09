package org.mytonwallet.app_air.uicomponents.commonViews

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.drawable.Drawable
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.widget.LinearLayout
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingLocalized
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WBlurryBackgroundView
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.helpers.DevicePerformanceClassifier
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.solidColorWithAlpha
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
open class WalletTypeView(
    context: Context,
    blurredBackground: Boolean = false
) : WFrameLayout(context) {

    private var eyeDrawable: Drawable? = null
    private var eyeImageView: AppCompatImageView? = null
    private var viewLabel: WLabel? = null
    private var viewTagView: LinearLayout? = null

    private var hardwareDrawable: Drawable? = null
    private var hardwareTagView: AppCompatImageView? = null

    private val walletTypeBlurView: WBlurryBackgroundView? =
        if (DevicePerformanceClassifier.isHighClass && blurredBackground)
            WBlurryBackgroundView(
                context,
                fadeSide = null
            ).apply {
                setOverlayColor(WColor.Transparent)
            }
        else
            null

    init {
        walletTypeBlurView?.let {
            addView(it, LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    fun setupBlurWith(viewGroup: ViewGroup) {
        walletTypeBlurView?.setupWith(viewGroup)
    }

    fun resumeBlurring() {
        walletTypeBlurView?.resumeBlurring()
    }

    fun pauseBlurring() {
        walletTypeBlurView?.pauseBlurring()
    }

    private var account: MAccount? = null
    fun configure(account: MAccount?) {
        if (this.account?.accountId == account?.accountId && this.account?.isTemporary == account?.isTemporary)
            return

        this.account = account ?: run {
            isGone = true
            return
        }

        when {
            account.isViewOnly -> configureViewTagView(account)
            account.isHardware -> configureHardwareTagView()
            else -> {
                isGone = true
                setOnClickListener(null)
            }
        }
    }

    private var backgroundColor = WColor.White.color.colorWithAlpha(41)
    private var color = WColor.White.color.colorWithAlpha(41)
    fun setColor(backgroundColor: Int, newColor: Int) {
        if (this.backgroundColor == backgroundColor && this.color == newColor) {
            return
        }

        val isTemporaryAccount = account?.isTemporary == true
        this.backgroundColor = backgroundColor
        color = newColor
        val tintColor = if (isTemporaryAccount) newColor.solidColorWithAlpha(255) else newColor
        eyeDrawable?.setTint(tintColor)
        viewLabel?.setTextColor(tintColor)
        hardwareDrawable?.setTint(newColor)
        if (viewTagView?.isVisible == true) {
            if (isTemporaryAccount) {
                (walletTypeBlurView ?: this).setBackgroundColor(
                    color = Color.TRANSPARENT,
                    radius = 14f.dp,
                    clipToBounds = true,
                    strokeColor = backgroundColor,
                    strokeWidth = 1
                )
            } else {
                if (walletTypeBlurView == null)
                    setBackgroundColor(backgroundColor, 10f.dp)
                else
                    walletTypeBlurView.setBackgroundColor(
                        Color.TRANSPARENT,
                        10f.dp,
                        clipToBounds = true
                    )
                setOnClickListener(null)
            }
        }
    }

    private fun configureViewTagView(account: MAccount) {
        isGone = false
        hardwareTagView?.isGone = true
        val tintColor = if (account.isTemporary) color.solidColorWithAlpha(255) else color
        if (viewTagView == null) {
            createViewTagView(account, tintColor)
        } else {
            viewTagView?.isGone = false
            eyeDrawable?.setTint(tintColor)
            viewLabel?.setTextColor(tintColor)
        }
        walletTypeBlurView?.isVisible = true

        setupViewTagBackground(account)
    }

    private fun createViewTagView(account: MAccount, tintColor: Int) {
        val iconRes = if (account.isTemporary) {
            org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye_add
        } else {
            org.mytonwallet.app_air.uicomponents.R.drawable.ic_wallet_eye
        }

        eyeDrawable = ContextCompat.getDrawable(context, iconRes)?.apply {
            setTint(tintColor)
        }

        eyeImageView = AppCompatImageView(context).apply {
            setImageDrawable(eyeDrawable)
        }

        viewLabel = WLabel(context).apply {
            text = LocaleController.getString("\$view_mode")
            setStyle(12f, WFont.SemiBold)
            setTextColor(tintColor)
            setPaddingLocalized(2.dp, 0, 0, 0)
        }

        val hPadding = if (account.isTemporary) {
            7.5f.dp.roundToInt()
        } else {
            4.5f.dp.roundToInt()
        }

        val height = if (account.isTemporary) 28.dp else 20.dp

        viewTagView = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(hPadding, 0, hPadding, 0)
            addView(eyeImageView)
            addView(viewLabel)
        }

        addView(viewTagView, LayoutParams(LayoutParams.WRAP_CONTENT, height))
    }

    private fun setupViewTagBackground(account: MAccount) {
        if (account.isTemporary) {
            (walletTypeBlurView ?: this).setBackgroundColor(
                color = Color.TRANSPARENT,
                radius = 14f.dp,
                clipToBounds = true,
                strokeColor = backgroundColor,
                strokeWidth = 1
            )
            setOnClickListener {
                AccountStore.saveTemporaryAccount(account)
            }
        } else {
            if (walletTypeBlurView == null)
                setBackgroundColor(backgroundColor, 10f.dp)
            else
                walletTypeBlurView.setBackgroundColor(
                    Color.TRANSPARENT,
                    10f.dp,
                    clipToBounds = true
                )
            setOnClickListener(null)
        }
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
                hardwareTagView,
                LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
            )
        } else {
            hardwareTagView?.isGone = false
        }
        background = null
        walletTypeBlurView?.isVisible = false
        setOnClickListener(null)
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)

        walletTypeBlurView?.measure(
            MeasureSpec.makeMeasureSpec(measuredWidth, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(measuredHeight, MeasureSpec.EXACTLY)
        )
    }
}
