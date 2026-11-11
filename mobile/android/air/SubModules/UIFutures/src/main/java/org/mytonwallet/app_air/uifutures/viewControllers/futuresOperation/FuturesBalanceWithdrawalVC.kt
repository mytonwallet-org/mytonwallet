package org.mytonwallet.app_air.uifutures.viewControllers.futuresOperation

import android.annotation.SuppressLint
import android.content.Context
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.widget.NestedScrollView
import java.lang.ref.WeakReference
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.PERPS_QUOTE_EXPIRED_ERROR
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresErrorText
import org.mytonwallet.app_air.uifutures.viewControllers.futuresEdit.futuresPaymentSymbol
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsBalanceWithdrawal
import org.mytonwallet.app_air.walletcore.moshi.MApiPerpsOperation
import org.mytonwallet.app_air.walletcore.moshi.PERPS_BALANCE_WITHDRAWAL_ASSET_ID
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_COMPLETED
import org.mytonwallet.app_air.walletcore.moshi.PERPS_OPERATION_RUNNING
import org.mytonwallet.app_air.walletcore.moshi.PERPS_PAYMENT_TOKEN_SLUG
import org.mytonwallet.app_air.walletcore.moshi.PERPS_QUOTE_WITHDRAW
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.PerpsStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

@SuppressLint("ViewConstructor")
class FuturesBalanceWithdrawalVC(
    context: Context,
    private val accountId: String,
    private var quote: MApiPerpsBalanceWithdrawal
) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "FuturesBalanceWithdrawal"

    override val shouldDisplayBottomBar = false

    override val displayedAccount = DisplayedAccount(accountId, AccountStore.isPushedTemporary)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var isSubmitting = false

    private val token
        get() = TokenStore.getToken(PERPS_PAYMENT_TOKEN_SLUG)

    private val receiveText
        get() = "${quote.receiveAmount} $futuresPaymentSymbol"

    private val scrollView = NestedScrollView(context).apply {
        id = View.generateViewId()
        isVerticalScrollBarEnabled = false
    }
    private val content = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val sections = mutableListOf<View>()

    private val bottomPanel by lazy { ReversedCornerViewUpsideDown(context, scrollView) }

    private val noteLabel = WLabel(context).apply {
        setStyle(14f)
        setLineHeight(20f)
        text = LocaleController.getString("PerpsBalanceWithdrawalNote")
    }

    private val confirmButton = WButton(context).apply {
        id = View.generateViewId()
        type = WButton.Type.PRIMARY
        text = LocaleController.getString("Confirm")
        setOnClickListener { confirm() }
    }

    override fun setupViews() {
        super.setupViews()
        setupNavBar(true)
        navigationBar?.addCloseButton()
        setNavTitle(LocaleController.getString("PerpsBalanceWithdrawalTitle"))

        addSections()

        scrollView.addView(content, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(scrollView, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(bottomPanel, ConstraintLayout.LayoutParams(MATCH_PARENT, 0))
        view.addView(confirmButton, ConstraintLayout.LayoutParams(0, WRAP_CONTENT))
        view.setConstraints {
            toTop(scrollView)
            toCenterX(scrollView)
            bottomToTop(scrollView, confirmButton, 12f)
            toCenterX(confirmButton, 20f)
            topToTop(bottomPanel, confirmButton, -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS)
            toBottom(bottomPanel)
        }
        insetsUpdated()
        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        sections.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp,
                clipToBounds = true
            )
        }
        noteLabel.setTextColor(WColor.SecondaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        content.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) + WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )
        view.setConstraints {
            toBottomPx(
                confirmButton,
                (navigationController?.getSystemBars()?.bottom ?: 0) + BUTTON_BOTTOM_MARGIN.dp
            )
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun addSection(view: View) {
        sections += view
        content.addView(
            view,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                bottomMargin = ViewConstants.GAP.dp
            }
        )
    }

    private fun summaryCard() = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(0, 24.dp, 0, 24.dp)
        addView(
            WCustomImageView(context).apply { token?.let(::setAsset) },
            LinearLayout.LayoutParams(SUMMARY_ICON_SIZE.dp, SUMMARY_ICON_SIZE.dp)
        )
        addView(
            WLabel(context).apply {
                setStyle(14f, WFont.Medium)
                setTextColor(WColor.SecondaryText)
                text = LocaleController.getString("You Receive")
            },
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = 16.dp }
        )
        addView(
            WLabel(context).apply {
                setStyle(28f, WFont.Medium)
                setTextColor(WColor.PrimaryText)
                setSingleLine()
                text = receiveText
            },
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply { topMargin = 4.dp }
        )
    }

    private fun detailsCard() = LinearLayout(context).apply {
        orientation = LinearLayout.VERTICAL
        val rows = listOfNotNull(
            row("PerpsWithdrawalFromHyperliquid", "${quote.amount} $futuresPaymentSymbol"),
            row("PerpsBridgeFee", "${quote.bridgeFee} $futuresPaymentSymbol"),
            quote.firstTransferFee?.let {
                row("PerpsFirstWithdrawalFee", "$it $futuresPaymentSymbol")
            },
            destinationRow()
        )
        rows.forEachIndexed { index, row ->
            row.setLast(index == rows.lastIndex)
            addView(row)
        }
    }

    private fun row(key: String, value: CharSequence) =
        KeyValueRowView(context, LocaleController.getString(key), value)

    private fun destinationRow(): KeyValueRowView {
        val address = quote.destination ?: return row("PerpsWithdrawalToWallet", "—")
        val text = address.formatStartEndAddress(6, 6)
        val value = SpannableStringBuilder(text).apply {
            AddressPopupHelpers.configSpannableAddress(
                viewController = WeakReference(this@FuturesBalanceWithdrawalVC),
                title = null,
                spannedString = this,
                startIndex = 0,
                length = text.length,
                network = MBlockchainNetwork.ofAccountId(accountId),
                blockchain = MBlockchain.arbitrum,
                address = address,
                popupXOffset = 0,
                centerHorizontally = false,
                showTemporaryViewOption = false
            )
            styleDots()
            setSpan(
                WForegroundColorSpan(WColor.PrimaryText),
                0,
                text.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        return row("PerpsWithdrawalToWallet", value)
    }

    private fun addSections() {
        content.removeAllViews()
        sections.clear()
        addSection(summaryCard())
        addSection(detailsCard())
        content.addView(
            noteLabel,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                marginStart = 16.dp
                marginEnd = 16.dp
            }
        )
    }

    private fun refreshReview() {
        if (isSubmitting) return
        isSubmitting = true
        confirmButton.isLoading = true
        scope.launch {
            val refreshed = try {
                WalletCore.call(ApiMethod.Perps.PrepareBalanceWithdrawal(accountId))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                isSubmitting = false
                confirmButton.isLoading = false
                val message = (e as? JSWebViewBridge.ApiError)?.thrownMessage.orEmpty()
                showAlert(LocaleController.getString("Error"), futuresErrorText(message))
                return@launch
            }
            isSubmitting = false
            confirmButton.isLoading = false
            quote = refreshed
            addSections()
            updateTheme()
            showAlert(null, LocaleController.getString("PerpsBalanceWithdrawalUpdated"))
        }
    }

    private fun confirm() {
        if (isSubmitting) return
        if ((quote.expiresAt ?: 0) <= System.currentTimeMillis()) {
            refreshReview()
            return
        }
        ProtectedActionAuth.confirm(
            onConfirmed = ::submit,
            requiresFreshAuthentication = true,
            onPasscodeRequired = {
                push(
                    PasscodeConfirmVC(
                        context,
                        PasscodeViewState.CustomHeader(
                            passcodeHeader(),
                            LocaleController.getString("Confirm")
                        ),
                        task = ::submit
                    )
                )
            }
        )
    }

    private fun passcodeHeader(): View {
        val availableHeight = window?.windowView?.height ?: 0
        return PasscodeHeaderSendView(
            WeakReference(this),
            (availableHeight * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
        ).apply {
            token?.let {
                config(
                    Content.of(it, false),
                    receiveText,
                    LocaleController.getString("You Receive")
                )
            }
        }
    }

    private fun submit(enclaveToken: String) {
        if (isSubmitting) return
        val quoteId = quote.id ?: return
        isSubmitting = true
        view.lockView()
        confirmButton.isLoading = true
        val operationId = UUID.randomUUID().toString()
        val execution = PerpsStore.execute(
            MApiPerpsOperation(
                id = operationId,
                accountId = accountId,
                assetId = PERPS_BALANCE_WITHDRAWAL_ASSET_ID,
                kind = PERPS_QUOTE_WITHDRAW,
                state = PERPS_OPERATION_RUNNING,
                stage = "preparing",
                createdAt = System.currentTimeMillis(),
                withdrawalAmount = quote.amount,
                balanceWithdrawal = quote
            ),
            submit = {
                WalletCore.call(
                    ApiMethod.Perps.ExecuteBalanceWithdrawal(
                        accountId,
                        enclaveToken,
                        quoteId,
                        operationId
                    )
                )
            },
            resolveFailure = ::futuresSubmissionFailure
        )
        scope.launch {
            val result = execution.await()
            if (navigationController?.viewControllers?.lastOrNull() is PasscodeConfirmVC) pop()
            isSubmitting = false
            view.unlockView()
            confirmButton.isLoading = false
            if (result.state == PERPS_OPERATION_COMPLETED) {
                window?.dismissLastNav()
                return@launch
            }
            // Nothing was sent
            if (result.error == PERPS_QUOTE_EXPIRED_ERROR) {
                refreshReview()
                return@launch
            }
            showAlert(
                futuresOperationTitle(result),
                futuresOperationMessage(result),
                buttonPressed = { window?.dismissLastNav() }
            )
        }
    }

    private companion object {
        const val SUMMARY_ICON_SIZE = 80
        const val BUTTON_BOTTOM_MARGIN = 16
    }
}
