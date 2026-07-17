import { ApiServerError } from '../errors';
import { importMnemonic } from './auth';

jest.mock('../chains', () => ({
  __esModule: true,
  default: {
    ton: { getWalletFromBip39Mnemonic: jest.fn() },
  },
}));

jest.mock('../chains/ton', () => ({
  __esModule: true,
  validateMnemonic: jest.fn(),
  getWalletFromMnemonic: jest.fn(),
  generateMnemonic: jest.fn(),
}));

jest.mock('../common/mnemonic', () => ({
  validateBip39Mnemonic: jest.fn(),
  encryptMnemonic: jest.fn().mockResolvedValue('encrypted'),
  decryptMnemonic: jest.fn().mockResolvedValue(['word']),
  generateBip39Mnemonic: jest.fn(),
  getMnemonic: jest.fn(),
}));

jest.mock('../common/accounts', () => ({
  getNewAccountId: jest.fn(),
  setAccountValue: jest.fn(),
  getAccountChains: jest.fn().mockReturnValue({}),
  fetchStoredAccount: jest.fn(),
  fetchStoredAccounts: jest.fn(),
  fetchStoredChainAccount: jest.fn(),
  removeAccountValue: jest.fn(),
  removeNetworkAccountsValue: jest.fn(),
  updateStoredAccount: jest.fn(),
  updateStoredWallet: jest.fn(),
}));

jest.mock('./accounts', () => ({
  activateAccount: jest.fn(),
  deactivateAllAccounts: jest.fn(),
}));

jest.mock('./polling', () => ({
  addPollingAccount: jest.fn(),
  removeAllPollingAccounts: jest.fn(),
  removeNetworkPollingAccounts: jest.fn(),
  removePollingAccount: jest.fn(),
}));

jest.mock('../common/tokens', () => ({ sendUpdateTokens: jest.fn() }));
jest.mock('../db', () => ({ tokenRepository: {} }));
jest.mock('../environment', () => ({ getEnvironment: jest.fn().mockReturnValue({}) }));
jest.mock('../storages', () => ({
  storage: { getItem: jest.fn(), setItem: jest.fn(), mutateItem: jest.fn() },
}));

// eslint-disable-next-line @typescript-eslint/no-require-imports
const ton = require('../chains/ton') as {
  validateMnemonic: jest.Mock;
  getWalletFromMnemonic: jest.Mock;
};
// eslint-disable-next-line @typescript-eslint/no-require-imports
const chains = require('../chains').default as { ton: { getWalletFromBip39Mnemonic: jest.Mock } };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { validateBip39Mnemonic } = require('../common/mnemonic') as { validateBip39Mnemonic: jest.Mock };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const { setAccountValue, getNewAccountId } = require('../common/accounts') as {
  setAccountValue: jest.Mock;
  getNewAccountId: jest.Mock;
};

// A phrase that validates as both a TON-native and a BIP39 mnemonic (~1/256): the only tiebreaker between the two
// derivations, which yield different addresses, is whether the TON derivation has on-chain history.
const DUAL_VALID = ['dual', 'valid', 'phrase'];

// Let any promise that the aborted import left detached (a sibling network branch still running) settle, so the
// assertion sees writes that happen after the error is returned rather than racing them.
const flushPromises = () => new Promise((resolve) => {
  setTimeout(resolve, 0);
});

describe('importMnemonic', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    validateBip39Mnemonic.mockReturnValue(true);
    ton.validateMnemonic.mockResolvedValue(true);
    chains.ton.getWalletFromBip39Mnemonic.mockResolvedValue([
      { address: 'EQ-bip39', publicKey: 'pk', version: 'W5', index: 0 },
    ]);
    getNewAccountId.mockImplementation((network: string) => Promise.resolve(`0-${network}`));
    setAccountValue.mockResolvedValue(undefined);
  });

  it('aborts with a server error and persists nothing when the history probe cannot reach the node', async () => {
    ton.getWalletFromMnemonic.mockRejectedValue(new ApiServerError('node unreachable'));

    const result = await importMnemonic(['mainnet'], DUAL_VALID, 'password');

    // A failed probe must surface as a retriable error, never fall through to a silent BIP39 import at a
    // different address than the user's funded TON wallet.
    expect(result).toEqual({ error: expect.any(String) });
    expect(setAccountValue).not.toHaveBeenCalled();
    expect(ton.getWalletFromMnemonic).toHaveBeenCalledWith('mainnet', DUAL_VALID, false);
  });

  it('persists no account on any network when the probe fails for one of several networks', async () => {
    ton.getWalletFromMnemonic.mockImplementation((network: string) => (
      network === 'testnet'
        ? Promise.reject(new ApiServerError('node unreachable'))
        : Promise.resolve({ address: 'EQ-ton', publicKey: 'pk', version: 'W5', index: 0 })
    ));

    const result = await importMnemonic(['mainnet', 'testnet'], DUAL_VALID, 'password');
    await flushPromises();

    // The multi-network import derives every network before writing, so a transient failure on one network
    // cannot leave a ghost account behind on the other (which a retry would duplicate and which would shadow
    // `verifyPassword`). Flushing first defeats the version where the surviving branch persists after the error.
    expect(result).toEqual({ error: expect.any(String) });
    expect(setAccountValue).not.toHaveBeenCalled();
  });

  it('imports the TON derivation when its address has on-chain history', async () => {
    ton.getWalletFromMnemonic.mockResolvedValue({
      address: 'EQ-ton', publicKey: 'pk', version: 'W5', index: 0, lastTxId: 'tx1',
    });

    await importMnemonic(['mainnet'], DUAL_VALID, 'password');

    expect(setAccountValue).toHaveBeenCalledWith('0-mainnet', 'accounts', expect.objectContaining({ type: 'ton' }));
  });
});
