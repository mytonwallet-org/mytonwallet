package org.mytonwallet.app_air.uiassets.models

import org.mytonwallet.app_air.walletcore.moshi.ApiNft

data class ExpiringDomainsData(
    val domainNfts: List<ApiNft>,
    val count: Int,
    val minDays: Int,
)
