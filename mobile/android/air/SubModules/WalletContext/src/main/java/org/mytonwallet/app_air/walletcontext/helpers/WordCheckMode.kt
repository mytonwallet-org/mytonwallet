package org.mytonwallet.app_air.walletcontext.helpers

sealed class WordCheckMode {
    data object Check : WordCheckMode()
    data class CheckAndImport(
        val isFirstWalletToAdd: Boolean,
        val isFirstPasscodeProtectedWallet: Boolean,
        // Used when adding new account (not first account!)
        var passedPasscode: String?
    ) : WordCheckMode()
}
