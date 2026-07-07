package org.mytonwallet.app_air.uiwalletconnectpay

import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.WalletConnectPayDataCollectionVC
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.WalletConnectPayPaymentStatusVC
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.payOptions.WalletConnectPayOptionsVC
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.WalletConnectPaySignDataInfoVC
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.signData.WalletConnectPaySignDataVC
import org.mytonwallet.app_air.uiwalletconnectpay.viewControllers.views.WalletConnectPayConfirmHeaderView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.MToken
import org.mytonwallet.app_air.walletcore.moshi.WcPayAmount
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentInfo
import org.mytonwallet.app_air.walletcore.moshi.WcPayPaymentOption
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod.Transfer.SignDappTransfers
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger

class WalletConnectPayController(private val window: WWindow) : WalletCore.UpdatesObserver {

    companion object {
        private const val WALLET_CONNECT_PAY_SIGN_URL = "https://walletconnect.com/pay"
        private var optionSelectionVC: WeakReference<WalletConnectPayOptionsVC>? = null
    }

    private var signNav: WeakReference<WNavigationController>? = null
    private var statusVC: WeakReference<WalletConnectPayPaymentStatusVC>? = null

    private var pendingPaymentAmount: WcPayAmount? = null
    private var pendingToken: MToken? = null

    override fun onBridgeUpdate(update: ApiUpdate) {
        when (update) {
            is ApiUpdate.ApiUpdateWalletConnectPayOptionSelection -> {
                window.doOnWalletReady {
                    val existingVC = optionSelectionVC?.get()?.takeIf { !it.isDisappeared }
                    if (existingVC != null) {
                        existingVC.setUpdate(update)
                    } else {
                        val vc = WalletConnectPayOptionsVC(window, update)
                        optionSelectionVC = WeakReference(vc)
                        val navVC = WNavigationController(window)
                        navVC.setRoot(vc)
                        window.presentOnWalletReady(navVC)
                    }
                }
            }

            is ApiUpdate.ApiUpdateWalletConnectPaySignTransaction -> {
                WalletCore.ensureAccountActivated(update.accountId) {
                    window.doOnWalletReady {
                        presentSignTransaction(update)
                    }
                }
            }

            is ApiUpdate.ApiUpdateWalletConnectPaySignData -> {
                WalletCore.ensureAccountActivated(update.accountId) {
                    window.doOnWalletReady {
                        presentSignData(update)
                    }
                }
            }

            is ApiUpdate.ApiUpdateWalletConnectPayDataCollection -> {
                window.doOnWalletReady {
                    presentDataCollection(update)
                }
            }

            is ApiUpdate.ApiUpdateWalletConnectPayProcessing -> {
                WalletCore.ensureAccountActivated(update.accountId) {
                    window.doOnWalletReady {
                        presentProcessing(update)
                    }
                }
            }

            is ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete -> {
                window.doOnWalletReady {
                    presentPaymentComplete(update)
                }
            }

            else -> {}
        }
    }

    private fun presentSignTransaction(update: ApiUpdate.ApiUpdateWalletConnectPaySignTransaction) {
        val account = AccountStore.accountById(update.accountId) ?: return
        val navTitle = LocaleController.getString("Confirm Sending")
        val payment = resolvePaymentSummary(update.paymentOption, update.paymentInfo)
        pendingPaymentAmount = payAmountFor(update.paymentOption, update.paymentInfo)
        pendingToken = payment?.token
        val header = WalletConnectPayConfirmHeaderView(
            window,
            merchant = update.merchant,
            token = payment?.token,
            amount = payment?.amount
        )
        var confirmed = false
        val onCancel = { if (!confirmed) cancel(update.promiseId) }

        if (account.isHardware) {
            val ledgerVC = LedgerConnectVC(
                window,
                LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                    account.tonAddress!!,
                    signData = LedgerConnectVC.SignData.SignWalletConnectPayTransfers(
                        update.accountId, update
                    ),
                    onDone = { confirmed = true; window.dismissToRoot() }
                ),
                headerView = header,
                onCancel = onCancel
            )
            present(ledgerVC)
            return
        }

        lateinit var passcodeVC: PasscodeConfirmVC
        passcodeVC = PasscodeConfirmVC(
            window,
            PasscodeViewState.CustomHeader(header, navbarTitle = navTitle, showNavbarTitle = true),
            task = { passcode ->
                confirmed = true
                signTransaction(update, passcode, passcodeVC, onSignFailed = { confirmed = false })
            },
            onCancel = onCancel
        )
        present(passcodeVC)
    }

    private fun presentSignData(update: ApiUpdate.ApiUpdateWalletConnectPaySignData) {
        val account = AccountStore.accountById(update.accountId) ?: return
        val payment = resolvePaymentSummary(update.paymentOption, update.paymentInfo)
        pendingPaymentAmount = payAmountFor(update.paymentOption, update.paymentInfo)
        pendingToken = payment?.token

        var confirmed = false
        val onCancelled = { if (!confirmed) cancel(update.promiseId) }

        val signDataVC = WalletConnectPaySignDataVC(
            window,
            merchant = update.merchant,
            paymentAmount = update.paymentInfo?.amount,
            paymentOption = update.paymentOption,
            onProceed = {
                proceedSignData(
                    update,
                    account,
                    header = {
                        WalletConnectPayConfirmHeaderView(
                            window,
                            merchant = update.merchant,
                            token = payment?.token,
                            amount = payment?.amount
                        )
                    },
                    onConfirmed = { confirmed = true },
                    onSignFailed = { confirmed = false }
                )
            },
            onCancelled = onCancelled,
            onShowTransferInfo = {
                signNav?.get()?.push(WalletConnectPaySignDataInfoVC(window, update.payloadToSign))
            }
        )
        present(signDataVC)
    }

    // Continues the sign-data flow after the user taps "Sign" on the confirm
    // screen: Ledger for hardware wallets, otherwise the passcode screen. Both
    // are pushed onto the sign-data screen's navigation controller.
    private fun proceedSignData(
        update: ApiUpdate.ApiUpdateWalletConnectPaySignData,
        account: MAccount,
        header: () -> WalletConnectPayConfirmHeaderView,
        onConfirmed: () -> Unit,
        onSignFailed: () -> Unit
    ) {
        val title = LocaleController.getString("Sign Data")

        if (account.isHardware) {
            val ledgerVC = LedgerConnectVC(
                window,
                LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                    account.tonAddress!!,
                    signData = LedgerConnectVC.SignData.SignWalletConnectPaySignData(
                        update.accountId, update
                    ),
                    onDone = { onConfirmed(); window.dismissToRoot() }
                ),
                headerView = header(),
                onCancel = {}
            )
            signNav?.get()?.push(ledgerVC)
            return
        }

        lateinit var passcodeVC: PasscodeConfirmVC
        passcodeVC = PasscodeConfirmVC(
            window,
            PasscodeViewState.CustomHeader(header(), navbarTitle = title, showNavbarTitle = false),
            task = { passcode ->
                onConfirmed()
                signData(update, passcode, passcodeVC, onSignFailed = onSignFailed)
            },
            onCancel = {}
        )
        signNav?.get()?.push(passcodeVC)
    }

    private data class PaymentSummary(
        val token: MToken?,
        val amount: WalletConnectPayConfirmHeaderView.Amount
    )

    private fun resolvePaymentSummary(
        paymentOption: WcPayPaymentOption?,
        paymentInfo: WcPayPaymentInfo?
    ): PaymentSummary? {
        paymentOption?.let { option ->
            val value = runCatching { BigInteger(option.amountValue) }.getOrNull()
            if (value != null) {
                return PaymentSummary(
                    token = option.slug?.let { TokenStore.getToken(it) },
                    amount = WalletConnectPayConfirmHeaderView.Amount(
                        value = value,
                        decimals = option.display.decimals,
                        currency = option.display.assetSymbol
                    )
                )
            }
        }

        val amount = paymentInfo?.amount ?: return null
        val value = runCatching { BigInteger(amount.value) }.getOrNull() ?: return null
        val fiatCurrency = amount.fiatCurrency
        return PaymentSummary(
            token = null,
            amount = if (fiatCurrency != null) {
                WalletConnectPayConfirmHeaderView.Amount(
                    value = value,
                    decimals = amount.display.decimals,
                    currency = fiatCurrency.sign,
                    forceCurrencyToRight = false
                )
            } else {
                WalletConnectPayConfirmHeaderView.Amount(
                    value = value,
                    decimals = amount.display.decimals,
                    currency = amount.display.assetSymbol
                )
            }
        )
    }

    private fun payAmountFor(
        paymentOption: WcPayPaymentOption?,
        paymentInfo: WcPayPaymentInfo?
    ): WcPayAmount? {
        paymentOption?.let { option ->
            return WcPayAmount(value = option.amountValue, display = option.display)
        }
        return paymentInfo?.amount
    }

    private fun presentDataCollection(update: ApiUpdate.ApiUpdateWalletConnectPayDataCollection) {
        val vc = WalletConnectPayDataCollectionVC(
            window,
            url = update.url,
            onComplete = { complete(update.promiseId) },
            onError = { cancel(update.promiseId) },
            onClosed = { cancel(update.promiseId) },
        )
        present(vc)
    }

    private fun presentProcessing(update: ApiUpdate.ApiUpdateWalletConnectPayProcessing) {
        if (statusVC?.get()?.takeIf { !it.isDisappeared } != null) return

        presentStatus {
            WalletConnectPayPaymentStatusVC(
                window,
                merchant = update.merchant,
                processing = true,
                paymentAmount = pendingPaymentAmount,
                token = pendingToken
            )
        }
    }

    private fun presentPaymentComplete(update: ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete) {
        val amount = update.paymentAmount ?: pendingPaymentAmount
        val token = pendingToken
        // Consumed here; clear so a later unrelated payment can't inherit them.
        pendingPaymentAmount = null
        pendingToken = null

        val existing = statusVC?.get()?.takeIf { !it.isDisappeared }
        if (existing != null) {
            existing.update(update)
            return
        }

        presentStatus {
            WalletConnectPayPaymentStatusVC(
                window,
                merchant = update.merchant,
                processing = false,
                paymentAmount = amount,
                token = token
            )
        }
    }

    private fun presentStatus(createVC: () -> WalletConnectPayPaymentStatusVC) {
        val signNavToDismiss = signNav?.get()
        signNav = null

        val present = {
            val vc = createVC()
            statusVC = WeakReference(vc)
            val nav = WNavigationController(
                window,
                WNavigationController.PresentationConfig(
                    style = WNavigationController.PresentationStyle.BottomSheet
                )
            )
            nav.setRoot(vc)
            signNav = WeakReference(nav)
            window.presentOnWalletReady(nav)
        }

        if (signNavToDismiss != null && window.topNavigationController === signNavToDismiss) {
            window.dismissLastNav(onCompletion = { present() })
        } else {
            signNavToDismiss?.let { window.dismissNav(it) }
            present()
        }
    }

    private fun complete(promiseId: String) {
        window.lifecycleScope.launch {
            try {
                WalletCore.call(ApiMethod.DApp.CompleteWalletConnectPayDataCollection(promiseId))
            } catch (t: CancellationException) {
                throw t
            } catch (t: Exception) {
                Logger.e(
                    Logger.LogTag.WALLET_PAY,
                    "WalletConnectPay completeDataCollection failed: ${t.message}"
                )
            }
        }
    }

    private fun cancel(promiseId: String) {
        window.lifecycleScope.launch {
            try {
                WalletCore.call(
                    ApiMethod.DApp.CancelWalletConnectPay(promiseId, "Canceled by the user")
                )
            } catch (t: CancellationException) {
                throw t
            } catch (t: Exception) {
                Logger.e(
                    Logger.LogTag.WALLET_PAY,
                    "WalletConnectPay cancel failed: ${t.message}"
                )
            }
        }
    }

    private fun present(vc: org.mytonwallet.app_air.uicomponents.base.WViewController) {
        val navVC = WNavigationController(window)
        navVC.setRoot(vc)
        signNav = WeakReference(navVC)
        window.presentOnWalletReady(navVC)
    }

    private fun signTransaction(
        update: ApiUpdate.ApiUpdateWalletConnectPaySignTransaction,
        passcode: String,
        passcodeVC: PasscodeConfirmVC,
        onSignFailed: () -> Unit
    ) {
        val account = AccountStore.accountById(update.accountId) ?: return
        val dappChain = account.dappChain(update.operationChain) ?: return
        window.lifecycleScope.launch {
            try {
                val signResult = WalletCore.call(
                    SignDappTransfers(
                        dappChain = dappChain,
                        accountId = update.accountId,
                        transactions = update.transactions,
                        options = SignDappTransfers.Options(
                            password = passcode,
                            validUntil = update.validUntil,
                            vestingAddress = null,
                            isLegacyOutput = update.isLegacyOutput ?: update.isSignOnly
                        )
                    )
                )
                val signedTransactions = when (signResult) {
                    is org.json.JSONArray -> signResult
                    is List<*> -> org.json.JSONArray(signResult)
                    else -> org.json.JSONArray(signResult?.toString().orEmpty())
                }
                WalletCore.call(
                    ApiMethod.DApp.ConfirmWalletConnectPaySignTransaction(
                        update.promiseId,
                        signedTransactions
                    )
                )
            } catch (t: CancellationException) {
                throw t
            } catch (t: Exception) {
                onSignFailed()
                handleSignError("signTransaction", t, passcodeVC)
            }
        }
    }

    private fun signData(
        update: ApiUpdate.ApiUpdateWalletConnectPaySignData,
        passcode: String,
        passcodeVC: PasscodeConfirmVC,
        onSignFailed: () -> Unit
    ) {
        val account = AccountStore.accountById(update.accountId) ?: return
        val dappChain = account.dappChain(update.operationChain) ?: return
        window.lifecycleScope.launch {
            try {
                val signedData = WalletCore.call(
                    ApiMethod.Transfer.SignDappData(
                        dappChain = dappChain,
                        accountId = update.accountId,
                        dappUrl = WALLET_CONNECT_PAY_SIGN_URL,
                        payloadToSign = update.payloadToSign,
                        password = passcode
                    )
                )
                WalletCore.call(
                    ApiMethod.DApp.ConfirmWalletConnectPaySignData(
                        update.promiseId,
                        signedData
                    )
                )
            } catch (t: CancellationException) {
                throw t
            } catch (t: Exception) {
                onSignFailed()
                handleSignError("signData", t, passcodeVC)
            }
        }
    }

    private fun handleSignError(operation: String, t: Throwable, passcodeVC: PasscodeConfirmVC) {
        Logger.e(Logger.LogTag.WALLET_PAY, "WalletConnectPay $operation failed: ${t.message}")
        val error = (t as? JSWebViewBridge.ApiError)?.parsed ?: MBridgeError.UNKNOWN
        passcodeVC.restartAuth()
        passcodeVC.showError(error)
    }

    fun onCreate() {
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayOptionSelection::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignTransaction::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignData::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayDataCollection::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayProcessing::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignTransactionComplete::class.java, this
        )
        WalletCore.subscribeToApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignDataComplete::class.java, this
        )
    }

    fun onDestroy() {
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayOptionSelection::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignTransaction::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignData::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayDataCollection::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayProcessing::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPayPaymentComplete::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignTransactionComplete::class.java, this
        )
        WalletCore.unsubscribeFromApiUpdates(
            ApiUpdate.ApiUpdateWalletConnectPaySignDataComplete::class.java, this
        )
    }
}
