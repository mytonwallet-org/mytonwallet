import { ApiCommonError, ApiTransactionDraftError } from '../../../api/types';

import { resolveTransferError } from './resolveTransferError';

const NO_ERRORS = {
  isMultisig: false,
  hasAddressFormatError: false,
  isAmountGreaterThanBalance: false,
  hasInsufficientFeeError: false,
};

describe('resolveTransferError', () => {
  it('returns nothing when the transfer can be sent', () => {
    expect(resolveTransferError(NO_ERRORS)).toBeUndefined();
  });

  it('shows the multisig restriction before any other reason', () => {
    expect(resolveTransferError({
      ...NO_ERRORS,
      isMultisig: true,
      hasAddressFormatError: true,
      isAmountGreaterThanBalance: true,
    })).toBe('multisig');
  });

  it('shows the address error even when the amount exceeds the balance', () => {
    expect(resolveTransferError({
      ...NO_ERRORS,
      hasAddressFormatError: true,
      isAmountGreaterThanBalance: true,
    })).toBe('invalidAddress');
  });

  it('tells an unresolved domain apart from other address errors of the draft check', () => {
    expect(resolveTransferError({
      ...NO_ERRORS,
      toAddressError: ApiCommonError.DomainNotResolved,
      isAmountGreaterThanBalance: true,
    })).toBe('domainNotFound');
    expect(resolveTransferError({ ...NO_ERRORS, toAddressError: ApiTransactionDraftError.InvalidToAddress }))
      .toBe('invalidAddress');
  });

  it('prefers the address format error to the draft check result', () => {
    expect(resolveTransferError({
      ...NO_ERRORS,
      hasAddressFormatError: true,
      toAddressError: ApiCommonError.DomainNotResolved,
    })).toBe('invalidAddress');
  });

  it('shows the balance shortage before the fee shortage', () => {
    expect(resolveTransferError({ ...NO_ERRORS, isAmountGreaterThanBalance: true, hasInsufficientFeeError: true }))
      .toBe('insufficientBalance');
    expect(resolveTransferError({ ...NO_ERRORS, hasInsufficientFeeError: true })).toBe('insufficientFee');
  });
});
