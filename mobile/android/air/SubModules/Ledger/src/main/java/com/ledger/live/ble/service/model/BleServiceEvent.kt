package com.ledger.live.ble.service.model

import com.ledger.live.ble.model.BleError

sealed class BleServiceEvent {
    data class BleDeviceConnected(val mtu: Int): BleServiceEvent()
    data class BleDeviceDisconnected(val error: BleError? = null): BleServiceEvent()
    data class SuccessSend(val sendId: String): BleServiceEvent()
    data class SendAnswer(val sendId: String, val answer: String): BleServiceEvent()
    data class ErrorSend(val sendId: String, val error: String): BleServiceEvent()
    data object BleServiceDisconnected: BleServiceEvent()
}
