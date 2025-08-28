package org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend

import android.annotation.SuppressLint
import android.content.Context
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
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
import org.mytonwallet.app_air.uicomponents.extensions.collectFlow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.uitonconnect.viewControllers.TonConnectRequestSendViewModel
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.adapter.Adapter
import org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSendDetails.TonConnectRequestSendDetailsVC
import org.mytonwallet.app_air.walletcontext.helpers.LocaleController
import org.mytonwallet.app_air.walletcontext.theme.ViewConstants
import org.mytonwallet.app_air.walletcontext.theme.WColor
import org.mytonwallet.app_air.walletcontext.theme.color
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TonConnectRequestSendVC(
    context: Context,
    private val update: ApiUpdate.ApiUpdateDappSendTransactions
) : WViewControllerWithModelStore(context), CustomListAdapter.ItemClickListener {

    override val shouldDisplayTopBar = true

    private val viewModel by lazy {
        ViewModelProvider(
            this,
            TonConnectRequestSendViewModel.Factory(update)
        )[TonConnectRequestSendViewModel::class.java]
    }

    private val confirmButtonView: WButton = WButton(context, WButton.Type.PRIMARY).apply {
        layoutParams = ViewGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT)
        text = LocaleController.getString("Confirm")
    }
    private val cancelButtonView: WButton =
        WButton(context, WButton.Type.Secondary(withBackground = true)).apply {
            layoutParams = ViewGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT)
            text = LocaleController.getString("Cancel")
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

    override fun setupViews() {
        super.setupViews()
        title = LocaleController.getString(
            LocaleController.getPluralWord(
                update.transactions.size,
                "Confirm Actions"
            )
        )

        rvAdapter.setOnItemClickListener(this)

        setupNavBar(true)
        navigationBar?.addCloseButton()
        navigationBar?.setTitleGravity(Gravity.CENTER)
        recyclerView.setPadding(
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            (navigationController?.getSystemBars()?.top ?: 0) +
                WNavigationBar.Companion.DEFAULT_HEIGHT.dp,
            ViewConstants.HORIZONTAL_PADDINGS.dp,
            0
        )

        view.addView(
            recyclerView, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        view.addView(cancelButtonView)
        view.addView(confirmButtonView)

        view.setConstraints {
            toLeft(cancelButtonView, 20f)
            toRight(confirmButtonView, 20f)

            leftToRight(confirmButtonView, cancelButtonView, 6f)
            rightToLeft(cancelButtonView, confirmButtonView, 6f)
        }

        cancelButtonView.setOnClickListener {
            viewModel.cancel(update.promiseId, null)
        }

        confirmButtonView.setOnClickListener {
            if (AccountStore.activeAccount?.isHardware == true) {
                confirmHardware()
            } else {
                confirmPasscode()
            }
        }

        collectFlow(viewModel.eventsFlow, ::onEvent)
        collectFlow(viewModel.uiItemsFlow, rvAdapter::submitList)
        collectFlow(viewModel.uiStateFlow) {
            cancelButtonView.isLoading = it.cancelButtonIsLoading
        }

        updateTheme()
        insetsUpdated()
    }

    private fun onEvent(event: TonConnectRequestSendViewModel.Event) {
        when (event) {
            is TonConnectRequestSendViewModel.Event.Close -> pop()
            is TonConnectRequestSendViewModel.Event.Complete -> {
                if (event.success)
                    navigationController?.window?.dismissLastNav()
                else
                    navigationController?.pop(true, onCompletion = {
                        showError(event.err)
                    })
            }

            is TonConnectRequestSendViewModel.Event.ShowWarningAlert -> {
                showAlert(event.title, event.text, allowLinkInText = event.allowLinkInText)
            }

            is TonConnectRequestSendViewModel.Event.OpenDappInBrowser -> {
                window?.dismissLastNav(onCompletion = {
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(event.url))
                })
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        viewModel.cancel(update.promiseId, null, window!!.lifecycleScope)
    }

    override fun updateTheme() {
        super.updateTheme()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
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
        val ime = (window?.imeInsets?.bottom ?: 0)
        val nav = (navigationController?.getSystemBars()?.bottom ?: 0)

        view.setConstraints {
            toBottomPx(recyclerView, 90.dp + max(ime, nav))
            toBottomPx(cancelButtonView, 20.dp + max(ime, nav))
            toBottomPx(confirmButtonView, 20.dp + max(ime, nav))
        }
    }

    private fun confirmHardware() {
        val account = AccountStore.activeAccount!!
        val ledger = account.ledger ?: return
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                ledger.index,
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.SignDappTransfers(update),
                onDone = {
                    viewModel.notifyDone(true, null)
                }),
            headerView = confirmHeaderView
        )
        navigationController?.push(ledgerConnectVC)
    }

    private fun confirmPasscode() {
        val confirmActionVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                confirmHeaderView,
                showNavbarTitle = false
            ), task = { passcode ->
                viewModel.accept(update.promiseId, passcode)
            })
        push(confirmActionVC)
    }

    private val confirmHeaderView: View
        get() {
            return PasscodeHeaderSendView(
                context,
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content.ofUrl(update.dapp.iconUrl ?: ""),
                    title ?: "",
                    update.dapp.host ?: "",
                    Content.Rounding.Radius(12f.dp)
                )
                setSubtitleColor(WColor.Tint)
            }
        }
}
