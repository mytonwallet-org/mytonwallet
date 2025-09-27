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
import android.text.TextUtils
import android.text.method.LinkMovementMethod
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import androidx.core.content.ContextCompat
import androidx.core.view.isGone
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.AnimatedKeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.image.WCustomImageView
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
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MBridgeError
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

    sealed class Mode {
        data class Send(
            val toAddress: String,
            val resolvedAddress: String,
            val fee: BigInteger
        ) : Mode()

        data object Burn : Mode()
    }

    private val viewModel = ConfirmNftVM(this)

    override var title: String?
        get() = LocaleController.getString(
            when (mode) {
                is Mode.Send -> "Send NFT"
                is Mode.Burn -> "Burn NFT"
            }
        )
        set(_) {}
    override val shouldDisplayBottomBar = true

    private val separatorDrawable: Drawable by lazy {
        SeparatorBackgroundDrawable().apply {
            backgroundWColor = WColor.Background
        }
    }

    private val titleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = LocaleController.getString("Asset")
    }

    private val nftImageView = WCustomImageView(context).apply {
        defaultRounding = Content.Rounding.Radius(12f.dp)
        set(Content.ofUrl(nft.image ?: ""))
    }

    private val nftTitleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = nft.name
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val nftDescriptionLabel = WLabel(context).apply {
        setStyle(14f)
        text = nft.collectionName
        setSingleLine()
        ellipsize = TextUtils.TruncateAt.END
    }

    private val nftInformationView = WView(context).apply {
        addView(nftTitleLabel)
        addView(nftDescriptionLabel)
        setConstraints {
            toTop(nftTitleLabel)
            topToBottom(nftDescriptionLabel, nftTitleLabel)
            toBottom(nftDescriptionLabel)
            toStart(nftTitleLabel)
            toStart(nftDescriptionLabel)
        }
    }

    private val assetSectionView = WView(context).apply {
        addView(titleLabel)
        addView(nftImageView, ViewGroup.LayoutParams(48.dp, 48.dp))
        addView(nftInformationView, ViewGroup.LayoutParams(0, WRAP_CONTENT))
        setConstraints {
            toTop(titleLabel, 16f)
            toStart(titleLabel, 20f)
            toTop(nftImageView, 48f)
            toStart(nftImageView, 20f)
            startToEnd(nftInformationView, nftImageView, 12f)
            centerYToCenterY(nftInformationView, nftImageView)
            toBottom(nftImageView, 16f)
        }
    }

    private val detailsTitleLabel = WLabel(context).apply {
        setStyle(16f, WFont.Medium)
        text = LocaleController.getString("Details")
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
            val address = viewModel.toAddress(mode)
            val formattedAddress = address.formatStartEndAddress()
            val addressAttr = SpannableStringBuilder(formattedAddress).apply {
                AddressPopupHelpers.configSpannableAddress(
                    WeakReference(this@ConfirmNftVC),
                    this,
                    length - formattedAddress.length,
                    formattedAddress.length,
                    TONCOIN_SLUG,
                    address,
                    0
                )
                updateDotsTypeface()
                setSpan(
                    WForegroundColorSpan(WColor.SecondaryText),
                    length - formattedAddress.length - 1,
                    length,
                    Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            text = addressAttr
            movementMethod = LinkMovementMethod.getInstance()
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
        addView(detailsTitleLabel)
        addView(sendToView, ViewGroup.LayoutParams(MATCH_PARENT, 56.dp))
        when (mode) {
            is Mode.Send -> {
                if (mode.resolvedAddress == mode.toAddress)
                    sendToView.visibility = View.GONE
            }

            else -> {}
        }
        addView(recipientAddressView, ViewGroup.LayoutParams(MATCH_PARENT, 56.dp))
        addView(feeView, ViewGroup.LayoutParams(MATCH_PARENT, 56.dp))
        setConstraints {
            toTop(detailsTitleLabel, 16f)
            toStart(detailsTitleLabel, 20f)
            toTop(sendToView, 48f)
            topToBottom(
                recipientAddressView,
                sendToView,
                if (sendToView.isGone) 48f else 0f
            )
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

    private val confirmButton by lazy {
        WButton(
            context,
            if (mode == Mode.Burn) WButton.Type.DESTRUCTIVE else WButton.Type.PRIMARY
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
        view.addView(confirmButton, ViewGroup.LayoutParams(0, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, confirmButton, 20f)
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

        if (mode == Mode.Burn) {
            confirmButton.isLoading = true
            viewModel.requestFee(
                nft,
                mode,
                comment
            )
        } else {
            confirmButton.isLoading = false
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color)
        if (ThemeManager.uiMode.hasRoundedCorners) {
            assetSectionView.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOP_RADIUS.dp,
                ViewConstants.BIG_RADIUS.dp
            )
            detailsSectionView.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BIG_RADIUS.dp
            )
        } else {
            assetSectionView.background = separatorDrawable
            detailsSectionView.background = separatorDrawable
            separatorDrawable.invalidateSelf()
        }
        titleLabel.setTextColor(WColor.PrimaryText.color)
        nftTitleLabel.setTextColor(WColor.PrimaryText.color)
        nftDescriptionLabel.setTextColor(WColor.SecondaryText.color)
        detailsTitleLabel.setTextColor(WColor.PrimaryText.color)
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)
        sentNftAddress = null
    }

    override fun feeUpdated(result: MApiCheckTransactionDraftResult?, err: MBridgeError?) {
        val ton = TokenStore.getToken(TONCOIN_SLUG)
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
        }
        confirmButton.isLoading = false
        confirmButton.isEnabled = err == null
        confirmButton.text = err?.toLocalized ?: title
    }

    private fun confirmSend() {
        if (AccountStore.activeAccount?.isHardware == true) {
            val account = AccountStore.activeAccount!!
            sentNftAddress = nft.address
            push(
                LedgerConnectVC(
                    context,
                    LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                        account.tonAddress!!,
                        viewModel.signNftTransferData(nft, comment)
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
            val sendingToString = LocaleController.getString("Sending To")
            val startOffset = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                typeface = WFont.Regular.typeface
                textSize = 16f.dp
            }.measureText(sendingToString)
            val addressAttr =
                SpannableStringBuilder(sendingToString).apply {
                    append(" $address")
                    AddressPopupHelpers.configSpannableAddress(
                        WeakReference(this@ConfirmNftVC),
                        this,
                        length - address.length,
                        address.length,
                        TONCOIN_SLUG,
                        viewModel.resolvedAddress!!,
                        startOffset.roundToInt()
                    )
                    updateDotsTypeface(sendingToString.length + 1)
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
    override fun onWalletEvent(walletEvent: WalletEvent) {
        val sentNftAddress = sentNftAddress ?: return
        when (walletEvent) {
            is WalletEvent.ReceivedPendingActivities -> {
                val activity = walletEvent.pendingActivities?.firstOrNull { activity ->
                    activity is MApiTransaction.Transaction &&
                        activity.nft?.address == sentNftAddress
                } ?: return
                this@ConfirmNftVC.sentNftAddress = null
                navigationController?.popToRoot(onCompletion = {
                    WalletCore.notifyEvent(WalletEvent.OpenActivity(activity))
                })
            }

            else -> {}
        }
    }
}
