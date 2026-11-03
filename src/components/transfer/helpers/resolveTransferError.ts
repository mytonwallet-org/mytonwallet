import type { ApiAnyDisplayError } from '../../../api/types';
import { ApiCommonError } from '../../../api/types';

export type TransferError =
  | 'multisig'
  | 'invalidAddress'
  | 'domainNotFound'
  | 'insufficientBalance'
  | 'insufficientFee';

interface Params {
  isMultisig: boolean;
  hasAddressFormatError: boolean;
  toAddressError?: ApiAnyDisplayError;
  isAmountGreaterThanBalance: boolean;
  hasInsufficientFeeError: boolean;
}

/**
 * Picks the reason the transfer can't be sent, to be shown on the submit button. When several reasons apply, the one
 * the user should resolve first wins: an address error is shown even when the amount exceeds the balance.
 */
export function resolveTransferError({
  isMultisig,
  hasAddressFormatError,
  toAddressError,
  isAmountGreaterThanBalance,
  hasInsufficientFeeError,
}: Params): TransferError | undefined {
  if (isMultisig) return 'multisig';
  if (hasAddressFormatError) return 'invalidAddress';
  if (toAddressError) return toAddressError === ApiCommonError.DomainNotResolved ? 'domainNotFound' : 'invalidAddress';
  if (isAmountGreaterThanBalance) return 'insufficientBalance';
  if (hasInsufficientFeeError) return 'insufficientFee';

  return undefined;
}
