package org.mytonwallet.app_air.walletcontext.models;

interface ICollectionTab {
    val chain: String
    val address: String
}

data class MCollectionTab(override val chain: String, override val address: String) :
    ICollectionTab
