package com.ledger.live.ble.service

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import com.ledger.live.ble.service.model.BlePairingEvent
import com.ledger.live.ble.service.model.GattCallbackEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.runBlocking

class BlePairingCallbackFlow(
    private val context: Context
) {
    private val pairingReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        @SuppressLint("MissingPermission")
        override fun onReceive(context: Context, intent: Intent) {
            val device: BluetoothDevice = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)!!
            when (device.bondState) {
                BluetoothDevice.BOND_NONE -> pushEvent(BlePairingEvent.None)
                BluetoothDevice.BOND_BONDING -> pushEvent(BlePairingEvent.Pairing)
                BluetoothDevice.BOND_BONDED -> pushEvent(BlePairingEvent.Paired)
            }
        }
    }

    private val _gattFlow =
        MutableSharedFlow<BlePairingEvent>(replay = 1, extraBufferCapacity = 0)
    val gattFlow: Flow<BlePairingEvent>
        get() = _gattFlow

    fun bind() {
        context.registerReceiver(
            pairingReceiver,
            IntentFilter("android.bluetooth.device.action.PAIRING_REQUEST")
        )
    }

    fun unbind() {
        context.unregisterReceiver(pairingReceiver)
    }

    private fun pushEvent(event: BlePairingEvent) {
        runBlocking {
            _gattFlow.emit(event)
        }
    }
}