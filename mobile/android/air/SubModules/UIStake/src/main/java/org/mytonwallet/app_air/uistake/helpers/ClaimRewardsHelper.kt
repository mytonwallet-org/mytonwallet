package org.mytonwallet.app_air.uistake.helpers

import org.mytonwallet.app_air.ledger.screens.ledgerConnect.LedgerConnectVC
import org.mytonwallet.app_air.uicomponents.base.WNavigationController
import org.mytonwallet.app_air.uicomponents.base.WViewController
import org.mytonwallet.app_air.uicomponents.base.WWindow
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeConfirmVC
import org.mytonwallet.app_air.uipasscode.viewControllers.passcodeConfirm.PasscodeViewState
import org.mytonwallet.app_air.uistake.confirm.ConfirmStakingHeaderView
import org.mytonwallet.app_air.uistake.util.getTonStakingFees
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import org.mytonwallet.app_air.walletcore.JSWebViewBridge
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.models.MBridgeError
import org.mytonwallet.app_air.walletcore.moshi.StakingState
import org.mytonwallet.app_air.walletcore.moshi.api.ApiMethod
import org.mytonwallet.app_air.walletcore.stores.AccountStore
import org.mytonwallet.app_air.walletcore.stores.TokenStore
import java.math.BigInteger

object ClaimRewardsHelper {
    fun canClaimRewards(stakingState: StakingState?): Boolean {
        return when (stakingState) {
            is StakingState.Jetton -> stakingState.unclaimedRewards > BigInteger.ZERO
            is StakingState.Ethena -> stakingState.isUnstakeRequestAmountUnlocked
            else -> false
        }
    }

    fun presentClaimRewards(
        viewController: WViewController,
        tokenSlug: String,
        stakingState: StakingState,
        amountToClaim: BigInteger?,
        onClaimed: (() -> Unit)? = null,
        onError: ((MBridgeError?) -> Unit)? = null,
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
        val nav = WNavigationController(window)
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
        val nav = WNavigationController(window)
        val passcodeConfirmVC = PasscodeConfirmVC(
            context = viewController.context,
            passcodeViewState = PasscodeViewState.CustomHeader(
                headerView = confirmHeaderView,
                navbarTitle = LocaleController.getString("Confirm")
            ),
            task = { passcode ->
                submitClaimRewards(
                    window = window,
                    tokenSlug = tokenSlug,
                    stakingState = stakingState,
                    passcode = passcode,
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
        tokenSlug: String,
        stakingState: StakingState,
        passcode: String,
        onClaimed: (() -> Unit)?,
        onError: ((MBridgeError?) -> Unit)?
    ) {
        val activeAccountId = AccountStore.activeAccountId ?: return
        val fee = getTonStakingFees(stakingState.stakingType)["claim"]?.real ?: return
        WalletCore.call(
            ApiMethod.Staking.SubmitStakingClaimOrUnlock(
                accountId = activeAccountId,
                password = passcode,
                state = stakingState,
                realFee = fee
            )
        ) { _, err ->
            logClaimResult(tokenSlug, err)
            if (stakingState is StakingState.Ethena) {
                window.dismissLastNav {
                    window.dismissLastNav()
                }
                if (err == null) {
                    onClaimed?.invoke()
                }
            } else {
                window.dismissLastNav()
                err?.let {
                    onError?.invoke(err.parsed)
                } ?: onClaimed?.invoke()
            }
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
