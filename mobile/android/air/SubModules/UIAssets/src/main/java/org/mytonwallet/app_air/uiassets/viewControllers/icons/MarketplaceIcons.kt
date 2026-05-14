package org.mytonwallet.app_air.uiassets.viewControllers.icons

import org.mytonwallet.app_air.uiassets.R
import org.mytonwallet.app_air.walletcore.models.MMarketplace

val MMarketplace.menuIconRes: Int?
    get() = when (this) {
        MMarketplace.Fragment -> R.drawable.ic_fragment
        MMarketplace.Getgems -> R.drawable.ic_getgems
        else -> null
    }
