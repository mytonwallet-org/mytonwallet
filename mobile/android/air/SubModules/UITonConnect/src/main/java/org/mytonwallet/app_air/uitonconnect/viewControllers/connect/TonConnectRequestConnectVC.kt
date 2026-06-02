package org.mytonwallet.app_air.uitonconnect.viewControllers.connect

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisettings.viewControllers.settings.cells.SettingsAccountCell
import org.mytonwallet.app_air.uisettings.viewControllers.settings.models.SettingsItem
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.ConnectRequestConfirmView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.ConnectRequestView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.TON_CHAIN
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.api.activateAccount
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import kotlin.math.max

@SuppressLint("ViewConstructor")
class TonConnectRequestConnectVC(
    context: Context,
    private var update: ApiUpdate.ApiUpdateDappConnect? = null
) : WViewController(context) {
    override val TAG = "TonConnectRequestConnect"

    override val shouldDisplayTopBar = false


    private val requestView = ConnectRequestView(context).apply {
        configure(update?.dapp)
    }

    private val headerView = HeaderCell(context).apply {
        alpha = 0f
    }

    private val accountView = SettingsAccountCell(context).apply {
        alpha = 0f
    }

    private val buttonView: WButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Connect Wallet")
    }

    private val scrollingContentView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL

        addView(
            requestView, ConstraintLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        addView(
            headerView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                48.dp
            ).apply {
                leftMargin = 10.dp
                rightMargin = 10.dp
            }
        )
        addView(
            accountView, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                SettingsAccountCell.heightForItem(true)
            ).apply {
                topMargin = 0.dp
                leftMargin = 10.dp
                rightMargin = 10.dp
            }
        )
        addView(
            buttonView, ConstraintLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                leftMargin = 20.dp
                topMargin = 8.dp
                rightMargin = 20.dp
                bottomMargin = 15.dp
            })
    }

    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
        addView(
            scrollingContentView, ConstraintLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
    }

    override fun setupViews() {
        super.setupViews()

        setupNavBar(true)
        navigationBar?.addCloseButton {
            navigationController?.window?.dismissLastNav()
        }

        view.addView(
            scrollView, ConstraintLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        view.setConstraints {
            allEdges(scrollView)
        }

        updateButtonState()
        updateHeaderView()
        updateAccountView()

        buttonView.setOnClickListener {
            val update = update ?: return@setOnClickListener

            val account = AccountStore.accountById(update.accountId)

            if (account?.accountType == MAccount.AccountType.VIEW && update.proof != null) {
                showAlert(
                    LocaleController.getString("Error"),
                    LocaleController.getString("Action is not possible on a view-only wallet.")
                )
                return@setOnClickListener
            }

            if (!update.permissions.proof) {
                connectConfirm(
                    update.promiseId,
                    passcode = ""
                ) { success, _ ->
                    if (success) {
                        window!!.dismissLastNav()
                    }
                }
                return@setOnClickListener
            }

            if (account?.isHardware == true) {
                confirmHardware()
            } else {
                confirmPasscode()
            }
        }

        updateTheme()
        insetsUpdated()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(
            WColor.SecondaryBackground.color,
            ViewConstants.BLOCK_RADIUS.dp,
            0f,
            true
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            0, (WNavigationBar.DEFAULT_HEIGHT - 28).dp, 0, max(
                (navigationController?.getSystemBars()?.bottom ?: 0),
                (window?.imeInsets?.bottom ?: 0)
            )
        )
    }

    private fun confirmHardware() {
        val update = update ?: return
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignLedgerProof(
                    accountId = update.accountId,
                    operationChain = TON_CHAIN,
                    promiseId = update.promiseId,
                    proof = update.proof!!
                ),
                onDone = {
                    window!!.dismissLastNav {
                        window!!.dismissLastNav()
                    }
                }),
            headerView = ConnectRequestConfirmView(context).apply { configure(update.dapp) }
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(ledgerConnectVC)
        window!!.present(nav)
    }

    private fun confirmPasscode() {
        val update = update ?: return
        val window = window ?: return
        lateinit var navVC: WNavigationController
        val passcodeVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                ConnectRequestConfirmView(context).apply { configure(update.dapp) },
                LocaleController.getString("Confirm")
            ), task = { passcode ->
                val accountHasMfa = AccountStore.accountById(update.accountId)
                    ?.byChain?.get(TON_CHAIN)?.mfa != null
                connectConfirm(
                    update.promiseId,
                    passcode,
                    { success, mfaHash ->
                        if (!success) return@connectConfirm
                        if (mfaHash != null) {
                            val mfaVC = org.mytonwallet.app_air.uicomponents
                                .viewControllers.MfaActionConfirmVC(
                                    context,
                                    requestHash = mfaHash,
                                    forceCloseButton = true,
                                    onConfirmed = { _ ->
                                        finalizeMfaDappConnect()
                                    },
                                )
                            navVC.push(mfaVC, onCompletion = {
                                navVC.removePrevViewControllerOnly()
                            })
                            return@connectConfirm
                        }
                        window.dismissLastNav()
                    }
                )
                if (!accountHasMfa) {
                    window.dismissLastNav {
                        window.dismissLastNav()
                    }
                }
            })
        navVC = WNavigationController(window)
        navVC.setRoot(passcodeVC)
        window.present(navVC)
    }

    var isConfirmed = false
    private fun connectConfirm(
        promiseId: String,
        passcode: String,
        onCompletion: (success: Boolean, mfaRequestHash: String?) -> Unit
    ) {
        val update = update ?: return
        isConfirmed = true


        fun callback(account: MAccount) {
            window!!.lifecycleScope.launch {
                try {
                    val signResult = if (update.proof != null) WalletCore.call(
                        ApiMethod.DApp.SignDappProof(
                            listOfNotNull(account.dappChain(TON_CHAIN)),
                            account.accountId,
                            update.proof,
                            passcode
                        )
                    ) else null

                    val accountMfa = account.byChain[TON_CHAIN]?.mfa
                    if (accountMfa != null) {
                        val mfaResult = WalletCore.call(
                            ApiMethod.DApp.CreateDappConnectMfaRequest(
                                accountId = account.accountId,
                                password = passcode,
                            )
                        )
                        val hash = mfaResult.mfaRequestHash
                        if (hash == null) {
                            isConfirmed = false
                            onCompletion(false, null)
                            return@launch
                        }
                        // Stash proofSignatures + accountId so the MFA confirm path
                        // can complete the dapp connect once Telegram approval lands.
                        pendingMfaConnect = PendingMfaConnect(
                            promiseId = promiseId,
                            accountId = account.accountId,
                            proofSignatures = signResult?.signatures,
                            hash = hash,
                        )
                        onCompletion(true, hash)
                        return@launch
                    }

                    WalletCore.call(
                        ApiMethod.DApp.ConfirmDappRequestConnect(
                            promiseId,
                            ApiMethod.DApp.ConfirmDappRequestConnect.Request(
                                account.accountId,
                                signResult?.signatures
                            )
                        )
                    )
                    onCompletion(true, null)
                } catch (err: JSWebViewBridge.ApiError) {
                    isConfirmed = false
                    onCompletion(false, null)
                }
            }
        }

        if (AccountStore.activeAccount?.accountId == update.accountId) {
            callback(AccountStore.activeAccount!!)
        } else {
            WalletCore.activateAccount(
                accountId = update.accountId,
                notifySDK = true
            ) { activatedAccount, _ ->
                val activatedAccount = activatedAccount ?: return@activateAccount
                callback(activatedAccount);
            }
        }
    }

    private data class PendingMfaConnect(
        val promiseId: String,
        val accountId: String,
        val proofSignatures: List<String>?,
        val hash: String,
    )

    private var pendingMfaConnect: PendingMfaConnect? = null

    private fun finalizeMfaDappConnect() {
        val pending = pendingMfaConnect ?: return
        pendingMfaConnect = null
        val window = window ?: return
        window.lifecycleScope.launch {
            try {
                WalletCore.call(
                    ApiMethod.DApp.ConfirmDappRequestConnect(
                        pending.promiseId,
                        ApiMethod.DApp.ConfirmDappRequestConnect.Request(
                            pending.accountId,
                            pending.proofSignatures,
                        ),
                    )
                )
            } catch (_: Throwable) {
            }
            navigationController?.let { window.dismissNav(it) }
        }
    }

    private fun connectReject() {
        val update = update ?: return
        window!!.lifecycleScope.launch {
            WalletCore.call(
                ApiMethod.DApp.CancelDappRequest(
                    promiseId = update.promiseId,
                    reason = "user reject"
                )
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        if (!isConfirmed)
            connectReject()
    }

    fun setDappUpdate(update: ApiUpdate.ApiUpdateDappConnect) {
        this.update = update
        requestView.configure(update.dapp)
        updateButtonState()
        updateHeaderView()
        updateAccountView()
        headerView.fadeIn()
        accountView.fadeIn()
    }

    private fun updateButtonState() {
        val isEnabled = isSelectedWalletConnectable()
        buttonView.isEnabled = isEnabled
        buttonView.alpha = if (isEnabled) 1.0f else 0.5f
    }

    private fun updateHeaderView() {
        headerView.configure(
            LocaleController.getString("Selected Wallet"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private fun updateAccountView() {
        val accountId = update?.accountId ?: return
        val accountData = WGlobalStorage.getAccount(accountId) ?: return
        val account = MAccount(accountId, accountData)

        accountView.configure(
            item = SettingsItem(
                identifier = SettingsItem.Identifier.ACCOUNT,
                title = account.name,
                account = account,
                hasTintColor = false,
                icon = null,
                value = null
            ),
            subtitle = null,
            isFirst = false,
            isLast = true,
            isEnabled = true,
            onTap = {
                openWalletSelection()
            }
        )
    }

    private fun openWalletSelection() {
        val dappHost = update?.dapp?.host ?: ""
        val walletSelectionVC = WalletSelectionVC(
            context = context,
            dappHost = dappHost,
            requiresProof = update?.proof != null
        )

        walletSelectionVC.setOnWalletSelectListener { selectedAccount ->
            update?.let { currentUpdate ->
                update = currentUpdate.copy(accountId = selectedAccount.accountId)
            }
            updateAccountView()
            updateButtonState()
        }

        // Open as regular modal (not bottom sheet) so push works inside it
        val navVC = WNavigationController(window!!)
        navVC.setRoot(walletSelectionVC)
        window!!.present(navVC)
    }

    private fun isSelectedWalletConnectable(): Boolean {
        val update = update ?: return false
        val account = AccountStore.accountById(update.accountId) ?: return false
        val hasTonWallet = account.tonAddress != null
        if (!hasTonWallet) return false
        val requiresProof = update.proof != null
        val accountHasMfa = account.byChain[TON_CHAIN]?.mfa != null
        if (account.isViewOnly && (requiresProof || accountHasMfa)) {
            return false
        }
        return true
    }
}
