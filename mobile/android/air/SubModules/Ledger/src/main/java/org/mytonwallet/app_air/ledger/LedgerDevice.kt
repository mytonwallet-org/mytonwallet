package org.mytonwallet.app_air.ledger

import com.ledger.live.ble.model.BleDevice
import com.ledger.live.ble.model.BleDeviceModel
import org.mytonwallet.app_air.ledger.usb.HIDDevice

sealed class LedgerDevice {
    data class Ble(val bleDevice: BleDeviceModel) : LedgerDevice()
    data class Usb(val hidDevice: HIDDevice) : LedgerDevice()

    enum class Model(val value: String, vararg val aliases: String) {
        BLUE("blue"),
        NANO_S("nanoS", "nano s"),
        NANO_S_PLUS("nanoSP"),
        NANO_X("nanoX", "nano x"),
        STAX("stax"),
        EUROPA("europa", "flex");

        override fun toString(): String = value

        companion object {
            private val map: Map<String, Model> =
                entries.flatMap { model ->
                    (listOf(model.value) + model.aliases).map { alias ->
                        alias.lowercase() to model
                    }
                }.toMap()

            fun fromValue(value: String?): Model? =
                value?.lowercase()?.let { map[it] }
        }
    }

    val id: String
        get() {
            return when (this) {
                is Ble -> bleDevice.id
                is Usb -> hidDevice.deviceId.toString()
            }
        }

    val name: String
        get() {
            return when (this) {
                is Ble -> bleDevice.name
                is Usb -> hidDevice.deviceName
            }
        }

    val model: Model?
        get() {
            return when (this) {
                is Ble -> {
                    when (bleDevice.device) {
                        BleDevice.NANOX -> Model.NANO_X
                        BleDevice.STAX -> Model.STAX
                        BleDevice.FLEX -> Model.EUROPA
                        else -> null
                    }
                }

                is Usb -> {
                    Model.fromValue(hidDevice.productName)
                }
            }
        }

    val productName: String?
        get() {
            return when (this) {
                is Ble -> {
                    when (bleDevice.device) {
                        BleDevice.NANOX -> "Ledger Nano X"
                        BleDevice.STAX -> "Ledger Stax"
                        BleDevice.FLEX -> "Ledger Flex"
                        else -> null
                    }
                }

                is Usb -> {
                    "${hidDevice.manufacturerName} ${hidDevice.productName}"
                }
            }
        }
}
