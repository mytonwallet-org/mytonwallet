const mockResolveExtensionAddress = jest.fn();
const mockFetchStoredChainAccount = jest.fn();
const mockUpdateStoredWallet = jest.fn();

jest.mock('../chains', () => ({
  __esModule: true,
  default: { ton: { mfa: { resolveExtensionAddress: (...args: unknown[]) => mockResolveExtensionAddress(...args) } } },
}));

jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
  fetchStoredAddress: jest.fn(),
  fetchStoredChainAccount: (...args: unknown[]) => mockFetchStoredChainAccount(...args),
  setAccountValue: jest.fn(),
  updateStoredWallet: (...args: unknown[]) => mockUpdateStoredWallet(...args),
}));

jest.mock('../common/mfa', () => ({}));

jest.mock('./other', () => ({
  getBackendAuthToken: jest.fn(),
  getStoredBackendAuthToken: jest.fn(() => Promise.resolve(undefined)),
}));

import type { ApiMfa } from '../types';

import { initMfa, refreshMfaStateAndNotify } from './mfa';

const ACCOUNT_ID = '4-mainnet';
const MFA_ADDRESS = '0:38976748c39aa4c7e2f5b5fb13680c4283554df6611caddc25081546d70397c0';

describe('refreshMfaStateAndNotify', () => {
  const onUpdate = jest.fn();
  let storedMfa: ApiMfa | undefined;

  beforeEach(() => {
    initMfa(onUpdate);
    storedMfa = undefined;
    mockFetchStoredChainAccount.mockImplementation(() => Promise.resolve({
      byChain: { ton: { address: 'wallet', mfa: storedMfa } },
    }));
    mockUpdateStoredWallet.mockImplementation((_accountId, _chain, { mfa }: { mfa?: ApiMfa }) => {
      storedMfa = mfa;
      return Promise.resolve();
    });
  });

  afterEach(() => {
    onUpdate.mockReset();
    mockResolveExtensionAddress.mockReset();
    mockFetchStoredChainAccount.mockReset();
    mockUpdateStoredWallet.mockReset();
  });

  it('reports MFA that the storage already has when nothing was reported yet', async () => {
    storedMfa = { address: MFA_ADDRESS };
    mockResolveExtensionAddress.mockResolvedValue(MFA_ADDRESS);

    const reportedMfa = await refreshMfaStateAndNotify(ACCOUNT_ID);

    expect(mockUpdateStoredWallet).not.toHaveBeenCalled();
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateAccount',
      accountId: ACCOUNT_ID,
      chain: 'ton',
      mfa: { address: MFA_ADDRESS },
    });
    expect(reportedMfa).toEqual({ address: MFA_ADDRESS });
  });

  it('does not report the state it reported before', async () => {
    storedMfa = { address: MFA_ADDRESS };
    mockResolveExtensionAddress.mockResolvedValue(MFA_ADDRESS);

    await refreshMfaStateAndNotify(ACCOUNT_ID, { address: MFA_ADDRESS });

    expect(onUpdate).not.toHaveBeenCalled();
  });

  it('reports the removal of MFA it reported before', async () => {
    storedMfa = { address: MFA_ADDRESS };
    mockResolveExtensionAddress.mockResolvedValue(undefined);

    const reportedMfa = await refreshMfaStateAndNotify(ACCOUNT_ID, { address: MFA_ADDRESS });

    expect(storedMfa).toBeUndefined();
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateAccount',
      accountId: ACCOUNT_ID,
      chain: 'ton',
      mfa: false,
    });
    expect(reportedMfa).toBe(false);
  });

  it('reports the removal of MFA that another flow stored after the absence was reported', async () => {
    storedMfa = { address: MFA_ADDRESS };
    mockResolveExtensionAddress.mockResolvedValue(undefined);

    const reportedMfa = await refreshMfaStateAndNotify(ACCOUNT_ID, false);

    expect(storedMfa).toBeUndefined();
    expect(onUpdate).toHaveBeenCalledWith({
      type: 'updateAccount',
      accountId: ACCOUNT_ID,
      chain: 'ton',
      mfa: false,
    });
    expect(reportedMfa).toBe(false);
  });

  it('does not report the absence of MFA it reported before', async () => {
    mockResolveExtensionAddress.mockResolvedValue(undefined);

    await refreshMfaStateAndNotify(ACCOUNT_ID, false);

    expect(onUpdate).not.toHaveBeenCalled();
  });
});
