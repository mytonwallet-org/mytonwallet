package org.mytonwallet.app_air.uitonconnect.viewControllers.connect

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.spans.WClickableSpan
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.ConnectRequestConfirmView
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.commonViews.ConnectRequestView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.WalletEvent
import kotlin.math.max

@SuppressLint("ViewConstructor")
class TonConnectRequestConnectVC(
    context: Context,
    private val update: ApiUpdate.ApiUpdateDappConnect
) : WViewController(context) {

    override val shouldDisplayTopBar = false

    private val requestView = ConnectRequestView(context).apply {
        configure(update.dapp)
        onShowUnverifiedSourceWarning = {
            showUnverifiedSourceWarning()
        }
    }

    private val buttonView: WButton = WButton(context, WButton.Type.PRIMARY).apply {
        text = LocaleController.getString("Confirm")
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
            buttonView, ConstraintLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                leftMargin = 20.dp
                topMargin = 24.dp
                rightMargin = 20.dp
                bottomMargin = 20.dp
            })
    }

    private val scrollView = ScrollView(context).apply {
        id = View.generateViewId()
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

        buttonView.setOnClickListener {
            if (!update.permissions.proof) {
                connectConfirm(
                    update.promiseId,
                    passcode = ""
                ) { success ->
                    if (success) {
                        window!!.dismissLastNav()
                    }
                }
                return@setOnClickListener
            }
            if (AccountStore.activeAccount?.accountType == MAccount.AccountType.VIEW) {
                showAlert(
                    LocaleController.getString("Error"),
                    LocaleController.getString("Action is not possible on a view-only wallet.")
                )
                return@setOnClickListener
            }
            if (AccountStore.activeAccount?.isHardware == true) {
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
            WColor.Background.color,
            ViewConstants.STANDARD_ROUNDS.dp,
            0f,
            true
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            0, WNavigationBar.Companion.DEFAULT_HEIGHT.dp, 0, max(
                (navigationController?.getSystemBars()?.bottom ?: 0),
                (window?.imeInsets?.bottom ?: 0)
            )
        )
    }

    private fun confirmHardware() {
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignLedgerProof(
                    update.promiseId,
                    update.proof!!
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
        val window = window ?: return
        val passcodeVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                ConnectRequestConfirmView(context).apply { configure(update.dapp) },
                LocaleController.getString("Confirm")
            ), task = { passcode ->
                connectConfirm(
                    update.promiseId,
                    passcode,
                    { success ->
                        if (success) {
                            window!!.dismissLastNav()
                        }
                    }
                )
                window.dismissLastNav {
                    window.dismissLastNav()
                }
            })
        val navVC = WNavigationController(window)
        navVC.setRoot(passcodeVC)
        window.present(navVC)
    }

    var isConfirmed = false
    private fun connectConfirm(
        promiseId: String,
        passcode: String,
        onCompletion: (success: Boolean) -> Unit
    ) {
        isConfirmed = true
        window!!.lifecycleScope.launch {
            try {
                val signResult = if (update.proof != null) WalletCore.call(
                    ApiMethod.DApp.SignTonProof(
                        update.accountId,
                        update.proof,
                        passcode
                    )
                ) else null
                WalletCore.call(
                    ApiMethod.DApp.ConfirmDappRequestConnect(
                        promiseId,
                        ApiMethod.DApp.ConfirmDappRequestConnect.Request(
                            update.accountId,
                            signResult?.signature
                        )
                    )
                )
                onCompletion(true)
            } catch (err: JSWebViewBridge.ApiError) {
                isConfirmed = false
                onCompletion(false)
            }
        }
    }

    private fun connectReject() {
        window!!.lifecycleScope.launch {
            WalletCore.call(
                ApiMethod.DApp.CancelDappRequest(
                    promiseId = update.promiseId,
                    reason = "user reject"
                )
            )
        }
    }

    private fun showUnverifiedSourceWarning() {
        val warningText = SpannableStringBuilder()
        val template = LocaleController.getString("\$reopen_in_iab")
        val browserButtonText = LocaleController.getString("MyTonWallet Browser")
        val browserButtonPlaceholder = "%browserButton%"

        val placeholderStart = template.indexOf(browserButtonPlaceholder)
        if (placeholderStart != -1) {
            warningText.append(template.substring(0, placeholderStart))

            val buttonStart = warningText.length
            warningText.append(browserButtonText)
            val buttonEnd = warningText.length

            val clickableSpan = WClickableSpan(update.dapp.url ?: "", onClick = {
                openDappInBrowser()
            })
            warningText.setSpan(
                clickableSpan,
                buttonStart,
                buttonEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )

            val placeholderEnd = placeholderStart + browserButtonPlaceholder.length
            if (placeholderEnd < template.length) {
                warningText.append(template.substring(placeholderEnd))
            }
        } else {
            warningText.append(template)
        }

        showAlert(
            title = LocaleController.getString("Unverified Source"),
            text = warningText,
            allowLinkInText = true
        )
    }

    private fun openDappInBrowser() {
        update.dapp.url?.let { url ->
            activeDialog?.dismiss()
            window?.dismissLastNav(onCompletion = {
                WalletCore.notifyEvent(WalletEvent.OpenUrl(url))
            })
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        if (!isConfirmed)
            connectReject()
    }
}
