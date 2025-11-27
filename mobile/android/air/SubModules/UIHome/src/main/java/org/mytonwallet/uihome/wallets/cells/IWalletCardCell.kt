package org.mytonwallet.uihome.wallets.cells

interface IWalletCardCell {
    var isShowingPopup: Boolean
    fun notifyBalanceChange()
}
