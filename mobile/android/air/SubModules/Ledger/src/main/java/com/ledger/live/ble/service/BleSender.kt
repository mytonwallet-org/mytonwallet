package com.ledger.live.ble.service

import android.annotation.SuppressLint
import com.ledger.live.ble.model.BleCommand
import com.ledger.live.ble.model.BleDeviceService
import com.ledger.live.ble.model.FrameCommand
import com.ledger.live.ble.service.model.BlePendingRequest
import timber.log.Timber
import java.util.ArrayDeque
import java.util.Queue
import java.util.concurrent.ConcurrentLinkedQueue

@SuppressLint("MissingPermission")
class BleSender(
    private val gatt: GattInteractor,
    private val deviceAddress: String,
    val pushWaitingResponseState: (String) -> Unit,
) {
    var isInitialized: Boolean = false

    var pendingApdu: Queue<BlePendingRequest> = ConcurrentLinkedQueue()
    fun queuApdu(apdu: ByteArray): String {
        val id = generateId(deviceAddress)
        pendingApdu.add(BlePendingRequest(id, apdu))
        return id
    }

    @Synchronized
    fun dequeuApdu() {
        if (!isInitialized) {
            throw IllegalStateException("Should not try to dequeu before initialize BleSender")
        }
        Timber.d("Try to dequeu pending request")
        Timber.d("pending request => ${pendingApdu.size}")
        if (pendingApdu.isNotEmpty() && pendingCommand == null) {
            Timber.d("Dequeu is possible")
            val pendingRequest = pendingApdu.remove()
            val command = BleCommand(pendingRequest.id, pendingRequest.apdu, mtuSize)
            sendCommands(command)
        } else {
            Timber.d("Dequeu is NOT possible")
        }
    }

    private val commandQueue: ArrayDeque<FrameCommand> = ArrayDeque()
    private fun sendCommands(command: BleCommand) {
        Timber.d("Need to send ${command.commands.size} frame")
        commandQueue.addAll(command.commands)
        val command = commandQueue.removeFirst()
        sendCommand(command)
    }

    var pendingCommand: FrameCommand? = null
    private fun sendCommand(command: FrameCommand) {
        val commandInByte: ByteArray = command.bytes
        pendingCommand = command
        gatt.sendBytes(deviceService, commandInByte)
        pushWaitingResponseState(command.id)
    }

    fun nextCommand() {
        if (commandQueue.isNotEmpty()) {
            val command = commandQueue.removeFirst()
            sendCommand(command)
        }
    }

    fun clearCommand() {
        pendingCommand = null
        commandQueue.clear()
    }

    private lateinit var deviceService: BleDeviceService
    private var mtuSize: Int = 0
    fun initialized(mtu: Int, deviceService: BleDeviceService) {
        this.mtuSize = mtu
        this.deviceService = deviceService
        isInitialized = true
    }

    fun isBusy(): Boolean =
        pendingApdu.isEmpty() && commandQueue.isEmpty() && pendingCommand != null

    companion object {
        fun generateId(deviceName: String): String {
            return "${deviceName}_send_${System.currentTimeMillis()}"
        }
    }

}
