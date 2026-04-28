package org.mytonwallet.uihome.home.views.header

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import org.mytonwallet.app_air.uiassets.viewControllers.CollectionsMenuHelpers
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WActionBar
import org.mytonwallet.app_air.uicomponents.base.WActionBar.TitleAnimationMode
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WImageButton
import org.mytonwallet.app_air.uicomponents.widgets.WProtectedView
import org.mytonwallet.app_air.uicomponents.widgets.WThemedView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.utils.getDrawableCompat
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.models.MScreenMode
import org.mytonwallet.uihome.R
import org.mytonwallet.uihome.home.views.UpdateStatusView

@SuppressLint("ViewConstructor", "ClickableViewAccessibility")
class StickyHeaderView(
    context: Context,
    private val screenMode: MScreenMode,
    private val onActionClick: (HeaderActionsView.Identifier) -> Unit
) : WFrameLayout(context), WThemedView, WProtectedView {

    private enum class ActionMode {
        REORDER,
        SELECT
    }

    init {
        clipChildren = false
        clipToPadding = false
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
        UpdateStatusView(context).apply {
            onTap = {
                onActionClick(HeaderActionsView.Identifier.WALLET_SETTINGS)
            }
        }
    }

    private val lockButton: WImageButton by lazy {
        val v = WImageButton(context)
        v.setImageDrawable(context.getDrawableCompat(R.drawable.ic_header_lock))
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
            context.getDrawableCompat(
                org.mytonwallet.app_air.icons.R.drawable.ic_qr_code_scan_18_24
            )
        )
        v.setOnClickListener {
            onActionClick(HeaderActionsView.Identifier.SCAN_QR)
        }
        v
    }
    private val backButton: WImageButton by lazy {
        WImageButton(context).apply {
            setOnClickListener {
                onActionClick(HeaderActionsView.Identifier.BACK)
            }
            val arrowDrawable = context.getDrawableCompat(
                org.mytonwallet.app_air.uicomponents.R.drawable.ic_nav_back
            )
            setImageDrawable(arrowDrawable)
            updateColors(WColor.SecondaryText, WColor.BackgroundRipple)
        }
    }

    private val actionBar: WActionBar by lazy {
        WActionBar(context).apply {
            alpha = 0f
            isInvisible = true
        }
    }

    private var actionMode: ActionMode? = null
    val isInActionMode: Boolean get() = actionMode != null
    private var hiddenViewsForActionMode: List<View> = emptyList()

    private fun setupViews() {
        addView(
            updateStatusView,
            LayoutParams(WRAP_CONTENT, WNavigationBar.DEFAULT_HEIGHT.dp).apply {
                gravity = Gravity.CENTER or Gravity.TOP
            })
        when (screenMode) {
            MScreenMode.Default -> {
                addView(scanButton, LayoutParams(40.dp, 40.dp).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    if (LocaleController.isRTL)
                        rightMargin = 8.dp
                    else
                        leftMargin = 8.dp
                    topMargin = 1.dp
                })
            }

            is MScreenMode.SingleWallet -> {
                addView(backButton, LayoutParams(40.dp, 40.dp).apply {
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                    if (LocaleController.isRTL)
                        rightMargin = 8.dp
                    else
                        leftMargin = 8.dp
                    topMargin = 1.dp
                })
            }
        }
        addView(lockButton, LayoutParams(40.dp, 40.dp).apply {
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            if (LocaleController.isRTL)
                leftMargin = 56.dp
            else
                rightMargin = 56.dp
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
        addView(actionBar, LayoutParams(MATCH_PARENT, HomeHeaderView.navDefaultHeight).apply {
            gravity = Gravity.CENTER or Gravity.TOP
        })

        listOf(scanButton, lockButton, eyeButton).forEach {
            it.updateColors(WColor.Tint, WColor.BackgroundRipple)
        }
        updateActions()
        updateTheme()
    }

    override fun updateTheme() {
        actionBar.updateTheme()
        updateEyeIcon()
    }

    override fun updateProtectedView() {
        updateEyeIcon()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        super.onMeasure(widthMeasureSpec, HomeHeaderView.navDefaultHeight.exactly)
    }

    fun update(mode: HomeHeaderView.Mode, state: UpdateStatusView.State, handleAnimation: Boolean) {
        val isShowing =
            state is UpdateStatusView.State.Updated && mode == HomeHeaderView.Mode.Collapsed
        updateStatusView.setAppearance(isShowing = !isShowing, animated = handleAnimation)
        updateStatusView.setState(state, handleAnimation)
    }

    fun updateActions() {
        lockButton.visibility =
            if (WGlobalStorage.isPasscodeSet()) VISIBLE else GONE
        val statusViewMargin = defaultStatusViewMargin()
        (updateStatusView.layoutParams as? MarginLayoutParams)?.let { layoutParams ->
            updateStatusView.layoutParams = layoutParams.apply {
                marginStart = statusViewMargin
                marginEnd = statusViewMargin
            }
        }
    }

    val animationDuration = AnimationConstants.QUICK_ANIMATION / 2
    fun enterActionMode(onResult: (save: Boolean) -> Unit) {
        actionMode = ActionMode.REORDER
        CollectionsMenuHelpers.configureReorderActionBar(
            actionBar = actionBar,
            onSaveTapped = {
                onResult(true)
                exitActionMode()
            },
            onCancelTapped = {
                onResult(false)
                exitActionMode()
            }
        )
        enterHeaderActionMode(needUpdateStatusView = false)
    }

    fun enterSelectionMode(
        selectedCount: Int,
        shouldShowTransferActions: Boolean,
        onClose: () -> Unit,
        onHide: () -> Unit,
        onSelectAll: () -> Unit,
        onSend: (() -> Unit)? = null,
        onBurn: (() -> Unit)? = null
    ) {
        actionMode = ActionMode.SELECT
        configureSelectionActionBar(
            selectedCount = selectedCount,
            animationMode = null,
            shouldShowTransferActions = shouldShowTransferActions,
            onClose = onClose,
            onHide = onHide,
            onSelectAll = onSelectAll,
            onSend = onSend,
            onBurn = onBurn
        )
        enterHeaderActionMode(needUpdateStatusView = true)
    }

    fun updateSelectionMode(
        selectedCount: Int,
        animationMode: TitleAnimationMode?,
        shouldShowTransferActions: Boolean,
        onClose: () -> Unit,
        onHide: () -> Unit,
        onSelectAll: () -> Unit,
        onSend: (() -> Unit)? = null,
        onBurn: (() -> Unit)? = null
    ) {
        if (actionMode != ActionMode.SELECT) {
            return
        }
        configureSelectionActionBar(
            selectedCount = selectedCount,
            animationMode = animationMode,
            shouldShowTransferActions = shouldShowTransferActions,
            onClose = onClose,
            onHide = onHide,
            onSelectAll = onSelectAll,
            onSend = onSend,
            onBurn = onBurn
        )
    }

    fun exitActionMode() {
        if (!actionBar.isVisible) {
            return
        }
        actionMode = null
        actionBar.fadeOut(animationDuration) {
            actionBar.isInvisible = true
            hiddenViewsForActionMode.forEach {
                it.alpha = 0f
                it.visibility = View.VISIBLE
                it.isClickable = true
            }
            hiddenViewsForActionMode.forEach { view ->
                view.fadeIn(animationDuration)
            }
            hiddenViewsForActionMode = emptyList()
        }
    }

    private fun updateEyeIcon() {
        eyeButton.setImageDrawable(
            context.getDrawableCompat(
                if (WGlobalStorage.getIsSensitiveDataProtectionOn()) org.mytonwallet.app_air.icons.R.drawable.ic_header_eye else org.mytonwallet.app_air.icons.R.drawable.ic_header_eye_hidden
            )
        )
    }

    private fun enterHeaderActionMode(needUpdateStatusView: Boolean) {
        if (actionBar.isVisible) {
            return
        }
        hiddenViewsForActionMode = currentHeaderViews(needUpdateStatusView)
        hiddenViewsForActionMode.forEach { it.isClickable = false }
        hiddenViewsForActionMode.forEach { view ->
            view.fadeOut(animationDuration)
        }
        actionBar.isVisible = true
        actionBar.alpha = 0f
        actionBar.fadeIn(animationDuration)
    }

    private fun configureSelectionActionBar(
        selectedCount: Int,
        animationMode: TitleAnimationMode?,
        shouldShowTransferActions: Boolean,
        onClose: () -> Unit,
        onHide: () -> Unit,
        onSelectAll: () -> Unit,
        onSend: (() -> Unit)? = null,
        onBurn: (() -> Unit)? = null
    ) {
        CollectionsMenuHelpers.configureSelectionActionBar(
            actionBar = actionBar,
            shouldShowTransferActions = shouldShowTransferActions,
            onCloseTapped = onClose,
            onHideTapped = onHide,
            onSelectAllTapped = onSelectAll,
            onSendTapped = onSend,
            onBurnTapped = onBurn
        )
        val title = if (selectedCount == 0) {
            LocaleController.getString("\$nft_select")
        } else {
            selectedCount.toString()
        }
        if (animationMode != null) {
            actionBar.setTitle(title, true, animationMode)
        } else {
            actionBar.setTitle(title, false)
        }
    }

    private fun currentHeaderViews(needUpdateStatusView: Boolean): List<View> {
        val views = mutableListOf<View>()
        when (screenMode) {
            MScreenMode.Default -> if (scanButton.isVisible) {
                views.add(scanButton)
            }

            is MScreenMode.SingleWallet -> if (backButton.isVisible) {
                views.add(backButton)
            }
        }
        if (needUpdateStatusView && updateStatusView.isVisible) {
            views.add(updateStatusView)
        }
        if (lockButton.isVisible) {
            views.add(lockButton)
        }
        if (eyeButton.isVisible) {
            views.add(eyeButton)
        }
        return views
    }

    private fun defaultStatusViewMargin(): Int {
        return if (lockButton.isVisible) 96.dp else 56.dp
    }
}
