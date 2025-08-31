package com.ledger.live.ble.service.model

import android.bluetooth.BluetoothGattService

sealed class GattCallbackEvent {
    sealed class ConnectionState: GattCallbackEvent() {
        object Connected: GattCallbackEvent()
        object Disconnected: GattCallbackEvent()
    }
    data class MtuNegociated(val mtuSize: Int): GattCallbackEvent()
    data class ServicesDiscovered(val services: List<BluetoothGattService>): GattCallbackEvent()
    data class CharacteristicChanged(val value: ByteArray): GattCallbackEvent()
    data class WriteDescriptorAck(val isSuccess: Boolean): GattCallbackEvent()
    data class WriteCharacteristicAck(val isSuccess: Boolean): GattCallbackEvent()
}