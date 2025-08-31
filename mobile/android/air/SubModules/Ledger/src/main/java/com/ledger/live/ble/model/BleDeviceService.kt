package com.ledger.live.ble.model

import android.bluetooth.BluetoothGattCharacteristic
import java.util.*

data class BleDeviceService(
    val uuid: UUID,
    val writeCharacteristic: BluetoothGattCharacteristic,
    val writeNoAnswerCharacteristic: BluetoothGattCharacteristic?,
    val notifyCharacteristic: BluetoothGattCharacteristic
) {
    class Builder(private val uuid: UUID) {
        private lateinit var writeCharacteristic: BluetoothGattCharacteristic
        private var writeNoAnswerCharacteristic: BluetoothGattCharacteristic? = null
        private lateinit var notifyCharacteristic: BluetoothGattCharacteristic

        fun setWriteCharacteristic(characteristic: BluetoothGattCharacteristic): Builder {
            writeCharacteristic = characteristic
            return this
        }

        fun setWriteNoAnswerCharacteristic(characteristic: BluetoothGattCharacteristic): Builder {
            writeNoAnswerCharacteristic = characteristic
            return this
        }

        fun setNotifyCharacteristic(characteristic: BluetoothGattCharacteristic): Builder {
            notifyCharacteristic = characteristic
            return this
        }

        fun build(): BleDeviceService = BleDeviceService(
            uuid = uuid,
            writeCharacteristic = writeCharacteristic,
            writeNoAnswerCharacteristic = writeNoAnswerCharacteristic,
            notifyCharacteristic = notifyCharacteristic,
        )
    }
}
