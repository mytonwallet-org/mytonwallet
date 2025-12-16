package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MBridgeError(val errorName: String? = null, var customMessage: String? = null) {
    AXIOS_ERROR("AxiosError"),
    SERVER_ERROR("ServerError"),
    INVALID_MNEMONIC("Invalid mnemonic"),

    // transaction errors
    PARTIAL_TRANSACTION_FAILURE("PartialTransactionFailure"),
    INCORRECT_DEVICE_TIME("IncorrectDeviceTime"),
    INSUFFICIENT_BALANCE("InsufficientBalance"),
    PAIR_NOT_FOUND("Pair not found"),
    TOO_SMALL_AMOUNT("Too small amount"),
    INSUFFICIENT_LIQUIDITY("Insufficient liquidity"),
    UNSUCCESSFUL_TRANSFER("UnsuccesfulTransfer"),
    CANCELED_BY_THE_USER("Canceled by the user"),
    HARDWARE_OUTDATED("HardwareOutdated"),
    HARDWARE_BLIND_SIGNING_NOT_ENABLED("BlindSigningNotEnabled"),
    REJECTED_BY_USER("RejectedByUser"),
    PROOF_TOO_LARGE("ProofTooLarge"),
    CONNECTION_BROKEN("ConnectionBroken"),
    WRONG_ADDRESS("WrongAddress"),
    WRONG_NETWORK("WrongNetwork"),
    INVALID_ADDRESS("InvalidAddress"),
    DOMAIN_NOT_RESOLVED("DomainNotResolved"),

    PARSE_ERROR("JSON Parse Error"),
    UNKNOWN("Unknown");

    val toLocalized: String
        get() {
            return customMessage ?: when (this) {
                INVALID_MNEMONIC -> LocaleController.getString("InvalidMnemonic")
                PARTIAL_TRANSACTION_FAILURE -> LocaleController.getString("Not all transactions were sent successfully")
                INCORRECT_DEVICE_TIME -> LocaleController.getString("The time on your device is incorrect, sync it and try again")
                INSUFFICIENT_BALANCE -> LocaleController.getString("Insufficient balance")
                PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")
                TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")
                CANCELED_BY_THE_USER, REJECTED_BY_USER -> LocaleController.getString("Canceled by the user")
                SERVER_ERROR, PARSE_ERROR, AXIOS_ERROR, UNKNOWN -> LocaleController.getString("No internet connection. Please check your connection and try again.")
                INSUFFICIENT_LIQUIDITY -> LocaleController.getString("Insufficient liquidity")
                UNSUCCESSFUL_TRANSFER -> LocaleController.getString("Transfer was unsuccessful. Try again later.")
                HARDWARE_OUTDATED -> LocaleController.getString("HardwareOutdated")
                HARDWARE_BLIND_SIGNING_NOT_ENABLED ->
                    LocaleController.getString("\$hardware_blind_sign_not_enabled")

                PROOF_TOO_LARGE -> LocaleController.getString("The proof for signing provided by the Dapp is too large")
                CONNECTION_BROKEN -> LocaleController.getString("\$ledger_connection_broken")

                WRONG_ADDRESS -> LocaleController.getString("WrongAddress")
                DOMAIN_NOT_RESOLVED -> LocaleController.getString("Domain is not connected to a wallet")
                WRONG_NETWORK -> LocaleController.getString("WrongNetwork")
                INVALID_ADDRESS -> LocaleController.getString("Invalid address")
            }
        }

    val toShortLocalized: String?
        get() {
            return customMessage ?: when (this) {
                SERVER_ERROR, PARSE_ERROR, UNKNOWN -> LocaleController.getString("Network Error")
                PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")
                TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")
                CANCELED_BY_THE_USER, REJECTED_BY_USER -> LocaleController.getString("Canceled by the user")
                INVALID_ADDRESS -> LocaleController.getString("Invalid address")
                else -> null
            }
        }
}
