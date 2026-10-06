import type { SolanaStandardWallet, StandardWalletAddress } from './solanaConnector';

import { registerSolanaInjectedWallet } from './solanaConnector';

const ACCOUNT: StandardWalletAddress = {
  address: '11111111111111111111111111111112',
  publicKey: new Uint8Array([0, 1]),
  chains: ['solana:mainnet'],
  features: ['solana:signTransaction'],
};
const UNSIGNED = new Uint8Array([1]);
const SIGNED = new Uint8Array([2]);

class FakeLegacyTransaction {
  constructor(public bytes: Uint8Array) {}

  serialize = jest.fn(() => this.bytes);

  static from(bytes: Uint8Array) {
    return new FakeLegacyTransaction(bytes);
  }
}

class FakeVersionedTransaction {
  constructor(public bytes: Uint8Array) {}

  serialize() {
    return this.bytes;
  }

  static deserialize(bytes: Uint8Array) {
    return new FakeVersionedTransaction(bytes);
  }
}

function createWallet(): SolanaStandardWallet {
  const wallet: SolanaStandardWallet = {
    version: '1.0.0',
    name: 'Test',
    icon: '',
    chains: ['solana:mainnet'],
    accounts: [],
    features: {
      'standard:connect': {
        version: '1.0.0',
        connect: jest.fn(() => {
          wallet.accounts = [ACCOUNT];
          return Promise.resolve({ accounts: wallet.accounts });
        }),
      },
      'standard:disconnect': { version: '1.0.0', disconnect: jest.fn() },
      'standard:events': { version: '1.0.0', on: jest.fn() },
      'solana:signTransaction': {
        version: '1.0.0',
        supportedTransactionVersions: ['legacy', 0],
        signTransaction: jest.fn(() => Promise.resolve([{ signedTransaction: SIGNED }])),
      },
      'solana:signMessage': { version: '1.0.0', signMessage: jest.fn() },
      'solana:signIn': { version: '1.0.0', signIn: jest.fn() },
    },
  };

  return wallet;
}

describe('registerSolanaInjectedWallet', () => {
  let errors: unknown[];
  const onError = (e: ErrorEvent) => {
    e.preventDefault();
    errors.push(e.error);
  };

  beforeEach(() => {
    jest.useFakeTimers();
    errors = [];
    window.addEventListener('error', onError);
    delete (window as Partial<Window>).solana;
  });

  afterEach(() => {
    window.removeEventListener('error', onError);
    jest.useRealTimers();
  });

  describe('Wallet Standard handshake', () => {
    it('does not break wallets that listen for `app-ready` like `@wallet-standard/wallet`', () => {
      const otherWalletListener = ({ detail }: any) => {
        detail.register({ name: 'Other' });
      };
      window.addEventListener('wallet-standard:app-ready', otherWalletListener);

      registerSolanaInjectedWallet(createWallet());
      window.removeEventListener('wallet-standard:app-ready', otherWalletListener);

      expect(errors).toEqual([]);
    });

    it('registers with an app that announces itself after the wallet', () => {
      const wallet = createWallet();
      registerSolanaInjectedWallet(wallet);

      const register = jest.fn();
      // `@wallet-standard/app` dispatches a plain `Event` subclass with a `detail` getter
      const appReady = Object.assign(new Event('wallet-standard:app-ready'), { detail: { register } });
      window.dispatchEvent(appReady);

      expect(register).toHaveBeenCalledWith(wallet);
    });

    it('ignores `app-ready` without a `register` function', () => {
      registerSolanaInjectedWallet(createWallet());

      window.dispatchEvent(new CustomEvent('wallet-standard:app-ready', { detail: () => undefined }));

      expect(errors).toEqual([]);
    });
  });

  describe('legacy `window.solana`', () => {
    it('returns a public key that formats as the base58 address', async () => {
      registerSolanaInjectedWallet(createWallet());

      const result = await window.solana.connect({});

      expect(result?.publicKey.toBase58()).toBe(ACCOUNT.address);
      expect(String(result?.publicKey)).toBe(ACCOUNT.address);
      expect(Array.from(result!.publicKey)).toEqual(Array.from(ACCOUNT.publicKey));
    });

    it('signs a legacy transaction as the connected account and returns the same kind', async () => {
      const wallet = createWallet();
      registerSolanaInjectedWallet(wallet);
      await window.solana.connect({});

      const tx = new FakeLegacyTransaction(UNSIGNED);
      const signed = await window.solana.signTransaction(tx);

      expect(tx.serialize).toHaveBeenCalledWith({ requireAllSignatures: false, verifySignatures: false });
      expect(wallet.features['solana:signTransaction'].signTransaction)
        .toHaveBeenCalledWith({ account: ACCOUNT, transaction: UNSIGNED });
      expect(signed).toBeInstanceOf(FakeLegacyTransaction);
      expect(signed.bytes).toBe(SIGNED);
    });

    it('signs every transaction in `signAllTransactions` one at a time', async () => {
      const wallet = createWallet();
      registerSolanaInjectedWallet(wallet);
      await window.solana.connect({});

      const signed = await window.solana.signAllTransactions([
        new FakeVersionedTransaction(UNSIGNED),
        new FakeVersionedTransaction(UNSIGNED),
      ]);

      expect(wallet.features['solana:signTransaction'].signTransaction).toHaveBeenCalledTimes(2);
      expect(signed).toHaveLength(2);
      signed.forEach((tx) => {
        expect(tx).toBeInstanceOf(FakeVersionedTransaction);
        expect(tx.bytes).toBe(SIGNED);
      });
    });

    it('rejects signing before connect', async () => {
      registerSolanaInjectedWallet(createWallet());

      await expect(window.solana.signTransaction(new FakeVersionedTransaction(UNSIGNED)))
        .rejects.toThrow('Wallet is not connected');
    });
  });
});
