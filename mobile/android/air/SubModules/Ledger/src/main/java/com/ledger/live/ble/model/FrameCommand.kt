package com.ledger.live.ble.model

import com.ledger.live.ble.extension.fromHexStringToBytes
import com.ledger.live.ble.extension.toHexString
import timber.log.Timber

class FrameCommand(
    val id: String,
    val index: Int,
    val size: Int = 0,
    val apdu: ByteArray
) {

    val apduSize
        get() = apdu.size

    private val prefix: String
        get() = FRAME_PREFIX

    private val commandHeaderHex: String
        get() {
            return buildCommandHeader(this)
        }

    val commandHex: String = "$commandHeaderHex${apdu.toHexString()}"

    val bytes: ByteArray
        get() = commandHex.fromHexStringToBytes()

    override fun toString(): String {
        return commandHex
    }

    companion object {
        private const val FRAME_PREFIX = "05"
        private const val INDEX_LENGTH = 4 //hex string Size
        private const val SIZE_LENGTH = 4 //hex string Size

        fun fromHex(id: String, hexCommand: String): FrameCommand {
            Timber.d(hexCommand)

            var cursor = BleCommand.FRAME_PREFIX.length
            val indexString = hexCommand.substring(
                startIndex = cursor,
                endIndex = cursor + INDEX_LENGTH
            )
            val frameIndex = indexString.toInt(16)
            //Move cursor for getting next attributes
            cursor += INDEX_LENGTH

            //For first frame we got APDU total size
            val size = if (frameIndex == 0) {
                val sizeString = hexCommand.substring(cursor, cursor + SIZE_LENGTH)
                val size = sizeString.toInt(16)
                cursor += SIZE_LENGTH
                size
            } else 0

            val apdu = hexCommand.substring(cursor)

            return FrameCommand(
                id = id,
                apdu = apdu.fromHexStringToBytes(),
                index = frameIndex,
                size = size
            )
        }

        private fun buildCommandHeader(command: FrameCommand): String {
            val header = command.prefix
            val indexHex = command.index.toHexString()
                .run { substring(this.length - INDEX_LENGTH) } //Only 2 Bytes so 4 characters
            val sizeHex = if (command.index == 0) {
                command.size.toHexString()
                    .run { substring(this.length - SIZE_LENGTH) }
            } else {
                "" //No size given if it's not the first frame (index == 0)
            }

            Timber.d("[Header] size for frame ${command.index} ==> $sizeHex")

            return "$header$indexHex$sizeHex"
        }
    }
}