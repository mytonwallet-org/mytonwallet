package org.mytonwallet.app_air.uisend.sendNft.sendNftConfirm

import android.content.Context
import android.graphics.Paint
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import com.google.android.material.chip.ChipGroup
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListIconDualLineCell
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AnimatedKeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WScrollView
import org.mytonwallet.app_air.uicomponents.widgets.WTagView
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
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

class ConfirmNftVC(
    context: Context,
    val mode: Mode,
    private val nfts: List<ApiNft>,
    private val comment: String?
) : WViewController(context), ConfirmNftVM.Delegate, WalletCore.EventObserver {

    override val TAG = "ConfirmNft"

    constructor(context: Context, mode: Mode, nft: ApiNft, comment: String?) : this(
        context,
        mode,
        listOf(nft),
        comment
    )

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)
    val account = AccountStore.activeAccount
    private val firstNft = nfts.first()
    private val chain = firstNft.chain ?: MBlockchain.ton

    private companion object {
        const val MAX_VISIBLE_NFT_TAGS = 10
        const val NFT_BATCH_SIZE = 4
        const val BURN_CHUNK_DURATION_APPROX_SEC = 30
    }

    sealed class Mode {
        abstract val chain: MBlockchain

        data class Send(
            override val chain: MBlockchain,
            val toAddress: String,
            val resolvedAddress: String,
            val fee: BigInteger,
            val addressName: String? = null,
            val isScam: Boolean = false
        ) : Mode()

        data class Burn(
            override val chain: MBlockchain,
        ) : Mode()
    }

    private val viewModel = ConfirmNftVM(mode, this)
    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    override var title: String?
        get() = LocaleController.getString(
            when (mode) {
                is Mode.Send -> if (nfts.size > 1) "Send Collectibles" else "Send NFT"
                is Mode.Burn -> if (nfts.size > 1) "Burn" else "Burn NFT"
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
        configure(
            Content.ofUrl(firstNft.image ?: ""),
            firstNft.name,
            firstNft.collectionName,
            false,
            12f.dp
        )
        allowSeparator(false)
    }

    private val multipleNftView = ChipGroup(context).apply {
        id = View.generateViewId()
        setPaddingDp(16)
        isSingleLine = false
        chipSpacingHorizontal = 8.dp
        chipSpacingVertical = 8.dp
        nfts.take(MAX_VISIBLE_NFT_TAGS).forEach { nft ->
            addView(WTagView(context).apply {
                configure(Content.ofUrl(nft.thumbnail ?: nft.image ?: ""), nft.name)
            })
        }
        val remainingNfts = nfts.size - MAX_VISIBLE_NFT_TAGS
        if (remainingNfts > 0) {
            addView(
                WLabel(context).apply {
                    setStyle(14f, WFont.Regular)
                    setTextColor(WColor.SecondaryText)
                    gravity = Gravity.CENTER_VERTICAL
                    text = LocaleController.getString("%amount% NFTs")
                        .replace("%amount%", "+$remainingNfts")
                },
                ViewGroup.LayoutParams(WRAP_CONTENT, 28.dp)
            )
        }
    }

    private val assetSectionView = WView(context).apply {
        if (nfts.size == 1) {
            addView(titleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            addView(nftView, ViewGroup.LayoutParams(MATCH_PARENT, ListIconDualLineCell.HEIGHT.dp))
            setConstraints {
                toTop(titleLabel)
                topToBottom(nftView, titleLabel)
            }
        } else {
            addView(multipleNftView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            setConstraints {
                toTop(multipleNftView)
            }
        }
    }

    private val addressTitleLabel = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Send to"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val addressInputView by lazy {
        CopyTextView(context).apply {
            id = View.generateViewId()
            typeface = WFont.Regular.typeface
            layoutParams = ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 12, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            val address = resolvedAddress()
            setText(
                buildRecipientPreview(address, resolvedName(), isScamAddress()),
                address
            )
            clipLabel = "Address"
            clipToast = LocaleController.getString("%chain% Address Copied")
                .replace("%chain%", mode.chain.displayName)
        }
    }

    private val memoText = comment?.trim()?.takeIf { it.isNotEmpty() }

    private val feeView = AnimatedKeyValueRowView(context).apply {
        id = View.generateViewId()
        title = LocaleController.getString("Fee")
        separator.allowSeparator = memoText != null
    }

    private val memoView by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("Memo"),
            memoText ?: "",
            KeyValueRowView.Mode.SECONDARY,
            isLast = true
        )
    }

    private val addressSectionView = WView(context).apply {
        addView(addressTitleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(addressInputView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(addressTitleLabel)
            topToBottom(addressInputView, addressTitleLabel)
        }
    }

    private val infoTitleLabel = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Info"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.NORMAL
        )
    }

    private val infoSectionView = WView(context).apply {
        addView(infoTitleLabel, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(feeView, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        if (memoText != null) {
            addView(memoView, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        }
        setConstraints {
            toTop(infoTitleLabel)
            topToBottom(feeView, infoTitleLabel)
            if (memoText != null) {
                topToBottom(memoView, feeView)
            }
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
        addView(addressSectionView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        addView(infoSectionView, ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        setConstraints {
            toTop(assetSectionView)
            topToBottom(addressSectionView, assetSectionView, ViewConstants.GAP.toFloat())
            topToBottom(infoSectionView, addressSectionView, ViewConstants.GAP.toFloat())
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

    private val burnWarningLabel by lazy {
        WAlertLabel(
            context,
            burnWarningText(),
            WColor.Red.color,
            coloredText = true
        ).apply {
            id = View.generateViewId()
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setNavTitle(title!!)
        setupNavBar(true)

        if (mode is Mode.Send && mode.isScam) {
            confirmButton.type = WButton.Type.DESTRUCTIVE
        }

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(confirmButton, ViewGroup.LayoutParams(0, 50.dp))
        if (mode is Mode.Burn) {
            view.addView(
                burnWarningLabel,
                ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                    constrainedWidth = true
                }
            )
        }
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            if (mode is Mode.Burn) {
                bottomToTop(scrollView, burnWarningLabel, 20f)
                bottomToTop(burnWarningLabel, confirmButton, 35f)
                toCenterX(burnWarningLabel, 20f)
            } else {
                bottomToTop(scrollView, confirmButton, 20f)
            }
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
                        burnWarningText(),
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
                    nfts = nfts,
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

    private fun burnWarningText(): String {
        return if (nfts.size > 1) {
            val burnWarning = LocaleController.getString("\$multi_burn_nft_warning")
                .replace("%amount%", nfts.size.toString())
                .trim()
            val durationWarning = LocaleController.getString("\$multi_send_nft_warning")
                .replace("%duration%", burnDurationMinutesText())
                .trim()
            "$burnWarning $durationWarning"
        } else {
            LocaleController.getString("Are you sure you want to burn this NFT? It will be lost forever.")
                .trim()
        }
    }

    private fun burnDurationMinutesText(): String {
        val durationMinutes =
            (ceil(nfts.size / NFT_BATCH_SIZE.toDouble()) * BURN_CHUNK_DURATION_APPROX_SEC) / 60
        return if (durationMinutes % 1.0 == 0.0) {
            durationMinutes.roundToInt().toString()
        } else {
            durationMinutes.toString()
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
        multipleNftView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        addressSectionView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        infoSectionView.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        val address = resolvedAddress()
        addressInputView.setText(
            buildRecipientPreview(address, resolvedName(), isScamAddress()),
            address
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setConstraints {
            toBottomPx(
                confirmButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        sentNftAddresses = null
    }

    override fun feeUpdated(fee: BigInteger?, err: MBridgeError?) {
        val address = resolvedAddress()
        addressInputView.setText(
            buildRecipientPreview(address, resolvedName(), isScamAddress()),
            address
        )
        val nativeToken = TokenStore.getToken(mode.chain.nativeSlug)
        nativeToken?.let {
            fee?.let { fee ->
                feeView.setTitleAndValue(
                    LocaleController.getString("Fee"),
                    fee.toString(
                        decimals = nativeToken.decimals,
                        currency = nativeToken.symbol,
                        currencyDecimals = fee.smartDecimalsCount(nativeToken.decimals),
                        showPositiveSign = false
                    )
                )
            }
        }
        confirmButton.isLoading = false
        confirmButton.isEnabled = err == null
        confirmButton.text = err?.toLocalized ?: title
    }

    private fun resolvedAddress(): String {
        return viewModel.resolvedAddress ?: viewModel.toAddress
    }

    private fun resolvedName(): String? {
        return (mode as? Mode.Send)?.addressName
    }

    private fun isScamAddress(): Boolean {
        return (mode as? Mode.Send)?.isScam == true
    }

    private fun buildRecipientPreview(
        address: String,
        name: String?,
        isScam: Boolean
    ): CharSequence {
        val safeName = name?.takeIf { it.isNotBlank() }
        return buildSpannedString {
            if (isScam) {
                append(" ", scamLabelSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                append(" ")
            }

            if (!isScam && safeName != null) {
                inSpans(WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryText.color)) {
                    append(safeName)
                }
                append(" · ")
            }

            append(buildAddressSpan(address)).styleDots()
        }.replaceSpacesWithNbsp()
    }

    private fun buildAddressSpan(address: String): CharSequence {
        if (address.length <= 12) {
            return buildSpannedString {
                inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                    append(address)
                }
            }
        }
        val prefix = address.take(6)
        val suffix = address.takeLast(6)
        val middle = address.substring(6, address.length - 6)
        return buildSpannedString {
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                append(prefix)
            }
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.SecondaryText.color)) {
                append(middle)
            }
            inSpans(WTypefaceSpan(WFont.Regular.typeface, WColor.PrimaryText.color)) {
                append(suffix)
            }
        }
    }

    private fun confirmSend() {
        if (account?.isHardware == true) {
            sentNftAddresses = nfts.mapTo(mutableSetOf()) { it.address }
            push(
                LedgerConnectVC(
                    context,
                    LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                        account.tonAddress!!,
                        viewModel.signNftTransferData(nfts, mode is Mode.Burn, comment)
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
                        sentNftAddresses = nfts.mapTo(mutableSetOf()) { it.address }
                        viewModel.submitTransferNft(
                            nfts,
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
                        blockchain = chain,
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
                    Content.ofUrl(firstNft.image ?: ""),
                    if (nfts.size == 1) {
                        firstNft.name ?: ""
                    } else {
                        LocaleController.getString("%amount% NFTs")
                            .replace("%amount%", nfts.size.toString())
                    },
                    addressAttr,
                    Content.Rounding.Radius(12f.dp)
                )
            }
        }

    private var sentNftAddresses: MutableSet<String>? = null
    private fun checkReceivedActivity(receivedActivity: MApiTransaction) {
        val pendingAddresses = sentNftAddresses ?: return
        val nftAddress = (receivedActivity as? MApiTransaction.Transaction)?.nft?.address ?: return
        if (!pendingAddresses.remove(nftAddress)) {
            return
        }
        if (pendingAddresses.isNotEmpty()) {
            return
        }

        sentNftAddresses = null
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
