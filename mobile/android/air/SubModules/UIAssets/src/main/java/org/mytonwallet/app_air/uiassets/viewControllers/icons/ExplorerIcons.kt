package org.mytonwallet.app_air.uiassets.viewControllers.icons

import org.mytonwallet.app_air.icons.R
import org.mytonwallet.app_air.walletcore.models.blockchain.MBlockchainExplorer

val MBlockchainExplorer.menuIconRes: Int?
    get() = when (this) {
        MBlockchainExplorer.TONSCAN -> R.drawable.ic_tonscan
        else -> null
    }
