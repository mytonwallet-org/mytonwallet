
import Foundation
import WalletContext


public enum BridgeCallError: Error {
    case message(BridgeCallErrorMessages, Any?)
    case customMessage(String, Any?)
    case unknown(baseError: Any? = nil)
    case apiReturnedError(error: String, data: Any)
    
    public init(message: String, payload: Any?) {
        if let known = BridgeCallErrorMessages(rawValue: message) {
            self = .message(known, payload)
        } else {
            self = .customMessage(message, payload)
        }
    }
    
    static func tryToParseDataAsErrorAndThrow(data: Any?) throws {
        if let data, let errorValue = try? JSONSerialization.decode(ApiReturnError.self, from: data) {
            throw BridgeCallError.apiReturnedError(error: errorValue.error, data: data)
        }
    }
}

public enum BridgeCallErrorMessages: String {
    case serverError = "ServerError"
    case invalidMnemonic = "Invalid mnemonic"
    
    // transaction errors
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case insufficientBalance = "InsufficientBalance"
    case unsuccesfulTransfer = "UnsuccesfulTransfer"
    case unsupportedHardwareContract = "UnsupportedHardwareContract"
    case unsupportedHardwarePayload = "UnsupportedHardwarePayload"
    case nonAsciiCommentForHardwareOperation = "NonAsciiCommentForHardwareOperation"
    case tooLongCommentForHardwareOperation = "TooLongCommentForHardwareOperation"
    case unsupportedHardwareNftOperation = "UnsupportedHardwareNftOperation"
    case invalidAddress = "InvalidAddress"
    case walletNotInitialized = "WalletNotInitialized"
    
    case unknown
    
    public var toLocalized: String {
        switch self {
        case .serverError:
            return lang("Please make sure your internet connection is working and try again.")
        case .invalidMnemonic:
            return lang("InvalidMnemonic")
        case .partialTransactionFailure:
            return lang("Not all transactions were sent successfully.")
        case .incorrectDeviceTime:
            return lang("The time on your device is incorrect, sync it and try again.")
        case .insufficientBalance:
            return lang("Insufficient balance")
        case .unsuccesfulTransfer:
            return lang("Transfer was unsuccessful. Try again later.")
        case .unsupportedHardwareContract:
            return lang("Transaction to this smart contract is not yet supported by Ledger.")
        case .unsupportedHardwarePayload:
            return lang("This type of transaction is not yet supported by Ledger.")
        case .nonAsciiCommentForHardwareOperation:
            return lang("The current version of Ledger only supports English-language comments without special characters.")
        case .tooLongCommentForHardwareOperation:
            return lang("Comment is too long.")
        case .unsupportedHardwareNftOperation:
            return lang("Transferring NFT is not yet supported by Ledger.")
        case .invalidAddress:
            return lang("Invalid address")
        case .walletNotInitialized:
            return lang("Encryption is not possible. The recipient is not a wallet or has no outgoing transactions.")
        case .unknown:
            return lang("Please make sure your internet connection is working and try again.")
        }
    }
}

public struct ApiReturnError: Decodable {
    public var error: String
}

extension BridgeCallError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .message(let message, _):
            return message.toLocalized
        case .customMessage(let string, _):
            return string
        case .unknown(let baseError):
            if let e = baseError as? LocalizedError {
                return e.errorDescription
            }
            return lang("Please make sure your internet connection is working and try again.")
        case .apiReturnedError(let error, _):
            return error
        }
    }
}
