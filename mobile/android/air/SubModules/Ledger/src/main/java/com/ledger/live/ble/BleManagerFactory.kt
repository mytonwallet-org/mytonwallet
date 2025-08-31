package com.ledger.live.ble

import android.content.Context

object BleManagerFactory {
    @Volatile
    private var INSTANCE: BleManager? = null
    fun newInstance(context: Context): BleManager = synchronized(this) {
        INSTANCE ?: BleManager(context).also { INSTANCE = it }
    }
}