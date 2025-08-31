package org.mytonwallet.app_air.uisend.send

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Build
import android.text.Editable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextWatcher
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatEditText
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.core.view.isGone
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.sqscan.screen.QrScannerDialog
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTitleCell
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.TokenAmountInputView
import org.mytonwallet.app_air.uicomponents.commonViews.feeDetailsDialog.FeeDetailsDialog
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.DieselAuthorizationHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.viewControllers.SendTokenVC
import org.mytonwallet.app_air.uicomponents.widgets.CopyTextView
import org.mytonwallet.app_air.uicomponents.widgets.WAlertLabel
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.hideKeyboard
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.showKeyboard
import org.mytonwallet.app_air.uisend.send.helpers.ScamDetectionHelpers
import org.mytonwallet.app_air.uisend.send.lauouts.AddressInputLayout
import org.mytonwallet.app_air.uisend.sent.SentVC
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ThemeManager
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletcontext.utils.toProcessedSpannableStringBuilder
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.PRICELESS_TOKEN_HASHES
import org.mytonwallet.app_air.walletcore.STAKED_MYCOIN_SLUG
import org.mytonwallet.app_air.walletcore.STAKED_USDE_SLUG
import org.mytonwallet.app_air.walletcore.STAKE_SLUG
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.deeplink.Deeplink
import org.mytonwallet.app_air.walletcore.deeplink.DeeplinkParser
import org.mytonwallet.app_air.walletcore.models.MBlockchain
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger
import kotlin.math.max

@SuppressLint("ViewConstructor")
class SendVC(
    context: Context,
    private val initialTokenSlug: String? = null,
    private val initialValues: InitialValues? = null,
) : WViewControllerWithModelStore(context) {
    private val viewModel by lazy { ViewModelProvider(this)[SendViewModel::class.java] }

    data class InitialValues(
        val address: String?,
        val amount: String? = null,
        val binary: String? = null,
        val comment: String? = null,
        val init: String? = null,
    )

    private val topGapView = View(context).apply {
        id = View.generateViewId()
    }

    private val title1 = ListTitleCell(context).apply {
        id = View.generateViewId()
        text = LocaleController.getString("Send to")
    }

    private val gap1 by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val amountInputView by lazy {
        TokenAmountInputView(context).apply {
            id = View.generateViewId()
        }
    }
    private val addressInputView by lazy {
        AddressInputLayout(context, onPaste = {
            amountInputView.amountEditText.requestFocus()
            amountInputView.amountEditText.showKeyboard()
        }).apply {
            id = View.generateViewId()
        }
    }

    private val gap2 by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val title2 = ListTitleCell(context).apply {
        id = View.generateViewId()
        setOnClickListener {
            if (AccountStore.activeAccount?.supportsCommentEncryption != true)
                return@setOnClickListener
            WMenuPopup.present(
                this@apply,
                listOf(
                    WMenuPopup.Item(
                        null,
                        LocaleController.getString("Comment or Memo"),
                        false,
                    ) {
                        viewModel.onShouldEncrypt(false)
                        updateCommentTitleLabel()
                    },
                    WMenuPopup.Item(
                        null,
                        LocaleController.getString("Encrypted Message"),
                        false,
                    ) {
                        viewModel.onShouldEncrypt(true)
                        updateCommentTitleLabel()
                    }),
                offset = if (LocaleController.isRTL) width - 190.dp else 20.dp,
                popupWidth = 180.dp,
                aboveView = false
            )
        }
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

    private val signatureWarningGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val signatureWarning by lazy {
        WAlertLabel(
            context,
            LocaleController.getString("\$signature_warning"),
            WColor.Red.color,
            coloredText = true
        )
    }

    private val binaryMessageGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val binaryMessageTitle by lazy {
        ListTitleCell(context).apply {
            id = View.generateViewId()
            text = LocaleController.getString("Signing Data")
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
            setPaddingDp(20, 8, 20, 20)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = initialValues?.binary
            clipLabel = LocaleController.getString("Signing Data")
            clipToast = LocaleController.getString("Signing Data was copied!")
        }
    }

    private val initDataGap by lazy { ListGapCell(context, ViewConstants.GAP.dp) }

    private val initDataTitle by lazy {
        ListTitleCell(context).apply {
            id = View.generateViewId()
            text = LocaleController.getString("Contract Initialization Data")
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
            setPaddingDp(20, 8, 20, 20)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = initialValues?.init
            clipLabel = LocaleController.getString("Contract Initialization Data")
            clipToast = LocaleController.getString("Contract Initialization Data was copied!")
        }
    }

    private val linearLayout by lazy {
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL

            val hasBinary = initialValues?.binary != null
            val hasInit = initialValues?.init != null

            addView(
                topGapView,
                ConstraintLayout.LayoutParams(
                    MATCH_PARENT,
                    (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT.dp
                )
            )
            addView(title1)
            addView(
                addressInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            addView(gap1)
            addView(
                amountInputView,
                ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            if (!hasBinary) {
                addView(gap2)
                addView(title2)
                addView(
                    commentInputView,
                    ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
                )
            }
            if (hasBinary) {
                addView(signatureWarningGap)
                addView(signatureWarning)
                // ^ It is better to place this one here, otherwise users may not scroll down enough to see it
                addView(binaryMessageGap)
                addView(binaryMessageTitle)
                addView(binaryMessageView)
            }
            if (hasInit) {
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
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            )
            id = View.generateViewId()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setOnScrollChangeListener { _, _, scrollY, _, _ ->
                    updateBlurViews(scrollView = this, computedOffset = scrollY)
                }
            }
            overScrollMode = ScrollView.OVER_SCROLL_ALWAYS
        }
    }

    private val continueButton by lazy {
        WButton(context).apply {
            id = View.generateViewId()
        }
    }

    private val onInputCommentTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            viewModel.onInputComment(s?.toString() ?: "")
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private val onInputDestinationTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            val address = s?.toString() ?: ""
            viewModel.onInputDestination(address)
            switchTokenBasedOnChain(address)
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    private val onAmountTextWatcher = object : TextWatcher {
        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            viewModel.onInputAmount(s?.toString() ?: "")
        }

        override fun afterTextChanged(s: Editable?) {}
    }

    override fun setupViews() {
        super.setupViews()
        setNavTitle(LocaleController.getString("\$send_action"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(continueButton, ViewGroup.LayoutParams(MATCH_PARENT, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            toTop(scrollView)
            bottomToTop(scrollView, continueButton, 20f)
            toCenterX(continueButton, 20f)
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }

        initialTokenSlug?.let {
            viewModel.onInputToken(it)
            updateCommentViews()
            showServiceTokenWarningIfRequired()
        }

        continueButton.setOnClickListener {
            if (viewModel.shouldAuthorizeDiesel()) {
                DieselAuthorizationHelpers.authorizeDiesel(context)
                return@setOnClickListener
            }
            viewModel.getConfirmationPageConfig()?.let { config ->
                val vc = SendConfirmVC(
                    context,
                    config,
                    viewModel.getTransferOptions(config, ""),
                    viewModel.getTokenSlug()
                )
                vc.setNextTask { passcode ->
                    lifecycleScope.launch {
                        if (AccountStore.activeAccount?.isHardware == true) {
                            // Sent using LedgerConnect
                            push(
                                SentVC(
                                    context,
                                    LocaleController.getString("Sent"),
                                    "-${config.request.amountEquivalent.getFmt(false)}",
                                    SpannableStringBuilder(
                                        config.request.amountEquivalent.getFmt(
                                            true
                                        )
                                    ),
                                    SpannableStringBuilder(
                                        LocaleController.getFormattedString(
                                            "Coins have been sent to %1$@", listOf(
                                                config.resolvedAddress?.formatStartEndAddress()
                                                    ?: ""
                                            )
                                        )
                                    ).apply {
                                        updateDotsTypeface()
                                    }
                                ),
                                onCompletion = { navigationController?.removePrevViewControllers() })
                        } else {
                            // Send with passcode
                            try {
                                viewModel.callSend(config, passcode!!)
                                push(
                                    SentVC(
                                        context,
                                        LocaleController.getString("Sent"),
                                        "-${config.request.amountEquivalent.getFmt(false)}",
                                        SpannableStringBuilder(
                                            config.request.amountEquivalent.getFmt(
                                                true
                                            )
                                        ),
                                        SpannableStringBuilder(
                                            LocaleController.getFormattedString(
                                                "Coins have been sent to %1$@", listOf(
                                                    config.resolvedAddress?.formatStartEndAddress()
                                                        ?: ""
                                                )
                                            )
                                        ).apply {
                                            updateDotsTypeface()
                                        }
                                    ),
                                    onCompletion = { navigationController?.removePrevViewControllers() })
                            } catch (e: JSWebViewBridge.ApiError) {
                                navigationController?.viewControllers[navigationController!!.viewControllers.size - 2]?.showError(
                                    e.parsed
                                )
                                navigationController?.pop(true)
                            }
                        }
                    }
                }
                view.hideKeyboard()
                push(vc)
            }
        }

        addressInputView.editTextView.addTextChangedListener(onInputDestinationTextWatcher)
        addressInputView.qrScanImageView.setOnClickListener {
            QrScannerDialog.build(context) {
                val deeplink = DeeplinkParser.parse(it.toUri())
                val address = if (deeplink is Deeplink.Invoice) deeplink.address else it
                addressInputView.editTextView.setText(address)
                switchTokenBasedOnChain(address)
            }.show()
        }

        commentInputView.addTextChangedListener(onInputCommentTextWatcher)

        amountInputView.doOnMaxButtonClick(viewModel::onInputMaxButton)
        amountInputView.doOnEquivalentButtonClick(viewModel::onInputToggleFiatMode)
        amountInputView.doOnFeeButtonClick {
            lateinit var dialogRef: WDialog
            dialogRef = FeeDetailsDialog.create(
                context,
                TokenStore.getToken(viewModel.getTokenSlug())!!,
                viewModel.getConfirmationPageConfig()!!.explainedFee!!
            ) {
                dialogRef.dismiss()
            }
            dialogRef.presentOn(this)
        }
        amountInputView.amountEditText.addTextChangedListener(onAmountTextWatcher)
        amountInputView.tokenSelectorView.setOnClickListener {
            push(SendTokenVC(context).apply {
                setOnAssetSelectListener {
                    viewModel.onInputToken(it.slug)
                    updateCommentViews()
                    showServiceTokenWarningIfRequired()
                }
            })
        }

        collectFlow(viewModel.inputStateFlow) {
            if (amountInputView.amountEditText.text.toString() != it.amount) {
                amountInputView.amountEditText.setText(it.amount)
            }
        }

        collectFlow(viewModel.uiStateFlow) {
            amountInputView.set(
                it.uiInput,
                (viewModel.getConfirmationPageConfig()?.explainedFee?.excessFee
                    ?: BigInteger.ZERO) > BigInteger.ZERO
            )
            continueButton.isLoading = it.uiButton.status.isLoading
            if (!it.uiButton.status.isLoading) {
                continueButton.isEnabled = it.uiButton.status.isEnabled
                continueButton.isError = it.uiButton.status.isError
                continueButton.text = it.uiButton.title
            }
            if (it.uiButton.status == SendViewModel.ButtonStatus.NotEnoughNativeToken) {
                showScamWarningIfRequired()
            }
        }

        collectFlow(viewModel.uiEventFlow) { event ->
            when (event) {
                is SendViewModel.UiEvent.ShowAlert -> {
                    showAlert(event.title, event.message)
                }
            }
        }

        updateTheme()
        setInitialValues()
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        title1.setBackgroundColor(WColor.Background.color, ViewConstants.TOP_RADIUS.dp, 0f)
        listOf(title2, binaryMessageTitle, initDataTitle).forEach {
           it.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BIG_RADIUS.dp,
                0f,
            )
        }
        val dataViews = listOf(addressInputView, commentInputView, binaryMessageView, initDataView)
        if (ThemeManager.uiMode.hasRoundedCorners) {
            dataViews.forEach {
                it.setBackgroundColor(
                    WColor.Background.color,
                    0f,
                    ViewConstants.BIG_RADIUS.dp
                )
            }
        } else {
            dataViews.forEach {
                it.background = SeparatorBackgroundDrawable().apply {
                    backgroundWColor = WColor.Background
                }
            }
        }
        commentInputView.setTextColor(WColor.PrimaryText.color)
        commentInputView.setHintTextColor(WColor.SecondaryText.color)

        updateCommentTitleLabel()
    }

    private fun updateCommentTitleLabel() {
        title2.apply {
            if (AccountStore.activeAccount?.supportsCommentEncryption == false) {
                text = LocaleController.getString("Comment or Memo")
                return@apply
            }
            val txt =
                LocaleController.getString(if (viewModel.getShouldEncrypt()) "Encrypted Message" else "Comment or Memo") + " "
            val ss = SpannableStringBuilder(txt)
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_8
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.PrimaryText.color)
                val width = 8.dp
                val height = 4.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                ss.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            text = ss
        }
    }

    private fun setInitialValues() {
        initialValues?.let {
            it.address?.let { address ->
                addressInputView.editTextView.setText(address)
            }
            it.amount?.let { amountBigDecimalString ->
                val token = TokenStore.getToken(initialTokenSlug ?: TONCOIN_SLUG)
                token?.let {
                    CoinUtils.fromDecimal(amountBigDecimalString, token.decimals)
                        ?.let { amountBigInt ->
                            val amountToSet = CoinUtils.toBigDecimal(
                                amountBigInt,
                                token.decimals
                            ).stripTrailingZeros().toPlainString()
                            viewModel.onInputAmount(amountToSet)
                        }
                }
            }
            it.comment?.let { comment ->
                if (it.binary == null) {
                    commentInputView.setText(comment)
                }
            }
            it.binary?.let { binary ->
                viewModel.setBinaryData(binary)
            }
            it.init?.let { init ->
                viewModel.setStateInit(init)
            }
        }
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        scrollView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )
        view.setConstraints {
            toBottomPx(
                continueButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun updateCommentViews() {
        val isCommentSupported =
            TokenStore.getToken(viewModel.getTokenSlug())?.mBlockchain?.isCommentSupported
        title2.isGone = isCommentSupported != true
        commentInputView.isGone = title2.isGone
        if (isCommentSupported != true) {
            commentInputView.text = null
        }
    }

    private fun showScamWarningIfRequired() {
        TokenStore.getToken(viewModel.getTokenSlug())?.mBlockchain?.let { blockchain ->
            if (ScamDetectionHelpers.shouldShowSeedPhraseScamWarning(blockchain)) {
                WGlobalStorage.removeAccountImportedAt(AccountStore.activeAccountId!!)
                AccountStore.activeAccount?.importedAt = null
                showAlert(
                    LocaleController.getString("Warning!"),
                    ScamDetectionHelpers.scamWarningMessage(),
                    button = LocaleController.getString("Got it"),
                    primaryIsDanger = true,
                    allowLinkInText = true
                )
            }
        }
    }

    private fun showServiceTokenWarningIfRequired() {
        val token = TokenStore.getToken(viewModel.getTokenSlug())
        if (token?.isLpToken == true ||
            listOf(
                STAKE_SLUG,
                STAKED_MYCOIN_SLUG,
                STAKED_USDE_SLUG
            ).contains(viewModel.getTokenSlug()) ||
            PRICELESS_TOKEN_HASHES.contains(viewModel.inputStateFlow.value.tokenCodeHash)
        )
            showAlert(
                LocaleController.getString("Warning!"),
                LocaleController.getString("\$service_token_transfer_warning"),
                button = LocaleController.getString("Got it"),
                primaryIsDanger = true
            )
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            scrollView.setOnScrollChangeListener(null)
        }
        addressInputView.qrScanImageView.setOnClickListener(null)
        addressInputView.editTextView.removeTextChangedListener(onInputDestinationTextWatcher)
        amountInputView.tokenSelectorView.setOnClickListener(null)
        amountInputView.doOnEquivalentButtonClick(null)
        amountInputView.doOnFeeButtonClick(null)
        amountInputView.doOnMaxButtonClick(null)
        amountInputView.amountEditText.removeTextChangedListener(onAmountTextWatcher)
        commentInputView.removeTextChangedListener(onInputCommentTextWatcher)
        continueButton.setOnClickListener(null)
    }

    private fun switchTokenBasedOnChain(address: String) {
        val token =
            TokenStore.getToken(viewModel.getTokenSlug())
        if (token?.mBlockchain?.isValidAddress(address) != true) {
            for (blockchain in MBlockchain.supportedChains) {
                if (blockchain.isValidAddress(address)) {
                    viewModel.onInputToken(blockchain.nativeSlug)
                }
            }
        }
    }
}
