package com.ledger.live.ble.service.model

data class BlePendingRequest(
    val id: String,
    val apdu: ByteArray
)
