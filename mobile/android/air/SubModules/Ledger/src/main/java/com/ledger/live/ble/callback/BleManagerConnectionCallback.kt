package com.ledger.live.ble.callback

import com.ledger.live.ble.model.BleDeviceModel
import com.ledger.live.ble.model.BleError

interface BleManagerConnectionCallback {
    fun onConnectionSuccess(device: BleDeviceModel)
    fun onConnectionError(error: BleError)
}
