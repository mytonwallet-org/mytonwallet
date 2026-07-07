package org.mytonwallet.app_air.uisettings.viewControllers.permissions

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.isGone
import androidx.core.view.isVisible
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.uicomponents.R
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WRecyclerViewAdapter
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.WEmptyIconTitleSubtitleView
import org.mytonwallet.app_air.uicomponents.drawable.RoundProgressDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WCell
import org.mytonwallet.app_air.uicomponents.widgets.WRecyclerView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.permissions.cells.PermissionCell
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.utils.IndexPath
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MWalletPermission
import java.lang.ref.WeakReference

@SuppressLint("ViewConstructor")
class PermissionsListVC(
    context: Context,
    accountId: String?,
    chain: MBlockchain,
    private val standalone: Boolean = false,
) : WViewController(context), WRecyclerViewAdapter.WRecyclerViewDataSource,
    PermissionsListVM.Delegate {
    override val TAG = "PermissionsList"

    override val shouldDisplayTopBar = standalone
    override val shouldDisplayBottomBar = true

    init {
        title = chain.displayName
    }

    companion object {
        private val PERMISSION_CELL = WCell.Type(1)
    }

    private val viewModel = PermissionsListVM(accountId, chain, this)

    private val rvAdapter = WRecyclerViewAdapter(WeakReference(this), arrayOf(PERMISSION_CELL))

    private val recyclerView = WRecyclerView(this).apply {
        adapter = rvAdapter
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
        setItemAnimator(null)
        clipToPadding = false
        addOnScrollListener(object : RecyclerView.OnScrollListener() {
            override fun onScrolled(recyclerView: RecyclerView, dx: Int, dy: Int) {
                super.onScrolled(recyclerView, dx, dy)
                if (dx == 0 && dy == 0) return
                updateBlurViews(recyclerView)
            }
        })
    }

    private val progressDrawable = RoundProgressDrawable(16f.dp, 0.5f.dp)
    private val progressView = object : View(context) {
        val size = 28.dp
        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val left = (width - size) / 2
            val top = (height - size) / 2
            progressDrawable.setBounds(left, top, left + size, top + size)
            progressDrawable.draw(canvas)
        }

        override fun verifyDrawable(who: Drawable): Boolean {
            if (who == progressDrawable) return isVisible
            return super.verifyDrawable(who)
        }
    }.apply {
        id = View.generateViewId()
        visibility = View.INVISIBLE
        progressDrawable.callback = this
    }

    private val emptyView by lazy {
        WEmptyIconTitleSubtitleView(
            context,
            animation = R.raw.animation_empty,
            title = LocaleController.getString("No Permissions"),
            subtitle = LocaleController.getString("Nothing to revoke on this chain")
        ).apply {
            id = View.generateViewId()
            isGone = true
        }
    }

    private val permissions get() = viewModel.permissions
    private val plugins get() = viewModel.plugins

    override fun setupViews() {
        super.setupViews()

        if (standalone) {
            setNavTitle(LocaleController.getString("Permissions"))
            setupNavBar(true)
        }

        view.addView(
            emptyView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT)
        )
        view.addView(progressView, ViewGroup.LayoutParams(40.dp, 40.dp))
        view.addView(
            recyclerView,
            ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, MATCH_CONSTRAINT)
        )
        view.setConstraints {
            toCenterY(emptyView)
            toStart(emptyView, 48f)
            toEnd(emptyView, 48f)
            toCenterX(progressView)
            toCenterY(progressView)
            allEdges(recyclerView)
        }

        updateTheme()
        updateRecyclerViewPadding()
        viewModel.load()
    }

    override fun permissionsDataUpdated() {
        renderState()
    }

    private fun renderState() {
        if (viewModel.isLoading) {
            progressView.visibility = View.VISIBLE
            recyclerView.visibility = View.INVISIBLE
            emptyView.isGone = true
            return
        }
        progressView.visibility = View.INVISIBLE

        if (viewModel.hasError) {
            recyclerView.visibility = View.INVISIBLE
            emptyView.setTitle(LocaleController.getString("Failed to Load"))
            emptyView.setSubtitle(LocaleController.getString("Please try again later"))
            emptyView.isGone = false
        } else if (permissions.isEmpty() && plugins.isEmpty()) {
            recyclerView.visibility = View.INVISIBLE
            emptyView.setTitle(LocaleController.getString("No Permissions"))
            emptyView.setSubtitle(LocaleController.getString("Nothing to revoke on this chain"))
            emptyView.isGone = false
        } else {
            recyclerView.visibility = View.VISIBLE
            emptyView.isGone = true
            rvAdapter.reloadData()
        }
    }

    override fun recyclerViewNumberOfSections(rv: RecyclerView) = 1

    override fun recyclerViewNumberOfItems(rv: RecyclerView, section: Int): Int {
        return if (permissions.isNotEmpty()) permissions.size else plugins.size
    }

    override fun recyclerViewCellType(rv: RecyclerView, indexPath: IndexPath) = PERMISSION_CELL

    override fun recyclerViewCellView(rv: RecyclerView, cellType: WCell.Type): WCell {
        return PermissionCell(context)
    }

    override fun recyclerViewConfigureCell(
        rv: RecyclerView,
        cellHolder: WCell.Holder,
        indexPath: IndexPath
    ) {
        val cell = cellHolder.cell as PermissionCell
        if (permissions.isNotEmpty()) {
            configurePermission(cell, permissions[indexPath.row], indexPath.row)
        } else {
            configurePlugin(cell, indexPath.row)
        }
    }

    private fun configurePermission(cell: PermissionCell, permission: MWalletPermission, row: Int) {
        val isFirst = row == 0
        val isLast = row == permissions.size - 1
        when (permission) {
            is MWalletPermission.Approval -> {
                val spenderLabel = permission.spenderName
                    ?: permission.spenderAddress.formatStartEndAddress()
                val amount = if (permission.isUnlimited) {
                    LocaleController.getString("Unlimited")
                } else {
                    permission.allowance.toBigInteger().toString(
                        permission.tokenDecimals,
                        permission.tokenSymbol,
                        permission.tokenDecimals,
                        false
                    )
                }
                cell.configure(
                    iconUrl = permission.tokenImage,
                    title = permission.tokenName,
                    subtitle = LocaleController.getStringWithKeyValues(
                        "Approved to %name%",
                        listOf("%name%" to spenderLabel)
                    ),
                    amount = amount,
                    isFirst = isFirst,
                    isLast = isLast,
                    onTap = { onPermissionClick(permission) }
                )
            }

            is MWalletPermission.Delegation -> {
                val delegateLabel = permission.delegateName
                    ?: permission.delegateAddress.formatStartEndAddress()
                cell.configure(
                    iconUrl = permission.delegateIcon,
                    title = delegateLabel,
                    subtitle = LocaleController.getString("Wallet Delegation"),
                    amount = null,
                    isFirst = isFirst,
                    isLast = isLast,
                    onTap = { onPermissionClick(permission) }
                )
            }
        }
    }

    private fun configurePlugin(cell: PermissionCell, row: Int) {
        val plugin = plugins[row]
        cell.configure(
            iconUrl = null,
            title = plugin.name ?: LocaleController.getString("Unknown Plugin"),
            subtitle = plugin.address.formatStartEndAddress(),
            amount = null,
            isFirst = row == 0,
            isLast = row == plugins.size - 1,
            onTap = null
        )
    }

    private fun onPermissionClick(permission: MWalletPermission) {
        val title: String
        val message: CharSequence
        when (permission) {
            is MWalletPermission.Approval -> {
                title = LocaleController.getString("Revoke Approval")
                message = LocaleController.getStringWithKeyValues(
                    "Are you sure you want to revoke approval for %token%?",
                    listOf("%token%" to permission.tokenName)
                )
            }

            is MWalletPermission.Delegation -> {
                title = LocaleController.getString("Revoke Delegation")
                message = LocaleController.getStringWithKeyValues(
                    "Are you sure you want to revoke delegation for %name%?",
                    listOf(
                        "%name%" to (permission.delegateName
                            ?: permission.delegateAddress.formatStartEndAddress())
                    )
                )
            }
        }
        showAlert(
            title,
            message,
            LocaleController.getString("Revoke"),
            { confirmRevoke(permission) },
            LocaleController.getString("Cancel"),
            preferPrimary = false,
            primaryIsDanger = true
        )
    }

    private fun confirmRevoke(permission: MWalletPermission) {
        val nav = navigationController
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.Default(
                LocaleController.getString("Locked"),
                LocaleController.getString(
                    if (WGlobalStorage.isBiometricActivated() &&
                        BiometricHelpers.canAuthenticate(window!!)
                    )
                        "Enter passcode or use fingerprint" else "Enter Passcode"
                ),
                LocaleController.getString("Revoke")
            ),
            task = { passcode ->
                nav?.pop()
                viewModel.revoke(
                    permission,
                    passcode,
                    onSuccess = {},
                    onError = { error ->
                        showAlert(
                            LocaleController.getString("Error"),
                            error ?: LocaleController.getString("An error occurred")
                        )
                    }
                )
            }
        )
        nav?.push(passcodeConfirmVC)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        progressDrawable.paint.color = WColor.SecondaryText.color
        progressView.invalidate()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        updateRecyclerViewPadding()
    }

    private fun updateRecyclerViewPadding() {
        val topInset = (navigationController?.getSystemBars()?.top ?: 0) +
            WNavigationBar.DEFAULT_HEIGHT.dp
        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            topInset,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            navigationController?.bottomInset ?: 0
        )
    }

    override fun scrollToTop() {
        super.scrollToTop()
        recyclerView.layoutManager?.smoothScrollToPosition(recyclerView, null, 0)
    }

    override fun onDestroy() {
        super.onDestroy()
        viewModel.dispose()
    }
}
