package org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.NestedScrollView
import java.util.Date
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.ClipboardHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futures.helpers.toPriceString
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.PERPS_QUOTE_EXPIRED_ERROR
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresErrorText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresPaymentSymbol
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_COMPLETED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_FAILED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_PARTIAL
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_RUNNING
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_UNKNOWN
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PARTIAL_FILL_ERROR
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_WITHDRAW
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore

private const val WITHDRAWAL_REJECTED_ERROR = "PerpsWithdrawalRejected"
private const val EXECUTION_UNKNOWN_ERROR = "PerpsExecutionUnknown"
private val PRE_SUBMISSION_ERRORS = listOf(
    "PerpsUnchanged",
    PERPS_QUOTE_EXPIRED_ERROR,
    "PerpsUnsupportedAccount",
    "PerpsOperationPending",
    "PerpsInvalidOperation"
)

internal fun WViewController.presentFuturesOperation(operation: MApiPerpsOperation) {
    presentInNavigation(FuturesOperationVC(context, operation.accountId, operation.id))
}

internal fun futuresOperationSymbol(operation: MApiPerpsOperation): String =
    PerpsStore.snapshotFor(operation.accountId)?.assets
        ?.firstOrNull { it.id == operation.assetId }?.symbol
        ?: operation.assetId.substringAfterLast(":")

internal fun futuresOperationTitle(operation: MApiPerpsOperation): String {
    val key = when (operation.kind) {
        "open" -> "Open Position"
        "increase" -> "Increase Position"
        "reduce" -> "Reduce Position"
        "close" -> "Close Position"
        "leverage" -> "PerpsChangeLeverage"
        PERPS_QUOTE_WITHDRAW -> "Withdrawal"
        else -> "Edit Position"
    }
    val symbol = futuresOperationSymbol(operation)
    return LocaleController.getString(key) + if (symbol.isEmpty()) "" else " · $symbol"
}

internal fun futuresOperationMessage(operation: MApiPerpsOperation): String = when {
    operation.kind == PERPS_QUOTE_WITHDRAW -> futuresWithdrawalMessage(operation)

    operation.error?.startsWith(WITHDRAWAL_REJECTED_ERROR) == true ->
        futuresErrorText(operation.error.orEmpty())

    else -> futuresStateMessage(operation)
}

private fun futuresWithdrawalMessage(operation: MApiPerpsOperation): String =
    when (operation.state) {
        PERPS_OPERATION_RUNNING -> LocaleController.getString("PerpsWithdrawalProcessing")
        PERPS_OPERATION_UNKNOWN -> LocaleController.getString("PerpsWithdrawalUnknown")
        PERPS_OPERATION_FAILED -> futuresErrorText(operation.error.orEmpty())
        else -> LocaleController.getString("PerpsWithdrawalOnItsWay")
    }

/** Only errors the SDK raises before submitting are safe to treat as failed. */
internal fun futuresSubmissionFailure(
    current: MApiPerpsOperation,
    error: Throwable
): MApiPerpsOperation {
    val thrownMessage = (error as? JSWebViewBridge.ApiError)?.thrownMessage
    val rejection = PRE_SUBMISSION_ERRORS.firstOrNull { thrownMessage?.contains(it) == true }
    return if (rejection != null) {
        current.copy(state = PERPS_OPERATION_FAILED, stage = "finished", error = rejection)
    } else {
        current.copy(state = PERPS_OPERATION_UNKNOWN, error = EXECUTION_UNKNOWN_ERROR)
    }
}

private fun futuresStateMessage(operation: MApiPerpsOperation): String = when (operation.state) {
    PERPS_OPERATION_RUNNING -> LocaleController.getString("PerpsProcessing")

    PERPS_OPERATION_PARTIAL -> LocaleController.getString("PerpsWithdrawalPending")

    PERPS_OPERATION_UNKNOWN -> LocaleController.getString("PerpsExecutionUnknown")

    PERPS_OPERATION_FAILED -> futuresErrorText(operation.error.orEmpty())

    else -> LocaleController.getString(
        if (operation.error == PERPS_PARTIAL_FILL_ERROR) {
            PERPS_PARTIAL_FILL_ERROR
        } else {
            "PerpsReconciled"
        }
    )
}

/** The status of one reviewed order, and the way out of a blocked one. */
@SuppressLint("ViewConstructor")
class FuturesOperationVC(
    context: Context,
    private val accountId: String,
    private val operationId: String
) : WViewController(context),
    WalletCore.EventObserver {
    @Suppress("PropertyName")
    override val TAG = "FuturesOperation"

    override val shouldDisplayBottomBar = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    override val displayedAccount =
        DisplayedAccount(accountId, AccountStore.isPushedTemporary)
    private val actions = FuturesOperationActions(
        this,
        accountId,
        scope,
        onBusyChanged = { updateContent() },
        onUpdated = { operation = it }
    )
    private val isBusy
        get() = actions.isBusy

    // Settled operations leave the store, so the last known record stays on screen
    private var operation = PerpsStore.operation(accountId, operationId)

    private val statusLabel = WLabel(context).apply {
        setStyle(20f, WFont.Medium)
        gravity = Gravity.CENTER
    }

    private val messageLabel = WLabel(context).apply {
        setStyle(16f)
        gravity = Gravity.CENTER
    }

    private val rowsView = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }

    private val scrollView = NestedScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
    }

    private val content = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
    }

    private val bottomPanel by lazy { ReversedCornerViewUpsideDown(context, scrollView) }

    private val refreshButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.SECONDARY_WITH_BACKGROUND
        text = LocaleController.getString("Refresh")
        setOnClickListener { refresh() }
    }

    private val actionButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.PRIMARY
        setOnClickListener { performAction() }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.addCloseButton()
        setNavTitle(LocaleController.getString("PerpsOperationStatus"))
        WalletCore.registerObserver(this)

        content.addView(
            statusLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = STATUS_TOP_MARGIN.dp
            }
        )
        content.addView(
            messageLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 8.dp
            }
        )
        content.addView(
            rowsView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = 24.dp
            }
        )
        scrollView.addView(content, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(bottomPanel, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(refreshButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.addView(actionButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toTop(scrollView)
            toCenterX(scrollView)
            bottomToTop(scrollView, actionButton, 12f)
            toStart(refreshButton, 20f)
            endToStart(refreshButton, actionButton, 6f)
            toEnd(actionButton, 20f)
            startToEnd(actionButton, refreshButton, 6f)
            topToTop(refreshButton, actionButton)
            topToTop(bottomPanel, actionButton, -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS)
            toBottom(bottomPanel)
        }
        insetsUpdated()
        updateTheme()
        updateContent()
    }

    override fun viewWillAppear() {
        super.viewWillAppear()
        refresh()
        PerpsStore.watch(this, POLL_INTERVAL_MS)
    }

    override fun viewWillDisappear() {
        super.viewWillDisappear()
        PerpsStore.unwatch(this)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        statusLabel.setTextColor(WColor.PrimaryText.color)
        messageLabel.setTextColor(WColor.SecondaryText.color)
        rowsView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            clipToBounds = true
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val bottomInset = navigationController?.getSystemBars()?.bottom ?: 0
        content.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        view.setConstraints {
            toBottomPx(actionButton, bottomInset + BUTTON_BOTTOM_MARGIN.dp)
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        if (walletEvent != WalletEvent.PerpsUpdated) return
        operation = PerpsStore.operation(accountId, operationId) ?: operation
        updateContent()
    }

    override fun onDestroy() {
        WalletCore.unregisterObserver(this)
        scope.cancel()
        PerpsStore.dismissOperationStatus(operationId)
        super.onDestroy()
    }

    private fun updateContent() {
        val operation = operation
        val isSuccess = operation?.state == PERPS_OPERATION_COMPLETED &&
            operation.error != PERPS_PARTIAL_FILL_ERROR
        statusLabel.text = LocaleController.getString(
            if (isSuccess) "PerpsCompleted" else "PerpsOperationStatus"
        )
        messageLabel.text = operation?.let(::futuresOperationMessage)
            ?: LocaleController.getString("Unavailable")
        actionButton.text = LocaleController.getString(
            when {
                operation?.state == PERPS_OPERATION_PARTIAL -> "PerpsWithdrawReleased"
                canAcknowledge(operation) -> "PerpsAllowNewOrders"
                operation?.blocksTrading == true -> "Hide"
                else -> "Close"
            }
        )
        actionButton.isLoading = isBusy
        actionButton.isEnabled = !isBusy
        updateRows(operation)
    }

    private fun updateRows(operation: MApiPerpsOperation?) {
        rowsView.removeAllViews()
        operation ?: return
        val rows = buildList {
            add(
                KeyValueRowView(
                    context,
                    LocaleController.getString("Order"),
                    futuresOperationTitle(operation)
                )
            )
            add(
                KeyValueRowView(
                    context,
                    LocaleController.getString("Date"),
                    Date(operation.createdAt).formatDateAndTime(DATE_FORMAT)
                )
            )
            operation.orderId?.let {
                add(KeyValueRowView(context, LocaleController.getString("Order ID"), it.toString()))
            }
            operation.filledSize?.let {
                add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Position Size"),
                        "$it ${futuresOperationSymbol(operation)}".trim()
                    )
                )
            }
            operation.averagePrice?.toDoubleOrNull()?.let {
                add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Price"),
                        it.toPriceString()
                    )
                )
            }
            operation.depositTxHash?.let { hash ->
                add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Transfer ID"),
                        hash
                    ).apply {
                        setOnClickListener {
                            ClipboardHelpers.copyToClipboard(context, "", hash)
                        }
                    }
                )
            }
        }
        rows.forEachIndexed { index, row: KeyValueRowView ->
            row.setLast(index == rows.lastIndex)
            rowsView.addView(row)
        }
    }

    private fun refresh() {
        if (!isBusy) PerpsStore.refreshOperations()
    }

    private fun performAction() {
        if (isBusy) return
        val operation = operation
        when {
            operation?.state == PERPS_OPERATION_PARTIAL -> actions.withdrawReleasedMargin(operation)

            canAcknowledge(operation) -> showAlert(
                LocaleController.getString("PerpsAllowNewOrders"),
                LocaleController.getString("PerpsAcknowledgeUnknown"),
                button = LocaleController.getString("PerpsAllowNewOrders"),
                buttonPressed = {
                    actions.acknowledge(operation!!) { window?.dismissLastNav() }
                },
                secondaryButton = LocaleController.getString("Cancel")
            )

            else -> window?.dismissLastNav()
        }
    }

    private companion object {
        const val STATUS_TOP_MARGIN = 24
        const val BUTTON_BOTTOM_MARGIN = 16
        const val POLL_INTERVAL_MS = 5_000L
        const val DATE_FORMAT = "MMM d, HH:mm"
    }
}

/** Offers a blocked operation's way out in an alert, in place of its status screen. */
internal fun WViewController.showFuturesOperationAlert(
    operation: MApiPerpsOperation,
    actions: FuturesOperationActions
) {
    if (actions.isBusy) return
    val title = futuresOperationTitle(operation)
    when {
        operation.state == PERPS_OPERATION_PARTIAL -> showAlert(
            title,
            futuresOperationMessage(operation),
            button = LocaleController.getString("PerpsWithdrawReleased"),
            buttonPressed = { actions.withdrawReleasedMargin(operation) },
            secondaryButton = LocaleController.getString("Cancel")
        )

        canAcknowledge(operation) -> showAlert(
            title,
            futuresOperationMessage(operation) + "\n\n" +
                LocaleController.getString("PerpsAcknowledgeUnknown"),
            button = LocaleController.getString("PerpsAllowNewOrders"),
            buttonPressed = { actions.acknowledge(operation) },
            secondaryButton = LocaleController.getString("Cancel")
        )

        else -> {
            PerpsStore.refreshOperations()
            showAlert(title, futuresOperationMessage(operation))
            if (operation.isUnseenPartialFill) PerpsStore.dismissOperationStatus(operation.id)
        }
    }
}

private fun canAcknowledge(operation: MApiPerpsOperation?) =
    operation?.state == PERPS_OPERATION_UNKNOWN && operation.acknowledgedAt == null

/** Unlocks new orders after an unknown result, or withdraws the margin a partial order released. */
internal class FuturesOperationActions(
    private val host: WViewController,
    val accountId: String,
    private val scope: CoroutineScope,
    private val onBusyChanged: () -> Unit = {},
    private val onUpdated: (MApiPerpsOperation) -> Unit = {}
) {
    var isBusy = false
        private set
    private var passcodeNav: WNavigationController? = null

    /** Call only after the user accepted that the original order may still complete. */
    fun acknowledge(saved: MApiPerpsOperation, onAcknowledged: () -> Unit = {}) {
        if (isBusy) return
        setBusy(true)
        scope.launch {
            val error = try {
                val updated = callOperation(ApiMethod.Perps.AcknowledgeOperation(accountId, saved))
                check(
                    updated.id == saved.id &&
                        updated.accountId == accountId &&
                        updated.assetId == saved.assetId &&
                        updated.kind == saved.kind &&
                        !updated.blocksTrading
                )
                PerpsStore.saveOperation(updated)
                null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                errorText(e)
            }
            setBusy(false)
            if (error == null) {
                onAcknowledged()
            } else {
                host.showAlert(LocaleController.getString("Error"), error)
            }
        }
    }

    fun withdrawReleasedMargin(saved: MApiPerpsOperation) {
        if (isBusy) return
        setBusy(true)
        scope.launch {
            val amount = callOrAlert(ApiMethod.Perps.PrepareWithdrawal(accountId, saved.id))
            setBusy(false)
            amount?.let { confirmWithdrawal(saved, it) }
        }
    }

    fun withdrawBalance() {
        if (isBusy) return
        PerpsStore.pendingOperation(accountId)?.let {
            host.showFuturesOperationAlert(it, this)
            return
        }
        setBusy(true)
        scope.launch {
            val quote = callOrAlert(ApiMethod.Perps.PrepareBalanceWithdrawal(accountId))
            setBusy(false)
            quote ?: return@launch
            host.presentInNavigation(FuturesBalanceWithdrawalVC(host.context, accountId, quote))
        }
    }

    private fun confirmWithdrawal(saved: MApiPerpsOperation, amount: String) {
        val task = { token: String -> withdraw(saved, token) }
        ProtectedActionAuth.confirm(
            onConfirmed = task,
            requiresFreshAuthentication = true,
            onPasscodeRequired = {
                passcodeNav = host.presentInNavigation(
                    PasscodeConfirmVC(
                        host.context,
                        PasscodeViewState.CustomHeader(
                            withdrawalHeader(amount),
                            LocaleController.getString("Confirm")
                        ),
                        task = task
                    )
                )
            }
        )
    }

    private fun withdrawalHeader(amount: String) = LinearLayout(host.context).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(0, 24.dp, 0, 24.dp)
        addView(
            WLabel(context).apply {
                setStyle(20f, WFont.Medium)
                gravity = Gravity.CENTER
                setTextColor(WColor.PrimaryText.color)
                text = LocaleController.getString("PerpsWithdrawReleased")
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )
        addView(
            WLabel(context).apply {
                setStyle(17f)
                gravity = Gravity.CENTER
                setTextColor(WColor.SecondaryText.color)
                text = "$amount $futuresPaymentSymbol"
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { topMargin = 8.dp }
        )
    }

    private fun withdraw(saved: MApiPerpsOperation, enclaveToken: String) {
        if (isBusy) return
        setBusy(true)
        val execution = PerpsStore.execute(
            saved.copy(state = PERPS_OPERATION_RUNNING, stage = "preparing"),
            submit = {
                WalletCore.call(
                    ApiMethod.Perps.RetryWithdrawal(accountId, enclaveToken, saved.id)
                )
            },
            resolveFailure = { current, error ->
                // Unless the review had expired, the withdrawal may have been submitted
                val isExpired = (error as? JSWebViewBridge.ApiError)?.thrownMessage
                    ?.contains(PERPS_QUOTE_EXPIRED_ERROR) == true
                current.copy(
                    state = if (isExpired) PERPS_OPERATION_PARTIAL else PERPS_OPERATION_UNKNOWN,
                    stage = "withdrawal",
                    error = if (isExpired) PERPS_QUOTE_EXPIRED_ERROR else "PerpsExecutionUnknown"
                )
            }
        )
        scope.launch {
            val result = execution.await()
            onUpdated(result)
            passcodeNav?.let { nav ->
                passcodeNav = null
                host.window?.dismissNav(nav)
            }
            setBusy(false)
            if (result.state != PERPS_OPERATION_COMPLETED &&
                result.state != PERPS_OPERATION_RUNNING
            ) {
                host.showAlert(
                    LocaleController.getString("Error"),
                    futuresOperationMessage(result)
                )
            }
        }
    }

    private suspend fun <T> callOrAlert(method: ApiMethod<T>): T? = try {
        WalletCore.call(method)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        host.showAlert(LocaleController.getString("Error"), errorText(e))
        null
    }

    /** The bridge reports an operation that carries an `error` as a failed call. */
    private suspend fun callOperation(method: ApiMethod<MApiPerpsOperation>): MApiPerpsOperation =
        try {
            WalletCore.call(method)
        } catch (e: JSWebViewBridge.ApiError) {
            e.parsedResult as? MApiPerpsOperation ?: throw e
        }

    private fun errorText(error: Throwable): String =
        (error as? JSWebViewBridge.ApiError)?.thrownMessage?.let(::futuresErrorText)
            ?: LocaleController.getString("PerpsUnavailable")

    private fun setBusy(isBusy: Boolean) {
        this.isBusy = isBusy
        onBusyChanged()
    }
}
