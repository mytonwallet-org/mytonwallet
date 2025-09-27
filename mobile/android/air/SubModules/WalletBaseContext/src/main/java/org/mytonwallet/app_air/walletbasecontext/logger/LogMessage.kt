package org.mytonwallet.app_air.walletbasecontext.logger

import org.mytonwallet.app_air.walletbasecontext.DEBUG_MODE

class LogMessage {
    enum class MessagePartPrivacy {
        PUBLIC, REDACTED
    }

    class Builder {
        val parts = mutableListOf<String>()

        fun append(value: Any?, privacy: MessagePartPrivacy): Builder {
            parts += when (privacy) {
                MessagePartPrivacy.PUBLIC -> value.toString()
                else -> {
                    if (DEBUG_MODE) {
                        "<redacted:${value.toString()}>"
                    } else {
                        "<redacted>"
                    }
                }
            }
            return this
        }

        fun build(): LogMessage {
            return LogMessage(parts)
        }

        operator fun String.unaryPlus() {
            parts += this
        }
    }

    override fun toString() = parts.joinToString(" ")

    private val parts: List<String>

    constructor(message: String) {
        this.parts = listOf(message)
    }

    private constructor(parts: List<String>) {
        this.parts = parts
    }
}
