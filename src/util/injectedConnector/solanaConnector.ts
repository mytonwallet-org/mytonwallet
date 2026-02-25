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

export const solanaConnectorIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" fill="none"><g clip-path="url(#a)"><path fill="url(#b)" d="M192 61a100 100 0 1 0 8 39 99 99 0 0 0-8-39m-8 80-5-12 11-6zM11 123l10 6-4 12zm-3-23v-9l8 9-8 9zm9-40 4 11-11 6zm173 17-11-6 5-12zm-54 86-8-6 8-5zm-23 8-6-8 9-2zm-25 0-3-10 9 2zm-6 6-13 8-4-14 13-9zm-18-14 1-11 8 5zm0-125 9 5-8 5zm24-9 6 8-9 2zm25 0 3 10-9-2zm5-6 13-8 5 14-13 9zm18 14v11l-8-5zm-36 119c-31 0-56-25-56-56a56 56 0 0 1 20-43h1l16-10h1a56 56 0 0 1 54 10 56 56 0 0 1 20 43c0 31-25 56-56 56m-63-51-10-5 10-5zm126-10 10 5-10 5zm-5-21 10 1-7 8zm-12-18 10-2-5 9zm-45-22L91 22l9-12 10 12zm-23 5L65 29l4-14 13 8zM49 63l-4-9 10 2zm-9 20-7-8h10zm-15-6 11 12-15 6-10-11zm-4 28 15 7-11 11-14-7zm19 13 3 8-10-1zm15 26-10 3 4-10zm46 22 9 12-10 12-9-12zm22-4 13 9-5 14-13-8zm28-25 5 10-11-3zm10-19 7 7-10 1zm15 5-11-11 14-7 10 11zm3-28-14-7 11-11 13 7zm-6-26-16-2 7-14 14 2zm-16-23-15 4 1-16 15-3zm-42-29-8-10 19 4zm-29 0-11-6 18-3zM58 50l-15-4V31l14 3zm-21 3 6 15-15 1-6-14zm-9 78 15 2-6 15-15-2zm15 23 15-3-1 16-14 3zm43 29 7 9-18-3zm29 0 11 6-19 4zm27-33 15 4 1 16-15-4zm22-3-7-14 16-2 5 15zm20-47 9-9v18zm-7-53-13-1 1-13zm-23-23-12 3-3-11zm-92-8-4 11-12-2zM36 33v13l-12 1zM24 153l12 1v13zm23 23 11-3 4 11zm92 8 3-11 12 3zm26-17-1-13 13-1z"/></g><defs><linearGradient id="b" x1="19.5" x2="228.5" y1="13" y2="78.2" gradientUnits="userSpaceOnUse"><stop stop-color="#71aaef"/><stop offset=".3" stop-color="#3f79cf"/><stop offset=".7" stop-color="#2e74b5"/><stop offset="1" stop-color="#2160a2"/></linearGradient><clipPath id="a"><path fill="#fff" d="M0 0h200v200H0z"/></clipPath></defs></svg>`;

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

  // this event & definition spam helps (proven)
  const interval = setInterval(() => {
    window.dispatchEvent(new CustomEvent('wallet-standard:request-provider'));
    window.dispatchEvent(new CustomEvent('wallet-standard:register-wallet', { detail: register }));

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
  }, 500);

  setTimeout(() => clearInterval(interval), 10_000);
  return solanaWallet;
}

export type RegisterSolanaInjectedWalletCb = typeof registerSolanaInjectedWallet;
