package org.mytonwallet.app_air.ledger

import com.ledger.live.ble.model.BleDeviceModel
import org.mytonwallet.app_air.ledger.usb.HIDDevice

sealed class LedgerDevice {
    data class Ble(val bleDevice: BleDeviceModel) : LedgerDevice()
    data class Usb(val hidDevice: HIDDevice) : LedgerDevice()

    val id: String
        get() {
            return when (this) {
                is Ble -> this.bleDevice.id
                is Usb -> this.hidDevice.deviceId.toString()
            }
        }

    val name: String
        get() {
            return when (this) {
                is Ble -> this.bleDevice.name
                is Usb -> this.hidDevice.deviceName
            }
        }
}
