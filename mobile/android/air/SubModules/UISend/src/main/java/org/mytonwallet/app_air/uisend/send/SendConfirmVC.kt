package org.mytonwallet.app_air.uisend.send

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.ScamLabelSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.spans.WForegroundColorSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.unlockView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uisend.send.lauouts.ConfirmAmountView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.models.MBaseCurrency
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcore.moshi.MApiSubmitTransferOptions
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class SendConfirmVC(
    context: Context,
    private val config: SendViewModel.DraftResult.Result,
    private val transferOptions: MApiSubmitTransferOptions,
    private val slug: String,
    private val name: String? = null,
    private val isScam: Boolean = false,
    private val isSell: Boolean = false
) : WViewController(context) {
    override val TAG = "SendConfirm"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)
    private var isShowingAccountMultichain =
        WGlobalStorage.isMultichain(AccountStore.activeAccountId!!)

    private var task: ((passcode: String?) -> Unit)? = null
    private val scamLabelSpan by lazy {
        ScamLabelSpan(LocaleController.getString("Scam").uppercase())
    }

    fun setNextTask(task: (passcode: String?) -> Unit) {
        this.task = task
    }

    private val amountInfoView by lazy {
        ConfirmAmountView(context).apply {
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)

            val amount = SpannableStringBuilder(config.request.amountEquivalent.getFmt(false))
            CoinUtils.setSpanToFractionalPart(amount, WForegroundColorSpan(WColor.SecondaryText))
            set(
                Content.of(config.request.token, showChain = isShowingAccountMultichain),
                amount = amount,
                currency = config.request.amountEquivalent.getFmt(true),
                fee = LocaleController.getString("\$fee_value_with_colon").replace(
                    "%fee%", config.showingFee?.toString(
                        config.request.token,
                        appendNonNative = true
                    ) ?: ""
                )
            )
        }
    }
    private val title1 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Send to"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val addressInputView by lazy {
        CopyTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 19, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            val destination = config.request.input.destination
            val resolved = resolvedAddress(destination)
            setText(
                buildRecipientPreview(resolved),
                resolved
            )
            clipLabel = "Address"
            clipToast = LocaleController.getString("%chain% Address Copied")
                .replace("%chain%", config.request.token.mBlockchain?.displayName ?: "")
        }
    }

    private val commentInputView by lazy {
        AppCompatTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 20, 20, 14)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = config.request.input.comment
        }
    }

    private val gap1 = ListGapCell(context)
    private val title2 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Amount"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val gap2 = ListGapCell(context)
    private val title3 = HeaderCell(context).apply {
        configure(
            title = LocaleController.getString("Comment or Memo"),
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )
    }

    private val signatureWarningGap = ListGapCell(context)

    private val signatureWarning by lazy {
        WAlertLabel(
            context,
            LocaleController.getString("\$signature_warning"),
            WColor.Red.color,
            coloredText = true
        )
    }

    private val binaryMessageGap = ListGapCell(context)

    private val binaryMessageTitle by lazy {
        HeaderCell(context).apply {
            configure(
                title = LocaleController.getString("Signing Data"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private val binaryMessageView by lazy {
        CopyTextView(context).apply {
            id = View.generateViewId()
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 14, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = config.request.input.binary
            clipLabel = "Signing Data"
            clipToast = LocaleController.getString("Data Copied")
        }
    }

    private val initDataGap = ListGapCell(context)

    private val initDataTitle by lazy {
        HeaderCell(context).apply {
            configure(
                title = LocaleController.getString("Contract Initialization Data"),
                titleColor = WColor.Tint,
                topRounding = HeaderCell.TopRounding.FIRST_ITEM
            )
        }
    }

    private val initDataView by lazy {
        CopyTextView(context).apply {
            id = View.generateViewId()
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 14, 20, 14)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = config.request.input.stateInit
            clipLabel = "Contract Initialization Data"
            clipToast = LocaleController.getString("Contract Initialization Data Copied")
        }
    }

    private val linearLayout by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            addView(title1)
            addView(addressInputView)
            addView(gap1)
            addView(title2)
            addView(
                amountInfoView,
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )

            if (config.request.input.comment.isNotEmpty() && config.request.input.binary == null) {
                addView(gap2)
                addView(title3)
                addView(
                    commentInputView,
                    LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
            }

            if (config.request.input.binary != null) {
                addView(signatureWarningGap)
                addView(signatureWarning)
                addView(binaryMessageGap)
                addView(binaryMessageTitle)
                addView(binaryMessageView)
            }

            if (config.request.input.stateInit != null) {
                addView(initDataGap)
                addView(initDataTitle)
                addView(initDataView)
            }
        }
    }

    private val scrollView by lazy {
        ScrollView(context).apply {
            addView(
                linearLayout,
                ViewGroup.LayoutParams(
                    MATCH_PARENT,
                    WRAP_CONTENT
                )
            )
            id = View.generateViewId()
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
            isVerticalScrollBarEnabled = false
        }
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, scrollView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    private val confirmButton by lazy {
        WButton(context, WButton.Type.PRIMARY).apply {
            id = View.generateViewId()
            text = LocaleController.getString("Confirm")
            setOnClickListener {
                if (AccountStore.activeAccount?.isHardware == true) {
                    confirmHardware(transferOptions)
                } else {
                    confirmWithPassword()
                }
            }
        }
    }

    private val cancelButton by lazy {
        WButton(context, WButton.Type.SECONDARY_WITH_BACKGROUND).apply {
            id = View.generateViewId()
            text = LocaleController.getString("Edit")
            setOnClickListener { pop() }
        }
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(if (isSell) LocaleController.getString("Sell") else LocaleController.getString("Is it all ok?"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        if (isScam) {
            confirmButton.type = WButton.Type.DESTRUCTIVE
        }

        if (isSell) {
            val tokenSymbol = config.request.token.symbol ?: MBaseCurrency.TON.currencyCode
            confirmButton.text = LocaleController.getStringWithKeyValues(
                "Sell %symbol%",
                listOf("%symbol%" to tokenSymbol)
            )
            cancelButton.isGone = true
        }

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
            )
        )
        view.addView(cancelButton, ViewGroup.LayoutParams(0, 50.dp))
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
            topToTop(
                bottomReversedCornerViewUpsideDown,
                confirmButton,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            if (isSell) {
                toLeft(confirmButton)
                toRight(confirmButton)
                setMargin(confirmButton.id, ConstraintSet.START, 20.dp)
                setMargin(confirmButton.id, ConstraintSet.END, 20.dp)
            } else {
                toBottomPx(
                    cancelButton, 20.dp + max(
                        (navigationController?.getSystemBars()?.bottom ?: 0),
                        (window?.imeInsets?.bottom ?: 0)
                    )
                )
                topToTop(
                    bottomReversedCornerViewUpsideDown,
                    cancelButton,
                    -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
                )
                topToTop(confirmButton, cancelButton)
                toLeft(cancelButton)
                leftToRight(confirmButton, cancelButton)
                toRight(confirmButton)
                setMargin(cancelButton.id, ConstraintSet.START, 20.dp)
                setMargin(confirmButton.id, ConstraintSet.START, 8.dp)
                setMargin(confirmButton.id, ConstraintSet.END, 20.dp)
                createHorizontalChain(
                    ConstraintSet.PARENT_ID, ConstraintSet.LEFT,
                    ConstraintSet.PARENT_ID, ConstraintSet.RIGHT,
                    if (LocaleController.isRTL)
                        intArrayOf(confirmButton.id, cancelButton.id)
                    else
                        intArrayOf(cancelButton.id, confirmButton.id),
                    null,
                    ConstraintSet.CHAIN_SPREAD
                )
            }
        }

        updateTheme()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)

        val topRoundedItems = listOf(
            title1, title2, title3, binaryMessageTitle, initDataTitle
        )
        val bottomRoundedItems = listOf(
            addressInputView, amountInfoView, commentInputView, binaryMessageView, initDataView
        )
        val primaryTextColored = listOf(
            addressInputView, commentInputView, binaryMessageView, initDataView
        )

        topRoundedItems.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                0f
            )
        }

        bottomRoundedItems.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BLOCK_RADIUS.dp
            )
        }

        primaryTextColored.forEach {
            it.setTextColor(WColor.PrimaryText.color)
        }

        gap1.showSeparator = false
        gap2.showSeparator = false
        gap1.invalidate()
        gap2.invalidate()

        val destination = config.request.input.destination
        val resolved = resolvedAddress(destination)
        addressInputView.setText(
            buildRecipientPreview(resolved),
            resolved
        )
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        linearLayout.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        view.setConstraints {
            toBottomPx(
                if (isSell) confirmButton else cancelButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun resolvedAddress(destination: String): String {
        return config.resolvedAddress ?: destination
    }

    private fun resolvedName(): String? {
        return name ?: config.addressName
    }

    private fun buildRecipientPreview(address: String): CharSequence {
        val name = resolvedName()?.takeIf { it.isNotBlank() }
        return buildSpannedString {
            if (isScam) {
                append(" ", scamLabelSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                append(" ")
            }

            if (!isScam && name != null) {
                inSpans(WTypefaceSpan(WFont.Medium.typeface, WColor.PrimaryText.color)) {
                    append(name)
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

    private fun confirmHardware(transferOptions: MApiSubmitTransferOptions) {
        Logger.d(
            Logger.LogTag.SEND,
            "confirmHardware: Confirming send with hardware wallet slug=$slug"
        )
        confirmButton.lockView()
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignTransfer(
                    accountId = account.accountId,
                    transferOptions = transferOptions,
                    slug = slug
                ),
                onDone = {
                    task?.invoke(null)
                }),
            headerView = PasscodeHeaderSendView(
                WeakReference(this),
                (view.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                configSendingToken(
                    config.request.token,
                    config.request.amountEquivalent.getFmt(false),
                    account.network,
                    config.resolvedAddress
                )
            }
        )
        push(ledgerConnectVC, onCompletion = {
            confirmButton.unlockView()
        })
    }

    private fun confirmWithPassword() {
        Logger.d(
            Logger.LogTag.SEND,
            "confirmWithPassword: Confirming send with passcode slug=$slug"
        )
        push(
            PasscodeConfirmVC(
                context,
                PasscodeViewState.CustomHeader(
                    PasscodeHeaderSendView(
                        WeakReference(this),
                        (view.height * 0.25f).roundToInt()
                    ).apply {
                        configSendingToken(
                            config.request.token,
                            config.request.amountEquivalent.getFmt(false),
                            AccountStore.activeAccount!!.network,
                            config.resolvedAddress
                        )
                    },
                    LocaleController.getString("Confirm")
                ),
                task = { passcode -> task?.invoke(passcode) }
            ))
    }
}
