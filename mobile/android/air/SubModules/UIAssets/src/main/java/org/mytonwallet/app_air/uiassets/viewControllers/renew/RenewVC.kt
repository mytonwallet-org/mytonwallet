package org.mytonwallet.app_air.uiassets.viewControllers.renew

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import androidx.constraintlayout.widget.ConstraintLayout
import androidx.constraintlayout.widget.ConstraintLayout.LayoutParams.MATCH_CONSTRAINT
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.commonViews.cells.activity.ActivitySingleTagView
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uicomponents.helpers.WFont
import org.mytonwallet.app_air.uicomponents.image.Content
import org.mytonwallet.app_air.uicomponents.widgets.WButton
import org.mytonwallet.app_air.uicomponents.widgets.WLabel
import org.mytonwallet.app_air.uicomponents.widgets.fadeIn
import org.mytonwallet.app_air.uicomponents.widgets.lockView
import org.mytonwallet.app_air.uicomponents.widgets.passcode.headers.PasscodeHeaderSendView
import org.mytonwallet.app_air.uicomponents.widgets.setBackgroundColor
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.views.PasscodeScreenView
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.theme.ViewConstants
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletbasecontext.utils.formatDateAndTime
import org.mytonwallet.app_air.walletbasecontext.utils.smartDecimalsCount
import org.mytonwallet.app_air.walletbasecontext.utils.toString
import org.mytonwallet.app_air.walletcore.TONCOIN_SLUG
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.moshi.ApiNft
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.BalanceStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.util.Date
import kotlin.math.roundToInt

class RenewVC(context: Context, val nft: ApiNft) : WViewController(context) {
    override val TAG = "Renew"

    override val displayedAccount =
        DisplayedAccount(AccountStore.activeAccountId, AccountStore.isPushedTemporary)

    override val shouldDisplayTopBar = false

    private var realFee = BigInteger.ZERO

    private val nftTagView = ActivitySingleTagView(context).apply {
        configure(nft)
    }

    private val feeLabel = WLabel(context).apply {
        setStyle(14f, WFont.Regular)
        setTextColor(WColor.SecondaryText)
    }

    private val renewButton = WButton(context).apply {
        text =
            LocaleController.getString("Renew")
        isLoading = true
        setOnClickListener {
            onRenewPressed()
        }
    }

    override fun setupViews() {
        super.setupViews()

        setNavTitle(LocaleController.getString("Renew Domain"))
        setNavSubtitle(
            LocaleController.getString("Until %date%").replace(
                "%date%",
                Date(System.currentTimeMillis() + 365L * 24 * 60 * 60 * 1000).formatDateAndTime()
            )
        )
        setupNavBar(true)

        navigationBar?.addCloseButton()

        view.addView(nftTagView, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        view.addView(feeLabel, FrameLayout.LayoutParams(WRAP_CONTENT, 21.dp))
        view.addView(renewButton, ConstraintLayout.LayoutParams(MATCH_CONSTRAINT, WRAP_CONTENT))
        view.setConstraints {
            topToBottom(nftTagView, navigationBar!!, 16f)
            toCenterX(nftTagView, 16f)
            topToBottom(feeLabel, nftTagView, 16f)
            toCenterX(feeLabel)
            topToBottom(renewButton, feeLabel, 16f)
            toCenterX(renewButton, 16f)
            toBottom(renewButton, 8f)
        }

        calculateFee()

        updateTheme()
    }

    override fun insetsUpdated() {
        super.insetsUpdated()
        view.setPadding(0, 0, 0, navigationController?.getSystemBars()?.bottom ?: 0)
    }

    override fun updateTheme() {
        super.updateTheme()

        view.setBackgroundColor(WColor.SecondaryBackground.color, ViewConstants.BLOCK_RADIUS.dp, 0f)
        nftTagView.setBackgroundColor(
            WColor.Background.color,
            12f.dp
        )
    }

    @SuppressLint("SetTextI18n")
    private fun calculateFee() {
        val accountId = displayedAccount.accountId ?: return
        WalletCore.call(
            ApiMethod.Domains.CheckDnsRenewalDraft(
                accountId,
                listOf(nft)
            ), callback = { res, err ->
                if (isDestroyed)
                    return@call
                this.realFee = res?.realFee ?: BigInteger.ZERO
                if (err != null || realFee == null) {
                    Handler(Looper.getMainLooper()).postDelayed({
                        calculateFee()
                    }, 5000)
                    return@call
                }
                val accountId = AccountStore.activeAccountId ?: return@call
                if ((BalanceStore.getBalances(accountId)
                        ?.get(TONCOIN_SLUG) ?: BigInteger.ZERO) >= realFee
                ) {
                    renewButton.isEnabled = true
                    renewButton.isLoading = false
                    val tonToken = TokenStore.getToken(TONCOIN_SLUG) ?: return@call
                    feeLabel.text =
                        "${LocaleController.getString("Fee")}: ${
                            realFee.toString(
                                decimals = tonToken.decimals,
                                currency = tonToken.symbol,
                                currencyDecimals = realFee.smartDecimalsCount(tonToken.decimals),
                                showPositiveSign = false,
                                forceCurrencyToRight = true
                            )
                        }"
                    feeLabel.alpha = 0f
                    feeLabel.fadeIn()
                } else {
                    renewButton.isEnabled = false
                    renewButton.setText(LocaleController.getString("Insufficient Balance"))
                }
            })
    }

    private fun onRenewPressed() {
        if (AccountStore.activeAccount?.isHardware == true) {
            renewWithHardware()
        } else {
            renewWithPassword()
        }
    }

    private val headerView: View
        get() {
            return PasscodeHeaderSendView(
                WeakReference(this),
                (window!!.windowView.height * PasscodeScreenView.TOP_HEADER_MAX_HEIGHT_RATIO).roundToInt()
            ).apply {
                config(
                    Content.ofUrl(nft.image ?: ""),
                    LocaleController.getString("Confirm Renewing"),
                    nft.name ?: "",
                    Content.Rounding.Radius(12f.dp)
                )
            }
        }

    private fun renewWithHardware() {
        renewButton.lockView()
        val account = AccountStore.activeAccount!!
        val ledgerConnectVC = LedgerConnectVC(
            context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                account.tonAddress!!,
                signData = LedgerConnectVC.SignData.RenewNfts(
                    accountId = account.accountId,
                    nfts = listOf(nft),
                    realFee = realFee
                ),
                onDone = {
                    window?.dismissLastNav {
                        window?.dismissLastNav { }
                    }
                }),
            headerView = headerView
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(ledgerConnectVC)
        window?.present(nav)
    }

    private fun renewWithPassword() {
        val passcodeConfirmVC = PasscodeConfirmVC(
            context,
            PasscodeViewState.CustomHeader(
                headerView,
                LocaleController.getString("Confirm Renewing")
            ),
            task = { passcode ->
                WalletCore.call(
                    ApiMethod.Domains.SubmitDnsRenewal(
                        AccountStore.activeAccountId!!,
                        passcode,
                        listOf(nft),
                        realFee
                    ), callback = { res, err ->
                        if (err != null) {
                            showError(err.parsed)
                            return@call
                        }
                        window?.dismissLastNav {
                            window?.dismissLastNav { }
                        }
                    })
            }
        )
        val nav = WNavigationController(window!!)
        nav.setRoot(passcodeConfirmVC)
        window?.present(nav)
    }
}
