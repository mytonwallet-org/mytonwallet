import type { ApiPerpsOperation } from '../../api/types';

import { persistCache } from '../cache';
import { getGlobal, setGlobal } from '../index';
import { updatePerpsOperation } from '../reducers';

const PRE_SUBMISSION_ERRORS = [
  'PerpsUnchanged', 'PerpsQuoteExpired', 'PerpsUnsupportedAccount', 'PerpsOperationPending', 'PerpsInvalidOperation',
];

export function persistPerpsSubmission(operation: ApiPerpsOperation) {
  const previous = getGlobal();
  const updated = updatePerpsOperation(previous, operation);
  if (updated === previous) throw new Error('Wallet is unavailable.');

  setGlobal(updated);
  try {
    if (!persistCache()) throw new Error('Could not save the operation. Please retry before submitting.');
  } catch (err) {
    setGlobal({ ...getGlobal(), byAccountId: previous.byAccountId });
    throw err;
  }
}

export function getPerpsOperationAfterSubmissionError(
  operation: ApiPerpsOperation, message: string, isWithdrawal: boolean,
): ApiPerpsOperation {
  if (operation.state !== 'running') return operation;
  const rejected = PRE_SUBMISSION_ERRORS.find((code) => message.includes(code));
  return {
    ...operation,
    state: rejected ? isWithdrawal ? 'partial' : 'failed' : 'unknown',
    error: rejected ?? 'PerpsExecutionUnknown',
  };
}
