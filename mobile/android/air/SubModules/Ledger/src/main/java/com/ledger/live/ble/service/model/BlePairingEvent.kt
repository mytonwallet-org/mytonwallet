package com.ledger.live.ble.service.model

sealed class BlePairingEvent: GattCallbackEvent() {
    object None: BlePairingEvent()
    object Pairing: BlePairingEvent()
    object Paired: BlePairingEvent()
}
