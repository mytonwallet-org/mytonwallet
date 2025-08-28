package org.mytonwallet.app_air.ledger.helpers

import com.ledger.live.ble.extension.toHexString
import java.nio.ByteBuffer

class APDUHelpers {
    companion object {
        private val LEDGER_SYSTEM = 0xB0
        const val LEDGER_CLA = 0xE0
        const val INS_VERSION = 0x03
        const val INS_ADDRESS = 0x05
        const val INS_SIGN_TX = 0x06
        const val INS_PROOF = 0x08
        const val INS_SIGN_DATA = 0x09

        fun currentApp(): String {
            return byteArrayOf(
                LEDGER_SYSTEM.toByte(),
                0x01,
                0x00,
                0x00,
                0x00
            ).toHexString()
        }

        fun getLedgerAccountPath(isTestnet: Boolean, workChain: Int, index: Int): List<Int> {
            return listOf(44, 607, if (isTestnet) 1 else 0, workChain, index, 0)
        }

        fun getPublicKey(isTestnet: Boolean, workChain: Int, index: Int): String {
            val paths = getLedgerAccountPath(isTestnet, workChain, index)
            return (byteArrayOf(
                LEDGER_CLA.toByte(),
                INS_ADDRESS.toByte(),
                0x00,
                0x00,
                (1 + paths.size * 4).toByte()
            ) + ByteBuffer.allocate(1 + paths.size * 4).apply {
                put(paths.size.toByte())
                paths.map { (it + 0x80000000).toInt() }.forEach(this::putInt)
            }.array()).toHexString()
        }

        fun decode(hex: String): List<Int> {
            return hex.chunked(2).map { it.toInt(16) }
        }

        fun decodeReadable(hex: String): List<String> {
            val bytes = hex.chunked(2)
                .map { it.toInt(16).toByte() }
                .toByteArray()

            val parts = mutableListOf<String>()
            val current = StringBuilder()

            for (byte in bytes) {
                val ch = byte.toInt().toChar()
                if (ch in ' '..'~') {
                    current.append(ch)
                } else {
                    if (current.isNotEmpty()) {
                        parts.add(current.toString())
                        current.clear()
                    }
                }
            }

            if (current.isNotEmpty()) {
                parts.add(current.toString())
            }

            return parts
        }
    }
}
