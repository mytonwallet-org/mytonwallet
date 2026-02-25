package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Drawable
import android.text.Spannable
import android.text.SpannableString
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.content.ContextCompat
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AnimatedKeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListIconDualLineCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ExtraHitLinkMovementMethod
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WView
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
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiCheckTransactionDraftResult
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.max
import kotlin.math.roundToInt

class ConfirmNftVC(
    context: Context,
    val mode: Mode,
    private val nft: ApiNft,
    private val comment: String?
) :
    WViewController(context),
    ConfirmNftVM.Delegate, WalletCore.EventObserver {
    override val TAG = "ConfirmNft"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)
    val account = AccountStore.activeAccount

    sealed class Mode {
        abstract val chain: MBlockchain

        data class Send(
            override val chain: MBlockchain,
            val toAddress: String,
            val resolvedAddress: String,
            val fee: BigInteger
        ) : Mode()

        data class Burn(
            override val chain: MBlockchain,
        ) : Mode()
    }

    private val viewModel = ConfirmNftVM(mode, this)

    override var title: String?
        get() = LocaleController.getString(
            when (mode) {
                is Mode.Send -> "Send NFT"
                is Mode.Burn -> "Burn NFT"
            }
        )
        set(_) {}

    private val titleLabel = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Asset"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val nftView = ListIconDualLineCell(context).apply {
        id = View.generateViewId()
        configure(Content.ofUrl(nft.image ?: ""), nft.name, nft.collectionName, false, 12f.dp)
        allowSeparator(false)
    }

    private val assetSectionView = WView(context).apply {
        addView(titleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(nftView, ViewGroup.LayoutParams(MATCH_PARENT, ListIconDualLineCell.HEIGHT.dp))
        setConstraints {
            toTop(titleLabel)
            topToBottom(nftView, titleLabel)
        }
    }

    private val detailsTitleLabel = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Details"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val sendToView: KeyValueRowView by lazy {
        val value: CharSequence
        when (mode) {
            is Mode.Burn -> {
                val burnAttr = SpannableStringBuilder()
                val drawable = ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.icons.R.drawable.ic_fire_24
                )!!
                drawable.setBounds(0, 0, 24.dp, 24.dp)
                val imageSpan = VerticalImageSpan(drawable)
                burnAttr.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                burnAttr.append(SpannableString(" ${LocaleController.getString("Burn NFT")}").apply {
                    setSpan(
                        WTypefaceSpan(WFont.Regular.typeface),
                        0,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                })
                value = burnAttr
            }

            is Mode.Send -> {
                value = mode.toAddress
            }
        }
        KeyValueRowView(
            context,
            LocaleController.getString("Send to"),
            value,
            KeyValueRowView.Mode.SECONDARY,
            isLast = false
        )
    }

    private val toAddressLabel: WLabel by lazy {
        WLabel(context).apply {
            val address = viewModel.resolvedAddress ?: viewModel.toAddress
            val formattedAddress = address.formatStartEndAddress()
            val addressAttr = SpannableStringBuilder(formattedAddress).apply {
                AddressPopupHelpers.configSpannableAddress(
                    viewController = WeakReference(this@ConfirmNftVC),
                    title = null,
                    spannedString = this,
                    startIndex = length - formattedAddress.length,
                    length = formattedAddress.length,
                    network = AccountStore.activeAccount!!.network,
                    blockchain = nft.chain,
                    address = address,
                    popupXOffset = 0,
                    centerHorizontally = false,
                    showTemporaryViewOption = false
                )
                styleDots()
                setSpan(
                    WForegroundColorSpan(WColor.SecondaryText),
                    length - formattedAddress.length - 1,
                    length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            text = addressAttr
            setPaddingDp(8, 4, 8, 4)
            movementMethod = ExtraHitLinkMovementMethod(paddingLeft, paddingTop)
            highlightColor = Color.TRANSPARENT
        }
    }

    private val recipientAddressView: KeyValueRowView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("Recipient Address"),
            "",
            KeyValueRowView.Mode.SECONDARY,
            isLast = false
        ).apply {
            setValueView(toAddressLabel)
        }
    }

    private val feeView = AnimatedKeyValueRowView(context).apply {
        id = View.generateViewId()
        title = LocaleController.getString("Fee")
        separator.allowSeparator = false
    }

    private val detailsSectionView = WView(context).apply {
        addView(detailsTitleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(sendToView, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        when (mode) {
            is Mode.Send -> {
                if (mode.resolvedAddress == mode.toAddress)
                    sendToView.visibility = View.GONE
            }

            else -> {}
        }
        addView(recipientAddressView, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        addView(feeView, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        setConstraints {
            toTop(detailsTitleLabel)
            topToBottom(sendToView, detailsTitleLabel)
            topToBottom(recipientAddressView, sendToView)
            topToBottom(feeView, recipientAddressView)
        }
    }

    private val contentView = WView(context).apply {
        setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        addView(assetSectionView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(detailsSectionView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(assetSectionView)
            topToBottom(detailsSectionView, assetSectionView, ViewConstants.GAP.toFloat())
        }
    }

    private val scrollView by lazy {
        WScrollView(WeakReference(this)).apply {
            addView(
                contentView,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    WRAP_CONTENT
                )
            )
            id = View.generateViewId()
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    private val confirmButton by lazy {
        WButton(
            context,
            if (mode is Mode.Burn) WButton.Type.DESTRUCTIVE else WButton.Type.PRIMARY
        ).apply {
            id = View.generateViewId()
            text = title
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setNavTitle(title!!)
        setupNavBar(true)

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(confirmButton, ViewGroup.LayoutParams(0, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, confirmButton, 20f)
            topToTop(
                bottomReversedCornerViewUpsideDown,
                confirmButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toBottomPx(
                confirmButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
            toCenterX(confirmButton, 20f)
        }

        confirmButton.setOnClickListener {
            when (mode) {
                is Mode.Burn -> {
                    showAlert(
                        title,
                        LocaleController.getString("Are you sure you want to burn this NFT? It will be lost forever.")
                            .trim(),
                        button = LocaleController.getString("Confirm"),
                        buttonPressed = {
                            confirmSend()
                        },
                        secondaryButton = LocaleController.getString("No"),
                        secondaryButtonPressed = {
                        },
                        preferPrimary = false,
                        primaryIsDanger = true
                    )
                }

                is Mode.Send -> {
                    confirmSend()
                }
            }
        }

        updateTheme()

        when (mode) {
            is Mode.Burn -> {
                confirmButton.isLoading = true
                viewModel.requestFee(
                    nft = nft,
                    isNftBurn = true,
                    comment = comment
                )
            }
            is Mode.Send -> {
                confirmButton.isLoading = false
                feeUpdated(mode.fee, null)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        assetSectionView.setBackgroundColor(
            WColor.Background.color,
            0f,
            ViewConstants.BLOCK_RADIUS.dp
        )
        detailsSectionView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        sentNftAddress = null
    }

    override fun feeUpdated(fee: BigInteger?, err: MBridgeError?) {
        val ton = TokenStore.getToken(TONCOIN_SLUG)
        ton?.let {
            fee?.let { fee ->
                feeView.setTitleAndValue(
                    LocaleController.getString("Fee"),
                    fee.toString(
                        decimals = ton.decimals,
                        currency = ton.symbol,
                        currencyDecimals = fee.smartDecimalsCount(ton.decimals),
                        showPositiveSign = false
                    )
                )
            }
        }
        confirmButton.isLoading = false
        confirmButton.isEnabled = err == null
        confirmButton.text = err?.toLocalized ?: title
    }

    private fun confirmSend() {
        if (account?.isHardware == true) {
            sentNftAddress = nft.address
            push(
                LedgerConnectVC(
                    context,
                    LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                        account.tonAddress!!,
                        viewModel.signNftTransferData(nft, mode is Mode.Burn, comment)
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
                            mode is Mode.Burn,
                            comment,
                            passcode
                        ) {
                            // Wait for Pending Activity event...
                        }
                    }
                )
            )
        }
    }

    private val headerView: View
        get() {
            val address = viewModel.resolvedAddress?.formatStartEndAddress() ?: ""
            val sendingToString = LocaleController.getString("Sending to")
            val startOffset = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = WFont.Regular.typeface
                textSize = 16f.dp
            }.measureText(sendingToString)
            val addressAttr =
                SpannableStringBuilder(sendingToString).apply {
                    append(" $address")
                    AddressPopupHelpers.configSpannableAddress(
                        viewController = WeakReference(this@ConfirmNftVC),
                        title = null,
                        spannedString = this,
                        startIndex = length - address.length,
                        length = address.length,
                        network = displayedAccount.network,
                        blockchain = nft.chain,
                        address = viewModel.resolvedAddress!!,
                        popupXOffset = startOffset.roundToInt(),
                        centerHorizontally = false,
                        showTemporaryViewOption = false
                    )
                    styleDots(sendingToString.length + 1)
                    setSpan(
                        WForegroundColorSpan(WColor.SecondaryText),
                        length - address.length - 1,
                        length,
                        Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                    )
                }
            return PasscodeHeaderSendView(
                WeakReference(this@ConfirmNftVC),
                (view.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content.ofUrl(nft.image ?: ""),
                    nft.name ?: "",
                    addressAttr,
                    Content.Rounding.Radius(12f.dp)
                )
            }
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
