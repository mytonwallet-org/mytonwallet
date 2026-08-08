package org.mytonwallet.app_air.sqscan.screen

interface QrScannerListener {
    fun onQrScanValidate(qrCode: String): Boolean = true

    fun onQrScanComplete(qrCode: String)
    fun onQrScanCancel() {}
}
