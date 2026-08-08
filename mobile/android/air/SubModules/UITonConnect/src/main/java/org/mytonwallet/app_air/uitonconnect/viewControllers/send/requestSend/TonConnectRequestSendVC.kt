package org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import androidx.core.view.doOnLayout
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListDecorator
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonCell
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonHeaderCell
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.dialog.WDialog
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uicomponents.widgets.updateLayoutParamsIfExists
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uitonconnect.viewControllers.TonConnectRequestSendViewModel
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.Adapter
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.TonConnectItem
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.holder.CellHeaderSendRequest
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSendDetails.TonConnectRequestSendDetailsVC
import org.mytonwallet.app_air.uitonconnect.viewControllers.signed.SignedVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.ApplicationContextHolder
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.helpers.DappDeeplinkReturnTracker
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore

private const val NOT_RESPONDING_DELAY_MS = 7000L
private const val BUTTONS_CONTENT_INSET_DP = 90
private const val BUTTONS_BOTTOM_MARGIN_DP = 15
private const val ERROR_CONTENT_INSET_DP = 26

@SuppressLint("ViewConstructor")
class TonConnectRequestSendVC(
    context: Context,
    private val connectionType: ApiConnectionType,
    private var update: ApiUpdate.ApiUpdateDappSignRequest? = null,
    // When opened as a placeholder by a wake deeplink: render no type-specific title and run the not-responding timer.
    private val isWaitingForRequest: Boolean = false,
    private val returnUrl: String? = null
) : WViewControllerWithModelStore(context),
    CustomListAdapter.ItemClickListener,
    SkeletonContainer {
    @Suppress("PropertyName")
    override val TAG = "TonConnectRequestSend"

    override val shouldDisplayTopBar = false

    private var viewModel: TonConnectRequestSendViewModel? = null

    private val skeletonView = SkeletonView(context)
    private var isShowingSkeleton = false

    private val notRespondingHandler = Handler(Looper.getMainLooper())

    private val walletPillSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val dappPillSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val headerConnectionSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val walletIconSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val headerIconSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val walletNameSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val walletBalanceSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val dappNameSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val dappAddressSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val totalAmountSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val transferSkeletonContainer = WView(context).apply {
        visibility = View.GONE
    }
    private val transferHeaderTitleSkeletonView = WBaseView(context)
    private val transferIconSkeletonView = WBaseView(context)
    private val transferTitleSkeletonView = WBaseView(context)
    private val transferSubtitleSkeletonView = WBaseView(context)
    private val headerSkeletonContainer = WView(context).apply {
        visibility = View.GONE
    }

    private val confirmButtonView: WButton = WButton(context, WButton.Type.PRIMARY).apply {
        layoutParams = ViewGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT)
        text = LocaleController.getString("Confirm")
    }
    private val cancelButtonView: WButton =
        WButton(context, WButton.Type.SECONDARY_WITH_BACKGROUND).apply {
            layoutParams = ViewGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT)
            text = LocaleController.getString("Cancel")
        }
    private val errorLabel = WLabel(context).apply {
        setStyle(14f)
        setTextColor(WColor.Error)
        gravity = Gravity.CENTER
        maxLines = 2
        visibility = View.GONE
    }
    private val rvAdapter = Adapter()

    private val recyclerView = RecyclerView(context).apply {
        id = View.generateViewId()
        adapter = rvAdapter
        addItemDecoration(CustomListDecorator())
        clipToPadding = false
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, recyclerView).apply {
            if (ignoreSideGuttering) setHorizontalPadding(0f)
        }

    override fun setupViews() {
        super.setupViews()

        if (update != null) {
            initializeWithUpdate()
        } else {
            showSkeleton()

            title = if (isWaitingForRequest) {
                null
            } else {
                when (connectionType) {
                    ApiConnectionType.SEND_TRANSACTION -> {
                        LocaleController.getPluralWord(
                            1,
                            "Confirm Actions"
                        )
                    }

                    ApiConnectionType.SIGN_DATA -> {
                        LocaleController.getString("Sign Data")
                    }

                    else -> null
                }
            }

            if (isWaitingForRequest) {
                notRespondingHandler.postDelayed({ showNotResponding() }, NOT_RESPONDING_DELAY_MS)
            }
        }

        rvAdapter.setOnItemClickListener(this)
        rvAdapter.onPreviewFeeClick = ::showFeeDetails

        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            navigationController?.getSystemBars()?.top ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )

        view.addView(
            recyclerView,
            ViewGroup.LayoutParams(
                MATCH_PARENT,
                MATCH_PARENT
            )
        )
        view.addView(
            headerSkeletonContainer,
            ViewGroup.LayoutParams(
                0,
                72.dp
            )
        )
        headerSkeletonContainer.addView(
            walletPillSkeletonView,
            ViewGroup.LayoutParams(
                142.dp,
                CellHeaderSendRequest.PILL_HEIGHT.dp
            )
        )
        headerSkeletonContainer.addView(
            dappPillSkeletonView,
            ViewGroup.LayoutParams(
                142.dp,
                CellHeaderSendRequest.PILL_HEIGHT.dp
            )
        )
        headerSkeletonContainer.addView(
            headerConnectionSkeletonView,
            ViewGroup.LayoutParams(
                0,
                1.dp
            )
        )
        headerSkeletonContainer.addView(
            walletIconSkeletonView,
            ViewGroup.LayoutParams(
                CellHeaderSendRequest.ICON_SIZE.dp,
                CellHeaderSendRequest.ICON_SIZE.dp
            )
        )
        headerSkeletonContainer.addView(
            headerIconSkeletonView,
            ViewGroup.LayoutParams(
                CellHeaderSendRequest.ICON_SIZE.dp,
                CellHeaderSendRequest.ICON_SIZE.dp
            )
        )
        headerSkeletonContainer.addView(
            walletNameSkeletonView,
            ViewGroup.LayoutParams(
                72.dp,
                14.dp
            )
        )
        headerSkeletonContainer.addView(
            walletBalanceSkeletonView,
            ViewGroup.LayoutParams(
                80.dp,
                14.dp
            )
        )
        headerSkeletonContainer.addView(
            dappNameSkeletonView,
            ViewGroup.LayoutParams(
                72.dp,
                14.dp
            )
        )
        headerSkeletonContainer.addView(
            dappAddressSkeletonView,
            ViewGroup.LayoutParams(
                80.dp,
                14.dp
            )
        )
        view.addView(
            totalAmountSkeletonView,
            ViewGroup.LayoutParams(
                120.dp,
                36.dp
            )
        )
        view.addView(transferSkeletonContainer, ViewGroup.LayoutParams(0, 100.dp))
        transferSkeletonContainer.addView(
            transferHeaderTitleSkeletonView,
            ViewGroup.LayoutParams(160.dp, 16.dp)
        )
        transferSkeletonContainer.addView(
            transferIconSkeletonView,
            ViewGroup.LayoutParams(
                ApplicationContextHolder.adaptiveIconSize.dp,
                ApplicationContextHolder.adaptiveIconSize.dp
            )
        )
        transferSkeletonContainer.addView(
            transferTitleSkeletonView,
            ViewGroup.LayoutParams(SkeletonCell.TITLE_WIDTH.first().dp, 16.dp)
        )
        transferSkeletonContainer.addView(
            transferSubtitleSkeletonView,
            ViewGroup.LayoutParams(SkeletonCell.SUBTITLE_WIDTH.first().dp, 14.dp)
        )
        view.addView(skeletonView, ViewGroup.LayoutParams(0, 0))

        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                (BUTTONS_CONTENT_INSET_DP + ViewConstants.BLOCK_RADIUS).dp.roundToInt()
            )
        )
        view.addView(cancelButtonView)
        view.addView(confirmButtonView)
        view.addView(
            errorLabel,
            ConstraintLayout.LayoutParams(
                MATCH_CONSTRAINT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        view.setConstraints {
            toCenterX(bottomReversedCornerViewUpsideDown)
            toBottom(bottomReversedCornerViewUpsideDown)
            toStart(cancelButtonView, 20f)
            toEnd(confirmButtonView, 20f)

            startToEnd(confirmButtonView, cancelButtonView, 6f)
            endToStart(cancelButtonView, confirmButtonView, 6f)

            toCenterX(errorLabel, 20f)
            bottomToTop(errorLabel, cancelButtonView, 12f)

            toTopPx(
                headerSkeletonContainer,
                navigationController?.getSystemBars()?.top ?: 0
            )
            toCenterX(headerSkeletonContainer, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
            topToBottom(totalAmountSkeletonView, headerSkeletonContainer, 34f)
            toCenterX(totalAmountSkeletonView)
            topToBottom(transferSkeletonContainer, headerSkeletonContainer, 108f)
            toCenterX(
                transferSkeletonContainer,
                ViewConstants.HORIZONTAL_PADDINGS.toFloat()
            )
            allEdges(skeletonView)
        }

        headerSkeletonContainer.setConstraints {
            toStart(walletPillSkeletonView)
            toCenterY(walletPillSkeletonView)

            startToEnd(headerConnectionSkeletonView, walletPillSkeletonView, 8f)
            endToStart(headerConnectionSkeletonView, dappPillSkeletonView, 8f)
            toCenterY(headerConnectionSkeletonView)

            toEnd(dappPillSkeletonView)
            toCenterY(dappPillSkeletonView)

            toStart(walletIconSkeletonView, 8f)
            toCenterY(walletIconSkeletonView)

            toEnd(headerIconSkeletonView, 8f)
            toCenterY(headerIconSkeletonView)

            startToEnd(walletBalanceSkeletonView, walletIconSkeletonView, 6f)
            toTop(walletBalanceSkeletonView, 19f)
            startToEnd(walletNameSkeletonView, walletIconSkeletonView, 6f)
            toBottom(walletNameSkeletonView, 19f)

            toTop(dappNameSkeletonView, 19f)
            endToStart(dappNameSkeletonView, headerIconSkeletonView, 6f)
            toBottom(dappAddressSkeletonView, 19f)
            endToStart(dappAddressSkeletonView, headerIconSkeletonView, 6f)
        }

        transferSkeletonContainer.setConstraints {
            toTop(transferHeaderTitleSkeletonView, 16f)
            toStart(transferHeaderTitleSkeletonView, 20f)
            toTop(
                transferIconSkeletonView,
                40f + (60f - ApplicationContextHolder.adaptiveIconSize) / 2f
            )
            toStart(transferIconSkeletonView, 12f)
            toTop(transferTitleSkeletonView, 49f)
            toStart(
                transferTitleSkeletonView,
                ApplicationContextHolder.adaptiveContentStart
            )
            toTop(transferSubtitleSkeletonView, 76f)
            toStart(
                transferSubtitleSkeletonView,
                ApplicationContextHolder.adaptiveContentStart
            )
        }

        cancelButtonView.setOnClickListener {
            val currentUpdate = update
            if (currentUpdate != null) {
                viewModel?.cancel(currentUpdate.promiseId, null)
            } else {
                // Placeholder (wake deeplink, no request yet): nothing to cancel, just close.
                window?.dismissLastNav()
            }
        }

        confirmButtonView.setOnClickListener {
            if (AccountStore.accountById(update?.accountId)?.isViewOnly == true) {
                window?.topViewController?.showAlert(
                    LocaleController.getString("Error"),
                    LocaleController.getString("Action is not possible on a view-only wallet.")
                )
                return@setOnClickListener
            }
            update?.let {
                didAccept = true
                WalletCore.recordTonConnectEvent(acceptedEventName, it.promiseId)
            }
            if (AccountStore.activeAccount?.isHardware == true) {
                confirmHardware()
            } else {
                confirmPasscode()
            }
        }

        updateTheme()
        insetsUpdated()
    }

    private fun showFeeDetails(item: TonConnectItem.PreviewFee) {
        val feeDetails = item.feeDetails ?: return
        lateinit var dialogRef: WDialog
        dialogRef = DappFeeDetailsDialog.create(
            context,
            item.token,
            feeDetails
        ) {
            dialogRef.dismiss()
        }
        dialogRef.presentOn(this)
    }

    private fun initializeWithUpdate() {
        val updateValue = update ?: return

        if (isShowingSkeleton) {
            hideSkeleton()
        }

        viewModel = ViewModelProvider(
            this,
            TonConnectRequestSendViewModel.Factory(updateValue)
        )[TonConnectRequestSendViewModel::class.java]

        title = when (updateValue) {
            is ApiUpdate.ApiUpdateDappSendTransactions -> {
                LocaleController.getPluralWord(
                    updateValue.transactions.size,
                    "Confirm Actions"
                )
            }

            is ApiUpdate.ApiUpdateDappSignData -> {
                LocaleController.getString("Sign Data")
            }

            else -> throw Exception()
        }
        setNavTitle(title!!)

        collectFlow(viewModel!!.eventsFlow, ::onEvent)
        collectFlow(viewModel!!.uiItemsFlow, rvAdapter::submitList)
        collectFlow(viewModel!!.uiStateFlow) {
            cancelButtonView.isLoading = it.cancelButtonIsLoading
        }
        collectFlow(viewModel!!.insufficientTokensFlow, ::updateInsufficientTokens)

        confirmButtonView.isEnabled = insufficientTokens == null
        updateConfirmButtonStyle()
    }

    private var insufficientTokens: String? = null
    private fun updateInsufficientTokens(symbols: String?) {
        if (insufficientTokens == symbols) return
        insufficientTokens = symbols
        errorLabel.text = symbols?.let {
            LocaleController.getStringWithKeyValues(
                "Not Enough %symbol%",
                listOf(Pair("%symbol%", it))
            )
        }
        errorLabel.visibility = if (symbols == null) View.GONE else View.VISIBLE
        confirmButtonView.isEnabled = symbols == null
        insetsUpdated()
    }

    private fun updateConfirmButtonStyle() {
        val isDangerous =
            update?.dapp?.resolvedUrlTrustStatus == ApiDappUrlTrustStatus.DANGEROUS
        confirmButtonView.type = if (isDangerous) WButton.Type.DESTRUCTIVE else WButton.Type.PRIMARY
        confirmButtonView.text = LocaleController.getString(
            if (isDangerous) "Confirm Anyway" else "Confirm"
        )
    }

    fun setUpdate(newUpdate: ApiUpdate.ApiUpdateDappSignRequest) {
        notRespondingHandler.removeCallbacksAndMessages(null)
        this.update = newUpdate
        if (isViewConfigured) {
            initializeWithUpdate()
        }
    }

    // True once the user tapped Confirm; prevents onDestroy from reporting `declined` after an accepted
    // request whose signing/MFA later failed (which would double-fire accepted + declined for one request).
    private var didAccept = false

    private val acceptedEventName: String
        get() = if (connectionType ==
            ApiConnectionType.SIGN_DATA
        ) {
            "wallet-sign-data-accepted"
        } else {
            "wallet-transaction-accepted"
        }

    private val declinedEventName: String
        get() = if (connectionType ==
            ApiConnectionType.SIGN_DATA
        ) {
            "wallet-sign-data-declined"
        } else {
            "wallet-transaction-declined"
        }

    private fun showNotResponding() {
        val url = returnUrl
        showAlert(
            title = LocaleController.getString("Dapp Not Responding"),
            text = LocaleController.getString(
                "You may need to reconnect your wallet from the dapp if this keeps happening."
            ),
            button = LocaleController.getString("OK"),
            buttonPressed = {
                // With a return URL ("OK"/"Cancel" pair), OK returns to the dapp and dismisses the skeleton;
                // without one (single "OK"), it just dismisses the alert and keeps waiting.
                url?.let {
                    window?.dismissLastNav(onCompletion = {
                        window?.startActivityCatching(Intent(Intent.ACTION_VIEW, Uri.parse(it)))
                    })
                }
            },
            secondaryButton = if (url != null) LocaleController.getString("Cancel") else null
        )
    }

    private fun showSkeleton() {
        if (isShowingSkeleton) return
        isShowingSkeleton = true

        recyclerView.visibility = View.INVISIBLE
        confirmButtonView.isEnabled = false

        headerSkeletonContainer.visibility = View.VISIBLE
        walletPillSkeletonView.visibility = View.VISIBLE
        dappPillSkeletonView.visibility = View.VISIBLE
        headerConnectionSkeletonView.visibility = View.VISIBLE
        walletIconSkeletonView.visibility = View.VISIBLE
        headerIconSkeletonView.visibility = View.VISIBLE
        walletNameSkeletonView.visibility = View.VISIBLE
        walletBalanceSkeletonView.visibility = View.VISIBLE
        dappNameSkeletonView.visibility = View.VISIBLE
        dappAddressSkeletonView.visibility = View.VISIBLE
        totalAmountSkeletonView.visibility =
            if (connectionType == ApiConnectionType.SEND_TRANSACTION) View.VISIBLE else View.GONE
        transferSkeletonContainer.visibility =
            if (connectionType == ApiConnectionType.SEND_TRANSACTION) View.VISIBLE else View.GONE

        walletPillSkeletonView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
        dappPillSkeletonView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
        headerConnectionSkeletonView.setBackgroundColor(WColor.Thumb.color, 0.5f.dp)
        walletIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
        headerIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
        walletNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
        walletBalanceSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
        dappNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
        dappAddressSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
        totalAmountSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 24f.dp)
        transferSkeletonContainer.setBackgroundColor(
            WColor.Background.color,
            ViewConstants.BLOCK_RADIUS.dp
        )
        transferHeaderTitleSkeletonView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            SkeletonHeaderCell.TITLE_SKELETON_RADIUS
        )
        transferIconSkeletonView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            SkeletonCell.CIRCLE_SKELETON_RADIUS
        )
        transferTitleSkeletonView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            SkeletonCell.TITLE_SKELETON_RADIUS
        )
        transferSubtitleSkeletonView.setBackgroundColor(
            WColor.SecondaryBackground.color,
            SkeletonCell.SUBTITLE_SKELETON_RADIUS
        )

        val skeletonViews = mutableListOf(
            walletIconSkeletonView,
            headerIconSkeletonView,
            walletNameSkeletonView,
            walletBalanceSkeletonView,
            dappNameSkeletonView,
            dappAddressSkeletonView,
            totalAmountSkeletonView,
            transferHeaderTitleSkeletonView,
            transferIconSkeletonView,
            transferTitleSkeletonView,
            transferSubtitleSkeletonView
        )
        val radiusMap = hashMapOf(
            0 to 16f,
            1 to 16f,
            2 to 7f,
            3 to 7f,
            4 to 7f,
            5 to 7f,
            6 to 24f.dp,
            7 to SkeletonHeaderCell.TITLE_SKELETON_RADIUS,
            8 to SkeletonCell.CIRCLE_SKELETON_RADIUS,
            9 to SkeletonCell.TITLE_SKELETON_RADIUS,
            10 to SkeletonCell.SUBTITLE_SKELETON_RADIUS
        )
        skeletonView.doOnLayout {
            if (!isShowingSkeleton) return@doOnLayout
            skeletonView.applyMask(skeletonViews, radiusMap)
            skeletonView.startAnimating()
        }
    }

    private fun hideSkeleton() {
        if (!isShowingSkeleton) return
        isShowingSkeleton = false

        skeletonView.stopAnimating()

        walletIconSkeletonView.fadeOut(onCompletion = {
            walletIconSkeletonView.visibility = View.GONE
        })
        headerIconSkeletonView.fadeOut(onCompletion = {
            headerIconSkeletonView.visibility = View.GONE
        })
        walletNameSkeletonView.fadeOut(onCompletion = {
            walletNameSkeletonView.visibility = View.GONE
        })
        walletBalanceSkeletonView.fadeOut(onCompletion = {
            walletBalanceSkeletonView.visibility = View.GONE
        })
        dappNameSkeletonView.fadeOut(onCompletion = {
            dappNameSkeletonView.visibility = View.GONE
        })
        dappAddressSkeletonView.fadeOut(onCompletion = {
            dappAddressSkeletonView.visibility = View.GONE
        })
        if (totalAmountSkeletonView.isVisible) {
            totalAmountSkeletonView.fadeOut(onCompletion = {
                totalAmountSkeletonView.visibility = View.GONE
            })
        }
        if (transferSkeletonContainer.isVisible) {
            transferSkeletonContainer.fadeOut(onCompletion = {
                transferSkeletonContainer.visibility = View.GONE
            })
        }
        headerSkeletonContainer.fadeOut(onCompletion = {
            headerSkeletonContainer.visibility = View.GONE
        })

        recyclerView.visibility = View.VISIBLE
        recyclerView.fadeIn()
    }

    private fun onEvent(event: TonConnectRequestSendViewModel.Event) {
        when (event) {
            is TonConnectRequestSendViewModel.Event.Close -> pop()

            is TonConnectRequestSendViewModel.Event.Complete -> {
                if (event.success) {
                    val shouldReturnToDapp =
                        DappDeeplinkReturnTracker.consumeCompletedRequest(update?.promiseId)
                    if (update is ApiUpdate.ApiUpdateDappSignData) {
                        navigationController?.push(SignedVC(context), onCompletion = {
                            navigationController?.removePrevViewControllers()
                            if (shouldReturnToDapp) window?.moveTaskToBack(true)
                        })
                    } else {
                        navigationController?.window?.dismissLastNav {
                            if (shouldReturnToDapp) window?.moveTaskToBack(true)
                        }
                    }
                } else {
                    navigationController?.pop(true, onCompletion = {
                        showError(event.err)
                    })
                }
            }

            is TonConnectRequestSendViewModel.Event.ShowWarningAlert -> {
                showAlert(event.title, event.text, allowLinkInText = event.allowLinkInText)
            }

            is TonConnectRequestSendViewModel.Event.OpenDappInBrowser -> {
                dismissActiveDialogs()
                window?.dismissLastNav(onCompletion = {
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(event.url))
                })
            }

            is TonConnectRequestSendViewModel.Event.MfaRequested -> {
                val promiseId = event.promiseId
                val requestWindow = window
                fun confirmMfaRequest() {
                    WalletCore.scope.launch {
                        try {
                            WalletCore.call(
                                ApiMethod.DApp.ConfirmDappRequestSendTransactionMfa(
                                    promiseId,
                                    event.requestHash
                                )
                            )
                            if (DappDeeplinkReturnTracker.consumeCompletedRequest(promiseId)) {
                                requestWindow?.moveTaskToBack(true)
                            }
                        } catch (t: Throwable) {
                            Logger.e(
                                Logger.LogTag.SEND,
                                "confirmDappRequestSendTransaction MFA failed " +
                                    "for promiseId=$promiseId: $t"
                            )
                        }
                    }
                }
                val mfaVC = org.mytonwallet.app_air.uicomponents.viewControllers
                    .MfaActionConfirmVC(
                        context,
                        requestHash = event.requestHash,
                        onConfirmed = { _ ->
                            confirmMfaRequest()
                        },
                        onClosedBeforeFinish = { wasMfaConfirmed, _ ->
                            if (wasMfaConfirmed) {
                                confirmMfaRequest()
                            } else {
                                requestWindow?.lifecycleScope?.launch {
                                    try {
                                        WalletCore.call(
                                            ApiMethod.DApp.CancelDappRequest(
                                                promiseId = promiseId,
                                                reason = "user reject"
                                            )
                                        )
                                    } catch (t: Throwable) {
                                        Logger.e(
                                            Logger.LogTag.SEND,
                                            "cancelDappRequestSendTransaction MFA failed " +
                                                "for promiseId=$promiseId: $t"
                                        )
                                    }
                                    val shouldReturnToDapp =
                                        DappDeeplinkReturnTracker
                                            .consumeCompletedRequest(promiseId)
                                    if (shouldReturnToDapp) {
                                        requestWindow.moveTaskToBack(true)
                                    }
                                }
                            }
                        }
                    )
                navigationController?.push(mfaVC, onCompletion = {
                    navigationController?.removePrevViewControllerOnly()
                })
            }
        }
    }

    override fun onDestroy() {
        isShowingSkeleton = false
        skeletonView.onDestroy()
        super.onDestroy()

        notRespondingHandler.removeCallbacksAndMessages(null)
        update?.let {
            val shouldReturnToDapp = viewModel?.isConfirmed != true &&
                DappDeeplinkReturnTracker.consumeCompletedRequest(it.promiseId)
            if (viewModel?.isConfirmed != true && !didAccept) {
                WalletCore.recordTonConnectEvent(declinedEventName, it.promiseId)
            }
            viewModel?.cancel(it.promiseId, null, window!!.lifecycleScope)
            if (shouldReturnToDapp) window?.moveTaskToBack(true)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)

        if (isShowingSkeleton) {
            walletPillSkeletonView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
            dappPillSkeletonView.setBackgroundColor(WColor.ThumbBackground.color, 24f.dp)
            headerConnectionSkeletonView.setBackgroundColor(WColor.Thumb.color, 0.5f.dp)
            walletIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
            headerIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 16f.dp)
            walletNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
            walletBalanceSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
            dappNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
            dappAddressSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 7f.dp)
            totalAmountSkeletonView.setBackgroundColor(WColor.GroupedBackground.color, 24f.dp)
            transferSkeletonContainer.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.BLOCK_RADIUS.dp
            )
            transferHeaderTitleSkeletonView.setBackgroundColor(
                WColor.SecondaryBackground.color,
                SkeletonHeaderCell.TITLE_SKELETON_RADIUS
            )
            transferIconSkeletonView.setBackgroundColor(
                WColor.SecondaryBackground.color,
                SkeletonCell.CIRCLE_SKELETON_RADIUS
            )
            transferTitleSkeletonView.setBackgroundColor(
                WColor.SecondaryBackground.color,
                SkeletonCell.TITLE_SKELETON_RADIUS
            )
            transferSubtitleSkeletonView.setBackgroundColor(
                WColor.SecondaryBackground.color,
                SkeletonCell.SUBTITLE_SKELETON_RADIUS
            )
        }
    }

    override fun onItemClickItems(
        view: View,
        position: Int,
        item: BaseListItem,
        items: List<BaseListItem>
    ) {
        push(TonConnectRequestSendDetailsVC(context, items))
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        val systemBottomInset = max(
            navigationController?.imeInsetBottom ?: 0,
            navigationController?.getSystemBars()?.bottom ?: 0
        )
        val errorContentInset =
            if (errorLabel.isVisible) ERROR_CONTENT_INSET_DP.dp else 0
        val contentBottomInset =
            BUTTONS_CONTENT_INSET_DP.dp + errorContentInset + systemBottomInset

        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            navigationController?.getSystemBars()?.top ?: 0,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            contentBottomInset
        )

        bottomReversedCornerViewUpsideDown.updateLayoutParamsIfExists {
            height = contentBottomInset + ViewConstants.BLOCK_RADIUS.dp.roundToInt()
        }
        view.setConstraints {
            toTopPx(
                headerSkeletonContainer,
                navigationController?.getSystemBars()?.top ?: 0
            )
            toBottom(recyclerView)
            toBottomPx(
                cancelButtonView,
                BUTTONS_BOTTOM_MARGIN_DP.dp + systemBottomInset
            )
            toBottomPx(
                confirmButtonView,
                BUTTONS_BOTTOM_MARGIN_DP.dp + systemBottomInset
            )
        }
    }

    private fun confirmHardware() {
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = ledgerSignDataObject,
                onDone = {
                    viewModel?.notifyDone(true, null)
                }
            ),
            headerView = confirmHeaderView
        )
        navigationController?.push(ledgerConnectVC)
    }

    private fun confirmPasscode() {
        val updateValue = update ?: return
        val confirmActionVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                confirmHeaderView,
                showNavbarTitle = false
            ),
            task = { passcode ->
                viewModel?.accept(updateValue.promiseId, passcode)
            }
        )
        push(confirmActionVC)
    }

    private val confirmHeaderView: View
        get() {
            val maximumHeight =
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO)
                    .roundToInt()
            return PasscodeHeaderSendView(
                WeakReference(this),
                maximumHeight
            ).apply {
                config(
                    Content.ofUrl(update?.dapp?.iconUrl ?: ""),
                    when (update) {
                        is ApiUpdate.ApiUpdateDappSignData -> {
                            LocaleController.getString("Confirm Action")
                        }

                        else -> title ?: ""
                    },
                    update?.dapp?.host ?: "",
                    Content.Rounding.Radius(12f.dp)
                )
                setSubtitleColor(WColor.Tint)
            }
        }

    private val ledgerSignDataObject: LedgerConnectVC.SignData
        get() {
            val updateValue = update ?: throw Exception("Update is null")
            val accountId = updateValue.accountId
            return when (updateValue) {
                is ApiUpdate.ApiUpdateDappSendTransactions -> {
                    LedgerConnectVC.SignData.SignDappTransfers(accountId, updateValue)
                }

                is ApiUpdate.ApiUpdateDappSignData -> {
                    LedgerConnectVC.SignData.SignDappData(accountId, updateValue)
                }

                else -> {
                    throw Exception()
                }
            }
        }

    override fun getChildViewMap(): HashMap<View, Float> = hashMapOf(
        walletIconSkeletonView to 16f,
        headerIconSkeletonView to 16f,
        walletNameSkeletonView to 7f,
        walletBalanceSkeletonView to 7f,
        dappNameSkeletonView to 7f,
        dappAddressSkeletonView to 7f,
        totalAmountSkeletonView to 24f.dp,
        transferHeaderTitleSkeletonView to SkeletonHeaderCell.TITLE_SKELETON_RADIUS,
        transferIconSkeletonView to SkeletonCell.CIRCLE_SKELETON_RADIUS,
        transferTitleSkeletonView to SkeletonCell.TITLE_SKELETON_RADIUS,
        transferSubtitleSkeletonView to SkeletonCell.SUBTITLE_SKELETON_RADIUS
    )
}
