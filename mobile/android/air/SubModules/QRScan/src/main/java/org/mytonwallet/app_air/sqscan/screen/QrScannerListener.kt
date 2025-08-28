package org.mytonwallet.app_air.sqscan.screen

interface QrScannerListener {
    fun onQrScanValidate(qrCode: String): Boolean {
        return true
    }

    fun onQrScanComplete(qrCode: String)
    fun onQrScanCancel() {}
}
