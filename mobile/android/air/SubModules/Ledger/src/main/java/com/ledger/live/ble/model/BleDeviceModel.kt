package com.ledger.live.ble.model

data class BleDeviceModel(
    val id: String,
    val name: String,
    val serviceId: String? = null,
    val rssi: Int = 0,
    val device: BleDevice,
) {
    val timestamp: Long = System.currentTimeMillis()
}

