import { fetchMaybeStoredAccount, getCurrentAccountId, loginResolve } from '../common/accounts';
import { storage } from '../storages';
import { restoreAccountAfterInitialization } from './accounts';
import { setActivePollingAccount } from './polling';
import { waitDataPreload } from './preload';

jest.mock('../common/accounts', () => ({
  fetchMaybeStoredAccount: jest.fn(), getCurrentAccountId: jest.fn(), loginResolve: jest.fn(),
}));
jest.mock('../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../hooks', () => ({ callHook: jest.fn() }));
jest.mock('./polling', () => ({ setActivePollingAccount: jest.fn() }));
jest.mock('./preload', () => ({ waitDataPreload: jest.fn() }));
jest.mock('../storages', () => ({ storage: { setItem: jest.fn(), removeItem: jest.fn() } }));
jest.mock('../../util/logs', () => ({ logDebugError: jest.fn() }));

const UI_ID = '0-ton-mainnet';
const SDK_ID = '1-mainnet';
const descriptor = {
  accountId: UI_ID,
  type: 'mnemonic' as const,
  addressByChain: { ton: 'EQpublic-a' },
};
const accounts: Record<string, any> = {
  [UI_ID]: { type: 'ton', byChain: { ton: { address: descriptor.addressByChain.ton } } },
  [SDK_ID]: { type: 'bip39', byChain: { ton: { address: 'EQpublic-b' } } },
};

beforeEach(() => {
  jest.clearAllMocks();
  jest.mocked(waitDataPreload).mockResolvedValue(undefined);
  jest.mocked(storage.setItem).mockResolvedValue(undefined);
  jest.mocked(storage.removeItem).mockResolvedValue(undefined);
  jest.mocked(getCurrentAccountId).mockResolvedValue(SDK_ID);
  jest.mocked(fetchMaybeStoredAccount).mockImplementation((id) => Promise.resolve(accounts[id]));
});

it('restores the exact UI account even when a previous SDK selection differs', async () => {
  await restoreAccountAfterInitialization(descriptor);
  expect(storage.setItem).toHaveBeenCalledWith('currentAccountId', UI_ID);
  expect(loginResolve).toHaveBeenCalledTimes(1);
  expect(setActivePollingAccount).toHaveBeenCalledWith(UI_ID, {}, undefined);
});

it.each([
  { ...descriptor, accountId: 'missing-mainnet' },
  { ...descriptor, type: 'view' as const },
  { ...descriptor, addressByChain: { ton: 'EQdifferent' } },
])('rejects a conflicting UI descriptor without writing currentAccountId: %j', async (current) => {
  await expect(restoreAccountAfterInitialization(current)).rejects.toThrow('account');
  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
});

it('does not force a stored account into a fresh empty UI', async () => {
  await restoreAccountAfterInitialization(undefined);
  expect(storage.setItem).not.toHaveBeenCalled();
});

it('restores and resolves login while network preload remains pending', async () => {
  jest.mocked(waitDataPreload).mockReturnValue(new Promise(() => undefined));
  await restoreAccountAfterInitialization(descriptor);
  expect(waitDataPreload).not.toHaveBeenCalled();
  expect(loginResolve).toHaveBeenCalledTimes(1);
  expect(setActivePollingAccount).toHaveBeenCalledWith(UI_ID, {}, undefined);
});

it('does not report login or start polling when the activation write fails', async () => {
  jest.mocked(storage.setItem).mockRejectedValue(new Error('write failed'));
  await expect(restoreAccountAfterInitialization(descriptor)).rejects.toThrow('write failed');
  expect(loginResolve).not.toHaveBeenCalled();
  expect(setActivePollingAccount).not.toHaveBeenCalled();
});

it.each([
  {
    sdk: { type: 'view', byChain: { ethereum: { address: '0x1111111111111111111111111111111111111111' } } },
    current: {
      accountId: UI_ID,
      type: 'view' as const,
      addressByChain: { ethereum: '0x1111111111111111111111111111111111111111' },
    },
  },
  {
    sdk: { type: 'ledger', byChain: { bitcoin: { address: 'bc1-public-ledger' } } },
    current: {
      accountId: UI_ID, type: 'hardware' as const, addressByChain: { bitcoin: 'bc1-public-ledger' },
    },
  },
  {
    sdk: { type: 'bip39', byChain: { solana: { address: 'public-solana-address' } } },
    current: {
      accountId: UI_ID, type: 'mnemonic' as const, addressByChain: { solana: 'public-solana-address' },
    },
  },
])('restores an exact $sdk.type account through its populated chain identity', async ({ sdk, current }) => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(sdk as never);
  await restoreAccountAfterInitialization(current);
  expect(storage.setItem).toHaveBeenCalledWith('currentAccountId', UI_ID);
});

it('rejects an EVM view account whose address differs without activating it', async () => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue({
    type: 'view',
    byChain: { ethereum: { address: '0x2222222222222222222222222222222222222222' } },
  } as never);

  await expect(restoreAccountAfterInitialization({
    accountId: UI_ID,
    type: 'view',
    addressByChain: { ethereum: '0x1111111111111111111111111111111111111111' },
  })).rejects.toThrow('account');

  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
  expect(setActivePollingAccount).not.toHaveBeenCalled();
});

it('accepts SDK-enriched chains when every UI identity matches', async () => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue({
    type: 'view',
    byChain: {
      ethereum: { address: '0x1111111111111111111111111111111111111111' },
      base: { address: '0x1111111111111111111111111111111111111111' },
    },
  } as never);

  await restoreAccountAfterInitialization({
    accountId: UI_ID,
    type: 'view',
    addressByChain: { ethereum: '0x1111111111111111111111111111111111111111' },
  });

  expect(storage.setItem).toHaveBeenCalledWith('currentAccountId', UI_ID);
});

it.each(['view', 'ledger', 'bip39'] as const)('rejects a %s account without a verifiable identity', async (type) => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue({ type, byChain: {} } as never);
  const uiType = type === 'ledger' ? 'hardware' : type === 'view' ? 'view' : 'mnemonic';

  await expect(restoreAccountAfterInitialization({
    accountId: UI_ID, type: uiType, addressByChain: {},
  })).rejects.toThrow('account');

  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
  expect(setActivePollingAccount).not.toHaveBeenCalled();
});

it.each([undefined, ''])('rejects a non-verifiable identity value: %p', async (address) => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue({
    type: 'view',
    byChain: address === undefined ? {} : { ethereum: { address } },
  } as never);

  await expect(restoreAccountAfterInitialization({
    accountId: UI_ID,
    type: 'view',
    addressByChain: { ethereum: address },
  })).rejects.toThrow('account');

  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
  expect(setActivePollingAccount).not.toHaveBeenCalled();
});

it('allows ordinary recovery of a missing SDK account without activating or deleting wallet data', async () => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(undefined);
  await restoreAccountAfterInitialization(descriptor, false);
  expect(storage.removeItem).toHaveBeenCalledTimes(1);
  expect(storage.removeItem).toHaveBeenCalledWith('currentAccountId');
  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
  expect(setActivePollingAccount).toHaveBeenCalledWith(undefined, {});
});

it('rejects ordinary recovery when deactivation cannot persist', async () => {
  jest.mocked(fetchMaybeStoredAccount).mockResolvedValue(undefined);
  jest.mocked(storage.removeItem).mockRejectedValue(new Error('deactivation failed'));
  await expect(restoreAccountAfterInitialization(descriptor, false)).rejects.toThrow('deactivation failed');
  expect(loginResolve).not.toHaveBeenCalled();
  expect(storage.setItem).not.toHaveBeenCalled();
});

it.each([
  { ...descriptor, type: 'view' as const },
  { ...descriptor, addressByChain: { ton: 'EQdifferent' } },
])('rejects a present conflicting account during ordinary recovery: %j', async (current) => {
  await expect(restoreAccountAfterInitialization(current, false)).rejects.toThrow('account');
  expect(storage.removeItem).not.toHaveBeenCalled();
  expect(storage.setItem).not.toHaveBeenCalled();
  expect(loginResolve).not.toHaveBeenCalled();
});
