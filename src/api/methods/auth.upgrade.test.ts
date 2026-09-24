import type { ApiAccountAny, ApiBip39Account } from '../types';

import chains from '../chains';
import { fetchStoredAccount, fetchStoredAccounts, updateStoredAccount } from '../common/accounts';
import { getMnemonic } from '../common/mnemonic';
import { getMultichainUpgradeCandidateIds, initAuth, upgradeMultichainAccounts } from './auth';

jest.mock('../../util/chain', () => ({
  ...jest.requireActual('../../util/chain'),
  getSupportedChains: () => ['ton', 'arc'],
}));
jest.mock('../chains', () => ({
  __esModule: true,
  default: { arc: { getWalletFromBip39Mnemonic: jest.fn() } },
}));
jest.mock('../chains/ton', () => ({}));
jest.mock('../common/accounts', () => ({
  fetchStoredAccount: jest.fn(),
  fetchStoredAccounts: jest.fn(),
  updateStoredAccount: jest.fn(),
}));
jest.mock('../common/mnemonic', () => ({ getMnemonic: jest.fn() }));
jest.mock('../common/tokens', () => ({}));
jest.mock('../db', () => ({}));
jest.mock('../environment', () => ({}));
jest.mock('../storages', () => ({}));
jest.mock('./accounts', () => ({}));
jest.mock('./dapps', () => ({}));
jest.mock('./other', () => ({}));
jest.mock('./polling', () => ({}));

const tonWallet: ApiBip39Account['byChain']['ton'] = {
  address: 'ton-address',
  publicKey: 'ton-public-key',
  authToken: 'existing-auth-token',
  version: 'W5',
  index: 0,
  derivation: { path: 'ton-path', index: 0 },
};
const arcWallet: ApiBip39Account['byChain']['arc'] = {
  address: 'arc-address',
  publicKey: 'arc-public-key',
  index: 0,
  derivation: { path: 'evm-path', index: 0 },
};

let accounts: Record<string, ApiAccountAny>;
const onUpdate = jest.fn();

beforeEach(() => {
  jest.clearAllMocks();
  accounts = {
    '1-mainnet': { type: 'bip39', byChain: { ton: tonWallet } },
    '2-mainnet': { type: 'bip39', byChain: { ton: tonWallet } },
    '3-mainnet': { type: 'bip39', byChain: { ton: tonWallet, arc: arcWallet } },
    '4-mainnet': { type: 'view', byChain: { ton: { address: 'view-address', index: 0, version: 'W5' } } },
  };
  jest.mocked(fetchStoredAccounts).mockImplementation(() => Promise.resolve(accounts));
  jest.mocked(fetchStoredAccount).mockImplementation((accountId) => Promise.resolve(accounts[accountId] as any));
  jest.mocked(updateStoredAccount).mockImplementation((accountId, partial) => {
    accounts[accountId] = { ...accounts[accountId], ...partial } as ApiAccountAny;
    return Promise.resolve();
  });
  jest.mocked(getMnemonic).mockImplementation((accountId) => Promise.resolve(
    accountId === '1-mainnet' ? undefined : ['test', 'mnemonic'],
  ));
  jest.mocked(chains.arc.getWalletFromBip39Mnemonic).mockResolvedValue([arcWallet]);
  initAuth(onUpdate);
});

it('excludes SDK-only accounts from native upgrade candidates', async () => {
  expect(await getMultichainUpgradeCandidateIds(['2-mainnet', '3-mainnet', '4-mainnet', 'missing-mainnet']))
    .toEqual(['2-mainnet']);
});

it('upgrades the selected account without exporting the orphan secret or changing its record', async () => {
  const orphan = accounts['1-mainnet'];
  const candidateIds = await getMultichainUpgradeCandidateIds(['2-mainnet', '3-mainnet', '4-mainnet']);

  await expect(upgradeMultichainAccounts('enclave-token', candidateIds)).resolves.toBeUndefined();

  expect(getMnemonic).toHaveBeenCalledTimes(1);
  expect(getMnemonic).toHaveBeenCalledWith('2-mainnet', 'enclave-token');
  expect(chains.arc.getWalletFromBip39Mnemonic).toHaveBeenCalledWith(
    'mainnet', ['test', 'mnemonic'], undefined, true,
  );
  expect(accounts['2-mainnet'].byChain.arc).toEqual(arcWallet);
  expect(accounts['1-mainnet']).toBe(orphan);
  expect(onUpdate).toHaveBeenCalledWith(expect.objectContaining({
    type: 'updateAccount', accountId: '2-mainnet', chain: 'arc', address: 'arc-address',
  }));
  expect(await getMultichainUpgradeCandidateIds(['2-mainnet'])).toEqual([]);
});

it('treats an empty account list as no eligible accounts', async () => {
  expect(await getMultichainUpgradeCandidateIds([])).toEqual([]);
  await expect(upgradeMultichainAccounts('enclave-token', [])).resolves.toBeUndefined();
  expect(getMnemonic).not.toHaveBeenCalled();
  expect(updateStoredAccount).not.toHaveBeenCalled();
});

it('preserves unscoped callers when no account list is supplied', async () => {
  expect(await getMultichainUpgradeCandidateIds()).toEqual(['1-mainnet', '2-mainnet']);
  jest.mocked(getMnemonic).mockResolvedValue(['test', 'mnemonic']);

  await expect(upgradeMultichainAccounts('enclave-token')).resolves.toBeUndefined();

  expect(accounts['1-mainnet'].byChain.arc).toEqual(arcWallet);
  expect(accounts['2-mainnet'].byChain.arc).toEqual(arcWallet);
  expect(getMnemonic).toHaveBeenCalledTimes(2);
});
