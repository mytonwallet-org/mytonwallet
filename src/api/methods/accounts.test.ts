import { logDebugError } from '../../util/logs';
import { fetchMaybeStoredAccount, fetchStoredAccounts, getCurrentAccountId } from '../common/accounts';
import { callHook } from '../hooks';
import { storage } from '../storages';
import { activateAccount, deactivateAllAccounts, initAccounts, loadAccountsWalletVersions } from './accounts';
import { setActivePollingAccount } from './polling';

jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'),
  IS_EXTENSION: true,
}));
jest.mock('../common/accounts', () => ({
  fetchMaybeStoredAccount: jest.fn(),
  fetchStoredAccount: jest.fn(),
  fetchStoredAccounts: jest.fn(),
  getAccountChains: jest.fn().mockReturnValue({}),
  getCurrentAccountId: jest.fn(),
  loginResolve: jest.fn(),
  updateStoredWallet: jest.fn(),
}));
jest.mock('../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./polling', () => ({ setActivePollingAccount: jest.fn() }));
jest.mock('../storages', () => ({
  storage: {
    getItem: jest.fn(),
    setItem: jest.fn(),
    removeItem: jest.fn(),
  },
}));
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));

const CURRENT_ACCOUNT_ID = '0-ton-mainnet';
const MISSING_ACCOUNT_ID = '1-ton-mainnet';

// The activation reports the divergence without waiting for it, so the assertions run once the queue is drained.
function flushDetachedWork() {
  return new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
}

describe('activateAccount', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.mocked(getCurrentAccountId).mockResolvedValue(CURRENT_ACCOUNT_ID);
    jest.mocked(fetchStoredAccounts).mockResolvedValue({ [CURRENT_ACCOUNT_ID]: {} as any });
  });

  it('reports an account the worker storage does not have', async () => {
    jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(undefined);

    await activateAccount(MISSING_ACCOUNT_ID);
    await flushDetachedWork();

    expect(logDebugError).toHaveBeenCalledWith(
      'activateAccount: the account is missing from the worker storage',
      {
        accountId: MISSING_ACCOUNT_ID,
        prevAccountId: CURRENT_ACCOUNT_ID,
        storedAccountIds: [CURRENT_ACCOUNT_ID],
      },
    );
  });

  it('activates the account it was asked for, missing or not', async () => {
    jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(undefined);

    await activateAccount(MISSING_ACCOUNT_ID);
    await flushDetachedWork();

    expect(setActivePollingAccount).toHaveBeenCalledWith(MISSING_ACCOUNT_ID, {}, undefined);
  });

  it('keeps the report readable when there is no account to come back to', async () => {
    jest.mocked(getCurrentAccountId).mockResolvedValue(undefined);
    jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(undefined);
    jest.mocked(fetchStoredAccounts).mockResolvedValue({});

    await activateAccount(MISSING_ACCOUNT_ID);
    await flushDetachedWork();

    expect(logDebugError).toHaveBeenCalledWith(
      'activateAccount: the account is missing from the worker storage',
      {
        accountId: MISSING_ACCOUNT_ID,
        prevAccountId: 'none',
        storedAccountIds: [],
      },
    );
  });

  it('says nothing when both stores hold the account', async () => {
    jest.mocked(fetchMaybeStoredAccount).mockResolvedValue({} as any);

    await activateAccount(CURRENT_ACCOUNT_ID);
    await flushDetachedWork();

    expect(logDebugError).not.toHaveBeenCalled();
  });

  it('never lets the diagnostics break the activation', async () => {
    const error = new Error('storage is unavailable');
    jest.mocked(fetchMaybeStoredAccount).mockRejectedValue(error);

    await expect(activateAccount(MISSING_ACCOUNT_ID)).resolves.toBeUndefined();
    await flushDetachedWork();

    expect(setActivePollingAccount).toHaveBeenCalledWith(MISSING_ACCOUNT_ID, {}, undefined);
    expect(logDebugError).toHaveBeenCalledWith(
      'activateAccount: failed to inspect the worker account storage',
      MISSING_ACCOUNT_ID,
      error,
    );
  });
});

describe('deactivateAllAccounts', () => {
  it('only retires account activity and never owns dApp deletion', async () => {
    jest.clearAllMocks();
    await deactivateAllAccounts();

    expect(setActivePollingAccount).toHaveBeenCalledWith(undefined, {});
    expect(storage.removeItem).toHaveBeenCalledWith('currentAccountId');
    expect(callHook).not.toHaveBeenCalled();
  });
});

describe('loadAccountsWalletVersions', () => {
  it('sends the stored version of each requested TON wallet that has one', async () => {
    const onUpdate = jest.fn();
    initAccounts(onUpdate);
    jest.mocked(fetchStoredAccounts).mockResolvedValue({
      '0-mainnet': { byChain: { ton: { address: 'UQ0', version: 'W5' } } },
      '1-mainnet': { byChain: { ton: { address: 'EQ1' } } },
      '2-mainnet': { byChain: { tron: { address: 'T2' } } },
      '3-mainnet': { byChain: { ton: { address: 'UQ3', version: 'v4R2' } } },
    } as any);

    await loadAccountsWalletVersions(['0-mainnet', '1-mainnet', '2-mainnet', 'removed-mainnet']);

    expect(onUpdate.mock.calls).toEqual([
      [{ type: 'updateAccount', accountId: '0-mainnet', chain: 'ton', version: 'W5' }],
    ]);
  });
});
