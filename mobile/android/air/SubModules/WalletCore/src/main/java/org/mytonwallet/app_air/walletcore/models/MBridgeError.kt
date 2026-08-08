package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

sealed interface MBridgeError {
    val type: Type
    val customMessage: String?

    enum class Type(override val errorName: String? = null) : MBridgeError {
        AXIOS_ERROR("AxiosError"),
        SERVER_ERROR("ServerError"),
        UNSUPPORTED_VERSION("UnsupportedVersion"),
        INVALID_MNEMONIC("Invalid mnemonic"),
        INVALID_PASSWORD("InvalidPassword"),
        INVALID_AMOUNT("InvalidAmount"),
        INVALID_TO_ADDRESS("InvalidToAddress"),
        INVALID_STATE_INIT("InvalidStateInit"),
        WALLET_NOT_INITIALIZED("WalletNotInitialized"),
        INVALID_ADDRESS_FORMAT("InvalidAddressFormat"),
        INACTIVE_CONTRACT("InactiveContract"),
        MFA_NFT_BATCH_LIMIT("MfaNftBatchLimit"),
        CONCURRENT_TRANSACTION("ConcurrentTransaction"),
        ADDRESS_DOES_NOT_EXIST("AddressDoesNotExist"),
        NOT_A_TOKEN_ADDRESS("NotATokenAddress"),

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
        WRONG_DEVICE("WrongDevice"),
        WRONG_ADDRESS("WrongAddress"),
        WRONG_NETWORK("WrongNetwork"),
        INVALID_ADDRESS("InvalidAddress"),
        DOMAIN_NOT_RESOLVED("DomainNotResolved"),
        SLIPPAGE_ERROR("SlippageError"),
        DEVICE_LOCKED("DeviceLocked"),

        BRIDGE_INTERRUPTED("BridgeInterrupted"),
        PARSE_ERROR("JSON Parse Error"),
        UNKNOWN("Unknown");

        override val type: Type
            get() = this

        override val customMessage: String?
            get() = null
    }

    class Custom internal constructor(override val type: Type, override val customMessage: String) :
        MBridgeError

    val errorName: String?
        get() = type.errorName

    fun withCustomMessage(message: String): MBridgeError = Custom(type, message)

    val toLocalized: String
        get() {
            return customMessage ?: when (type) {
                Type.INVALID_MNEMONIC -> LocaleController.getString("InvalidMnemonic")

                Type.INVALID_PASSWORD -> LocaleController.getString(
                    "Wrong password, please try again."
                )

                Type.INVALID_AMOUNT -> LocaleController.getString("Invalid amount")

                Type.INVALID_TO_ADDRESS -> LocaleController.getString("Invalid address")

                Type.INVALID_STATE_INIT -> LocaleController.getString("\$state_init_invalid")

                Type.WALLET_NOT_INITIALIZED -> LocaleController.getString(
                    "Encryption is not possible. The recipient is not a wallet or has no outgoing transactions."
                )

                Type.INVALID_ADDRESS_FORMAT -> LocaleController.getString(
                    "Invalid address format. Only URL Safe Base64 format is allowed."
                )

                Type.INACTIVE_CONTRACT -> LocaleController.getString(
                    "\$transfer_inactive_contract_error"
                )

                Type.MFA_NFT_BATCH_LIMIT -> LocaleController.getString(
                    "MFA NFT transfers support up to 4 NFTs at a time."
                )

                Type.CONCURRENT_TRANSACTION -> LocaleController.getString(
                    "Another transaction was sent from this wallet simultaneously. Please try again."
                )

                Type.ADDRESS_DOES_NOT_EXIST -> LocaleController.getString("Address doesn't exist")

                Type.NOT_A_TOKEN_ADDRESS -> LocaleController.getString(
                    "The address is not a token minter address"
                )

                Type.PARTIAL_TRANSACTION_FAILURE -> LocaleController.getString(
                    "Not all transactions were sent successfully"
                )

                Type.INCORRECT_DEVICE_TIME -> LocaleController.getString(
                    "The time on your device is incorrect, sync it and try again."
                )

                Type.INSUFFICIENT_BALANCE -> LocaleController.getString("Insufficient balance")

                Type.PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")

                Type.TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")

                Type.SLIPPAGE_ERROR -> LocaleController.getString("\$swap_slippage_violation")

                Type.CANCELED_BY_THE_USER, Type.REJECTED_BY_USER -> LocaleController.getString(
                    "Canceled by the user"
                )

                Type.SERVER_ERROR,
                Type.PARSE_ERROR,
                Type.AXIOS_ERROR,
                Type.BRIDGE_INTERRUPTED,
                Type.UNKNOWN -> LocaleController.getString(
                    "No internet connection. Please check your connection and try again."
                )

                Type.INSUFFICIENT_LIQUIDITY -> LocaleController.getString("Insufficient liquidity")

                Type.UNSUCCESSFUL_TRANSFER -> LocaleController.getString(
                    "Transfer was unsuccessful. Try again later."
                )

                Type.HARDWARE_OUTDATED -> LocaleController.getString("HardwareOutdated")

                Type.HARDWARE_BLIND_SIGNING_NOT_ENABLED ->
                    LocaleController.getString("\$hardware_blind_sign_not_enabled")

                Type.PROOF_TOO_LARGE -> LocaleController.getString(
                    "The proof for signing provided by the app is too large"
                )

                Type.CONNECTION_BROKEN -> LocaleController.getString("\$ledger_connection_broken")

                Type.WRONG_DEVICE -> LocaleController.getString("\$ledger_wrong_device")

                Type.WRONG_ADDRESS -> LocaleController.getString("WrongAddress")

                Type.DOMAIN_NOT_RESOLVED -> LocaleController.getString(
                    "Domain is not connected to a wallet"
                )

                Type.WRONG_NETWORK -> LocaleController.getString("WrongNetwork")

                Type.INVALID_ADDRESS -> LocaleController.getString("Invalid address")

                Type.UNSUPPORTED_VERSION -> LocaleController.getString("Unsupported version")

                Type.DEVICE_LOCKED -> "${LocaleController.getString("Unlock")}. ${
                    LocaleController.getString("Please try again")
                }"
            }
        }

    val toShortLocalized: String?
        get() {
            return customMessage ?: when (type) {
                Type.SERVER_ERROR, Type.PARSE_ERROR, Type.UNKNOWN -> LocaleController.getString(
                    "Network Error"
                )

                Type.PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")

                Type.TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")

                Type.SLIPPAGE_ERROR -> LocaleController.getString("\$swap_slippage_violation")

                Type.CANCELED_BY_THE_USER, Type.REJECTED_BY_USER -> LocaleController.getString(
                    "Canceled by the user"
                )

                Type.INVALID_ADDRESS -> LocaleController.getString("Invalid address")

                Type.DEVICE_LOCKED -> "${LocaleController.getString("Unlock")}. ${
                    LocaleController.getString("Please try again")
                }"

                else -> null
            }
        }

    companion object {
        fun fromErrorName(errorName: String?): MBridgeError? =
            Type.entries.firstOrNull { it.errorName == errorName }
    }
}
