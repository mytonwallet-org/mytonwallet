package org.mytonwallet.app_air.uitransaction.viewControllers.transaction

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.text.Layout
import android.text.Spannable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.ClickableSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.Toast
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.constraintlayout.widget.ConstraintSet
import androidx.core.content.ContextCompat
import androidx.core.text.buildSpannedString
import androidx.core.text.inSpans
import androidx.core.view.isGone
import androidx.core.widget.NestedScrollView
import org.mytonwallet.app_air.uicomponents.AnimationConstants
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.HeaderActionsView
import org.mytonwallet.app_air.uicomponents.commonViews.KeyValueRowView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.HeaderCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.IncomingCommentDrawable
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.OutgoingCommentDrawable
import org.mytonwallet.app_air.uicomponents.drawable.SeparatorBackgroundDrawable
import org.mytonwallet.app_air.uicomponents.drawable.WRippleDrawable
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.exactly
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDp
import org.mytonwallet.app_air.uicomponents.extensions.setPaddingDpLocalized
import org.mytonwallet.app_air.uicomponents.extensions.setSizeBounds
import org.mytonwallet.app_air.uicomponents.extensions.styleDots
import org.mytonwallet.app_air.uicomponents.extensions.unspecified
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers
import org.mytonwallet.app_air.uicomponents.helpers.AddressPopupHelpers.Companion.presentMenu
import org.mytonwallet.app_air.uicomponents.helpers.HapticType
import org.mytonwallet.app_air.uicomponents.helpers.Haptics
import org.mytonwallet.app_air.uicomponents.helpers.SpannableHelpers
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.helpers.spans.WTypefaceSpan
import org.mytonwallet.app_air.uicomponents.helpers.typeface
import org.mytonwallet.app_air.uicomponents.widgets.WFrameLayout
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WReplaceableLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.animateHeight
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup
import org.mytonwallet.app_air.uicomponents.widgets.menu.WMenuPopup.BackgroundStyle
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
import org.mytonwallet.app_air.uitransaction.R
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.WORD_JOIN
import org.mytonwallet.app_air.walletbasecontext.utils.doubleAbsRepresentation
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.formatStartEndAddress
import org.mytonwallet.app_air.walletbasecontext.utils.replaceSpacesWithNbsp
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toBigInteger
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcontext.globalStorage.WGlobalStorage
import org.mytonwallet.app_air.walletcontext.helpers.BiometricHelpers
import org.mytonwallet.app_air.walletcontext.helpers.WInterpolator
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcontext.utils.CoinUtils
import org.mytonwallet.app_air.walletcontext.utils.VerticalImageSpan
import org.mytonwallet.app_air.walletcontext.utils.colorWithAlpha
import org.mytonwallet.app_air.walletcontext.utils.lerpColor
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.ActivityHelpers
import org.mytonwallet.app_air.walletcore.helpers.ExplorerHelpers
import org.mytonwallet.app_air.walletcore.models.InAppBrowserConfig
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MFee
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchain
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionStatus
import org.mytonwallet.app_air.walletcore.moshi.ApiTransactionType
import org.mytonwallet.app_air.walletcore.moshi.MApiSwapAsset
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction
import org.mytonwallet.app_air.walletcore.moshi.MApiTransaction.Swap
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.ActivityStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TransactionVC(
    context: Context,
    private val showingAccountId: String,
    tx: MApiTransaction,
    isInBottomSheet: Boolean = true
) : WViewController(context),
    WalletCore.EventObserver {
    override val TAG = "Transaction"

    override val isSwipeBackAllowed = !isInBottomSheet
    override val displayedAccount =
        DisplayedAccount(showingAccountId, AccountStore.isPushedTemporary)

    private companion object {
        const val TITLE_TEXT_SIZE = 22f
        val TAG_PADDING = 8.dp
    }

    private fun adjustTransactionStatusForUi(transaction: MApiTransaction): MApiTransaction {
        when (transaction) {
            is MApiTransaction.Swap -> {
                return transaction
            }

            is MApiTransaction.Transaction -> {
                if (!transaction.isIncoming && (transaction.isPending() || transaction.isLocal()))
                    return transaction.copy(status = ApiTransactionStatus.CONFIRMED)
                return transaction
            }
        }
    }

    private var transaction = adjustTransactionStatusForUi(tx)

    val titleLabel: WReplaceableLabel? by lazy {
        WReplaceableLabel(context).apply {
            isSelected = true
            isHorizontalFadingEdgeEnabled = true
            setGravity(Gravity.START)
        }
    }

    val tagLabel: WLabel by lazy {
        WLabel(context).apply {
            setPaddingDp(4, 0, 4, 0)
            setStyle(14f, WFont.SemiBold)
        }
    }

    private val titleView: FrameLayout by lazy {
        FrameLayout(context).apply {
            addView(titleLabel, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).apply {
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            })
            addView(tagLabel, FrameLayout.LayoutParams(WRAP_CONTENT, 20.dp).apply {
                topMargin = 0.5f.dp.roundToInt()
                gravity = Gravity.START or Gravity.CENTER_VERTICAL
            })
        }
    }

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
                        -transaction.fromAmount.absoluteValue,
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
                        token.decimals,
                        true
                    )
                }
            }

            is MApiTransaction.Swap -> {
                transaction.toToken?.let { token ->
                    lbl.setAmount(
                        transaction.toAmount,
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
                        LocaleController.getString("Message is encrypted"),
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
        val canDecrypt =
            AccountStore.activeAccount?.accountType == MAccount.AccountType.MNEMONIC
        if (transaction is MApiTransaction.Transaction) {
            if (!transaction.encryptedComment.isNullOrEmpty()) {
                commentLabel.text = SpannableHelpers.encryptedCommentSpan(context)
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
            if (transaction is MApiTransaction.Transaction && !transaction.encryptedComment.isNullOrEmpty() && canDecrypt) {
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
    private val headerViewContainer: WFrameLayout by lazy {
        WFrameLayout(context).apply {
            addView(headerView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
    }
    private val headerView = WView(context).apply {
        clipChildren = false
    }

    private fun ensureCorrectHeaderView() {
        val transaction = transaction

        if (transaction is MApiTransaction.Transaction) {
            if (transaction.nft != null) {
                if (nftHeaderView != null) {
                    nftHeaderView?.transaction = transaction
                    nftHeaderView?.reloadData()
                    return
                }

                headerView.removeAllViews()
                transactionHeaderView = null
                swapHeaderView = null
                nftHeaderView = NftHeaderView(WeakReference(this), transaction)
                headerView.addView(nftHeaderView)
            } else {
                if (transactionHeaderView != null) {
                    transactionHeaderView?.transaction = transaction
                    transactionHeaderView?.reloadData()
                    return
                }

                headerView.removeAllViews()
                nftHeaderView = null
                swapHeaderView = null
                transactionHeaderView =
                    TransactionHeaderView(WeakReference(this), transaction) { slug ->
                        navigateToToken(slug)
                    }
                headerView.addView(transactionHeaderView)
            }

            if (transaction.hasComment) {
                headerView.addView(
                    commentView,
                    ConstraintLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT)
                )
            }

            headerView.setConstraints {
                val innerHeaderView: WView = nftHeaderView ?: transactionHeaderView!!

                toTop(innerHeaderView, 24f)
                toCenterX(innerHeaderView)

                if (transaction.hasComment) {
                    commentView.maxWidth = window!!.windowView.width - 40.dp
                    topToBottom(commentView, innerHeaderView, 23f)
                    toCenterX(commentView, 20f)
                    toBottom(commentView, 22f)
                } else {
                    toBottom(innerHeaderView, if (innerHeaderView is NftHeaderView) 24f else 26f)
                }
            }
        }

        if (transaction is MApiTransaction.Swap) {
            if (swapHeaderView != null) {
                swapHeaderView?.transaction = transaction
                swapHeaderView?.reloadData()
                return
            }

            headerView.removeAllViews()
            nftHeaderView = null
            transactionHeaderView = null
            swapHeaderView = SwapHeaderView(context, transaction) { slug ->
                navigateToToken(slug)
            }
            headerView.addView(swapHeaderView)

            headerView.setConstraints {
                toCenterX(swapHeaderView!!)
                toTop(swapHeaderView!!, 24f)
                toBottom(swapHeaderView!!, 21f)
            }
        }
    }

    private fun generateActions(): List<HeaderActionsView.Item> {
        return listOfNotNull(
            HeaderActionsView.Item(
                HeaderActionsView.Identifier.DETAILS,
                ContextCompat.getDrawable(
                    context,
                    R.drawable.ic_act_details_outline
                )!!,
                LocaleController.getString("Details")
            ),
            if (shouldShowRepeatAction()) HeaderActionsView.Item(
                HeaderActionsView.Identifier.REPEAT,
                ContextCompat.getDrawable(
                    context,
                    R.drawable.ic_act_repeat_outline
                )!!,
                LocaleController.getString("Repeat")
            ) else null,
            if (!transaction.getTxHash().isNullOrEmpty())
                HeaderActionsView.Item(
                    HeaderActionsView.Identifier.SHARE,
                    ContextCompat.getDrawable(
                        context,
                        R.drawable.ic_act_share_outline
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
    )

    private val transactionDetailsLabel: WLabel by lazy {
        WLabel(context).apply {
            setStyle(14f, WFont.DemiBold)
            text = LocaleController.getString("Details")
            setPadding(0, 0, 0, 10.dp)
        }
    }

    private var transactionAddressHeader: HeaderCell? = null
    private var transactionAddress: WView? = null
    private var addressLabel: WLabel? = null
    private var addressSpans: List<WTypefaceSpan> = emptyList()
    private var addressPopupDisplayProgress: Float = 0f

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
            useSkeletonIndicatorWithWidth = 80.dp
            isLoading = valueLabel.contentView.text.isNullOrEmpty()
        }
    }
    private var transactionIdRow: KeyValueRowView? = null
    private var changellyIdRow: KeyValueRowView? = null
    private val transactionDetails: WView by lazy {
        val v = WView(context)
        v.addView(transactionDetailsLabel)
        val shouldShowViewInExplorer =
            transaction.getTxIdentifier()?.isNotEmpty() == true
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
                                isTinted = true
                                setOnClickListener {
                                    val url = transaction.nft?.collectionUrl ?: return@setOnClickListener
                                    WalletCore.notifyEvent(
                                        WalletEvent.OpenUrl(url)
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
                                    currencyDecimals = token.decimals,
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
                        transaction.fromAmount.absoluteValue.toString(
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
                        transaction.toAmount.toString(
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
                        (transaction.fromAmount.absoluteValue / transaction.toAmount).toString(
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
            )
            detailsRowViews.add(changellyIdRow!!)
        } else if (shouldShowViewInExplorer) {
            transactionIdRow = KeyValueRowView(
                context,
                LocaleController.getString("Transaction ID"),
                "",
                mode = KeyValueRowView.Mode.SECONDARY,
                isLast = false
            )
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
        v.addView(
            actionsView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, HeaderActionsView.HEIGHT.dp)
        )
        val transaction = transaction as? MApiTransaction.Transaction
        if (transaction != null && shouldShowTransactionAddress(transaction)) {
            initTransactionAddress(transaction)
            displayTransactionAddress(transaction)
            updateTransactionAddressBackgroundColor()
        }
        val transactionAddress = this.transactionAddress
        if (transactionAddress != null) {
            v.addView(transactionAddress, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }
        v.addView(transactionDetails, ConstraintLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        v.setConstraints {
            toTop(headerViewContainer)
            toCenterX(headerViewContainer)
            topToBottom(actionsView, headerViewContainer, ViewConstants.GAP.toFloat())
            if (transactionAddress != null) {
                topToBottom(transactionAddress, actionsView, ViewConstants.GAP.toFloat())
                topToBottom(transactionDetails, transactionAddress, ViewConstants.GAP.toFloat())
                toCenterX(transactionAddress, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            } else {
                topToBottom(transactionDetails, actionsView, ViewConstants.GAP.toFloat())
            }
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

    private fun shouldShowTransactionAddress(transaction: MApiTransaction.Transaction): Boolean {
        return transaction.shouldShowTransactionAddress || transaction.type == ApiTransactionType.STAKE
    }

    private fun initTransactionAddress(transaction: MApiTransaction.Transaction) {
        val addressDetailsLabel = HeaderCell(context).apply {
            transactionAddressHeader = this
        }

        //noinspection WrongConstant
        val addressLabel = WLabel(context).apply {
            setStyle(16f, WFont.Regular)
            setTextColor(WColor.SecondaryText)
            setLineHeight(TypedValue.COMPLEX_UNIT_SP, 24f)
            letterSpacing = -0.015f
            breakStrategy = Layout.BREAK_STRATEGY_SIMPLE
            hyphenationFrequency = Layout.HYPHENATION_FREQUENCY_NONE
            setPadding(0, 0, 0, 16.dp)
            foreground = WRippleDrawable.create(0f).apply {
                rippleColor = WColor.SubtitleText.color.colorWithAlpha(25)
            }
            setOnClickListener {
                transactionAddress?.let { onAddressClicked(it, transaction) }
            }
            setOnLongClickListener {
                val blockchain = TokenStore.getToken(transaction.slug)?.mBlockchain
                    ?: return@setOnLongClickListener false
                val address = if (transaction.isIncoming) {
                    transaction.fromAddress
                } else {
                    transaction.toAddress
                } ?: return@setOnLongClickListener false
                AddressPopupHelpers.copyAddress(context, address, blockchain)
                true
            }
            addressLabel = this
        }

        WView(context).apply {
            addView(addressDetailsLabel)
            addView(
                addressLabel, ConstraintLayout.LayoutParams(
                    MATCH_CONSTRAINT, WRAP_CONTENT
                )
            )
            setConstraints {
                toTop(addressDetailsLabel)
                toStart(addressDetailsLabel)
                toStart(addressLabel, 20f)
                toEnd(addressLabel, 20f)
                topToBottom(addressLabel, addressDetailsLabel, 8f)
            }
            transactionAddress = this
        }
    }

    private fun displayTransactionAddress(transaction: MApiTransaction.Transaction) {
        val addressLabel = this.addressLabel ?: return
        val headerText = if (transaction.isIncoming) {
            LocaleController.getString("Sender")
        } else {
            LocaleController.getString("Recipient")
        }
        transactionAddressHeader?.configure(
            title = headerText,
            titleColor = WColor.Tint,
            topRounding = HeaderCell.TopRounding.FIRST_ITEM
        )

        val peerAddress = transaction.peerAddress
        val addressName = transaction.addressName()
        val activeAccount = AccountStore.activeAccount
        val chainIconDrawable = if (activeAccount?.isMultichain == true) {
            TokenStore.getToken(transaction.getTxSlug())?.chain?.let { chain ->
                MBlockchain.valueOf(chain).symbolIconPadded?.let { symbol ->
                    ContextCompat.getDrawable(context, symbol)?.mutate()
                }
            }
        } else {
            null
        }

        val addressText = buildSpannedString {
            if (chainIconDrawable != null) {
                with(chainIconDrawable) {
                    setTint(WColor.SecondaryText.color)
                    setSizeBounds(16.dp, 16.dp)
                }
                inSpans(
                    VerticalImageSpan(
                        chainIconDrawable,
                        endPadding = 2.dp,
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
                append(WORD_JOIN)
            }
            if (addressName != null) {
                inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText)) {
                    append(addressName)
                }
                append(" · ")
                append(peerAddress.formatStartEndAddress(6, 6)).styleDots()
            } else {
                val first = peerAddress.take(6)
                val last = peerAddress.takeLast(6)
                val middle = peerAddress.substring(6, peerAddress.length - 6)
                val colorSpans = mutableListOf<WTypefaceSpan>()
                inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText).also {
                    colorSpans.add(it)
                }) {
                    append(first)
                }
                append(middle)
                inSpans(WTypefaceSpan(WFont.Medium, WColor.PrimaryText).also {
                    colorSpans.add(it)
                }) {
                    append(last)
                }
                addressSpans = colorSpans
            }
            val expandDrawable = ContextCompat.getDrawable(
                context, org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
            )?.mutate()?.apply {
                setTint(WColor.SecondaryText.color)
                alpha = 204
                setSizeBounds(7.dp, 14.dp)
            }
            if (expandDrawable != null) {
                append(WORD_JOIN)
                inSpans(
                    VerticalImageSpan(
                        expandDrawable,
                        startPadding = 4.5f.dp.roundToInt(),
                        verticalAlignment = VerticalImageSpan.VerticalAlignment.TOP_BOTTOM
                    )
                ) { append(" ") }
            }
        }

        addressLabel.text = addressText.replaceSpacesWithNbsp()
        if (!WGlobalStorage.getAreAnimationsActive()) {
            return
        }
        val transactionAddress = this.transactionAddress ?: return
        if (transactionAddress.measuredHeight == 0 || transactionAddress.measuredWidth == 0) {
            return
        }
        val oldHeight = transactionAddress.measuredHeight
        transactionAddress.measure(transactionAddress.width.exactly, 0.unspecified)
        val newHeight = transactionAddress.measuredHeight
        transactionAddress.animateHeight(oldHeight, newHeight)
    }

    private fun onAddressClicked(
        view: View,
        transaction: MApiTransaction.Transaction
    ) {
        val account = AccountStore.activeAccount ?: return
        val addressToShow = transaction.addressToShow(6, 6)
        val addressText = addressToShow?.first ?: ""
        val transactionAddress = this.transactionAddress
        val windowBackgroundStyle = if (transactionAddress == null) {
            BackgroundStyle.Transparent
        } else {
            BackgroundStyle.Cutout.fromView(view, roundRadius = ViewConstants.BLOCK_RADIUS.dp)
        }

        val blockchain = TokenStore.getToken(transaction.slug)?.mBlockchain ?: return
        presentMenu(
            viewController = WeakReference(this),
            view = view,
            title = if (addressToShow?.second == true) addressText else null,
            blockchain = blockchain,
            network = account.network,
            address = if (transaction.isIncoming) {
                transaction.fromAddress ?: ""
            } else {
                transaction.toAddress ?: ""
            },
            centerHorizontally = true,
            showTemporaryViewOption = true,
            windowBackgroundStyle = windowBackgroundStyle
        ) { displayProgress ->
            addressPopupDisplayProgress = displayProgress
            updateAddressSpans()
        }
    }

    override fun setupViews() {
        super.setupViews()

        WalletCore.registerObserver(this)
        setupNavBar(true)
        navigationBar?.setTitleView(titleView, animated = false)
        navigationBar?.addCloseButton()
        setNavSubtitle(transaction.dt.formatDateAndTime())
        configureTitle(animated = false)

        actionsView.setPadding(0, 0, 0, 16.dp)

        view.addView(
            scrollView,
            ConstraintLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT)
        )
        view.setConstraints {
            allEdges(scrollView)
        }

        ensureCorrectHeaderView()
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
        updateAddressSpans()
        updateTransactionAddressBackgroundColor()
        // headerView corners are updated in updateBackground()
        transactionDetails.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
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
        transactionAddressHeader?.updateTheme()
        transactionDetailsLabel.setTextColor(WColor.Tint.color)
        transactionIdRow?.setValue(transactionIdValue)
        changellyIdRow?.setValue(changellyIdValue)

        separatorDrawable.invalidateSelf()
    }

    private fun updateBackground() {
        val expandProgress = 10f / 3f * (((modalExpandProgress ?: 0f) - 0.7f).coerceIn(0f, 1f))
        // Use fixed radius when Rounded Corners is off, otherwise use BLOCK_RADIUS
        val halfExpandedRadius =
            if (ViewConstants.BLOCK_RADIUS == 0f) 24f.dp else ViewConstants.BLOCK_RADIUS.dp
        val currentRadius = (1 - expandProgress) * halfExpandedRadius
        innerContentView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            currentRadius,
            0f
        )

        // Update headerView corners when Rounded Corners is off
        if (ViewConstants.BLOCK_RADIUS == 0f) {
            headerView.setBackgroundColor(WColor.Background.color, currentRadius, 0f)
        } else {
            headerView.setBackgroundColor(WColor.Background.color, ViewConstants.BLOCK_RADIUS.dp)
        }
        if (modalExpandProgress == 1f) {
            view.setBackgroundColor(WColor.SecondaryBackground.color)
        } else {
            view.background = null
        }
    }

    private fun updateAddressSpans() {
        val addressLabel = this.addressLabel ?: return
        if (addressSpans.isEmpty()) {
            return
        }
        val dismissAddressHighlightColor = WColor.PrimaryText.color
        val presentAddressHighlightColor = WColor.SecondaryText.color
        val addressHighlightColor = lerpColor(
            dismissAddressHighlightColor,
            presentAddressHighlightColor,
            WInterpolator.emphasized.getInterpolation(addressPopupDisplayProgress)
        )
        addressSpans.forEach { it.foregroundColor = addressHighlightColor }
        addressLabel.invalidate()
    }

    override fun getModalHalfExpandedHeight(): Int? {
        return innerContentView.top + actionsView.bottom + 36.dp
    }

    override fun onModalSlide(expandOffset: Int, expandProgress: Float) {
        super.onModalSlide(expandOffset, expandProgress)
        updateBackground()
        transactionDetails.alpha = expandProgress
        transactionAddress?.alpha = expandProgress
        val padding = (ViewConstants.HORIZONTAL_PADDINGS.dp * expandProgress).roundToInt()
        headerViewContainer.setPadding(padding, 0, padding, 0)
    }

    private fun configureTitle(animated: Boolean) {
        updateTitleIfNeeded(animated)
        updateTagIfNeeded(animated)
    }

    private fun updateTitleIfNeeded(animated: Boolean) {
        val newTitle = transaction.title
        if (title == newTitle) return

        title = newTitle
        titleLabel?.setText(
            config = WReplaceableLabel.Config(
                text = newTitle,
                isLoading = false,
                isExpandable = false,
                textColor = WColor.PrimaryText,
                textSize = TITLE_TEXT_SIZE,
                font = WFont.SemiBold
            ),
            animated = animated
        )
    }

    private val titleTextPaint by lazy {
        TextPaint().apply {
            typeface = WFont.SemiBold.typeface
            textSize = TITLE_TEXT_SIZE.dp
        }
    }

    private fun updateTagIfNeeded(animated: Boolean) {
        var tagText = transaction.tagText
        if (tagLabel.text == tagText) return

        val translationX = TAG_PADDING + titleTextWidth(title)

        val applyTagUpdate = {
            tagLabel.text = tagText
            val tagColor = transaction.tagColor
            tagLabel.setTextColor(tagColor)
            tagLabel.translationX = translationX
            tagLabel.isGone = tagText.isNullOrEmpty()
            updateTagLabelBackgroundColor()
        }

        if (animated) {
            tagLabel.animate().cancel()
            val duration =
                if (tagText.isNullOrEmpty())
                    AnimationConstants.QUICK_ANIMATION
                else
                    AnimationConstants.QUICK_ANIMATION / 2
            tagLabel.fadeOut(duration = duration) {
                tagLabel.fadeIn(duration = duration)
                tagText = transaction.tagText
                applyTagUpdate()
            }
        } else {
            applyTagUpdate()
        }
    }

    private fun titleTextWidth(text: String?): Float =
        text?.let { titleTextPaint.measureText(text) } ?: 0f

    private fun updateTagLabelBackgroundColor() {
        val transactionTagColor = transaction.tagColor
        tagLabel.setBackgroundColor(transactionTagColor.color.colorWithAlpha(25), 4f.dp)
    }

    private fun updateTransactionAddressBackgroundColor() {
        transactionAddress?.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp,
            ViewConstants.BLOCK_RADIUS.dp
        )
    }

    private fun reloadData() {
        configureTitle(animated = true)
        setNavSubtitle(transaction.dt.formatDateAndTime())
        ensureCorrectHeaderView()
        reloadCommentView()
        reloadTransactionAddressView()
        actionsView.resetTabs(generateActions())
        calcFee(transaction)?.let { fee ->
            feeRow?.setValue(
                fee,
                fadeIn = false
            )
            feeRow?.isLoading = false
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

    private fun reloadTransactionAddressView() {
        val transaction = transaction as? MApiTransaction.Transaction
        if (transaction != null && shouldShowTransactionAddress(transaction)) {
            displayTransactionAddress(transaction)
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
            spannedString.styleDots()
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.SecondaryText.color)
                drawable.alpha = 204
                val width = 7.dp
                val height = 14.dp
                val leftPadding = 3.5f.dp.roundToInt()
                drawable.setBounds(leftPadding, 0, leftPadding + width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        val contentView = transactionIdRow?.valueLabel?.contentView ?: return
                        WMenuPopup.present(
                            contentView,
                            listOf(
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_copy_30,
                                    LocaleController.getString("Copy Transaction ID"),
                                ) {
                                    val clipboard =
                                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                                    val clip = ClipData.newPlainText(
                                        "",
                                        transaction.getTxIdentifier()
                                    )
                                    clipboard.setPrimaryClip(clip)
                                    Haptics.play(context, HapticType.LIGHT_TAP)
                                    Toast.makeText(
                                        context,
                                        LocaleController.getString("Transaction ID Copied"),
                                        Toast.LENGTH_SHORT
                                    ).show()
                                },
                                WMenuPopup.Item(
                                    org.mytonwallet.app_air.icons.R.drawable.ic_world_30,
                                    LocaleController.getString("View on Explorer"),
                                ) {
                                    val network = MBlockchainNetwork.ofAccountId(showingAccountId)
                                    val token = TokenStore.getToken(transaction.getTxSlug())
                                    val chain =
                                        if (token?.chain != null) MBlockchain.valueOf(token.chain)
                                        else if (transaction is Swap) MBlockchain.ton
                                        else return@Item
                                    val txHash = transaction.getTxHash() ?: return@Item
                                    val config = ExplorerHelpers.createTransactionExplorerConfig(
                                        chain, network, txHash
                                    ) ?: return@Item
                                    val browserVC = InAppBrowserVC(context, null, config)
                                    val nav = WNavigationController(window!!)
                                    nav.setRoot(browserVC)
                                    window?.present(nav)
                                }),
                            yOffset = 0,
                            popupWidth = WRAP_CONTENT,
                            positioning = WMenuPopup.Positioning.BELOW,
                            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                                contentView,
                                roundRadius = 16f.dp
                            )
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
            spannedString.styleDots()
            ContextCompat.getDrawable(
                context,
                org.mytonwallet.app_air.icons.R.drawable.ic_arrows_14
            )?.let { drawable ->
                drawable.mutate()
                drawable.setTint(WColor.SecondaryText.color)
                drawable.alpha = 204
                val width = 7.dp
                val height = 14.dp
                val leftPadding = 3.5f.dp.roundToInt()
                drawable.setBounds(leftPadding, 0, leftPadding + width, height)
                val imageSpan = VerticalImageSpan(drawable)
                spannedString.append(" ", imageSpan, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            spannedString.setSpan(
                object : ClickableSpan() {
                    override fun onClick(widget: View) {
                        val contentView = changellyIdRow?.valueLabel?.contentView ?: return
                        WMenuPopup.present(
                            contentView,
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
                                    Haptics.play(context, HapticType.LIGHT_TAP)
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
                                                injectDappConnect = false
                                            )
                                        )
                                    val nav = WNavigationController(window!!)
                                    nav.setRoot(browserVC)
                                    window?.present(nav)
                                }),
                            popupWidth = WRAP_CONTENT,
                            positioning = WMenuPopup.Positioning.BELOW,
                            windowBackgroundStyle = BackgroundStyle.Cutout.fromView(
                                contentView,
                                roundRadius = 16f.dp
                            )
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
        val accountId = AccountStore.activeAccountId ?: return
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
                    feeRow?.isLoading = false
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
                                comment = transaction.comment
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
                        transaction.fromAmount.absoluteValue
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
        shareIntent.putExtra(
            Intent.EXTRA_TEXT,
            transaction.explorerUrl(MBlockchainNetwork.ofAccountId(showingAccountId))
        )
        window?.startActivity(
            Intent.createChooser(
                shareIntent,
                LocaleController.getString("Share")
            )
        )
    }

    private fun navigateToToken(slug: String) {
        window?.dismissLastNav {
            WalletCore.notifyEvent(WalletEvent.OpenToken(slug))
        }
    }

    override fun onWalletEvent(walletEvent: WalletEvent) {
        when (walletEvent) {
            is WalletEvent.AccountSavedAddressesChanged,
            is WalletEvent.ByChainUpdated  -> {
                reloadData()
            }
            is WalletEvent.ReceivedNewActivities -> {
                walletEvent.newActivities?.find {
                    return@find if (it.isLocal())
                        ActivityHelpers.localActivityMatches(this.transaction, it)
                    else
                        this.transaction.isSame(it)
                }?.let {
                    this.transaction = adjustTransactionStatusForUi(it)
                    reloadData()
                }
            }

            else -> {}
        }
    }
}
