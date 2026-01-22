package org.mytonwallet.app_air.uisend.sendNft

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.widget.doOnTextChanged
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListIconDualLineCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTitleCell
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.AddressInputLayout
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class SendNftVC(
    context: Context,
    val nft: ApiNft,
) : WViewController(context), SendNftVM.Delegate, WalletCore.EventObserver {
    override val TAG = "SendNft"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    private val viewModel = SendNftVM(this, nft)

    private val separatorBackgroundDrawable = SeparatorBackgroundDrawable().apply {
        backgroundWColor = WColor.Background
    }

    private val title1 = ListTitleCell(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Send to")
    }

    private val addressInputView by lazy {
        AddressInputLayout(
            WeakReference(this),
            onTextEntered = {
                view.hideKeyboard()
            }).apply {
            id = View.generateViewId()
        }
    }

    private val title2 = ListTitleCell(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Asset")
    }

    private val nftView by lazy {
        ListIconDualLineCell(context).apply {
            id = View.generateViewId()
            configure(Content.ofUrl(nft.image ?: ""), nft.name, nft.collectionName, false, 12f.dp)
        }
    }

    private val title3 = ListTitleCell(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Comment or Memo")
    }

    private val commentInputView by lazy {
        AppCompatEditText(context).apply {
            id = View.generateViewId()
            background = null
            hint = LocaleController.getString("Add a message, if needed")
            typeface = WFont.Regular.typeface
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 8, 20, 20)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            }
        }
    }
    private val contentLayout by lazy {
        WView(context).apply {
            setPadding(
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0,
                ViewConstants.HORIZONTAL_PADDINGS.dp,
                0
            )
            addView(title1)
            addView(
                addressInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(
                title2,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(
                nftView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(title3)
            addView(
                commentInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            setConstraints {
                toTop(title1)
                topToBottom(addressInputView, title1)
                topToBottom(title2, addressInputView, ViewConstants.GAP.toFloat())
                topToBottom(nftView, title2)
                topToBottom(title3, nftView, ViewConstants.GAP.toFloat())
                topToBottom(commentInputView, title3)
                toBottom(commentInputView)
            }
        }
    }

    private val scrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            addView(
                contentLayout,
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = View.generateViewId()
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    private val continueButton by lazy {
        WButton(context).apply {
            id = View.generateViewId()
        }.apply {
            isEnabled = false
            text = LocaleController.getString("Wallet Address or Domain")
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setNavTitle(LocaleController.getString("\$send_action"))
        setupNavBar(true)

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, continueButton, 20f)
            topToTop(
                bottomReversedCornerViewUpsideDown,
                continueButton,
                -ViewConstants.GAP - ViewConstants.BIG_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }

        continueButton.setOnClickListener {
            val address = viewModel.resolvedAddress?.formatStartEndAddress() ?: ""
            val sendingToString = LocaleController.getString("Sending To")
            val startOffset = continueButton.measureText(sendingToString)
            val addressAttr =
                SpannableStringBuilder(sendingToString).apply {
                    append(" $address")
                    AddressPopupHelpers.configSpannableAddress(
                        WeakReference(this@SendNftVC),
                        null,
                        this,
                        length - address.length,
                        address.length,
                        AccountStore.activeAccount!!.network,
                        TONCOIN_SLUG,
                        viewModel.resolvedAddress!!,
                        startOffset.roundToInt(),
                        showTemporaryViewOption = false
                    )
                    styleDots()
                    setSpan(
                        WForegroundColorSpan(WColor.SecondaryText),
                        length - address.length - 1,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            val headerView = PasscodeHeaderSendView(
                WeakReference(this),
                (view.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content.ofUrl(nft.image ?: ""),
                    nft.name ?: "",
                    addressAttr,
                    Content.Rounding.Radius(12f.dp)
                )
            }
            if (AccountStore.activeAccount?.isHardware == true) {
                val account = AccountStore.activeAccount!!
                push(
                    LedgerConnectVC(
                        context,
                        LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                            account.tonAddress!!,
                            viewModel.signNftTransferData()
                        ) {
                            // Wait for Pending Activity event...
                        },
                        headerView = headerView
                    )
                )
            } else {
                push(
                    PasscodeConfirmVC(
                        context,
                        PasscodeViewState.CustomHeader(
                            headerView,
                            LocaleController.getString("Confirm")
                        ),
                        task = { passcode ->
                            sentNftAddress = nft.address
                            viewModel.submitTransferNft(
                                nft,
                                passcode
                            ) {
                                // Wait for Pending Activity event...
                            }
                        }
                    ))
            }
        }

        addressInputView.doOnTextChanged { text, _, _, _ ->
            viewModel.inputChanged(address = text.toString())
        }

        commentInputView.doOnTextChanged { text, _, _, _ ->
            viewModel.inputChanged(comment = text.toString())
        }

        updateTheme()
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        title1.setBackgroundColor(WColor.Background.color, ViewConstants.TOP_RADIUS.dp, 0f)
        title2.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            0f,
        )
        title3.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BIG_RADIUS.dp,
            0f,
        )
        addressInputView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BIG_RADIUS.dp
        )
        nftView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BIG_RADIUS.dp
        )
        commentInputView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BIG_RADIUS.dp
        )
        commentInputView.setTextColor(WColor.PrimaryText.color)
        commentInputView.setHintTextColor(WColor.SecondaryText.color)
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
        addressInputView.insetsUpdated()
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        sentNftAddress = null
    }

    override fun feeUpdated(result: MApiCheckTransactionDraftResult?, err: MBridgeError?) {
        if (result == null && err == null) {
            continueButton.isLoading = true
            return
        }
        /*val ton = TokenStore.getToken(TONCOIN_SLUG)
        ton?.let {
            result?.fee?.let { fee ->
                feeView.setTitleAndValue(
                    LocaleController.getString("Fee"),
                    fee.toString(
                        decimals = ton.decimals,
                        currency = ton.symbol,
                        currencyDecimals = ton.decimals,
                        showPositiveSign = false
                    )
                )
            }
        }*/
        continueButton.isLoading = false
        continueButton.isEnabled = err == null
        continueButton.text = err?.toLocalized ?: title
    }

    private var sentNftAddress: String? = null
    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        if (sentNftAddress == null) {
            return
        }

        val txMatch =
            receivedActivity is MApiTransaction.Transaction && receivedActivity.nft?.address == sentNftAddress
        if (!txMatch) {
            return
        }

        sentNftAddress = null
        WalletCore.unregisterObserver(this)
        if (window?.topNavigationController != navigationController) {
            window?.dismissNav(navigationController)
            return
        }
        if ((window?.navigationControllers?.size ?: 0) > 1) {
            window?.dismissLastNav {
                WalletCore.notifyEvent(
                    WalletEvent.OpenActivity(
                        displayedAccount.accountId!!,
                        receivedActivity
                    )
                )
            }
        } else {
            navigationController?.popToRoot {
                WalletCore.notifyEvent(
                    WalletEvent.OpenActivity(
                        displayedAccount.accountId!!,
                        receivedActivity
                    )
                )
            }
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.NewLocalActivities -> {
                walletEvent.localActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.forEach {
                    checkReceivedActivity(it)
                }
            }

            else -> {}
        }
    }
}
