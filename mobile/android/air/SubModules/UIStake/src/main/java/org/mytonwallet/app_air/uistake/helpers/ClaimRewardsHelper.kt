package org.mytonwallet.app_air.uistake.helpers

import android.content.Context
import android.content.res.ColorStateList
import android.view.View
import android.widget.ProgressBar
import androidx.constraintlayout.widget.ConstraintLayout
import java.math.BigInteger
import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uicomponents.extensions.dp
import org.mytonwallet.app_air.uipasscode.ProtectedActionAuth
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uistake.confirm.ConfirmStakingHeaderView
import org.mytonwallet.app_air.uistake.util.getTonStakingFees
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletbasecontext.theme.WColor
import org.mytonwallet.app_air.walletbasecontext.theme.color
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore

private class ClaimProgressVC(context: Context) : WViewController(context) {
    @Suppress("PropertyName")
    override val TAG = "ClaimProgress"
    override val isBackAllowed = false
    override val isSwipeBackAllowed = false
    override val shouldDisplayBottomBar = false

    override fun setupViews() {
        super.setupViews()
        view.setBackgroundColor(WColor.SecondaryBackground.color)
        val indicator = ProgressBar(context).apply {
            id = View.generateViewId()
            indeterminateTintList = ColorStateList.valueOf(WColor.Tint.color)
            contentDescription = LocaleController.getString("Claim Rewards")
        }
        view.addView(indicator, ConstraintLayout.LayoutParams(40.dp, 40.dp))
        view.setConstraints {
            toCenterX(indicator)
            toCenterY(indicator)
        }
        view.isEnabled = false
    }
}

object ClaimRewardsHelper {
    fun canClaimRewards(stakingState: StakingState?): Boolean = when (stakingState) {
        is StakingState.Jetton -> stakingState.unclaimedRewards > BigInteger.ZERO
        is StakingState.Ethena -> stakingState.isUnstakeRequestAmountUnlocked
        else -> false
    }

    fun presentClaimRewards(
        viewController: WViewController,
        tokenSlug: String,
        stakingState: StakingState,
        amountToClaim: BigInteger?,
        onClaimed: (() -> Unit)? = null,
        onError: ((MBridgeError?) -> Unit)? = null
    ) {
        val window = viewController.window ?: return
        val token = TokenStore.getToken(tokenSlug) ?: return
        val amount = amountToClaim ?: BigInteger.ZERO
        if (amount <= BigInteger.ZERO) {
            return
        }

        val confirmHeaderView = ConfirmStakingHeaderView(viewController.context).apply {
            config(
                token = token,
                amountInCrypto = amount,
                showPositiveSignForAmount = true,
                messageString = LocaleController.getString(
                    if (stakingState is StakingState.Ethena) {
                        "Confirm Unstaking"
                    } else {
                        "Confirm Rewards Claim"
                    }
                )
            )
        }

        Logger.d(Logger.LogTag.STAKING, "claimRewards: tokenSlug=$tokenSlug")
        if (AccountStore.activeAccount?.isHardware == true) {
            presentHardwareClaimRewards(
                viewController = viewController,
                window = window,
                stakingState = stakingState,
                confirmHeaderView = confirmHeaderView
            )
        } else {
            presentPasscodeClaimRewards(
                viewController = viewController,
                window = window,
                tokenSlug = tokenSlug,
                stakingState = stakingState,
                confirmHeaderView = confirmHeaderView,
                onClaimed = onClaimed,
                onError = onError
            )
        }
    }

    private fun presentHardwareClaimRewards(
        viewController: WViewController,
        window: WWindow,
        stakingState: StakingState,
        confirmHeaderView: ConfirmStakingHeaderView
    ) {
        val account = AccountStore.activeAccount ?: return
        val address = account.tonAddress ?: return
        val fee = getTonStakingFees(stakingState.stakingType)["claim"]?.real ?: return
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        val ledgerConnectVC = LedgerConnectVC(
            viewController.context,
            LedgerConnectVC.Mode.ConnectToSubmitTransfer(
                address = address,
                signData = LedgerConnectVC.SignData.ClaimRewards(
                    accountId = account.accountId,
                    stakingState = stakingState,
                    realFee = fee
                )
            ) {},
            headerView = confirmHeaderView
        )
        nav.setRoot(ledgerConnectVC)
        window.present(nav)
    }

    private fun presentPasscodeClaimRewards(
        viewController: WViewController,
        window: WWindow,
        tokenSlug: String,
        stakingState: StakingState,
        confirmHeaderView: ConfirmStakingHeaderView,
        onClaimed: (() -> Unit)?,
        onError: ((MBridgeError?) -> Unit)?
    ) {
        ProtectedActionAuth.confirm(
            onConfirmed = { token ->
                if (viewController.isDestroyed || window.topViewController is ClaimProgressVC) {
                    return@confirm
                }
                val nav = WNavigationController(
                    window,
                    WNavigationController.PresentationConfig.PreferredFullScreen
                )
                nav.setRoot(ClaimProgressVC(viewController.context))
                window.present(nav, animated = false)
                submitClaimRewards(
                    window,
                    nav,
                    viewController.navigationController,
                    tokenSlug,
                    stakingState,
                    token,
                    onClaimed,
                    onError
                )
            },
            onPasscodeRequired = {
                showPasscodeClaimRewards(
                    viewController,
                    window,
                    tokenSlug,
                    stakingState,
                    confirmHeaderView,
                    onClaimed,
                    onError
                )
            }
        )
    }

    private fun showPasscodeClaimRewards(
        viewController: WViewController,
        window: WWindow,
        tokenSlug: String,
        stakingState: StakingState,
        confirmHeaderView: ConfirmStakingHeaderView,
        onClaimed: (() -> Unit)?,
        onError: ((MBridgeError?) -> Unit)?
    ) {
        val nav = WNavigationController(
            window,
            WNavigationController.PresentationConfig.PreferredFullScreen
        )
        val passcodeConfirmVC = PasscodeConfirmVC(
            context = viewController.context,
            passcodeViewState = PasscodeViewState.CustomHeader(
                headerView = confirmHeaderView,
                navbarTitle = LocaleController.getString("Confirm")
            ),
            task = { enclaveToken ->
                submitClaimRewards(
                    window = window,
                    claimNav = nav,
                    parentNav = viewController.navigationController,
                    tokenSlug = tokenSlug,
                    stakingState = stakingState,
                    enclaveToken = enclaveToken,
                    onClaimed = onClaimed,
                    onError = onError
                )
            }
        )
        nav.setRoot(passcodeConfirmVC)
        window.present(nav)
    }

    private fun submitClaimRewards(
        window: WWindow,
        claimNav: WNavigationController,
        parentNav: WNavigationController?,
        tokenSlug: String,
        stakingState: StakingState,
        enclaveToken: String,
        onClaimed: (() -> Unit)?,
        onError: ((MBridgeError?) -> Unit)?
    ) {
        val activeAccountId = AccountStore.activeAccountId ?: run {
            dismissClaimNav(window, claimNav) { onError?.invoke(null) }
            return
        }
        val fee = getTonStakingFees(stakingState.stakingType)["claim"]?.real ?: run {
            dismissClaimNav(window, claimNav) { onError?.invoke(null) }
            return
        }
        WalletCore.call(
            ApiMethod.Staking.SubmitStakingClaimOrUnlock(
                accountId = activeAccountId,
                state = stakingState,
                realFee = fee,
                enclaveToken = enclaveToken
            )
        ) { result, err ->
            logClaimResult(tokenSlug, err)
            if (err == null && result == null) {
                dismissClaimNav(window, claimNav) { onError?.invoke(null) }
                return@call
            }
            if (result?.error != null) {
                val error =
                    MBridgeError.fromErrorName(result.error) ?: MBridgeError.Type.UNEXPECTED_ERROR
                dismissClaimNav(window, claimNav) { onError?.invoke(error) }
                return@call
            }
            val mfaHash = result?.mfaRequestHash
            if (err == null && mfaHash != null) {
                val presentMfa = {
                    val mfaVC = org.mytonwallet.app_air.uicomponents.viewControllers
                        .MfaActionConfirmVC(window.applicationContext, requestHash = mfaHash)
                    val mfaNav = WNavigationController(
                        window,
                        WNavigationController.PresentationConfig.PreferredFullScreen
                    )
                    mfaNav.setRoot(mfaVC)
                    window.present(mfaNav)
                }
                dismissClaimNav(window, claimNav, presentMfa)
                return@call
            }
            if (err == null && result?.activityId.isNullOrBlank()) {
                dismissClaimNav(window, claimNav) {
                    onError?.invoke(MBridgeError.Type.UNEXPECTED_ERROR)
                }
                return@call
            }
            if (stakingState is StakingState.Ethena) {
                if (err == null) {
                    dismissClaimNav(window, claimNav) { window.dismissNav(parentNav) }
                    onClaimed?.invoke()
                } else {
                    dismissClaimNav(window, claimNav) { onError?.invoke(err.parsed) }
                }
            } else {
                val finish = {
                    err?.let {
                        onError?.invoke(err.parsed)
                    } ?: onClaimed?.invoke()
                    Unit
                }
                dismissClaimNav(window, claimNav, finish)
            }
        }
    }

    private fun dismissClaimNav(
        window: WWindow,
        claimNav: WNavigationController,
        onCompletion: () -> Unit
    ) {
        if (claimNav !in window.navigationControllers) return
        if (window.navigationControllers.lastOrNull() === claimNav) {
            window.dismissLastNav(onCompletion = onCompletion)
        } else {
            window.dismissNav(claimNav, animated = false)
            onCompletion()
        }
    }

    private fun logClaimResult(tokenSlug: String, err: JSWebViewBridge.ApiError?) {
        if (err != null) {
            Logger.d(
                Logger.LogTag.STAKING,
                "requestClaimRewards: Failed error=${err.parsed}"
            )
        } else {
            Logger.d(
                Logger.LogTag.STAKING,
                "requestClaimRewards: Success tokenSlug=$tokenSlug"
            )
        }
    }
}
