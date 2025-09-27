package org.mytonwallet.uihome.home.views.header

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.views.UpdateStatusView

@SuppressLint("ViewConstructor")
class StickyHeaderView(
    context: Context,
    private val onActionClick: (HeaderActionsView.Identifier) -> Unit
) : FrameLayout(context), WThemedView, WProtectedView {

    init {
        id = generateViewId()
    }

    private var configured = false
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (configured)
            return
        configured = true
        setupViews()
    }

    val updateStatusView: UpdateStatusView by lazy {
        val v = UpdateStatusView(context)
        v
    }

    private val lockButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setImageDrawable(ContextCompat.getDrawable(context, R.drawable.ic_header_lock))
        v.setOnClickListener {
            onActionClick(HeaderActionsView.Identifier.LOCK_APP)
        }
        v
    }

    private val eyeButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setOnClickListener {
            onActionClick(HeaderActionsView.Identifier.TOGGLE_SENSITIVE_DATA_PROTECTION)
            updateEyeIcon()
        }
        v
    }

    private val scanButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_18_24
            )
        )
        v.setOnClickListener {
            onActionClick(HeaderActionsView.Identifier.SCAN_QR)
        }
        v
    }

    private val cancelButton: WLabel by lazy {
        WLabel(context).apply {
            text = LocaleController.getString("Cancel")
            setTextColor(WColor.Tint.color)
            setStyle(18f, WFont.Medium)
            setPaddingDp(12, 4, 12, 4)
            alpha = 0f
        }
    }

    private val saveButton: WLabel by lazy {
        WLabel(context).apply {
            text = LocaleController.getString("Save")
            setTextColor(WColor.Tint.color)
            setStyle(18f, WFont.Medium)
            setPaddingDp(12, 4, 12, 4)
            alpha = 0f
        }
    }

    private fun setupViews() {
        addView(
            updateStatusView,
            LayoutParams(WRAP_CONTENT, WNavigationBar.DEFAULT_HEIGHT.dp).apply {
                gravity = Gravity.CENTER or Gravity.TOP
            })
        addView(scanButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            if (LocaleController.isRTL)
                rightMargin = 8.dp
            else
                leftMargin = 8.dp
            topMargin = 1.dp
        })
        addView(lockButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            if (LocaleController.isRTL)
                leftMargin = 48.dp
            else
                rightMargin = 48.dp
            topMargin = 1.dp
        })
        addView(eyeButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            if (LocaleController.isRTL)
                leftMargin = 8.dp
            else
                rightMargin = 8.dp
            topMargin = 1.dp
        })

        listOf(scanButton, lockButton, eyeButton).forEach {
            it.updateColors(WColor.Tint, WColor.BackgroundRipple)
        }
        updateActions()
        updateTheme()
    }

    override fun updateTheme() {
        updateEyeIcon()
    }

    override fun updateProtectedView() {
        updateEyeIcon()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(HomeHeaderView.navDefaultHeight, MeasureSpec.EXACTLY)
        )
    }

    fun update(mode: HomeHeaderView.Mode, state: UpdateStatusView.State, handleAnimation: Boolean) {
        if (mode == HomeHeaderView.Mode.Expanded && state == UpdateStatusView.State.Updated) {
            updateStatusView.setState(
                state,
                handleAnimation,
                AccountStore.activeAccount?.name ?: ""
            )
        } else {
            updateStatusView.setState(state, handleAnimation, "")
        }
    }

    fun updateActions() {
        lockButton.visibility =
            if (WGlobalStorage.isPasscodeSet()) VISIBLE else GONE
        val statusViewMargin = if (lockButton.isVisible) 96.dp else 56.dp
        updateStatusView.layoutParams =
            (updateStatusView.layoutParams as MarginLayoutParams).apply {
                marginStart = statusViewMargin
                marginEnd = statusViewMargin
            }
    }

    val animationDuration = AnimationConstants.QUICK_ANIMATION / 2
    fun enterActionMode(onResult: (save: Boolean) -> Unit) {
        if (saveButton.parent == null) {
            addView(cancelButton, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
                marginStart = 4.dp
                topMargin = 1.dp
            })
            addView(saveButton, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.END or Gravity.CENTER_VERTICAL
                marginEnd = 4.dp
                topMargin = 1.dp
            })
        }
        cancelButton.setOnClickListener {
            onResult(false)
            exitActionMode()
        }
        saveButton.setOnClickListener {
            onResult(true)
            exitActionMode()
        }
        scanButton.fadeOut(animationDuration)
        lockButton.fadeOut(animationDuration)
        eyeButton.fadeOut(animationDuration) {
            scanButton.isClickable = false
            lockButton.isClickable = false
            eyeButton.isClickable = false
            cancelButton.fadeIn(animationDuration)
            saveButton.fadeIn(animationDuration) {
                cancelButton.isClickable = true
                saveButton.isClickable = true
            }
        }
    }

    fun exitActionMode() {
        cancelButton.setOnClickListener(null)
        saveButton.setOnClickListener(null)
        cancelButton.fadeOut(animationDuration)
        saveButton.fadeOut(animationDuration) {
            cancelButton.isClickable = false
            saveButton.isClickable = false
            scanButton.fadeIn(animationDuration)
            lockButton.fadeIn(animationDuration)
            eyeButton.fadeIn(animationDuration) {
                scanButton.isClickable = true
                lockButton.isClickable = true
                eyeButton.isClickable = true
            }
        }
    }

    private fun updateEyeIcon() {
        eyeButton.setImageDrawable(
            ContextCompat.getDrawable(
                context,
                if (WGlobalStorage.getIsSensitiveDataProtectionOn()) org.mytonwallet.app_air.icons.R.drawable.ic_header_eye else org.mytonwallet.app_air.icons.R.drawable.ic_header_eye_hidden
            )
        )
    }
}
