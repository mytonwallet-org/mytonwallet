// Raw key bytes that also answer the `PublicKey` methods legacy `window.solana` callers use
type LegacyPublicKey = Uint8Array<ArrayBuffer> & {
  toBase58: () => string;
  toBytes: () => Uint8Array<ArrayBuffer>;
  toJSON: () => string;
};

declare global {
  interface Window {
    solana: {
      isMyTonWallet: boolean;
      publicKey: LegacyPublicKey | null;
      isConnected: boolean;
      connect: (options: any) => Promise<{
        publicKey: LegacyPublicKey;
      } | undefined>;
      disconnect: () => Promise<void>;
      signTransaction: (tx: any) => Promise<any>;
      signAllTransactions: (txs: any[]) => Promise<any[]>;
      on: (event: any, cb: any) => () => void;
    };
  }
}

export type SolanaRequestMethods =
  | 'connect'
  | 'reconnect'
  | 'sendTransaction'
  | 'signData'
  | 'disconnect'
  // EVM-only, but the request name lives on the same `walletConnect_*` namespace
  // and the dispatcher type is shared with EvmConnector.
  | 'proxyEvmRpc';

export interface StandardWalletAddress {
  address: string;
  publicKey: Uint8Array<ArrayBuffer>;
  chains: string[];
  features: string[];
}

export interface SolanaStandardWallet {
  version: string;
  name: string;
  icon: string;
  chains: string[];
  features: {
    'standard:connect': {
      version: string;
      connect: (input?: { silent: boolean }) => Promise<{ accounts: StandardWalletAddress[] }>;
    };
    'standard:disconnect': {
      version: string;
      disconnect: () => Promise<void>;
    };
    'standard:events': {
      version: string;
      on: (event: any, listener: any) => () => void;
    };
    'solana:signTransaction': {
      version: string;
      supportedTransactionVersions: (string | number)[];
      signTransaction: (...inputs: any[]) => Promise<{ signedTransaction: Uint8Array }[]>;
    };
    'solana:signMessage': {
      version: string;
      signMessage: (input: any) => Promise<{ signature: Uint8Array; signedMessage: Uint8Array }[]>;
    };
    'solana:signIn': {
      version: string;
      signIn: (input: any) => Promise<any[]>;
    };
  };
  accounts: StandardWalletAddress[];
  onDisconnect?: () => void;
}

export function registerSolanaInjectedWallet(connector: SolanaStandardWallet) {
  const solanaWallet = connector;

  const register = (registerCallback: any) => {
    registerCallback.register(solanaWallet);
  };

  // try literally EVERYTHING to let dApp know about us
  window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));

  window.addEventListener('wallet-standard:request-provider', () => {
    window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
  });

  // A dApp that starts listening after our `register-wallet` dispatch announces itself with `app-ready`
  window.addEventListener('wallet-standard:app-ready', (e) => {
    const api = (e as CustomEvent).detail;
    if (typeof api?.register === 'function') {
      register(api);
    }
  });

  if (!window.solana) {
    window.solana = {
      isMyTonWallet: true, // maybe it helps, who knows
      // eslint-disable-next-line no-null/no-null
      publicKey: null,
      isConnected: false,
      connect: async (options: any) => {
        const result = await solanaWallet.features['standard:connect'].connect(options);
        if (result.accounts.length) {
          const publicKey = toLegacyPublicKey(result.accounts[0]);
          window.solana.publicKey = publicKey;
          window.solana.isConnected = true;

          return { publicKey };
        }
        return undefined;
      },
      disconnect: async () => {
        await solanaWallet.features['standard:disconnect'].disconnect();
        window.solana.isConnected = false;
        // eslint-disable-next-line no-null/no-null
        window.solana.publicKey = null;
      },
      signTransaction: signLegacyTransaction,
      signAllTransactions: async (txs: any[]) => {
        // One at a time, so that each transaction gets its own confirmation
        const signed = [];
        for (const tx of txs) {
          signed.push(await signLegacyTransaction(tx));
        }

        return signed;
      },
      on: (event: any, cb: any) => {
        return solanaWallet.features['standard:events'].on(event, cb);
      },
    };
  }

  // this event & definition spam helps (proven)
  const interval = setInterval(() => {
    window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
  }, 500);

  setTimeout(() => clearInterval(interval), 10_000);
  return solanaWallet;

  // Accepts a web3.js `Transaction`/`VersionedTransaction` (or raw bytes) and returns the same kind, signed
  async function signLegacyTransaction(tx: any) {
    const account = solanaWallet.accounts[0];
    if (!account) {
      throw new Error('Wallet is not connected');
    }

    const transaction: Uint8Array = tx instanceof Uint8Array
      ? tx
      : tx.serialize({ requireAllSignatures: false, verifySignatures: false });
    const [output] = await solanaWallet.features['solana:signTransaction'].signTransaction({ account, transaction });
    if (!output) {
      throw new Error('Transaction was not signed');
    }

    if (tx instanceof Uint8Array) {
      return output.signedTransaction;
    }

    const TransactionClass = tx.constructor;
    return typeof TransactionClass.deserialize === 'function'
      ? TransactionClass.deserialize(output.signedTransaction)
      : TransactionClass.from(output.signedTransaction);
  }
}

function toLegacyPublicKey({ address, publicKey }: StandardWalletAddress): LegacyPublicKey {
  return Object.assign(new Uint8Array(publicKey), {
    toBase58: () => address,
    toString: () => address,
    toBytes: () => publicKey,
    toJSON: () => address,
  });
}

export type RegisterSolanaInjectedWalletCb = typeof registerSolanaInjectedWallet;
