declare global {
  interface Window {
    solana: {
      isMyTonWallet: boolean;
      publicKey: Uint8Array<ArrayBuffer> | null;
      isConnected: boolean;
      connect: (options: any) => Promise<{
        publicKey: Uint8Array<ArrayBuffer>;
      } | undefined>;
      disconnect: () => Promise<void>;
      signTransaction: (tx: any) => Promise<{
        signedTransaction: Uint8Array<ArrayBufferLike>;
      }>;
      signAllTransactions: (txs: any[]) => Promise<{
        signedTransactions: void[];
      }>;
      on: (event: any, cb: any) => () => void;
    };
  }
}

export type SolanaRequestMethods = 'connect' | 'reconnect' | 'sendTransaction' | 'signData' | 'disconnect';

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
    'solana:signAndSendTransaction': {
      version: string;
      supportedTransactionVersions: (string | number)[];
      signAndSendTransaction: (input: any) => Promise<void>;
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

  window.dispatchEvent(new CustomEvent('wallet-standard:app-ready', {
    detail: register,
  }));

  if (!window.solana) {
    window.solana = {
      isMyTonWallet: true, // maybe it helps, who knows
      // eslint-disable-next-line no-null/no-null
      publicKey: null,
      isConnected: false,
      connect: async (options: any) => {
        const result = await solanaWallet.features['standard:connect'].connect(options);
        if (result.accounts.length) {
          const account = result.accounts[0];
          window.solana.publicKey = account.publicKey;
          window.solana.isConnected = true;

          return { publicKey: account.publicKey };
        }
        return undefined;
      },
      disconnect: async () => {
        await solanaWallet.features['standard:disconnect'].disconnect();
        window.solana.isConnected = false;
        // eslint-disable-next-line no-null/no-null
        window.solana.publicKey = null;
      },
      signTransaction: async (tx: any) => {
        const res = await solanaWallet.features['solana:signTransaction'].signTransaction(tx);
        return {
          signedTransaction: res[0].signedTransaction,
        };
      },
      // TODO: find dApp to test this
      signAllTransactions: async (txs: any[]) => {
        const signed = await Promise.all(txs.map(async (e) => {
          await solanaWallet.features['solana:signAndSendTransaction'].signAndSendTransaction(e);
        }));

        return {
          signedTransactions: signed,
        };
      },
      on: (event: any, cb: any) => {
        return solanaWallet.features['standard:events'].on(event, cb);
      },
    };
  }

  // this event & definition spam helps (proven)
  const interval = setInterval(() => {
    window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));
    window.dispatchEvent(new CustomEvent('wallet-standard:request-provider'));
  }, 500);

  setTimeout(() => clearInterval(interval), 10_000);
  return solanaWallet;
}

export type RegisterSolanaInjectedWalletCb = typeof registerSolanaInjectedWallet;
