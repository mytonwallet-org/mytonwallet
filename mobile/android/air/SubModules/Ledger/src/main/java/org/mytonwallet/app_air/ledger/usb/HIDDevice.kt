package org.mytonwallet.app_air.ledger.usb

import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.hardware.usb.UsbRequest
import org.mytonwallet.app_air.walletbasecontext.logger.Logger
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.min

class HIDDevice(manager: UsbManager, device: UsbDevice) {
    private val connectedDevice: UsbDevice
    private val connection: UsbDeviceConnection
    private val dongleInterface: UsbInterface
    private val `in`: UsbEndpoint?
    private val out: UsbEndpoint?
    private val transferBuffer: ByteArray
    private val executor: ExecutorService
    private var debug = false

    init {
        val dongleInterface = device.getInterface(0)
        var `in`: UsbEndpoint? = null
        var out: UsbEndpoint? = null
        for (i in 0..<dongleInterface.getEndpointCount()) {
            val tmpEndpoint = dongleInterface.getEndpoint(i)
            if (tmpEndpoint.getDirection() == UsbConstants.USB_DIR_IN) {
                `in` = tmpEndpoint
            } else {
                out = tmpEndpoint
            }
        }
        val connection = manager.openDevice(device)
        if (connection == null) {
            throw Exception()
        }
        connection.claimInterface(dongleInterface, true)

        this.connectedDevice = device
        this.connection = connection
        this.dongleInterface = dongleInterface
        this.`in` = `in`
        this.out = out

        transferBuffer = ByteArray(HID_BUFFER_SIZE)
        executor = Executors.newSingleThreadExecutor()
    }

    @Throws(Exception::class)
    fun exchange(commandSource: ByteArray?, onCompletion: (String?) -> Unit) {
        val exchange = Runnable {
            try {
                val response = ByteArrayOutputStream()
                var responseData: ByteArray? = null
                var offset = 0
                var responseSize: Int
                val command = LedgerUSBHelpers.wrapCommandAPDU(
                    LEDGER_DEFAULT_CHANNEL,
                    commandSource,
                    HID_BUFFER_SIZE
                )
                if (debug) {
                    Logger.d(Logger.LogTag.SHIDDevice, "exchange: command=" + toHex(command))
                }

                var request = UsbRequest()
                if (!request.initialize(connection, out)) {
                    throw Exception("I/O error")
                }
                while (offset != command.size) {
                    val blockSize = (min(
                        (command.size - offset).toDouble(),
                        HID_BUFFER_SIZE.toDouble()
                    )).toInt()
                    System.arraycopy(command, offset, transferBuffer, 0, blockSize)
                    if (!request.queue(ByteBuffer.wrap(transferBuffer), HID_BUFFER_SIZE)) {
                        request.close()
                        throw Exception("I/O error")
                    }
                    connection.requestWait()
                    offset += blockSize
                }
                val responseBuffer = ByteBuffer.allocate(HID_BUFFER_SIZE)
                request = UsbRequest()
                if (!request.initialize(connection, `in`)) {
                    request.close()
                    throw Exception("I/O error")
                }

                while ((LedgerUSBHelpers.unwrapResponseAPDU(
                        LEDGER_DEFAULT_CHANNEL, response.toByteArray(),
                        HID_BUFFER_SIZE
                    ).also { responseData = it }) == null
                ) {
                    responseBuffer.clear()
                    if (!request.queue(responseBuffer, HID_BUFFER_SIZE)) {
                        request.close()
                        throw Exception("I/O error")
                    }
                    connection.requestWait()
                    responseBuffer.rewind()
                    responseBuffer.get(transferBuffer, 0, HID_BUFFER_SIZE)
                    response.write(transferBuffer, 0, HID_BUFFER_SIZE)
                }

                if (debug) {
                    Logger.d(Logger.LogTag.SHIDDevice, "exchange: response=" + toHex(responseData!!))
                }

                request.close()

                onCompletion(toHex(responseData!!))
            } catch (e: Exception) {
                e.printStackTrace()
                onCompletion(null)
            }
        }
        this.executor.submit(exchange)
    }

    fun close() {
        try {
            connection.releaseInterface(dongleInterface)
            connection.close()
            this.executor.shutdown()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun setDebug(debugFlag: Boolean) {
        this.debug = debugFlag
    }

    val deviceId: Int
        get() = connectedDevice.deviceId

    val deviceName: String
        get() = connectedDevice.deviceName

    val manufacturerName: String?
        get() = connectedDevice.manufacturerName

    val productName: String?
        get() = connectedDevice.productName

    companion object {
        private const val HID_BUFFER_SIZE = 64
        private const val LEDGER_DEFAULT_CHANNEL = 1

        @JvmOverloads
        fun toHex(buffer: ByteArray, offset: Int = 0, length: Int = buffer.size): String {
            val result = StringBuilder()
            for (i in 0..<length) {
                var temp = Integer.toHexString((buffer[offset + i]).toInt() and 0xff)
                if (temp.length < 2) {
                    temp = "0" + temp
                }
                result.append(temp)
            }
            return result.toString()
        }
    }
}
