export enum ApiCommonError {
  Unexpected = 'Unexpected',
  ServerError = 'ServerError',
  DebugError = 'DebugError',
  UnsupportedVersion = 'UnsupportedVersion',
  InvalidPassword = 'InvalidPassword',
}

export enum ApiAuthError {
  InvalidMnemonic = 'InvalidMnemonic',
  InvalidAddress = 'InvalidAddress',
  DomainNotResolved = 'DomainNotResolved',
}

export enum ApiTransactionDraftError {
  InvalidAmount = 'InvalidAmount',
  InvalidToAddress = 'InvalidToAddress',
  InsufficientBalance = 'InsufficientBalance',
  InvalidStateInit = 'InvalidStateInit',
  DomainNotResolved = 'DomainNotResolved',
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
  /** Used when the Ledger TON app needs to be updated to support this transaction */
  HardwareOutdated = 'HardwareOutdated',
  BlindSigningNotEnabled = 'BlindSigningNotEnabled',
  RejectedByUser = 'RejectedByUser',
  ProofTooLarge = 'ProofTooLarge',
}

export type ApiAnyDisplayError =
  | ApiCommonError
  | ApiAuthError
  | ApiTransactionDraftError
  | ApiTransactionError
  | ApiHardwareError;
