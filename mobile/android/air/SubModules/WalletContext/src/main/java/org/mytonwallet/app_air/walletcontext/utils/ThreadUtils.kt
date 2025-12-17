package org.mytonwallet.app_air.walletcontext.utils;

import android.os.Handler
import android.os.Looper

fun ensureMainThread(action: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
        action()
    } else {
        Handler(Looper.getMainLooper()).post {
            action()
        }
    }
}
