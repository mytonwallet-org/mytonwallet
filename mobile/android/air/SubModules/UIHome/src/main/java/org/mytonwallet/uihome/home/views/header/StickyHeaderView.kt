package org.mytonwallet.uihome.home.views.header

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.views.UpdateStatusView

@SuppressLint("ViewConstructor")
class StickyHeaderView(
    context: Context,
    private val onActionClick: (HeaderActionsView.Identifier) -> Unit
) : FrameLayout(context), WThemedView {

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

    private fun setupViews() {
        addView(updateStatusView, LayoutParams(WRAP_CONTENT, MATCH_PARENT).apply {
            gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
        })
        addView(scanButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.START or Gravity.CENTER_VERTICAL
            leftMargin = 8.dp
            topMargin = 1.dp
        })
        addView(lockButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            rightMargin = 48.dp
            topMargin = 1.dp
        })
        addView(eyeButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            rightMargin = 8.dp
            topMargin = 1.dp
        })

        listOf(scanButton, lockButton, eyeButton).forEach {
            it.updateColors(WColor.Tint, WColor.TintRipple)
        }
        updateActions()
        updateTheme()
    }

    override fun updateTheme() {
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
            if (AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC) VISIBLE else GONE
        val statusViewMargin = if (lockButton.isVisible) 96.dp else 56.dp
        updateStatusView.layoutParams =
            (updateStatusView.layoutParams as MarginLayoutParams).apply {
                marginStart = statusViewMargin
                marginEnd = statusViewMargin
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
