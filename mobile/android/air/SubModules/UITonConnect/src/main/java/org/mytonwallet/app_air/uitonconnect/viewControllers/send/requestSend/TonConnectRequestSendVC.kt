package org.mytonwallet.app_air.uitonconnect.viewControllers.send.requestSend

import android.annotation.SuppressLint
import android.content.Context
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
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WBaseView
import org.mytonwallet.app_air.uicomponents.widgets.WButton
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
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.moshi.ApiConnectionType
import org.mytonwallet.app_air.walletcore.moshi.api.ApiUpdate
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import java.lang.ref.WeakReference
import kotlin.math.max
import kotlin.math.roundToInt

@SuppressLint("ViewConstructor")
class TonConnectRequestSendVC(
    context: Context,
    private val connectionType: ApiConnectionType,
    private var update: ApiUpdate.ApiUpdateDappSignRequest? = null
) : WViewControllerWithModelStore(context), CustomListAdapter.ItemClickListener, SkeletonContainer {
    override val TAG = "TonConnectRequestSend"

    override val shouldDisplayTopBar = true

    private var viewModel: TonConnectRequestSendViewModel? = null

    private val skeletonView = SkeletonView(context)
    private var isShowingSkeleton = false

    private val headerImageSkeletonView = WBaseView(context).apply {
        visibility = View.GONE
    }
    private val headerTitleSkeletonView = WBaseView(context).apply {
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

            title = when (connectionType) {
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
        view.addView(
            headerSkeletonContainer, ViewGroup.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
        )
        headerSkeletonContainer.addView(
            headerImageSkeletonView, ViewGroup.LayoutParams(
                80.dp,
                80.dp
            )
        )
        headerSkeletonContainer.addView(
            headerTitleSkeletonView, ViewGroup.LayoutParams(
                220.dp,
                26.dp
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

            topToBottom(headerSkeletonContainer, navigationBar!!)
            toCenterX(headerSkeletonContainer, ViewConstants.HORIZONTAL_PADDINGS.toFloat())
        }

        headerSkeletonContainer.setConstraints {
            toCenterX(headerImageSkeletonView)
            toTop(headerImageSkeletonView, 14f)

            topToBottom(headerTitleSkeletonView, headerImageSkeletonView, 17f)
            toCenterX(headerTitleSkeletonView)
            toBottom(headerTitleSkeletonView, 12f)

            edgeToEdge(skeletonView, headerSkeletonContainer)
        }

        cancelButtonView.setOnClickListener {
            update?.let {
                viewModel?.cancel(it.promiseId, null)
            }
        }

        confirmButtonView.setOnClickListener {
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

        confirmButtonView.isEnabled = true
    }

    fun setUpdate(newUpdate: ApiUpdate.ApiUpdateDappSignRequest) {
        this.update = newUpdate
        initializeWithUpdate()
    }

    private fun showSkeleton() {
        if (isShowingSkeleton) return
        isShowingSkeleton = true

        recyclerView.visibility = View.INVISIBLE
        confirmButtonView.isEnabled = false

        headerSkeletonContainer.visibility = View.VISIBLE
        headerImageSkeletonView.visibility = View.VISIBLE
        headerTitleSkeletonView.visibility = View.VISIBLE

        headerImageSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 20f.dp)
        headerTitleSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)

        val skeletonViews = listOf(headerImageSkeletonView, headerTitleSkeletonView)
        val radiusMap = hashMapOf(0 to 20f, 1 to 12f)
        skeletonView.doOnLayout {
            skeletonView.applyMask(skeletonViews, radiusMap)
            skeletonView.startAnimating()
        }
    }

    private fun hideSkeleton() {
        if (!isShowingSkeleton) return
        isShowingSkeleton = false

        skeletonView.stopAnimating()

        headerImageSkeletonView.fadeOut(onCompletion = {
            headerImageSkeletonView.visibility = View.GONE
        })
        headerTitleSkeletonView.fadeOut(onCompletion = {
            headerTitleSkeletonView.visibility = View.GONE
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
                activeDialog?.dismiss()
                window?.dismissLastNav(onCompletion = {
                    WalletCore.notifyEvent(WalletEvent.OpenUrl(event.url))
                })
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()

        update?.let {
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
            headerImageSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 20f.dp)
            headerTitleSkeletonView.setBackgroundColor(WColor.SecondaryBackground.color, 12f.dp)
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
            headerImageSkeletonView to 20f,
            headerTitleSkeletonView to 12f
        )
    }
}
