package org.mytonwallet.app_air.walletcontext.models

import org.json.JSONObject

abstract class WStoringObject() {
    abstract fun toJSONObject(): JSONObject
}
