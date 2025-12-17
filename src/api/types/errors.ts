export enum ApiCommonError {
  Unexpected = 'Unexpected',
  ServerError = 'ServerError',
  DebugError = 'DebugError',
  UnsupportedVersion = 'UnsupportedVersion',
  InvalidPassword = 'InvalidPassword',
  InvalidAddress = 'InvalidAddress',
  DomainNotResolved = 'DomainNotResolved',
}

export enum ApiAuthError {
  InvalidMnemonic = 'InvalidMnemonic',
}

export enum ApiTransactionDraftError {
  InvalidAmount = 'InvalidAmount',
  InvalidToAddress = 'InvalidToAddress',
  InsufficientBalance = 'InsufficientBalance',
  InvalidStateInit = 'InvalidStateInit',
  WalletNotInitialized = 'WalletNotInitialized',
  InvalidAddressFormat = 'InvalidAddressFormat',
  InactiveContract = 'InactiveContract',
}

export enum ApiTransactionError {
  PartialTransactionFailure = 'PartialTransactionFailure',
  IncorrectDeviceTime = 'IncorrectDeviceTime',
  InsufficientBalance = 'InsufficientBalance',
  UnsuccesfulTransfer = 'UnsuccesfulTransfer',
  WrongAddress = 'WrongAddress',
  WrongNetwork = 'WrongNetwork',
  ConcurrentTransaction = 'ConcurrentTransaction',
}

export enum ApiHardwareError {
  /** Used when the chain's Ledger app needs to be updated to support this transaction */
  HardwareOutdated = 'HardwareOutdated',
  BlindSigningNotEnabled = 'BlindSigningNotEnabled',
  RejectedByUser = 'RejectedByUser',
  ProofTooLarge = 'ProofTooLarge',
  ConnectionBroken = 'ConnectionBroken',
  WrongDevice = 'WrongDevice',
}

export enum ApiTokenImportError {
  AddressDoesNotExist = 'AddressDoesNotExist',
  NotATokenAddress = 'NotATokenAddress',
}

export type ApiAnyDisplayError =
  | ApiCommonError
  | ApiAuthError
  | ApiTransactionDraftError
  | ApiTransactionError
  | ApiHardwareError
  | ApiTokenImportError;
