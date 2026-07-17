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
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.adapter.BaseListItem
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListAdapter
import org.mytonwallet.app_air.uicomponents.adapter.implementation.CustomListDecorator
import org.mytonwallet.app_air.uicomponents.base.WNavigationBar
import org.mytonwallet.app_air.uicomponents.base.WViewControllerWithModelStore
import org.mytonwallet.app_air.uicomponents.base.showAlert
import org.mytonwallet.app_air.uicomponents.commonViews.ReversedCornerViewUpsideDown
import org.mytonwallet.app_air.uicomponents.commonViews.SkeletonView
import org.mytonwallet.app_air.uicomponents.commonViews.cells.SkeletonContainer
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.extensions.startActivityCatching
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.WView
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.fadeOut
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uitonconnect.viewControllers.TonConnectRequestSendViewModel
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.Adapter
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSendDetails.TonConnectRequestSendDetailsVC
import org.mytonwallet.app_air.uitonconnect.viewControllers.signed.SignedVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import kotlinx.coroutines.launch
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.ApiDappUrlTrustStatus
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt
import androidx.core.view.isVisible

private const val NOT_RESPONDING_DELAY_MS = 7000L

@SuppressLint("ViewConstructor")
class TonConnectRequestSendVC(
    context: Context,
    private val connectionType: ApiConnectionType,
    private var update: ApiUpdate.ApiUpdateDappSignRequest? = null,
    // When opened as a placeholder by a wake deeplink: render no type-specific title and run the not-responding timer.
    private val isWaitingForRequest: Boolean = false,
    private val returnUrl: String? = null,
) : WViewControllerWithModelStore(context), CustomListAdapter.ItemClickListener, SkeletonContainer {
    override val TAG = "TonConnectRequestSend"

    override val shouldDisplayTopBar = true

    private var viewModel: TonConnectRequestSendViewModel? = null

    private val skeletonView = SkeletonView(context)
    private var isShowingSkeleton = false

    private val notRespondingHandler = Handler(Looper.getMainLooper())

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
        val layoutManager = LinearLayoutManager(context)
        layoutManager.isSmoothScrollbarEnabled = true
        setLayoutManager(layoutManager)
    }

    private val bottomReversedCornerViewUpsideDown: ReversedCornerViewUpsideDown =
        ReversedCornerViewUpsideDown(context, recyclerView).apply {
            if (ignoreSideGuttering)
                setHorizontalPadding(0f)
        }

    override fun setupViews() {
        super.setupViews()

        if (update != null) {
            initializeWithUpdate()
        } else {
            showSkeleton()

            title = if (isWaitingForRequest) {
                null
            } else when (connectionType) {
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

            if (isWaitingForRequest) {
                notRespondingHandler.postDelayed({ showNotResponding() }, NOT_RESPONDING_DELAY_MS)
            }
        }

        rvAdapter.setOnItemClickListener(this)

        setupNavBar(true)
        navigationBar?.addCloseButton()
        navigationBar?.setTitleGravity(Gravity.CENTER)
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )

        view.addView(
            recyclerView, ViewGroup.LayoutParams(
                MATCH_PARENT, MATCH_PARENT
            )
        )
        view.addView(
            headerSkeletonContainer, ViewGroup.LayoutParams(
                0,
                72.dp,
            )
        )
        headerSkeletonContainer.addView(
            headerIconSkeletonView, ViewGroup.LayoutParams(
                48.dp,
                48.dp
            )
        )
        headerSkeletonContainer.addView(
            walletNameSkeletonView, ViewGroup.LayoutParams(
                88.dp,
                20.dp
            )
        )
        headerSkeletonContainer.addView(
            walletBalanceSkeletonView, ViewGroup.LayoutParams(
                72.dp,
                15.dp
            )
        )
        headerSkeletonContainer.addView(
            dappNameSkeletonView, ViewGroup.LayoutParams(
                84.dp,
                20.dp
            )
        )
        headerSkeletonContainer.addView(
            dappAddressSkeletonView, ViewGroup.LayoutParams(
                96.dp,
                15.dp
            )
        )
        view.addView(skeletonView, ViewGroup.LayoutParams(0, 0))

        view.addView(
            bottomReversedCornerViewUpsideDown,
            ConstraintLayout.LayoutParams(
                MATCH_PARENT,
                MATCH_CONSTRAINT
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
            topToTop(
                bottomReversedCornerViewUpsideDown,
                cancelButtonView,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
            toBottom(bottomReversedCornerViewUpsideDown)
            toLeft(cancelButtonView, 20f)
            toRight(confirmButtonView, 20f)

            leftToRight(confirmButtonView, cancelButtonView, 6f)
            rightToLeft(cancelButtonView, confirmButtonView, 6f)

            toCenterX(errorLabel, 20f)
            bottomToTop(errorLabel, cancelButtonView, 12f)

            topToBottom(headerSkeletonContainer, navigationBar!!)
            toCenterX(headerSkeletonContainer, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }

        headerSkeletonContainer.setConstraints {
            toEnd(headerIconSkeletonView, 12f)
            toCenterY(headerIconSkeletonView)

            toStart(walletNameSkeletonView, 16f)
            toTop(walletNameSkeletonView, 14.5f)
            toStart(walletBalanceSkeletonView, 16f)
            toBottom(walletBalanceSkeletonView, 14.5f)

            toTop(dappNameSkeletonView, 14.5f)
            endToStart(dappNameSkeletonView, headerIconSkeletonView, 12f)
            toBottom(dappAddressSkeletonView, 14.5f)
            endToStart(dappAddressSkeletonView, headerIconSkeletonView, 12f)

            edgeToEdge(skeletonView, headerSkeletonContainer)
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
        if (insufficientTokens == symbols)
            return
        insufficientTokens = symbols
        errorLabel.text = symbols?.let {
            LocaleController.getStringWithKeyValues(
                "Not Enough %symbol%",
                listOf(Pair("%symbol%", it))
            )
        }
        errorLabel.visibility = if (symbols == null) View.GONE else View.VISIBLE
        confirmButtonView.isEnabled = symbols == null
        view.setConstraints {
            topToTop(
                bottomReversedCornerViewUpsideDown,
                if (symbols == null) cancelButtonView else errorLabel,
                -ViewConstants.GAP - ViewConstants.BLOCK_RADIUS
            )
        }
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
        initializeWithUpdate()
    }

    // True once the user tapped Confirm; prevents onDestroy from reporting `declined` after an accepted
    // request whose signing/MFA later failed (which would double-fire accepted + declined for one request).
    private var didAccept = false

    private val acceptedEventName: String
        get() = if (connectionType == ApiConnectionType.SIGN_DATA) "wallet-sign-data-accepted" else "wallet-transaction-accepted"

    private val declinedEventName: String
        get() = if (connectionType == ApiConnectionType.SIGN_DATA) "wallet-sign-data-declined" else "wallet-transaction-declined"

    private fun showNotResponding() {
        val url = returnUrl
        showAlert(
            title = LocaleController.getString("Dapp Not Responding"),
            text = LocaleController.getString("You may need to reconnect your wallet from the dapp if this keeps happening."),
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
            secondaryButton = if (url != null) LocaleController.getString("Cancel") else null,
        )
    }

    private fun showSkeleton() {
        if (isShowingSkeleton) return
        isShowingSkeleton = true

        recyclerView.visibility = View.INVISIBLE
        confirmButtonView.isEnabled = false

        headerSkeletonContainer.visibility = View.VISIBLE
        headerIconSkeletonView.visibility = View.VISIBLE
        walletNameSkeletonView.visibility = View.VISIBLE
        walletBalanceSkeletonView.visibility = View.VISIBLE
        dappNameSkeletonView.visibility = View.VISIBLE
        dappAddressSkeletonView.visibility = View.VISIBLE

        headerIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
        walletNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
        walletBalanceSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 8f.dp)
        dappNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
        dappAddressSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 8f.dp)

        val skeletonViews = listOf(
            headerIconSkeletonView,
            walletNameSkeletonView,
            walletBalanceSkeletonView,
            dappNameSkeletonView,
            dappAddressSkeletonView
        )
        val radiusMap = hashMapOf(
            0 to 12f,
            1 to 12f,
            2 to 8f,
            3 to 12f,
            4 to 8f
        )
        skeletonView.doOnLayout {
            skeletonView.applyMask(skeletonViews, radiusMap)
            skeletonView.startAnimating()
        }
    }

    private fun hideSkeleton() {
        if (!isShowingSkeleton) return
        isShowingSkeleton = false

        skeletonView.stopAnimating()

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
                    if (update is ApiUpdate.ApiUpdateDappSignData) {
                        navigationController?.push(SignedVC(context), onCompletion = {
                            navigationController?.removePrevViewControllers()
                        })
                    } else {
                        navigationController?.window?.dismissLastNav()
                    }
                } else
                    navigationController?.pop(true, onCompletion = {
                        showError(event.err)
                    })
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
                val mfaVC = org.mytonwallet.app_air.uicomponents.viewControllers
                    .MfaActionConfirmVC(
                        context,
                        requestHash = event.requestHash,
                        onConfirmed = { _ ->
                            WalletCore.scope.launch {
                                try {
                                    WalletCore.call(
                                        ApiMethod.DApp.ConfirmDappRequestSendTransactionMfa(
                                            promiseId,
                                            event.requestHash,
                                        )
                                    )
                                } catch (t: Throwable) {
                                    Logger.e(
                                        Logger.LogTag.SEND,
                                        "confirmDappRequestSendTransaction MFA failed " +
                                            "for promiseId=$promiseId: $t",
                                    )
                                }
                            }
                        },
                    )
                navigationController?.push(mfaVC, onCompletion = {
                    navigationController?.removePrevViewControllerOnly()
                })
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        notRespondingHandler.removeCallbacksAndMessages(null)
        update?.let {
            if (viewModel?.isConfirmed != true && !didAccept) {
                WalletCore.recordTonConnectEvent(declinedEventName, it.promiseId)
            }
            viewModel?.cancel(it.promiseId, null, window!!.lifecycleScope)
        }
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)

        if (isShowingSkeleton) {
            headerSkeletonContainer.setBackgroundColor(
                WColor.Background.color,
                ViewConstants.TOOLBAR_RADIUS.dp,
                ViewConstants.BLOCK_RADIUS.dp
            )
            headerIconSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
            walletNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
            walletBalanceSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 8f.dp)
            dappNameSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
            dappAddressSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 8f.dp)
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
        val ime = (navigationController?.imeInsetBottom ?: 0)
        val nav = (navigationController?.getSystemBars()?.bottom ?: 0)

        recyclerView.setPaddingRelative(
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarStartInset,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp + systemBarEndInset,
            0
        )

        val errorExtra = if (errorLabel.isVisible) 26.dp else 0
        view.setConstraints {
            toBottomPx(recyclerView, 90.dp + errorExtra + max(ime, nav))
            toBottomPx(cancelButtonView, 20.dp + max(ime, nav))
            toBottomPx(confirmButtonView, 20.dp + max(ime, nav))
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
                }),
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
            ), task = { passcode ->
                viewModel?.accept(updateValue.promiseId, passcode)
            })
        push(confirmActionVC)
    }

    private val confirmHeaderView: View
        get() {
            return PasscodeHeaderSendView(
                WeakReference(this),
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
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

    override fun getChildViewMap(): HashMap<View, Float> {
        return hashMapOf(
            headerIconSkeletonView to 12f,
            walletNameSkeletonView to 12f,
            walletBalanceSkeletonView to 8f,
            dappNameSkeletonView to 12f,
            dappAddressSkeletonView to 8f
        )
    }
}
