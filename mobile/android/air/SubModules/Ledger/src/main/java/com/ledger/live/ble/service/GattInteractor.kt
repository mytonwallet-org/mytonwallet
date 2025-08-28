package com.ledger.live.ble.service

import android.annotation.SuppressLint
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattDescriptor
import com.ledger.live.ble.extension.fromHexStringToBytes
import com.ledger.live.ble.model.BleDeviceService
import kotlinx.coroutines.CoroutineScope
import timber.log.Timber

@SuppressLint("MissingPermission")
class GattInteractor(val gatt: BluetoothGatt) {

    init {
        gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH)
    }

    fun discoverService(){
        Timber.d("Try discover services")
        gatt.discoverServices()
    }

    fun enableNotification(deviceService: BleDeviceService) {
        Timber.d("Enable Notification")
        gatt.setCharacteristicNotification(deviceService.notifyCharacteristic, true)
        deviceService.notifyCharacteristic.descriptors.forEach {
            it.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            gatt.writeDescriptor(it)
        }
    }

    fun negotiateMtu() {
        Timber.d("Megociate MTU")
        gatt.requestMtu(MAX_MTU_VALUE)
    }

    fun askMtu(deviceService: BleDeviceService) {
        Timber.d("Ask MTU size")
        deviceService.writeCharacteristic.value = BleService.MTU_HANDSHAKE_COMMAND.fromHexStringToBytes()
        gatt.writeCharacteristic(deviceService.writeCharacteristic)
    }

    fun sendBytes(deviceService: BleDeviceService, bytes: ByteArray) {
        deviceService.let {
            if (it.writeNoAnswerCharacteristic != null) {
                it.writeNoAnswerCharacteristic.value = bytes
                gatt.writeCharacteristic(it.writeNoAnswerCharacteristic)
            } else {
                it.writeCharacteristic.value = bytes
                gatt.writeCharacteristic(it.writeCharacteristic)
            }
        }
    }

    companion object{
        private const val MAX_MTU_VALUE = 512
        const val GATT_HEADER_SIZE = 3
    }
}