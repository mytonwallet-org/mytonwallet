package org.mytonwallet.app_air.walletcore.models

import org.mytonwallet.app_air.walletbasecontext.localization.LocaleController

enum class MBridgeError(val errorName: String? = null, var customMessage: String? = null) {
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
    WRONG_DEVICE("WrongDevice"),
    WRONG_ADDRESS("WrongAddress"),
    WRONG_NETWORK("WrongNetwork"),
    INVALID_ADDRESS("InvalidAddress"),
    DOMAIN_NOT_RESOLVED("DomainNotResolved"),
    SLIPPAGE_ERROR("SlippageError"),

    PARSE_ERROR("JSON Parse Error"),
    UNKNOWN("Unknown");

    val toLocalized: String
        get() {
            return customMessage ?: when (this) {
                INVALID_MNEMONIC -> LocaleController.getString("InvalidMnemonic")
                INVALID_PASSWORD -> LocaleController.getString("Wrong password, please try again.")
                INVALID_AMOUNT -> LocaleController.getString("Invalid amount")
                INVALID_TO_ADDRESS -> LocaleController.getString("Invalid address")
                INVALID_STATE_INIT -> LocaleController.getString("\$state_init_invalid")
                WALLET_NOT_INITIALIZED -> LocaleController.getString("Encryption is not possible. The recipient is not a wallet or has no outgoing transactions.")
                INVALID_ADDRESS_FORMAT -> LocaleController.getString("Invalid address format. Only URL Safe Base64 format is allowed.")
                INACTIVE_CONTRACT -> LocaleController.getString("\$transfer_inactive_contract_error")
                MFA_NFT_BATCH_LIMIT -> LocaleController.getString("MFA NFT transfers support up to 4 NFTs at a time.")
                CONCURRENT_TRANSACTION -> LocaleController.getString("Another transaction was sent from this wallet simultaneously. Please try again.")
                ADDRESS_DOES_NOT_EXIST -> LocaleController.getString("Address doesn't exist")
                NOT_A_TOKEN_ADDRESS -> LocaleController.getString("The address is not a token minter address")
                PARTIAL_TRANSACTION_FAILURE -> LocaleController.getString("Not all transactions were sent successfully")
                INCORRECT_DEVICE_TIME -> LocaleController.getString("The time on your device is incorrect, sync it and try again.")
                INSUFFICIENT_BALANCE -> LocaleController.getString("Insufficient balance")
                PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")
                TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")
                SLIPPAGE_ERROR -> LocaleController.getString("\$swap_slippage_violation")
                CANCELED_BY_THE_USER, REJECTED_BY_USER -> LocaleController.getString("Canceled by the user")
                SERVER_ERROR, PARSE_ERROR, AXIOS_ERROR, UNKNOWN -> LocaleController.getString("No internet connection. Please check your connection and try again.")
                INSUFFICIENT_LIQUIDITY -> LocaleController.getString("Insufficient liquidity")
                UNSUCCESSFUL_TRANSFER -> LocaleController.getString("Transfer was unsuccessful. Try again later.")
                HARDWARE_OUTDATED -> LocaleController.getString("HardwareOutdated")
                HARDWARE_BLIND_SIGNING_NOT_ENABLED ->
                    LocaleController.getString("\$hardware_blind_sign_not_enabled")

                PROOF_TOO_LARGE -> LocaleController.getString("The proof for signing provided by the app is too large")
                CONNECTION_BROKEN -> LocaleController.getString("\$ledger_connection_broken")

                WRONG_DEVICE -> LocaleController.getString("\$ledger_wrong_device")
                WRONG_ADDRESS -> LocaleController.getString("WrongAddress")
                DOMAIN_NOT_RESOLVED -> LocaleController.getString("Domain is not connected to a wallet")
                WRONG_NETWORK -> LocaleController.getString("WrongNetwork")
                INVALID_ADDRESS -> LocaleController.getString("Invalid address")
                UNSUPPORTED_VERSION -> LocaleController.getString("Unsupported version")
            }
        }

    val toShortLocalized: String?
        get() {
            return customMessage ?: when (this) {
                SERVER_ERROR, PARSE_ERROR, UNKNOWN -> LocaleController.getString("Network Error")
                PAIR_NOT_FOUND -> LocaleController.getString("Invalid Pair")
                TOO_SMALL_AMOUNT -> LocaleController.getString("\$swap_too_small_amount")
                SLIPPAGE_ERROR -> LocaleController.getString("\$swap_slippage_violation")
                CANCELED_BY_THE_USER, REJECTED_BY_USER -> LocaleController.getString("Canceled by the user")
                INVALID_ADDRESS -> LocaleController.getString("Invalid address")
                else -> null
            }
        }
}
