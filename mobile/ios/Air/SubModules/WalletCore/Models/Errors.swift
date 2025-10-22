
public enum ApiCommonError: String, Error {
    case unexpected = "Unexpected"
    case serverError = "ServerError"
    case debugError = "DebugError"
    case unsupportedVersion = "UnsupportedVersion"
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
}

public enum ApiTransactionError: String, Error {
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case insufficientBalance = "InsufficientBalance"
    case unsuccessfulTransfer = "UnsuccessfulTransfer"
    case notSupportedHardwareOperation = "NotSupportedHardwareOperation"
    case hardwareBlindSigningNotEnabled = "HardwareBlindSigningNotEnabled"
    case wrongAddress = "WrongAddress"
    case wrongNetwork = "WrongNetwork"
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


public enum ApiAnyDisplayError: String, Codable, Error {
    // Common
    case unexpected = "Unexpected"
    case serverError = "ServerError"
    case debugError = "DebugError"
    case unsupportedVersion = "UnsupportedVersion"

    // Auth
    case invalidMnemonic = "InvalidMnemonic"

    // TransactionDraft
    case invalidAmount = "InvalidAmount"
    case invalidToAddress = "InvalidToAddress"
    case invalidStateInit = "InvalidStateInit"
    case stateInitWithoutBin = "StateInitWithoutBin"
    case domainNotResolved = "DomainNotResolved"
    case walletNotInitialized = "WalletNotInitialized"
    case invalidAddressFormat = "InvalidAddressFormat"
    case inactiveContract = "InactiveContract"

    // Transaction
    case partialTransactionFailure = "PartialTransactionFailure"
    case incorrectDeviceTime = "IncorrectDeviceTime"
    case unsuccessfulTransfer = "UnsuccessfulTransfer"
    case notSupportedHardwareOperation = "NotSupportedHardwareOperation"
    case hardwareBlindSigningNotEnabled = "HardwareBlindSigningNotEnabled"
    case wrongAddress = "WrongAddress"
    case wrongNetwork = "WrongNetwork"

    // TransactionDraft/Transaction
    case insufficientBalance = "InsufficientBalance"
    
    // Hardware
    /** Used when the chain's Ledger app needs to be updated to support this transaction */
    case hardwareOutdated = "HardwareOutdated"
    case blindSigningNotEnabled = "BlindSigningNotEnabled"
    case rejectedByUser = "RejectedByUser"
    case proofTooLarge = "ProofTooLarge"
    case connectionBroken = "ConnectionBroken"
    case wrongDevice = "WrongDevice"
    
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
