package org.mytonwallet.app_air.uisend.send

import android.annotation.SuppressLint
import android.content.Context
import android.text.SpannableStringBuilder
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.LinearLayout
import android.widget.ScrollView
import androidx.appcompat.widget.AppCompatTextView
import androidx.constraintlayout.widget.ConstraintSet
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListGapCell
import org.mytonwallet.app_air.uicomponents.adapter.implementation.holders.ListTitleCell
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
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
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
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
    private val slug: String
) : WViewController(context) {

    private var task: ((passcode: String?) -> Unit)? = null

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
                Content.of(config.request.token),
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
    private val title1 = ListTitleCell(context).apply {
        text = LocaleController.getString("Send to")
    }
    private val addressInputView by lazy {
        CopyTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams = LinearLayout.LayoutParams(
                MATCH_PARENT,
                WRAP_CONTENT
            )
            setPaddingDp(20, 8, 20, 20)

            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = config.resolvedAddress
            clipLabel = "Address"
            clipToast = LocaleController.getString("Address was copied!")
        }
    }

    private val commentInputView by lazy {
        AppCompatTextView(context).apply {
            typeface = WFont.Regular.typeface
            layoutParams =
                ViewGroup.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            setPaddingDp(20, 0, 20, 20)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            text = config.request.input.comment
        }
    }

    private val gap1 = ListGapCell(context)
    private val title2 = ListTitleCell(context).apply {
        text = LocaleController.getString("Amount")
    }

    private val gap2 = ListGapCell(context)
    private val title3 = ListTitleCell(context).apply {
        text = LocaleController.getString("Comment or Memo")
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
            text = config.request.input.binary
            clipLabel = "Signing Data"
            clipToast = LocaleController.getString("Data was copied!")
        }
    }

    private val initDataGap = ListGapCell(context)

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
            text = config.request.input.stateInit
            clipLabel = "Contract Initialization Data"
            clipToast = LocaleController.getString("Contract Initialization Data was copied!")
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
        }
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
        setNavTitle(LocaleController.getString("Is it all ok?"))
        setupNavBar(true)
        navigationBar?.addCloseButton()

        view.addView(scrollView, ViewGroup.LayoutParams(MATCH_PARENT, 0))
        view.addView(cancelButton, ViewGroup.LayoutParams(0, 50.dp))
        view.addView(confirmButton, ViewGroup.LayoutParams(0, 50.dp))
        view.setConstraints {
            toCenterX(scrollView)
            topToBottom(scrollView, navigationBar!!)
            bottomToTop(scrollView, confirmButton, 20f)
            toBottomPx(
                cancelButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
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
                ViewConstants.BAR_ROUNDS.dp,
                0f
            )
        }

        bottomRoundedItems.forEach {
            it.setBackgroundColor(
                WColor.Background.color,
                0f,
                ViewConstants.BIG_RADIUS.dp
            )
        }

        primaryTextColored.forEach {
            it.setTextColor(WColor.PrimaryText.color)
        }

        val showSeparator =
            !ThemeManager.uiMode.hasRoundedCorners && !ThemeManager.isDark
        gap1.showSeparator = showSeparator
        gap2.showSeparator = showSeparator
        gap1.invalidate()
        gap2.invalidate()
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
                cancelButton, 20.dp + max(
                    (navigationController?.getSystemBars()?.bottom ?: 0),
                    (window?.imeInsets?.bottom ?: 0)
                )
            )
        }
    }

    private fun confirmHardware(transferOptions: MApiSubmitTransferOptions) {
        confirmButton.lockView()
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignTransfer(
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
                    config.resolvedAddress
                )
            }
        )
        push(ledgerConnectVC, onCompletion = {
            confirmButton.unlockView()
        })
    }

    private fun confirmWithPassword() {
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
                            config.resolvedAddress
                        )
                    },
                    LocaleController.getString("Confirm")
                ),
                task = { passcode -> task?.invoke(passcode) }
            ))
    }
}
