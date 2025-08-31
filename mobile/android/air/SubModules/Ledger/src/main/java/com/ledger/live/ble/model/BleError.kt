package com.ledger.live.ble.model

enum class BleError(
    val message: String,
    val errorCode: Int
) {

    UNKNOWN(ERROR_MESSAGE_UNKNOWN, ERROR_CODE_UNKNOWN),
    PAIRING_FAILED(ERROR_MESSAGE_PAIRING_FAILED, ERROR_CODE_PAIRING_FAILED),
    CONNECTION_TIMEOUT(ERROR_MESSAGE_TIMEOUT, ERROR_CODE_TIMEOUT),
    INITIALIZING_FAILED(ERROR_MESSAGE_INITIALIZING_FAILED, ERROR_CODE_INITIALIZING_FAILED),
    DEVICE_NOT_FOUND(ERROR_MESSAGE_DEVICE_NOT_FOUND, ERROR_CODE_DEVICE_NOT_FOUND),
    NO_DEVICE_ADDRESS(ERROR_MESSAGE_NO_DEVICE_ADDRESS, ERROR_CODE_NO_DEVICE_ADDRESS),
    SERVICE_NOT_FOUND(ERROR_MESSAGE_SERVICES_NOT_FOUND,ERROR_CODE_SERVICE_NOT_FOUND),
    INTERNAL_STATE(ERROR_MESSAGE_INTERNAL_STATE, ERROR_CODE_INTERNAL_STATE_ERROR);

    companion object {
        fun foundForErrorCode(errorCode: Int): BleError = when (errorCode) {
            ERROR_CODE_UNKNOWN -> UNKNOWN
            ERROR_CODE_PAIRING_FAILED -> PAIRING_FAILED
            ERROR_CODE_TIMEOUT -> CONNECTION_TIMEOUT
            ERROR_CODE_INITIALIZING_FAILED -> INITIALIZING_FAILED
            ERROR_CODE_DEVICE_NOT_FOUND -> DEVICE_NOT_FOUND
            ERROR_CODE_SERVICE_NOT_FOUND -> SERVICE_NOT_FOUND
            ERROR_CODE_INTERNAL_STATE_ERROR -> INTERNAL_STATE
            else -> UNKNOWN
        }
    }
}

//Error Code
private const val ERROR_CODE_UNKNOWN = 1
private const val ERROR_CODE_PAIRING_FAILED = 2
private const val ERROR_CODE_TIMEOUT = 3
private const val ERROR_CODE_INITIALIZING_FAILED = 4
private const val ERROR_CODE_DEVICE_NOT_FOUND = 5
private const val ERROR_CODE_NO_DEVICE_ADDRESS = 6
private const val ERROR_CODE_SERVICE_NOT_FOUND = 7
private const val ERROR_CODE_INTERNAL_STATE_ERROR = 8


//Error Message
private const val ERROR_MESSAGE_UNKNOWN = "Unknown disconnection happened"
private const val ERROR_MESSAGE_PAIRING_FAILED = "Pairing with device failed"
private const val ERROR_MESSAGE_TIMEOUT = "Connection timeout error"
private const val ERROR_MESSAGE_INITIALIZING_FAILED = "BleService initialization failed"
private const val ERROR_MESSAGE_DEVICE_NOT_FOUND = "Cannot found device for connection"
private const val ERROR_MESSAGE_NO_DEVICE_ADDRESS = "Error with the device address"
private const val ERROR_MESSAGE_SERVICES_NOT_FOUND = "No usable service found for device"
private const val ERROR_MESSAGE_INTERNAL_STATE = "Something went wrong in the internal state machine"




