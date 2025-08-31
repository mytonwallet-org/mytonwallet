package com.ledger.live.ble.model

import com.ledger.live.ble.extension.fromHexStringToBytes
import com.ledger.live.ble.extension.toHexString
import timber.log.Timber

class BleCommand(
    val id: String,
    val apdu: ByteArray,
    mtu: Int
) {

    val commands: List<FrameCommand>

    init {
        val size = apdu.size
        this.commands = if (size + FIRST_FRAME_HEADER_LENGTH <= mtu) {
            mutableListOf(
                FrameCommand(
                    id = id,
                    index = 0,
                    apdu = apdu,
                    size = size
                )
            )
        } else {
            val apduHex = apdu.toHexString()
            var cursor = 0
            val apduHexChunks: MutableList<String> = mutableListOf()
            val hexMtu = mtu * 2 //mtu for hexa string
            Timber.d("APDU hex length => ${apduHex.length}")
            while (cursor < apduHex.length) {
                Timber.d("Cursor => $cursor")
                val headerLenghtChars = (if (cursor == 0) FIRST_FRAME_HEADER_LENGTH else OTHER_FRAME_HEADER_LENGTH) * 2 //Bytes to hexstring
                if (apduHex.length < cursor + (hexMtu - headerLenghtChars) ) { //End of payload
                    apduHexChunks.add(apduHex.substring(cursor))
                    cursor = apduHex.length
                } else {
                    val chunkSize = hexMtu - headerLenghtChars
                    apduHexChunks.add(apduHex.substring(cursor, cursor + chunkSize))
                    cursor += chunkSize
                }
            }

            apduHexChunks.mapIndexed { index, apduChunk ->
                Timber.d(apduChunk)
                FrameCommand(
                    id = id,
                    index = index,
                    size = apdu.size,
                    apdu = apduChunk.fromHexStringToBytes()
                )
            }
        }
    }

    companion object {
        private const val FIRST_FRAME_HEADER_LENGTH = 5
        private const val OTHER_FRAME_HEADER_LENGTH = 3
        internal const val FRAME_PREFIX = "05"
    }
}
