package org.mytonwallet.app_air.uitransaction.viewControllers

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.widget.NestedScrollView
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.IncomingCommentDrawable
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.OutgoingCommentDrawable
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.updateDotsTypeface
import org.mytonwallet.app_air.uicomponents.helpers.SpannableHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.sensitiveDataContainer.WSensitiveDataContainer
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uiinappbrowser.InAppBrowserVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uisend.send.SendVC
import org.mytonwallet.app_air.uistake.earn.EarnRootVC
import org.mytonwallet.app_air.uistake.staking.StakingVC
import org.mytonwallet.app_air.uistake.staking.StakingViewModel
import org.mytonwallet.app_air.uiswap.screens.swap.SwapVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ThemeManager
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TransactionVC(context: Context, var transaction: MApiTransaction) : WViewController(context),
    WalletCore.EventObserver {

    override val isSwipeBackAllowed = false

    private val firstLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context)
        val transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                lbl.setStyle(36f, WFont.Medium)
                val token = TokenStore.getToken(transaction.slug)
                token?.let {
                    lbl.setAmount(
                        transaction.amount,
                        token.decimals,
                        token.symbol,
                        token.decimals,
                        smartDecimals = true,
                        showPositiveSign = true,
                        forceCurrencyToRight = true
                    )
                }
            }

            is MApiTransaction.Swap -> {
                lbl.setStyle(22f, WFont.Medium)
                transaction.fromToken?.let { token ->
                    lbl.setAmount(
                        -transaction.fromAmount.toDouble(),
                        token.decimals,
                        token.symbol,
                        token.decimals,
                        true
                    )
                }
            }
        }
        WSensitiveDataContainer(
            lbl,
            WSensitiveDataContainer.MaskConfig(
                8,
                2,
                Gravity.CENTER,
                protectContentLayoutSize = false
            )
        )
    }

    private val secondLabel: WSensitiveDataContainer<WLabel> by lazy {
        val lbl = WLabel(context).apply {
            setStyle(22f, WFont.Medium)
        }
        val transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                val token = TokenStore.getToken(transaction.slug)
                token?.let {
                    lbl.setAmount(
                        (token.price
                            ?: 0.0) * transaction.amount.doubleAbsRepresentation(token.decimals),
                        token.decimals,
                        WalletCore.baseCurrency.sign,
                        WalletCore.baseCurrency.decimalsCount,
                        true
                    )
                }
            }

            is MApiTransaction.Swap -> {
                transaction.toToken?.let { token ->
                    lbl.setAmount(
                        transaction.toAmount.toDouble(),
                        token.decimals,
                        token.symbol,
                        token.decimals,
                        smartDecimals = true,
                        showPositiveSign = true
                    )
                }
            }
        }
        WSensitiveDataContainer(lbl, WSensitiveDataContainer.MaskConfig(8, 2, Gravity.CENTER))
    }

    private val commentLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f)
        lbl.setTextColor(Color.WHITE)
        lbl
    }

    private val decryptButtonBackground: WRippleDrawable by lazy {
        WRippleDrawable.create(20f.dp).apply {
            backgroundColor = Color.WHITE
            rippleColor = Color.BLACK.colorWithAlpha(25)
        }
    }
    private val decryptButton: WLabel by lazy {
        if (transaction !is MApiTransaction.Transaction)
            throw Exception()
        val btn = WLabel(context)
        btn.text = LocaleController.getString("Decrypt")
        btn.background = decryptButtonBackground
        btn.gravity = Gravity.CENTER
        btn.setPaddingDp(8, 4, 8, 4)
        btn.setOnClickListener {
            val nav = WNavigationController(window!!)
            nav.setRoot(
                PasscodeConfirmVC(
                    context,
                    PasscodeViewState.Default(
                        LocaleController.getString("Message is encrypted."),
                        LocaleController.getString(
                            if (WGlobalStorage.isBiometricActivated() &&
                                BiometricHelpers.canAuthenticate(window!!)
                            )
                                "Enter passcode or use fingerprint" else "Enter Passcode"
                        ),
                        LocaleController.getString("Decrypt"),
                        showNavigationSeparator = false,
                        startWithBiometrics = true
                    ),
                    task = { passcode ->
                        WalletCore.call(
                            ApiMethod.WalletData.DecryptComment(
                                AccountStore.activeAccountId!!,
                                transaction,
                                passcode
                            )
                        ) { res, err ->
                            if (err != null)
                                return@call
                            commentLabel.text = res
                            commentView.removeView(decryptButton)
                            commentView.setConstraints {
                                toEnd(commentLabel)
                                constrainMaxWidth(
                                    commentLabel.id,
                                    ConstraintSet.MATCH_CONSTRAINT_SPREAD
                                )
                            }
                            window?.dismissLastNav()
                        }
                    }
                ))
            window?.present(nav)
        }
        btn
    }

    private val commentView: WView by lazy {
        val v = WView(context)
        v.addView(commentLabel, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        val transaction = transaction
        if (transaction is MApiTransaction.Transaction) {
            if (!transaction.encryptedComment.isNullOrEmpty()) {
                commentLabel.text = SpannableHelpers.encryptedCommentSpan(context)
                val canDecrypt =
                    AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC
                if (canDecrypt) {
                    v.addView(
                        decryptButton,
                        ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                    )
                    decryptButton.setTextColor((if (transaction.isIncoming) WColor.IncomingComment else WColor.OutgoingComment).color)
                }
            } else {
                commentLabel.text = transaction.comment
            }
            if (transaction.isIncoming)
                v.setPaddingDpLocalized(18, 6, 12, 6)
            else
                v.setPaddingDpLocalized(12, 6, 18, 6)
        }
        v.minimumHeight = 36.dp
        v.setConstraints {
            constrainedWidth(commentLabel.id, true)
            toTop(commentLabel)
            toStart(commentLabel)
            toBottom(commentLabel)
            if (transaction is MApiTransaction.Transaction && !transaction.encryptedComment.isNullOrEmpty()) {
                setHorizontalBias(decryptButton.id, 1f)
                toCenterY(decryptButton)
                endToStart(commentLabel, decryptButton, 8f)
                toEnd(decryptButton)
                v.post {
                    v.setConstraints {
                        constrainMaxWidth(
                            commentLabel.id,
                            commentView.width - decryptButton.width - 38.dp
                        )
                    }
                }
            } else {
                toEnd(commentLabel)
            }
        }
        v
    }

    private val separatorDrawable = SeparatorBackgroundDrawable().apply {
        backgroundWColor = WColor.Background
    }

    private var transactionHeaderView: TransactionHeaderView? = null
    private var swapHeaderView: SwapHeaderView? = null
    private var nftHeaderView: NftHeaderView? = null
    private val headerViewContainer: FrameLayout by lazy {
        FrameLayout(context).apply {
            id = View.generateViewId()
            addView(headerView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }
    private val headerView: WView by lazy {
        val v = WView(context)
        val transaction = transaction
        if (transaction is MApiTransaction.Transaction) {
            if (transaction.nft != null) {
                nftHeaderView = NftHeaderView(WeakReference(this), transaction)
                v.addView(nftHeaderView)
            } else {
                transactionHeaderView = TransactionHeaderView(WeakReference(this), transaction)
                v.addView(transactionHeaderView)
            }
        }
        if (transaction is MApiTransaction.Swap) {
            swapHeaderView = SwapHeaderView(context, transaction)
            v.addView(swapHeaderView)
        }
        if (transaction is MApiTransaction.Transaction && transaction.hasComment) {
            v.addView(commentView, ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        }
        v.setConstraints {
            when (transaction) {
                is MApiTransaction.Transaction -> {
                    val innerHeaderView: WView = nftHeaderView ?: transactionHeaderView!!

                    toTop(innerHeaderView, 24f)
                    toCenterX(innerHeaderView)
                    if (transaction.hasComment) {
                        commentView.maxWidth = window!!.windowView.width - 40.dp
                        topToBottom(commentView, innerHeaderView, 27f)
                        toCenterX(commentView, 20f)
                        toBottom(commentView, 22f)
                    } else {
                        toBottom(
                            innerHeaderView,
                            if (innerHeaderView is NftHeaderView) 24f else 26f
                        )
                    }
                }

                is MApiTransaction.Swap -> {
                    toCenterX(swapHeaderView!!)
                    toTop(swapHeaderView!!, 24f)
                    toBottom(swapHeaderView!!, 21f)
                }
            }
        }
        v
    }

    private fun generateActions(): List<HeaderActionsView.Item> {
        return listOfNotNull(
            HeaderActionsView.Item(
                HeaderActionsView.Identifier.DETAILS,
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uitransaction.R.drawable.ic_act_details
                )!!,
                LocaleController.getString("Details")
            ),
            if (shouldShowRepeatAction()) HeaderActionsView.Item(
                HeaderActionsView.Identifier.REPEAT,
                ContextCompat.getDrawable(
                    context,
                    org.mytonwallet.app_air.uitransaction.R.drawable.ic_act_repeat
                )!!,
                LocaleController.getString("Repeat")
            ) else null,
            if (!transaction.getTxHash().isNullOrEmpty())
                HeaderActionsView.Item(
                    HeaderActionsView.Identifier.SHARE,
                    ContextCompat.getDrawable(
                        context,
                        org.mytonwallet.app_air.uitransaction.R.drawable.ic_act_share
                    )!!,
                    LocaleController.getString("Share")
                ) else null
        )
    }

    private val actionsView = HeaderActionsView(
        context,
        generateActions(),
        onClick = { identifier ->
            when (identifier) {
                HeaderActionsView.Identifier.DETAILS -> {
                    toggleModalState()
                }

                HeaderActionsView.Identifier.REPEAT -> {
                    repeatPressed()
                }

                HeaderActionsView.Identifier.SHARE -> {
                    sharePressed()
                }

                else -> {
                    throw Error()
                }
            }
        },
        bottomPadding = 4.dp
    )

    private val transactionDetailsLabel: WLabel by lazy {
        val lbl = WLabel(context)
        lbl.setStyle(16f, WFont.Medium)
        lbl.text = LocaleController.getString("Transaction Details")
        lbl.setPadding(0, 0, 0, 10.dp)
        lbl
    }

    private var detailsRowViews = ArrayList<KeyValueRowView>()
    private val feeRow: KeyValueRowView? by lazy {
        KeyValueRowView(
            context,
            LocaleController.getString("Fee"),
            calcFee(transaction) ?: "",
            mode = KeyValueRowView.Mode.SECONDARY,
            isLast = false
        ).apply {
            isSensitiveData = true
        }
    }
    private var transactionIdRow: KeyValueRowView? = null
    private var changellyIdRow: KeyValueRowView? = null
    private val transactionDetails: WView by lazy {
        val v = WView(context)
        v.addView(transactionDetailsLabel)
        val shouldShowViewInExplorer =
            transaction.getTxIdentifier()?.isNotEmpty() == true && !transaction.isLocal()
        val transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                if (transaction.isNft && transaction.nft != null) {
                    detailsRowViews.add(
                        KeyValueRowView(
                            context,
                            LocaleController.getString("Collection"),
                            "",
                            KeyValueRowView.Mode.SECONDARY,
                            false
                        ).apply {
                            setValueView(WLabel(context).apply {
                                setStyle(16f)
                                setTextColor(WColor.Tint)
                                setOnClickListener {
                                    WalletCore.notifyEvent(
                                        WalletEvent.OpenUrl(
                                            transaction.nft!!.collectionUrl
                                        )
                                    )
                                }
                                text =
                                    if (transaction.nft!!.isStandalone()) LocaleController.getString(
                                        "Standalone"
                                    ) else transaction.nft!!.collectionName ?: ""
                            })
                        }
                    )
                } else {
                    TokenStore.getToken(transaction.slug)?.let { token ->
                        val equivalent = token.price?.let { price ->
                            (price * transaction.amount.doubleAbsRepresentation(decimals = token.decimals)).toString(
                                token.decimals,
                                WalletCore.baseCurrency.sign,
                                WalletCore.baseCurrency.decimalsCount,
                                smartDecimals = true,
                                roundUp = false
                            )
                        }
                        detailsRowViews.add(
                            KeyValueRowView(
                                context,
                                LocaleController.getString("Amount"),
                                transaction.amount.abs().toString(
                                    decimals = token.decimals,
                                    currency = token.symbol,
                                    currencyDecimals = transaction.amount.smartDecimalsCount(token.decimals),
                                    showPositiveSign = false,
                                    forceCurrencyToRight = true
                                ) + if (equivalent != null) " ($equivalent)" else "",
                                mode = KeyValueRowView.Mode.SECONDARY,
                                isLast = false
                            ).apply {
                                isSensitiveData = true
                            }
                        )
                    }
                }
                if (
                    (transaction.fee > BigInteger.ZERO ||
                        transaction.shouldLoadDetails == true) && feeRow != null
                )
                    detailsRowViews.add(feeRow!!)
                if (detailsRowViews.isEmpty()) {
                    transactionDetailsLabel.visibility = View.GONE
                }
            }

            is MApiTransaction.Swap -> {
                detailsRowViews.add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Swapped at"),
                        transaction.dt.formatDateAndTime(),
                        mode = KeyValueRowView.Mode.SECONDARY,
                        isLast = false
                    ).apply { visibility = View.GONE }
                )
                val fromToken = transaction.fromToken
                detailsRowViews.add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Sent"),
                        transaction.fromAmount.toDouble().toString(
                            fromToken?.decimals ?: 9,
                            fromToken?.symbol ?: "",
                            fromToken?.decimals ?: 9,
                            smartDecimals = false,
                            showPositiveSign = false
                        )!!,
                        mode = KeyValueRowView.Mode.SECONDARY,
                        isLast = false
                    ).apply { visibility = View.GONE }
                )
                val toToken = transaction.toToken
                detailsRowViews.add(
                    KeyValueRowView(
                        context,
                        LocaleController.getString("Received"),
                        transaction.toAmount.toDouble().toString(
                            toToken?.decimals ?: 9,
                            toToken?.symbol ?: "",
                            toToken?.decimals ?: 9,
                            smartDecimals = false,
                            showPositiveSign = false
                        )!!,
                        mode = KeyValueRowView.Mode.SECONDARY,
                        isLast = false
                    ).apply { visibility = View.GONE }
                )
                val shouldShowFeeRow =
                    (transaction.networkFee ?: 0.0) > 0 ||
                        ((transaction.ourFee ?: 0.0) > 0 && transaction.ourFee!!.isFinite()) ||
                        transaction.shouldLoadDetails == true
                detailsRowViews.add(
                    KeyValueRowView(
                        context,
                        "${LocaleController.getString("Price per")} 1 ${toToken?.symbol ?: ""}",
                        (transaction.fromAmount.toDouble() / transaction.toAmount.toDouble()).toString(
                            fromToken?.decimals ?: 9,
                            fromToken?.symbol ?: "",
                            fromToken?.decimals ?: 9,
                            smartDecimals = false,
                            showPositiveSign = false
                        )!!,
                        KeyValueRowView.Mode.SECONDARY,
                        !shouldShowFeeRow && !shouldShowViewInExplorer
                    )
                )
                if (shouldShowFeeRow && feeRow != null) {
                    detailsRowViews.add(feeRow!!)
                }
            }
        }

        if ((transaction is MApiTransaction.Swap) && !transaction.cex?.transactionId.isNullOrEmpty()) {
            changellyIdRow = KeyValueRowView(
                context,
                LocaleController.getString("Changelly ID"),
                "",
                mode = KeyValueRowView.Mode.SECONDARY,
                isLast = false
            ).apply {
                hideSeparator()
            }
            detailsRowViews.add(changellyIdRow!!)
        } else if (shouldShowViewInExplorer) {
            transactionIdRow = KeyValueRowView(
                context,
                LocaleController.getString("Transaction ID"),
                "",
                mode = KeyValueRowView.Mode.SECONDARY,
                isLast = false
            ).apply {
                hideSeparator()
            }
            detailsRowViews.add(transactionIdRow!!)
        }

        detailsRowViews.forEach { v.addView(it) }
        detailsRowViews.lastOrNull()?.setLast(true)

        v.setConstraints {
            toTop(transactionDetailsLabel, 16f)
            detailsRowViews.forEachIndexed { index, rowView ->
                if (index == 0)
                    topToBottom(rowView, transactionDetailsLabel, 0f)
                else
                    topToBottom(rowView, detailsRowViews[index - 1])
                toCenterX(rowView)
            }
            toBottom(detailsRowViews.last())
            toStart(transactionDetailsLabel, 20f)
        }
        v
    }

    private val innerContentView: WView by lazy {
        val v = WView(context)
        v.addView(headerViewContainer, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.addView(actionsView, ConstraintLayout.LayoutParams(MATCH_PARENT, 70.dp))
        v.addView(transactionDetails, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(headerViewContainer)
            toCenterX(headerViewContainer)
            topToBottom(actionsView, headerViewContainer, 12f)
            topToBottom(transactionDetails, actionsView, 12f)
            toCenterX(transactionDetails, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            toBottomPx(transactionDetails, navigationController?.getSystemBars()?.bottom ?: 0)
            setVerticalBias(transactionDetails.id, 0f)
        }
        v
    }
    private val scrollingContentView: WView by lazy {
        WView(context).apply {
            addView(innerContentView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            setConstraints {
                toTopPx(
                    innerContentView, (navigationController?.getSystemBars()?.top ?: 0) +
                        WNavigationBar.DEFAULT_HEIGHT.dp
                )
                constrainMinHeight(
                    innerContentView.id,
                    window!!.windowView.height - (navigationController?.getSystemBars()?.top
                        ?: 0) - WNavigationBar.DEFAULT_HEIGHT.dp
                )
            }
        }
    }

    private val scrollView: NestedScrollView by lazy {
        NestedScrollView(context).apply {
            id = View.generateViewId()
            addView(scrollingContentView, ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setNavTitle(transaction.title)
        setNavSubtitle(transaction.dt.formatDateAndTime())
        setupNavBar(true)

        navigationBar?.addCloseButton()

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.setConstraints {
            allEdges(scrollView)
        }

        updateTheme()

        if (transaction.shouldLoadDetails == true)
            loadActivityDetails()
    }

    override fun onDestroy() {
        super.onDestroy()
        WalletCore.unregisterObserver(this)
    }

    override fun updateTheme() {
        super.updateTheme()

        updateBackground()
        reloadCommentView()
        if (ThemeManager.uiMode.hasRoundedCorners) {
            headerView.setBackgroundColor(WColor.Background.color, ViewConstants.BIG_RADIUS.dp)
            transactionDetails.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BIG_RADIUS.dp,
                ViewConstants.BIG_RADIUS.dp
            )
        } else {
            headerView.background = separatorDrawable
            transactionDetails.setBackgroundColor(WColor.Background.color)
        }
        val transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                firstLabel.contentView.setTextColor(
                    if (transaction.amount >= BigInteger.ZERO) WColor.Green.color else WColor.PrimaryText.color
                )
                secondLabel.contentView.setTextColor(WColor.SecondaryText.color)
            }

            is MApiTransaction.Swap -> {
                firstLabel.contentView.setTextColor(WColor.PrimaryText.color)
                secondLabel.contentView.setTextColor(WColor.Green.color)
            }
        }
        transactionDetailsLabel.setTextColor(WColor.Tint.color)
        transactionIdRow?.setValue(transactionIdValue)
        changellyIdRow?.setValue(changellyIdValue)

        separatorDrawable.invalidateSelf()
    }

    private fun updateBackground() {
        val expandProgress = 10 / 3 * (((modalExpandProgress ?: 0f) - 0.7f).coerceIn(0f, 1f))
        innerContentView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            (1 - expandProgress) * ViewConstants.BIG_RADIUS.dp,
            0f
        )
        if (modalExpandProgress == 1f) {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        } else {
            view.background = null
        }
    }

    override fun getModalHalfExpandedHeight(): Int? {
        return innerContentView.top + actionsView.bottom + 36.dp
    }

    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        super.onModalSlide(expandOffset, expandProgress)
        updateBackground()
        transactionDetails.alpha = (expandOffset.toFloat() / ViewConstants.GAP.dp).coerceIn(0f, 1f)
        val padding = (ViewConstants.HORIZONTAL_PADDINGS.dp * expandProgress).roundToInt()
        headerViewContainer.setPadding(padding, 0, padding, 0)
    }

    private fun reloadData() {
        transactionHeaderView?.apply {
            transaction = this@TransactionVC.transaction
            reloadData()
        }
        swapHeaderView?.apply {
            transaction = this@TransactionVC.transaction
            reloadData()
        }
        nftHeaderView?.apply {
            transaction = this@TransactionVC.transaction
            reloadData()
        }
        reloadCommentView()
        actionsView.resetTabs(generateActions())
        calcFee(transaction)?.let { fee ->
            feeRow?.setValue(
                fee,
                fadeIn = false
            )
        } ?: run {
            loadActivityDetails()
        }
    }

    private fun reloadCommentView() {
        (transaction as? MApiTransaction.Transaction)?.let { transaction ->
            if (!transaction.hasComment)
                return@let
            commentView.background =
                (if (transaction.isIncoming) IncomingCommentDrawable() else OutgoingCommentDrawable()).apply {
                    if (transaction.status == ApiTransactionStatus.FAILED)
                        setBubbleColor(WColor.Red.color.colorWithAlpha(38))
                }
            commentLabel.setTextColor(
                if (transaction.status == ApiTransactionStatus.FAILED) WColor.Red else WColor.White
            )
        }
    }

    private fun shouldShowRepeatAction() = {
        val transaction = transaction
        AccountStore.activeAccount?.accountType != MAccount.AccountType.VIEW &&
            (
                transaction is MApiTransaction.Swap ||
                    (
                        transaction is MApiTransaction.Transaction &&
                            !transaction.isPending() &&
                            (transaction.isStaking || (!transaction.isIncoming && transaction.nft == null))
                        )
                )
    }()

    private fun calcFee(transaction: MApiTransaction): String? {
        if (transaction.shouldLoadDetails == true)
            return null
        when (transaction) {
            is MApiTransaction.Transaction -> {
                val token = TokenStore.getToken(transaction.slug)
                val nativeToken = token?.nativeToken
                return if (nativeToken == null) {
                    null
                } else {
                    transaction.fee.toString(
                        nativeToken.decimals,
                        nativeToken.symbol,
                        transaction.fee.smartDecimalsCount(nativeToken.decimals),
                        false
                    )
                }
            }

            is MApiTransaction.Swap -> {
                val isNative = transaction.fromToken?.isBlockchainNative == true
                val feeTerms = MFee.FeeTerms(
                    token = if (!isNative && transaction.ourFee != null && transaction.ourFee!!.isFinite()) transaction.ourFee!!.toBigInteger(
                        transaction.fromToken!!.decimals
                    ) else BigInteger.ZERO,
                    native = (
                        (transaction.networkFee?.absoluteValue ?: 0.0) +
                            (if (isNative && transaction.ourFee?.isFinite() == true) transaction.ourFee!! else 0.0)
                        ).toBigInteger(9),
                    stars = null
                )
                return MFee(
                    if (transaction.status.uiStatus == MApiTransaction.UIStatus.PENDING) MFee.FeePrecision.APPROXIMATE else MFee.FeePrecision.EXACT,
                    feeTerms,
                    nativeSum = null
                ).toString(
                    transaction.fromToken!!,
                    appendNonNative = true
                )
            }
        }
    }

    private val transactionIdValue: CharSequence
        get() {
            val spannedString = SpannableStringBuilder(
                transaction.getTxHash()?.formatStartEndAddress(6, 6)
            )
            spannedString.updateDotsTypeface()
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.SecondaryText.color)
                val width = 20.dp
                val height = 20.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        WMenuPopup.present(
                            transactionIdRow!!.valueLabel.contentView,
                            listOf(
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_copy,
                                    LocaleController.getString("Copy Transaction ID"),
                                ) {
                                    val clipboard =
                                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = ClipData.newPlainText(
                                        "",
                                        transaction.getTxIdentifier()
                                    )
                                    clipboard.setPrimaryClip(clip)
                                    Toast.makeText(
                                        context,
                                        LocaleController.getString("Transaction ID was copied!"),
                                        Toast.LENGTH_SHORT
                                    ).show()
                                },
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_world,
                                    LocaleController.getString("View on Explorer"),
                                ) {
                                    val browserVC =
                                        InAppBrowserVC(
                                            context,
                                            null,
                                            InAppBrowserConfig(
                                                transaction.explorerUrl ?: "",
                                                injectTonConnectBridge = true
                                            )
                                        )
                                    val nav = WNavigationController(window!!)
                                    nav.setRoot(browserVC)
                                    window?.present(nav)
                                }),
                            popupWidth = WRAP_CONTENT,
                            aboveView = false
                        )
                    }

                    override fun updateDrawState(ds: TextPaint) {
                        super.updateDrawState(ds)
                        ds.setColor(WColor.PrimaryText.color)
                        ds.isUnderlineText = false
                    }
                },
                0,
                spannedString.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            return spannedString
        }

    private val changellyIdValue: CharSequence
        get() {
            val changellyId = (transaction as? MApiTransaction.Swap)?.cex?.transactionId
            val spannedString = SpannableStringBuilder(changellyId)
            spannedString.updateDotsTypeface()
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrow_bottom_24
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.SecondaryText.color)
                val width = 20.dp
                val height = 20.dp
                drawable.setBounds(0, 0, width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        WMenuPopup.present(
                            changellyIdRow!!.valueLabel.contentView,
                            listOf(
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_copy,
                                    LocaleController.getString("Copy Changelly ID"),
                                ) {
                                    val clipboard =
                                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = ClipData.newPlainText(
                                        "",
                                        changellyId
                                    )
                                    clipboard.setPrimaryClip(clip)
                                    Toast.makeText(
                                        context,
                                        LocaleController.getString("Changelly ID Copied!"),
                                        Toast.LENGTH_SHORT
                                    ).show()
                                },
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_world,
                                    LocaleController.getString("View on Explorer"),
                                ) {
                                    val browserVC =
                                        InAppBrowserVC(
                                            context,
                                            null,
                                            InAppBrowserConfig(
                                                "https://changelly.com/track/${changellyId}",
                                                injectTonConnectBridge = false
                                            )
                                        )
                                    val nav = WNavigationController(window!!)
                                    nav.setRoot(browserVC)
                                    window?.present(nav)
                                }),
                            popupWidth = WRAP_CONTENT,
                            aboveView = false
                        )
                    }

                    override fun updateDrawState(ds: TextPaint) {
                        super.updateDrawState(ds)
                        ds.setColor(WColor.PrimaryText.color)
                        ds.isUnderlineText = false
                    }
                },
                0,
                spannedString.length,
                Spannable.SPAN_EXCLUSIVE_EXCLUSIVE
            )
            return spannedString
        }

    private fun loadActivityDetails() {
        val accountId = AccountStore.activeAccountId!!
        WalletCore.call(
            ApiMethod.WalletData.FetchActivityDetails(
                accountId,
                transaction
            ),
            callback = { res, err ->
                if (err != null) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (view.parent == null)
                            return@postDelayed
                        loadActivityDetails()
                    }, 3000)
                    return@call
                }
                res?.let { transaction ->
                    ActivityStore.updateCachedTransaction(accountId, transaction)
                    feeRow?.setValue(
                        calcFee(transaction),
                        fadeIn = feeRow?.valueLabel?.contentView?.text.isNullOrEmpty()
                    )
                }
            })
    }

    private fun repeatPressed() {
        val navVC = WNavigationController(window!!)

        val transaction = transaction
        when (transaction) {
            is MApiTransaction.Transaction -> {
                val token = TokenStore.getToken(transaction.slug) ?: return
                if (transaction.isStaking) {
                    navVC.setRoot(EarnRootVC(context))
                    if (transaction.type != ApiTransactionType.UNSTAKE_REQUEST)
                        navVC.push(
                            StakingVC(
                                context,
                                transaction.slug,
                                if (transaction.type == ApiTransactionType.STAKE) StakingViewModel.Mode.STAKE else StakingViewModel.Mode.UNSTAKE
                            ),
                            animated = false
                        )
                } else {
                    navVC.setRoot(
                        SendVC(
                            context, transaction.slug,
                            SendVC.InitialValues(
                                transaction.toAddress,
                                CoinUtils.toBigDecimal(
                                    transaction.amount.abs(),
                                    token.decimals
                                ).toPlainString(),
                                transaction.comment
                            )
                        )
                    )
                }
            }

            is MApiTransaction.Swap -> {
                val fromToken = transaction.fromToken ?: return
                val toToken = transaction.toToken ?: return
                navVC.setRoot(
                    SwapVC(
                        context,
                        MApiSwapAsset.from(fromToken),
                        MApiSwapAsset.from(toToken),
                        transaction.fromAmount
                    )
                )
            }
        }

        window?.present(navVC, onCompletion = {
            window?.navigationControllers?.size?.let { size ->
                window?.dismissNav(size - 2)
            }
        })
    }

    private fun sharePressed() {
        val shareIntent = Intent(Intent.ACTION_SEND)
        shareIntent.setType("text/plain")
        shareIntent.putExtra(Intent.EXTRA_TEXT, transaction.explorerUrl)
        window?.startActivity(
            Intent.createChooser(
                shareIntent,
                LocaleController.getString("Share")
            )
        )
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountSavedAddressesChanged -> {
                reloadData()
            }

            is WalletEvent.ReceivedPendingActivities -> {
                walletEvent.pendingActivities?.firstOrNull { this.transaction.isSame(it) }?.let {
                    this.transaction = it
                    reloadData()
                }
            }

            is WalletEvent.ReceivedNewActivities -> {
                walletEvent.newActivities?.firstOrNull { this.transaction.isSame(it) }?.let {
                    this.transaction = it
                    reloadData()
                }
            }

            else -> {}
        }
    }
}
