import {
  type ApiAnyDisplayError,
  ApiAuthError,
  ApiCommonError,
  ApiHardwareError,
  ApiTransactionDraftError,
  ApiTransactionError,
} from '../../api/types';

/** Returns `true` if the error should be shown in the <PasswordForm /> or <LedgerConfirmOperation /> screen instead of a dialog */
export function isInlineError(error: ApiAnyDisplayError | string | undefined) {
  const _error = error as ApiAnyDisplayError;
  return _error === ApiCommonError.InvalidPassword
    || _error === ApiHardwareError.HardwareOutdated
    || _error === ApiHardwareError.BlindSigningNotEnabled
    || _error === ApiHardwareError.RejectedByUser;
}

export function errorCodeToMessage(error: ApiAnyDisplayError | string = ApiCommonError.Unexpected): string {
  const _error = error as ApiAnyDisplayError;
  switch (_error) {
    case ApiTransactionDraftError.InvalidAmount:
      return 'Invalid amount';

    case ApiAuthError.InvalidAddress:
    case ApiTransactionDraftError.InvalidToAddress:
      return 'Invalid address';

    case ApiTransactionDraftError.InvalidStateInit:
      return '$state_init_invalid';

    case ApiTransactionDraftError.InsufficientBalance:
      return 'Insufficient balance';

    case ApiAuthError.DomainNotResolved:
    case ApiTransactionDraftError.DomainNotResolved:
      return 'Domain is not connected to a wallet';

    case ApiTransactionDraftError.WalletNotInitialized:
      return 'Encryption is not possible. The recipient is not a wallet or has no outgoing transactions.';

    case ApiTransactionDraftError.InvalidAddressFormat:
      return 'Invalid address format. Only URL Safe Base64 format is allowed.';

    case ApiTransactionError.PartialTransactionFailure:
      return 'Not all transactions were sent successfully';

    case ApiTransactionError.IncorrectDeviceTime:
      return 'The time on your device is incorrect, sync it and try again';

    case ApiTransactionError.UnsuccesfulTransfer:
      return 'Transfer was unsuccessful. Try again later.';

    case ApiTransactionError.ConcurrentTransaction:
      return 'Another transaction was sent from this wallet simultaneously. Please try again.';

    case ApiTransactionDraftError.InactiveContract:
      return '$transfer_inactive_contract_error';

    case ApiHardwareError.HardwareOutdated:
      return '$ledger_outdated';

    case ApiHardwareError.BlindSigningNotEnabled:
      return '$hardware_blind_sign_not_enabled_internal';

    case ApiHardwareError.RejectedByUser:
      return 'Canceled by the user';

    case ApiHardwareError.ProofTooLarge:
      return 'The proof for signing provided by the Dapp is too large';

    case ApiCommonError.ServerError:
      return window.navigator.onLine
        ? 'An error on the server side. Please try again.'
        : 'No internet connection. Please check your connection and try again.';

    case ApiCommonError.DebugError:
      return 'Unexpected error. Please let the support know.';

    case ApiCommonError.Unexpected:
      return 'Unexpected';

    case ApiCommonError.InvalidPassword:
      return 'Wrong password, please try again.';

    default:
      return error;
  }
}
