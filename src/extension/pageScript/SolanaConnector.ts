import type {
  DappConnectionRequest,
  DappConnectionResult,
  DappMethodResult,
  DappProtocolType,
  DappSessionChain,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../api/dappProtocols';
import type { WalletConnectSessionProposal } from '../../api/dappProtocols/adapters/walletConnect/types';
import type {
  SolanaRequestMethods,
  SolanaStandardWallet,
  StandardWalletAddress,
} from '../../util/injectedConnector/solanaConnector';
import type { Connector } from '../../util/PostMessageConnector';

import { APP_NAME } from '../../config';
import { base58FromUint8Array, base64FromBuffer, uint8ArrayFromBase58 } from '../../util/casting';
import { INJECTED_ICON } from '../../util/injectedConnector/injectedIcon';
import {
  registerSolanaInjectedWallet,
} from '../../util/injectedConnector/solanaConnector';

class SolanaConnect implements SolanaStandardWallet {
  private lastGeneratedId: number = 0;

  private listeners = new Set();

  constructor(private apiConnector: Connector) {}

  accounts: StandardWalletAddress[] = [];

  version = '1.0.0';
  name = APP_NAME;

  icon = `data:image/svg+xml,${encodeURIComponent(INJECTED_ICON)}`;
  chains = [
    'solana:mainnet',
    'solana:devnet',
    'solana:testnet',
  ];

  features = {
    'standard:connect': {
      version: '1.0.0',
      connect: async (input?: { silent: boolean }): Promise<{ accounts: StandardWalletAddress[] }> => {
        try {
          if (input?.silent) {
            return this.connectSilent();
          }

          if (this.accounts.length) {
            return { accounts: this.accounts };
          }

          return this.connectWithModal();
        } catch (err) {
          // eslint-disable-next-line no-console
          console.error('SolanaConnector:standard:connect', err);

          return { accounts: [] };
        }
      },
    },
    'standard:disconnect': {
      version: '1.0.0',
      disconnect: async () => {
        const id = ++this.lastGeneratedId;
        await this.request.bind(this)(
          'disconnect',
          [{ requestId: id }],
        ) as DappMethodResult<DappProtocolType.WalletConnect>;

        this.accounts = [];
      },
    },
    'standard:events': {
      version: '1.0.0',
      on: (event: any, listener: any) => {
        if (event !== 'change') {
          return () => {};
        }

        this.listeners.add(listener);
        return () => {
          this.listeners.delete(listener);
        };
      },
    },
    'solana:signTransaction': {
      version: '1.0.0',
      supportedTransactionVersions: ['legacy', 0],
      signTransaction: async (input: {
        account: { address: string; chains: string[]; features: string[] };
        transaction: Uint8Array;
      }): Promise<{ signedTransaction: Uint8Array<ArrayBufferLike> }[]> => {
        const id = ++this.lastGeneratedId;
        const unifiedPayload: DappTransactionRequest<DappProtocolType.WalletConnect> = {
          id: String(id),
          chain: 'solana',
          payload: {
            isSignOnly: true,
            url: window.origin,
            address: input.account.address,
            data: base64FromBuffer(Buffer.from(input.transaction)),
          },
        };

        const response = await this.request.bind(this)(
          'sendTransaction',
          [unifiedPayload],
        ) as DappMethodResult<DappProtocolType.WalletConnect>;

        if (!response.success) {
          return [];
        }

        return [{
          signedTransaction: new Uint8Array(uint8ArrayFromBase58(response.result.result)),
        }];
      },
    },
    'solana:signMessage': {
      version: '1.0.0',
      signMessage: async (input: {
        account: { address: string; chains: string[]; features: string[] };
        message: Uint8Array;
      }) => {
        const id = ++this.lastGeneratedId;
        const unifiedPayload: DappSignDataRequest<DappProtocolType.WalletConnect> = {
          id: String(id),
          chain: 'solana',
          payload: {
            url: window.origin,
            address: input.account.address,
            data: base58FromUint8Array(input.message),
          },
        };

        const response = await this.request.bind(this)(
          'signData',
          [unifiedPayload],
        ) as DappMethodResult<DappProtocolType.WalletConnect>;

        if (!response.success) {
          return [];
        }

        return [{
          signature: new Uint8Array(uint8ArrayFromBase58(response.result.result)),
          signedMessage: input.message,
        }];
      },
    },
    'solana:signIn': {
      version: '1.0.0',
      signIn: async (input: any) => {
        // TODO: find dapp to test this
        await Promise.resolve();

        return [];
      },
    },
  };

  onDisconnect() {
    ++this.lastGeneratedId;
    this.accounts = [];

    this.emit({ accounts: [] });
  }

  emit(data: any) {
    this.listeners.forEach((listener: any) => {
      try {
        listener(data);
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('SolanaConnector:emit', err);
      }
    });
  }

  private mapSessionChainsToAccounts(chains: DappSessionChain[]): StandardWalletAddress[] {
    return chains.filter((chain) => chain.chain === 'solana').map((chain) => ({
      address: chain.address,
      publicKey: new Uint8Array(uint8ArrayFromBase58(chain.address)),
      chains: [`${chain.chain}:${chain.network === 'mainnet' ? 'mainnet' : 'devnet'}`],
      features: Object.keys(this.features),
    }));
  }

  private async connectSilent(): Promise<{ accounts: StandardWalletAddress[] }> {
    const id = ++this.lastGeneratedId;

    const response = await this.request.bind(this)(
      'reconnect',
      [id],
    ) as DappConnectionResult<DappProtocolType.WalletConnect>;

    if (!response.success) {
      return { accounts: [] };
    }

    const standardWalletAddresses = this.mapSessionChainsToAccounts(response.session.chains);

    this.accounts = standardWalletAddresses;

    return { accounts: this.accounts };
  }

  private async connectWithModal(): Promise<{ accounts: StandardWalletAddress[] }> {
    const id = ++this.lastGeneratedId;

    const metadata = {
      url: window.origin,
      name: (document.querySelector<HTMLMetaElement>('meta[property*="og:title"]'))?.content
        || document.title,
      description: '',
      icons: [(document.querySelector<HTMLLinkElement>('link[rel*="icon"]'))?.href
        || `${window.location.origin}/favicon.ico` || ''],
    };

    const payload: WalletConnectSessionProposal = {
      id,
      params: {
        id,
        expiryTimestamp: 0,
        relays: [],
        proposer: {
          publicKey: '',
          metadata,
        },
        requiredNamespaces: {},
        optionalNamespaces: {
          solana: {
            methods: [],
            events: [],
          },
        },
        pairingTopic: '',
      },
    };

    const unifiedPayload: DappConnectionRequest<DappProtocolType.WalletConnect> = {
      protocolType: 'walletConnect',
      transport: 'extension',
      protocolData: payload,
      permissions: {
        isPasswordRequired: false,
        isAddressRequired: false,
      },
      requestedChains: [{
        chain: 'solana',
        network: 'mainnet',
      }],
    };

    const response = await this.request.bind(this)(
      'connect',
      [unifiedPayload],
    ) as DappConnectionResult<DappProtocolType.WalletConnect>;

    if (!response.success) {
      return { accounts: [] };
    }

    const standardWalletAddresses = this.mapSessionChainsToAccounts(response.session.chains);

    this.accounts = standardWalletAddresses;

    return { accounts: this.accounts };
  }

  private request(name: SolanaRequestMethods, args: any[] = []) {
    return this.apiConnector.request({ name: `walletConnect_${name}`, args });
  }
}

export function initSolanaConnect(apiConnector: Connector) {
  return registerSolanaInjectedWallet(new SolanaConnect(apiConnector));
}
