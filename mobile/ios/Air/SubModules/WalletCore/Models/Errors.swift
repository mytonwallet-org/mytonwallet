
public enum ApiCommonError: String, Error {
    case unexpected = "Unexpected"
    case serverError = "ServerError"
    case debugError = "DebugError"
    case unsupportedVersion = "UnsupportedVersion"
    case invalidAddress = "InvalidAddress"
}

public enum ApiAuthError: String, Error {
    case invalidMnemonic = "InvalidMnemonic"
    case domainNotResolved = "DomainNotResolved"
}

public enum ApiTransactionDraftError: String, Error {
    case invalidAmount = "InvalidAmount"
    case invalidToAddress = "InvalidToAddress"
    case insufficientBalance = "InsufficientBalance"
    case invalidStateInit = "InvalidStateInit"
    case domainNotResolved = "DomainNotResolved"
    case walletNotInitialized = "WalletNotInitialized"
    case invalidAddressFormat = "InvalidAddressFormat"
    case inactiveContract = "InactiveContract"
}

public enum ApiTransactionError: String, Error {
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case insufficientBalance = "InsufficientBalance"
    case unsuccessfulTransfer = "UnsuccessfulTransfer"
    case wrongAddress = "WrongAddress"
    case wrongNetwork = "WrongNetwork"
    case concurrentTransaction = "ConcurrentTransaction"
}

public enum ApiHardwareError: String, Error {
  /** Used when the chain's Ledger app needs to be updated to support this transaction */
  case hardwareOutdated = "HardwareOutdated"
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

public enum ApiAnyDisplayError: String, Codable, Error, Sendable {
    // ApiCommonError
    case unexpected = "Unexpected"
    case serverError = "ServerError"
    case debugError = "DebugError"
    case unsupportedVersion = "UnsupportedVersion"
    case invalidAddress = "InvalidAddress"
    
    // ApiAuthError
    case invalidMnemonic = "InvalidMnemonic"
    case domainNotResolved = "DomainNotResolved"
    
    // ApiTransactionDraftError
    case invalidAmount = "InvalidAmount"
    case invalidToAddress = "InvalidToAddress"
    case insufficientBalance = "InsufficientBalance"
    case invalidStateInit = "InvalidStateInit"
    case walletNotInitialized = "WalletNotInitialized"
    case invalidAddressFormat = "InvalidAddressFormat"
    case inactiveContract = "InactiveContract"
    
    // ApiTransactionError
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case unsuccessfulTransfer = "UnsuccessfulTransfer"
    case wrongAddress = "WrongAddress"
    case wrongNetwork = "WrongNetwork"
    case concurrentTransaction = "ConcurrentTransaction"
    
    // ApiHardwareError
    case hardwareOutdated = "HardwareOutdated"
    case blindSigningNotEnabled = "BlindSigningNotEnabled"
    case rejectedByUser = "RejectedByUser"
    case proofTooLarge = "ProofTooLarge"
    case connectionBroken = "ConnectionBroken"
    case wrongDevice = "WrongDevice"
    
    // ApiTokenImportError
    case addressDoesNotExist = "AddressDoesNotExist"
    case notATokenAddress = "NotATokenAddress"
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let error = ApiAnyDisplayError(rawValue: string) {
            self = error
        } else {
            assertionFailure("failed to parse any known type")
            self = .unexpected
        }
    }
}
