package org.mytonwallet.app_air.uicreatewallet.viewControllers.wordDisplay

import android.annotation.SuppressLint
import android.content.Context
import org.mytonwallet.app_air.uicreatewallet.WalletCreationVM
import org.mytonwallet.app_air.uicreatewallet.viewControllers.walletAdded.WalletAddedVC
import org.mytonwallet.app_air.uipasscode.viewControllers.setPasscode.SetPasscodeVC
import org.mytonwallet.app_air.uisettings.viewControllers.RecoveryPhraseVC
import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController
import org.mytonwallet.app_air.walletcontext.helpers.WordCheckMode
import org.mytonwallet.app_air.walletcontext.models.MBlockchainNetwork
import org.mytonwallet.app_air.walletcore.WalletCore
import org.mytonwallet.app_air.walletcore.WalletEvent
import org.mytonwallet.app_air.walletcore.models.MAccount
import org.mytonwallet.app_air.walletcore.models.MBridgeError

@SuppressLint("ViewConstructor")
class WordDisplayVC(
    context: Context,
    private val network: MBlockchainNetwork,
    private val words: Array<String>,
    private val isFirstWalletToAdd: Boolean,
    private val isFirstPasscodeProtectedWallet: Boolean,
    // Used when adding new account (not first account!)
    private val passedPasscode: String?
) : RecoveryPhraseVC(context, network, words), WalletCreationVM.Delegate {

    override val shouldDisplayTopBar = false
    override val isBackAllowed = isFirstWalletToAdd

    override val skipTitle = LocaleController.getString("Open wallet without checking")
    override val checkMode =
        WordCheckMode.CheckAndImport(
            isFirstWalletToAdd = isFirstWalletToAdd,
            isFirstPasscodeProtectedWallet = isFirstPasscodeProtectedWallet,
            passedPasscode = passedPasscode
        )

    private val walletCreationVM by lazy {
        WalletCreationVM(this)
    }

    override fun setupViews() {
        super.setupViews()

        if (!isFirstWalletToAdd)
            navigationBar?.addCloseButton()
    }

    override fun skipPressed() {
        if (isFirstPasscodeProtectedWallet) {
            push(SetPasscodeVC(context, true, null) { passcode, biometricsActivated ->
                walletCreationVM.finalizeAccount(window!!, network, words, passcode, biometricsActivated, 0)
            }, onCompletion = {
                navigationController?.removePrevViewControllers()
            })
        } else {
            skipButton.isLoading = true
            view.lockView()
            walletCreationVM.finalizeAccount(window!!, network, words, passedPasscode ?: "", null, 0)
        }
    }

    override fun showError(error: MBridgeError?) {
        super.showError(error)

        skipButton.isLoading = false
        view.unlockView()
    }

    override fun finalizedCreation(createdAccount: MAccount) {
        if (isFirstWalletToAdd) {
            push(WalletAddedVC(context, true), {
                navigationController?.removePrevViewControllers()
            })
        } else {
            WalletCore.notifyEvent(WalletEvent.AddNewWalletCompletion)
            window!!.dismissLastNav()
        }
    }
}
