
import Foundation
import WalletContext

public enum ApiCommonError: String, Error {
    case unexpected = "Unexpected"
    case serverError = "ServerError"
    case debugError = "DebugError"
    case unsupportedVersion = "UnsupportedVersion"
    case invalidPassword = "InvalidPassword"
    case invalidAddress = "InvalidAddress"
    case domainNotResolved = "DomainNotResolved"
}

public enum ApiAuthError: String, Error {
    case invalidMnemonic = "InvalidMnemonic"
}

public enum ApiTransactionDraftError: String, Error {
    case invalidAmount = "InvalidAmount"
    case invalidToAddress = "InvalidToAddress"
    case insufficientBalance = "InsufficientBalance"
    case invalidStateInit = "InvalidStateInit"
    case stateInitWithoutBin = "StateInitWithoutBin"
    case domainNotResolved = "DomainNotResolved"
    case walletNotInitialized = "WalletNotInitialized"
    case invalidAddressFormat = "InvalidAddressFormat"
    case inactiveContract = "InactiveContract"
    case mfaNftBatchLimit = "MfaNftBatchLimit"
}

public enum ApiTransactionError: String, Error {
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case insufficientBalance = "InsufficientBalance"
    case unsuccesfulTransfer = "UnsuccesfulTransfer"
    case wrongAddress = "WrongAddress"
    case wrongNetwork = "WrongNetwork"
    case concurrentTransaction = "ConcurrentTransaction"
}

public enum ApiHardwareError: String, Error {
    /** Used when the chain's Ledger app needs to be updated to support this transaction */
    case hardwareOutdated = "HardwareOutdated"
    case notSupportedHardwareOperation = "NotSupportedHardwareOperation"
    case blindSigningNotEnabled = "BlindSigningNotEnabled"
    case rejectedByUser = "RejectedByUser"
    case proofTooLarge = "ProofTooLarge"
    case connectionBroken = "ConnectionBroken"
    case wrongDevice = "WrongDevice"
}

public enum ApiTokenImportError: String, Error {
    case addressDoesNotExist = "AddressDoesNotExist"
    case notATokenAddress = "NotATokenAddress"
}

public enum ApiSwapError: String, Error {
    case slippageError = "SlippageError"
}

public enum ApiAnyDisplayError: RawRepresentable, Codable, Error, Sendable, Equatable, Hashable {
    public typealias RawValue = String

    // ApiCommonError
    case unexpected
    case serverError
    case debugError
    case unsupportedVersion
    case invalidPassword
    case invalidAddress
    case domainNotResolved

    // ApiAuthError
    case invalidMnemonic

    // ApiTransactionDraftError
    case invalidAmount
    case invalidToAddress
    case insufficientBalance
    case invalidStateInit
    case stateInitWithoutBin
    case walletNotInitialized
    case invalidAddressFormat
    case inactiveContract
    case mfaNftBatchLimit

    // ApiTransactionError
    case partialTransactionFailure
    case incorrectDeviceTime
    case unsuccesfulTransfer
    case wrongAddress
    case wrongNetwork
    case concurrentTransaction

    // ApiHardwareError
    case hardwareOutdated
    case notSupportedHardwareOperation
    case blindSigningNotEnabled
    case rejectedByUser
    case proofTooLarge
    case connectionBroken
    case wrongDevice

    // ApiTokenImportError
    case addressDoesNotExist
    case notATokenAddress

    // ApiSwapError
    case slippageError

    case unknown(String)

    public init?(rawValue: String) {
        guard let error = Self.from(rawValue) else {
            return nil
        }
        self = error
    }

    public var rawValue: String {
        switch self {
        case .unexpected:
            return "Unexpected"
        case .serverError:
            return "ServerError"
        case .debugError:
            return "DebugError"
        case .unsupportedVersion:
            return "UnsupportedVersion"
        case .invalidPassword:
            return "InvalidPassword"
        case .invalidAddress:
            return "InvalidAddress"
        case .domainNotResolved:
            return "DomainNotResolved"
        case .invalidMnemonic:
            return "InvalidMnemonic"
        case .invalidAmount:
            return "InvalidAmount"
        case .invalidToAddress:
            return "InvalidToAddress"
        case .insufficientBalance:
            return "InsufficientBalance"
        case .invalidStateInit:
            return "InvalidStateInit"
        case .stateInitWithoutBin:
            return "StateInitWithoutBin"
        case .walletNotInitialized:
            return "WalletNotInitialized"
        case .invalidAddressFormat:
            return "InvalidAddressFormat"
        case .inactiveContract:
            return "InactiveContract"
        case .mfaNftBatchLimit:
            return "MfaNftBatchLimit"
        case .partialTransactionFailure:
            return "PartialTransactionFailure"
        case .incorrectDeviceTime:
            return "IncorrectDeviceTime"
        case .unsuccesfulTransfer:
            return "UnsuccesfulTransfer"
        case .wrongAddress:
            return "WrongAddress"
        case .wrongNetwork:
            return "WrongNetwork"
        case .concurrentTransaction:
            return "ConcurrentTransaction"
        case .hardwareOutdated:
            return "HardwareOutdated"
        case .notSupportedHardwareOperation:
            return "NotSupportedHardwareOperation"
        case .blindSigningNotEnabled:
            return "BlindSigningNotEnabled"
        case .rejectedByUser:
            return "RejectedByUser"
        case .proofTooLarge:
            return "ProofTooLarge"
        case .connectionBroken:
            return "ConnectionBroken"
        case .wrongDevice:
            return "WrongDevice"
        case .addressDoesNotExist:
            return "AddressDoesNotExist"
        case .notATokenAddress:
            return "NotATokenAddress"
        case .slippageError:
            return "SlippageError"
        case .unknown(let rawValue):
            return rawValue
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ApiAnyDisplayError.from(rawValue) ?? .unknown(rawValue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func from(_ rawValue: String) -> ApiAnyDisplayError? {
        switch rawValue {
        case "UnsuccessfulTransfer":
            return .unsuccesfulTransfer
        case "Invalid mnemonic":
            return .invalidMnemonic
        case "HardwareBlindSigningNotEnabled":
            return .blindSigningNotEnabled
        case "Unexpected":
            return .unexpected
        case "ServerError":
            return .serverError
        case "DebugError":
            return .debugError
        case "UnsupportedVersion":
            return .unsupportedVersion
        case "InvalidPassword":
            return .invalidPassword
        case "InvalidAddress":
            return .invalidAddress
        case "DomainNotResolved":
            return .domainNotResolved
        case "InvalidMnemonic":
            return .invalidMnemonic
        case "InvalidAmount":
            return .invalidAmount
        case "InvalidToAddress":
            return .invalidToAddress
        case "InsufficientBalance":
            return .insufficientBalance
        case "InvalidStateInit":
            return .invalidStateInit
        case "StateInitWithoutBin":
            return .stateInitWithoutBin
        case "WalletNotInitialized":
            return .walletNotInitialized
        case "InvalidAddressFormat":
            return .invalidAddressFormat
        case "InactiveContract":
            return .inactiveContract
        case "MfaNftBatchLimit":
            return .mfaNftBatchLimit
        case "PartialTransactionFailure":
            return .partialTransactionFailure
        case "IncorrectDeviceTime":
            return .incorrectDeviceTime
        case "UnsuccesfulTransfer":
            return .unsuccesfulTransfer
        case "WrongAddress":
            return .wrongAddress
        case "WrongNetwork":
            return .wrongNetwork
        case "ConcurrentTransaction":
            return .concurrentTransaction
        case "HardwareOutdated":
            return .hardwareOutdated
        case "NotSupportedHardwareOperation":
            return .notSupportedHardwareOperation
        case "BlindSigningNotEnabled":
            return .blindSigningNotEnabled
        case "RejectedByUser":
            return .rejectedByUser
        case "ProofTooLarge":
            return .proofTooLarge
        case "ConnectionBroken":
            return .connectionBroken
        case "WrongDevice":
            return .wrongDevice
        case "AddressDoesNotExist":
            return .addressDoesNotExist
        case "NotATokenAddress":
            return .notATokenAddress
        case "SlippageError":
            return .slippageError
        default:
            return nil
        }
    }

    public var toLocalized: String {
        switch self {
        case .serverError:
            return lang("Please make sure your internet connection is working and try again.")
        case .unexpected:
            return lang("Unexpected")
        case .debugError:
            return lang("Unexpected error. Please let the support know.")
        case .unsupportedVersion:
            return lang("Unsupported version")
        case .invalidMnemonic:
            return lang("InvalidMnemonic")
        case .invalidPassword:
            return lang("Wrong password, please try again.")
        case .invalidAmount:
            return lang("Invalid amount")
        case .invalidAddress, .invalidToAddress:
            return lang("Invalid address")
        case .insufficientBalance:
            return lang("Insufficient balance")
        case .invalidStateInit:
            return lang("$state_init_invalid")
        case .stateInitWithoutBin:
            return lang("State init supplied without message body")
        case .domainNotResolved:
            return lang("Domain is not connected to a wallet")
        case .walletNotInitialized:
            return lang("Encryption is not possible. The recipient is not a wallet or has no outgoing transactions.")
        case .invalidAddressFormat:
            return lang("Invalid address format. Only URL Safe Base64 format is allowed.")
        case .inactiveContract:
            return lang("$transfer_inactive_contract_error")
        case .mfaNftBatchLimit:
            return lang("MFA NFT transfers support up to 4 NFTs at a time.")
        case .partialTransactionFailure:
            return lang("Not all transactions were sent successfully.")
        case .incorrectDeviceTime:
            return lang("The time on your device is incorrect, sync it and try again.")
        case .unsuccesfulTransfer:
            return lang("Transfer was unsuccessful. Try again later.")
        case .wrongAddress:
            return lang("WrongAddress")
        case .wrongNetwork:
            return lang("WrongNetwork")
        case .concurrentTransaction:
            return lang("Another transaction was sent from this wallet simultaneously. Please try again.")
        case .hardwareOutdated, .notSupportedHardwareOperation:
            return lang("$ledger_outdated")
        case .blindSigningNotEnabled:
            return lang("$hardware_blind_sign_not_enabled")
        case .rejectedByUser:
            return lang("Canceled by the user")
        case .proofTooLarge:
            return lang("The proof for signing provided by the Dapp is too large")
        case .connectionBroken:
            return lang("$ledger_connection_broken")
        case .wrongDevice:
            return lang("$ledger_wrong_device")
        case .addressDoesNotExist:
            return lang("Address doesn't exist")
        case .notATokenAddress:
            return lang("The address is not a token minter address")
        case .slippageError:
            return lang("$swap_slippage_violation")
        case .unknown(let rawValue):
            return Self.localizedFallback(forRawValue: rawValue) ?? rawValue
        }
    }

    public var toShortLocalized: String? {
        switch self {
        case .serverError:
            return lang("Network Error")
        case .slippageError:
            return toLocalized
        case .rejectedByUser:
            return lang("Canceled by the user")
        case .invalidAddress:
            return lang("Invalid address")
        case .unknown(let rawValue):
            return Self.shortLocalizedFallback(forRawValue: rawValue)
        default:
            return nil
        }
    }

    public static func localizedFallback(forRawValue rawValue: String) -> String? {
        switch rawValue {
        case "AxiosError", "Unknown":
            return lang("Please make sure your internet connection is working and try again.")
        case "Pair not found":
            return lang("Invalid Pair")
        case "Too small amount":
            return lang("$swap_too_small_amount")
        case "Insufficient liquidity":
            return lang("Insufficient liquidity")
        case "Canceled by the user":
            return lang("Canceled by the user")
        default:
            return nil
        }
    }

    public static func shortLocalizedFallback(forRawValue rawValue: String) -> String? {
        switch rawValue {
        case "Unknown":
            return lang("Network Error")
        case "Pair not found":
            return lang("Invalid Pair")
        case "Too small amount":
            return lang("$swap_too_small_amount")
        case "Canceled by the user":
            return lang("Canceled by the user")
        default:
            return nil
        }
    }
}

extension ApiAnyDisplayError: LocalizedError {
    public var errorDescription: String? {
        toLocalized
    }
}
