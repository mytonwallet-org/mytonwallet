package com.ledger.live.ble.service

import com.ledger.live.ble.extension.toHexString
import com.ledger.live.ble.model.FrameCommand
import com.ledger.live.ble.service.model.BleAnswer

class BleReceiver {
    private var pendingAnswers: MutableList<FrameCommand> = mutableListOf()
    fun handleAnswer(id: String, hexAnswer: String): BleAnswer? {
        val command: FrameCommand = FrameCommand.fromHex(id, hexAnswer)
        pendingAnswers.add(command)

        val isAnswerComplete = if (command.index == 0) {
            command.size == command.apdu.size
        } else {
            val totalReceivedSize = pendingAnswers.sumOf { it.apdu.size }
            pendingAnswers.first().size == totalReceivedSize
        }

        return if (isAnswerComplete) {
            val completeApdu = pendingAnswers.joinToString("") { it.apdu.toHexString() }
            pendingAnswers.clear()
            BleAnswer(id, completeApdu)
        } else {
            null
        }
    }
}