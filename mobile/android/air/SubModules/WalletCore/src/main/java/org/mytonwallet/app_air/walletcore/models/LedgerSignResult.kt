package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletcore.moshi.MApiSignedTransfer

data class LedgerSignResult(val signedTransfer: MApiSignedTransfer, val pendingTransferId: String)
