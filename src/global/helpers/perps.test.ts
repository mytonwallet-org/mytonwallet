import type { ApiPerpsOperation } from '../../api/types';

import { persistCache } from '../cache';
import { getGlobal, setGlobal } from '../index';
import { INITIAL_STATE } from '../initialState';
import { getPerpsOperationAfterSubmissionError, persistPerpsSubmission } from './perps';

jest.mock('../cache', () => ({ persistCache: jest.fn() }));

const OPERATION: ApiPerpsOperation = {
  id: 'reduce-1', accountId: '0-mainnet', assetId: 'hyperliquid:hl:BTC', kind: 'reduce',
  state: 'running', stage: 'preparing', createdAt: 1, orderId: 123, withdrawalRequestedAmount: '5.123456',
};

it.each(['PerpsQuoteExpired', 'PerpsOperationPending', 'PerpsUnsupportedAccount', 'PerpsInvalidOperation'])(
  'keeps withdrawal-only recovery after %s', (error) => {
    expect(getPerpsOperationAfterSubmissionError(OPERATION, error, true)).toEqual({
      ...OPERATION, state: 'partial', error,
    });
  },
);

it('keeps an uncertain withdrawal blocked instead of making it retryable', () => {
  expect(getPerpsOperationAfterSubmissionError(OPERATION, 'Worker disconnected', true).state).toBe('unknown');
});

it.each(['disabled', 'quota'])('rejects a submission when its journal cannot persist (%s)', (failure) => {
  const previous = {
    ...INITIAL_STATE,
    accounts: { byId: { [OPERATION.accountId]: { type: 'mnemonic' as const, byChain: {} } } },
    byAccountId: { [OPERATION.accountId]: {} },
  };
  setGlobal(previous);
  jest.mocked(persistCache).mockImplementation(() => {
    if (failure === 'quota') throw new Error('QuotaExceededError');
    return false;
  });

  expect(() => persistPerpsSubmission(OPERATION)).toThrow();
  expect(getGlobal().byAccountId).toBe(previous.byAccountId);
});
