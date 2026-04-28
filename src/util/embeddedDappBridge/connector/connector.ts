import type { DeviceInfo } from '@tonconnect/protocol';

import type { ChainIdByChain, EvmTransactionParams } from '../../../api/dappProtocols/adapters/walletConnect/types';
import type { DappConnectionResult, DappSessionChain } from '../../../api/dappProtocols/types';
import type { ApiChain, ApiNetwork } from '../../../api/types';
import type { RegisterEvmInjectedWalletCb } from '../../injectedConnector/evmConnector';
import type {
  RegisterSolanaInjectedWalletCb,
  SolanaStandardWallet,
  StandardWalletAddress,
} from '../../injectedConnector/solanaConnector';
import type { BridgeApi } from '../provider/bridgeApi';
import type { BrowserTonConnectBridgeMethods } from '../provider/tonConnectBridgeApi';

interface TonConnectProperties {
  deviceInfo: DeviceInfo;
  protocolVersion: number;
  isWalletBrowser: boolean;
}

type ApiMethodName = keyof BridgeApi;
type ApiArgs<T extends ApiMethodName = any> = Parameters<Required<BridgeApi>[T]>;
type ApiMethodResponse<T extends ApiMethodName = any> = ReturnType<Required<BridgeApi>[T]>;

interface RequestState {
  resolve: AnyToVoidFunction;
  reject: AnyToVoidFunction;
}

interface OutMessageData {
  channel: string;
  messageId: string;
  type: 'callMethod';
  name: ApiMethodName;
  args: ApiArgs;
}

type InMessageData = {
  channel: string;
  messageId: string;
  type: 'methodResponse';
  response?: ApiMethodResponse;
  error?: { message: string };
} | {
  channel: string;
  messageId: string;
  type: 'update';
  update: string;
};

type CordovaPostMessageTarget = { postMessage: AnyToVoidFunction };
type Handler = (update: string) => void;

/**
 * Allows calling functions, provided by another messenger (the parent window, or the Capacitor main view), in this messenger.
 * The other messenger must provide the functions using `createReverseIFrameInterface`.
 *
 * `PostMessageConnect` is not used here (as any other dependencies) because this needs to be easily stringified.
 */
export function initConnector(
  bridgeKey: string,
  channel: string,
  target: Window | CordovaPostMessageTarget,
  tonConnectProperties: TonConnectProperties,
  appName: string,
  icon: string,
  registerSolanaInjectedWallet: RegisterSolanaInjectedWalletCb,
  registerEvmInjectedWallet: RegisterEvmInjectedWalletCb,
) {
  if ((window as any)[bridgeKey]) return;

  const TON_CONNECT_BRIDGE_METHODS = ['connect', 'restoreConnection', 'disconnect', 'send'] as const;

  const requestStates = new Map<string, RequestState>();
  const tonUpdateHandlers = new Set<Handler>();
  const solanaUpdateHandlers = new Set<Handler>();

  setupPostMessageHandler();
  setupGlobalOverrides();
  initTonConnect();
  initSolanaConnect();
  initEvmConnect();

  function setupPostMessageHandler() {
    window.addEventListener('message', ({ data }) => {
      const message = data as InMessageData;

      if (message.channel !== channel) {
        return;
      }

      if (message.type === 'methodResponse') {
        const requestState = requestStates.get(message.messageId);
        if (!requestState) return;

        requestStates.delete(message.messageId);

        if (message.error) {
          requestState.reject(message.error);
        } else {
          requestState.resolve(message.response);
        }
      } else if (message.type === 'update') {
        tonUpdateHandlers.forEach((handler) => handler(message.update));
      }
    });
  }

  function setupGlobalOverrides() {
    window.open = (url) => {
      url = sanitizeUrl(url);
      if (url) {
        void callApi('window:open', { url });
      }

      // eslint-disable-next-line no-null/no-null
      return null;
    };

    window.close = () => {
      void callApi('window:close');
    };

    window.addEventListener('click', (e) => {
      if (!(e.target instanceof HTMLElement)) return;

      const { href, target } = e.target.closest('a') || {};
      if (href && (target === '_blank' || !href.startsWith('http'))) {
        e.preventDefault();

        const url = sanitizeUrl(href);
        if (url) {
          void callApi('window:open', { url });
        }
      }
    }, false);
  }

  function initTonConnect() {
    const methods = Object.fromEntries(TON_CONNECT_BRIDGE_METHODS.map((name) => {
      return [
        name,
        (...args: Parameters<BrowserTonConnectBridgeMethods[typeof name]>) => callApi(`tonConnect:${name}`, ...args),
      ];
    }));

    function addUpdateHandler(cb: Handler) {
      tonUpdateHandlers.add(cb);

      return () => {
        tonUpdateHandlers.delete(cb);
      };
    }

    (window as any)[bridgeKey] = {
      tonconnect: {
        ...tonConnectProperties,
        ...methods,
        listen: addUpdateHandler,
      },
    };
  }

  function initSolanaConnect() {
    class SolanaConnect implements SolanaStandardWallet {
      accounts: StandardWalletAddress[] = [];

      version = '1.0.0';
      name = appName;

      icon = `data:image/svg+xml,${encodeURIComponent(icon)}`;
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
              const metadata = {
                url: window.origin,
                name: (document.querySelector<HTMLMetaElement>('meta[property*="og:title"]'))?.content
                  || document.title,
                description: '',
                icons: [(document.querySelector<HTMLLinkElement>('link[rel*="icon"]'))?.href
                  || `${window.location.origin}/favicon.ico` || ''],
              };

              const result = await callApi('solanaConnect:connect', ...[metadata, input?.silent]);

              this.accounts = result.accounts.map((e) => ({
                ...e,
                publicKey: new Uint8Array(Object.values(e.publicKey)),
              }));

              return { accounts: this.accounts };
            } catch (error) {
              return { accounts: [] };
            }
          },
        },
        'standard:disconnect': {
          version: '1.0.0',
          disconnect: async () => {
            await callApi('solanaConnect:disconnect');

            this.accounts = [];
          },
        },
        'standard:events': {
          version: '1.0.0',
          on: (event: any, listener: any) => {
            if (event !== 'change') {
              return () => {};
            }

            solanaUpdateHandlers.add(listener);
            return () => {
              solanaUpdateHandlers.delete(listener);
            };
          },
        },
        'solana:signAndSendTransaction': {
          version: '1.0.0',
          supportedTransactionVersions: ['legacy', 0],
          signAndSendTransaction: async (input: any) => {
            // TODO: find dapp to test this
            await Promise.resolve();
          },
        },
        'solana:signTransaction': {
          version: '1.0.0',
          supportedTransactionVersions: ['legacy', 0],
          signTransaction: async (input: {
            account: { address: string; chains: string[]; features: string[] };
            transaction: Uint8Array;
          }): Promise<{ signedTransaction: Uint8Array<ArrayBufferLike> }[]> => {
            const response = await callApi('solanaConnect:signTransaction', input);

            return response.map((e) => ({
              signedTransaction: new Uint8Array(Object.values(e.signedTransaction)),
            }));
          },
        },
        'solana:signMessage': {
          version: '1.0.0',
          signMessage: async (input: {
            account: { address: string; chains: string[]; features: string[] };
            message: Uint8Array;
          }) => {
            const response = await callApi('solanaConnect:signMessage', input);

            return response.map((e) => ({
              signature: new Uint8Array(Object.values(e.signature)),
              signedMessage: new Uint8Array(Object.values(e.signedMessage)),
            }));
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
    }

    registerSolanaInjectedWallet(new SolanaConnect());
  }

  function callApi<ApiMethodName extends keyof BridgeApi>(
    name: ApiMethodName,
    ...args: ApiArgs<ApiMethodName>
  ) {
    const messageId = generateUniqueId();

    const promise = new Promise<any>((resolve, reject) => {
      requestStates.set(messageId, { resolve, reject });
    });

    const messageData: OutMessageData = {
      channel,
      messageId,
      type: 'callMethod',
      name,
      args,
    };

    if ('parent' in target) {
      target.postMessage(messageData, '*');
    } else {
      target.postMessage(JSON.stringify(messageData));
    }

    return promise as ApiMethodResponse<ApiMethodName>;
  }

  function generateUniqueId() {
    return Date.now().toString(36) + Math.random().toString(36).slice(2);
  }

  function sanitizeUrl(url?: string | URL) {
    if (!url) return undefined;

    // eslint-disable-next-line no-control-regex
    url = String(url).trim().replace(/[\x00-\x1F\x7F]/g, '');

    if (url.startsWith('//')) {
      return `https:${url}`;
    }

    const UNSAFE_PATTERNS = [
      /^\s*javascript\s*:/i,
      /^\s*data\s*:/i,
      /^\s*vbscript\s*:/i,
      /^\s*file\s*:/i,
      /^\s*about\s*:/i,
      /^\s*blob\s*:/i,
      /^\s*filesystem\s*:/i,
      /^\s*chrome(-extension)?\s*:/i,
      /^\s*moz-extension\s*:/i,
      /^\s*ms-browser-extension\s*:/i,
    ];

    if (UNSAFE_PATTERNS.some((p) => p.test(url))) {
      return undefined;
    }

    if (!/^[a-z][a-z0-9+.-]*:/i.test(url)) {
      return undefined;
    }

    return url;
  }

  function initEvmConnect() {
    const EVM_CHAIN_IDS: ChainIdByChain = {
      'eip155:1': { chain: 'ethereum', network: 'mainnet' },
      'eip155:5': { chain: 'ethereum', network: 'testnet' },
      'eip155:8453': { chain: 'base', network: 'mainnet' },
      'eip155:84532': { chain: 'base', network: 'testnet' },
      // 'eip155:137': { chain: 'polygon', network: 'mainnet' },
      // 'eip155:80002': { chain: 'polygon', network: 'testnet' },
      'eip155:42161': { chain: 'arbitrum', network: 'mainnet' },
      'eip155:421614': { chain: 'arbitrum', network: 'testnet' },
      'eip155:56': { chain: 'bnb', network: 'mainnet' },
      'eip155:97': { chain: 'bnb', network: 'testnet' },
      // 'eip155:43114': { chain: 'avalanche', network: 'mainnet' },
      // 'eip155:43113': { chain: 'avalanche', network: 'testnet' },
      // 'eip155:143': { chain: 'monad', network: 'mainnet' },
      // 'eip155:10143': { chain: 'monad', network: 'testnet' },
      'eip155:999': { chain: 'hyperliquid', network: 'mainnet' },
      'eip155:998': { chain: 'hyperliquid', network: 'testnet' },
    };

    const EVM_EIP155_NAMESPACES = {
      eip155: {
        methods: [
          'eth_sendTransaction',
          'eth_signTransaction',
          'personal_sign',
          'eth_sign',
          'eth_signTypedData',
          'eth_signTypedData_v4',
        ],
        chains: Object.keys(EVM_CHAIN_IDS),
        events: ['accountsChanged', 'chainChanged'],
      },
    };

    function caip2ToHexChainId(caip2: string): string {
      const match = /^eip155:(\d+)$/.exec(caip2);

      if (!match) {
        throw new Error('Invalid CAIP-2 chain id');
      }

      return `0x${BigInt(match[1]).toString(16)}`;
    }

    function hexToEip155Caip2(hex: string): string {
      const withPrefix = hex.startsWith('0x') ? hex : `0x${hex}`;

      return `eip155:${BigInt(withPrefix)}`;
    }

    function normalizeHexChainId(hex: string): string {
      const withPrefix = hex.startsWith('0x') ? hex : `0x${hex}`;

      return `0x${BigInt(withPrefix).toString(16)}`;
    }

    function getCaip2ForSessionChain(chain: string, network: string): string | undefined {
      return Object.entries(EVM_CHAIN_IDS).find(
        ([, v]) => v.chain === chain && v.network === network,
      )?.[0];
    }

    type Eip1193Event = 'accountsChanged' | 'chainChanged' | 'connect' | 'disconnect';

    class EvmInAppConnect {
      private lastGeneratedId = 0;

      private readonly eventListeners = new Map<Eip1193Event, Set<(...args: unknown[]) => void>>();

      private sessionChains: DappSessionChain[] = [];

      private selectedCaip2: string | undefined;

      private addListener(event: Eip1193Event, handler: (...args: unknown[]) => void) {
        let set = this.eventListeners.get(event);

        if (!set) {
          set = new Set();
          this.eventListeners.set(event, set);
        }

        set.add(handler);
      }

      private removeListener(event: Eip1193Event, handler: (...args: unknown[]) => void) {
        this.eventListeners.get(event)?.delete(handler);
      }

      private emit(event: Eip1193Event, args: unknown[]) {
        this.eventListeners.get(event)?.forEach((listener) => {
          try {
            listener(...args);
          } catch (err) {
            // eslint-disable-next-line no-console
            console.error('EvmInAppConnect:emit', err);
          }
        });
      }

      private async requestWc(name: string, args: any[] = []) {
        switch (name) {
          case 'reconnect':
            return callApi('evmConnect:reconnect', args[0]);
          case 'connect':
            return callApi('evmConnect:connect', args[0]);
          case 'sendTransaction':
            return callApi('evmConnect:sendTransaction', args[0]);
          case 'signData':
            return callApi('evmConnect:signData', args[0]);
          default:
            throw new Error(`Unknown wallet connect op: ${name}`);
        }
      }

      private get evmChains(): DappSessionChain[] {
        return this.sessionChains.filter((c) =>
          new Set(Object.values(EVM_CHAIN_IDS).map((c) => c.chain)).has(c.chain),
        );
      }

      private getAccountsLower(): string[] {
        return [...new Set(this.evmChains.map((c) => c.address.toLowerCase()))];
      }

      private chainIdHex(): string {
        const caip2 = this.selectedCaip2 ?? getCaip2ForSessionChain(
          this.evmChains[0]?.chain ?? 'ethereum',
          this.evmChains[0]?.network ?? 'mainnet',
        );

        if (!caip2) {
          return '0x1';
        }

        return caip2ToHexChainId(caip2);
      }

      private resolveChainForAddress(address: string, caip?: string): { chain: ApiChain; network: ApiNetwork } {
        // Default to Ethereum mainnet if no CAIP is provided (for chain-agnostic methods like personal_sign, eth_sign, etc.)
        caip = caip || 'eip155:1';

        // Cannot use getAddress here, so use toLowerCase instead
        const normalized = address.toLowerCase();

        const targetChain = caip ? EVM_CHAIN_IDS[caip] : undefined;

        if (!targetChain) {
          return { chain: 'ethereum', network: 'mainnet' };
        }

        const row = this.evmChains.find(
          (c) => c.address.toLowerCase() === normalized && c.chain === targetChain.chain);

        if (row) {
          return { chain: row.chain, network: row.network };
        }

        return {
          chain: this.evmChains[0]?.chain ?? 'ethereum',
          network: this.evmChains[0]?.network ?? 'mainnet',
        };
      }

      private applySessionResult(response: DappConnectionResult<'walletConnect'>) {
        if (!response.success) {
          return;
        }

        this.sessionChains = response.session.chains;
        const evm = this.evmChains;

        if (evm.length) {
          const caip0 = getCaip2ForSessionChain(evm[0].chain, evm[0].network);

          this.selectedCaip2 = this.selectedCaip2 !== caip0
            ? this.selectedCaip2
            : caip0 ?? this.selectedCaip2;

          this.emit('connect', [{ chainId: this.chainIdHex() }]);
          this.emit('accountsChanged', [this.getAccountsLower()]);
        }
      }

      private async connectWallet(silent: boolean) {
        const id = ++this.lastGeneratedId;

        if (silent) {
          return this.requestWc('reconnect', [id]);
        }

        const metadata = {
          url: window.origin,
          name: document.querySelector<HTMLMetaElement>('meta[property*="og:title"]')?.content
            || document.title,
          description: '',
          icons: [document.querySelector<HTMLLinkElement>('link[rel*="icon"]')?.href
            || `${window.location.origin}/favicon.ico` || ''],
        };

        const payload = {
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
              ...EVM_EIP155_NAMESPACES,
            },
            pairingTopic: '',
          },
        };

        const unifiedPayload = {
          protocolType: 'walletConnect',
          transport: 'extension',
          protocolData: payload,
          permissions: {
            isPasswordRequired: false,
            isAddressRequired: false,
          },
          requestedChains: Object.values(EVM_CHAIN_IDS),
        };

        return this.requestWc('connect', [unifiedPayload]);
      }

      private async request(args: { method: string; params?: readonly unknown[] | Record<string, unknown> }) {
        const { method } = args;
        const params = (args.params ?? []) as unknown[];

        try {
          switch (method) {
            case 'eth_requestAccounts': {
              const result = await this.connectWallet(false);

              if (!result?.success || !('session' in result)) {
                return [];
              }

              this.applySessionResult(result);

              return this.getAccountsLower();
            }
            case 'eth_accounts': {
              const result = await this.connectWallet(true);

              if (!result?.success || !('session' in result)) {
                return [];
              }

              this.applySessionResult(result);

              if (!result?.success) {
                return [];
              }

              return this.getAccountsLower();
            }
            case 'eth_chainId':
              return this.chainIdHex();
            case 'net_version':
              return String(BigInt(this.chainIdHex()));
            case 'wallet_switchEthereumChain': {
              const p = params[0] as { chainId?: string } | undefined;

              const chainIdHex = p?.chainId ? normalizeHexChainId(p.chainId) : '';
              const targetCaip = hexToEip155Caip2(chainIdHex);

              if (!EVM_CHAIN_IDS[targetCaip]) {
                return Promise.reject({
                  code: 4902,
                  message: 'Unrecognized chain',
                });
              }

              const match = this.evmChains.find(
                (c) => getCaip2ForSessionChain(c.chain, c.network) === targetCaip,
              );

              if (!match) {
                return Promise.reject({
                  code: 4902,
                  message: 'Chain not added',
                });
              }

              this.selectedCaip2 = targetCaip;
              this.emit('chainChanged', [this.chainIdHex()]);

              return undefined;
            }
            case 'eth_sendTransaction':
            case 'eth_signTransaction': {
              let txParams = params[0] as EvmTransactionParams | undefined;

              if (txParams && !txParams?.chainId) {
                txParams = {
                  ...txParams,
                  chainId: this.selectedCaip2 ? caip2ToHexChainId(this.selectedCaip2) : undefined,
                };
              }

              if (!txParams?.from) {
                return Promise.reject({ code: -32602, message: 'Invalid params: missing from' });
              }

              if (!txParams.chainId) {
                return Promise.reject({ code: -32602, message: 'Invalid params: missing chainId' });
              }

              const targetCaip = hexToEip155Caip2(txParams.chainId);
              const isValidCaip = Object.keys(EVM_CHAIN_IDS).some((caip) => caip === targetCaip);

              const { chain } = this.resolveChainForAddress(txParams.from, targetCaip);

              if (!isValidCaip) {
                return Promise.reject({ code: 4100, message: 'Unknown chain for signer' });
              }

              const wcId = ++this.lastGeneratedId;

              const unifiedPayload = {
                id: String(wcId),
                chain,
                payload: {
                  isSignOnly: method === 'eth_signTransaction',
                  url: window.origin,
                  address: txParams.from,
                  data: txParams,
                },
              };
              const response = await this.requestWc(
                'sendTransaction',
                [unifiedPayload],
              );

              if (!response?.success || !('result' in response)) {
                return Promise.reject({
                  code: 4001,
                  message: 'Rejected',
                });
              }

              return response.result.result;
            }
            case 'personal_sign': {
              const msg = params[0] as string;
              const addr = params[1] as string;

              return this.signPersonalOrEth(addr, msg);
            }
            case 'eth_sign': {
              const addr = params[0] as string;
              const data = params[1] as string;

              return this.signPersonalOrEth(addr, data);
            }
            case 'eth_signTypedData':
            case 'eth_signTypedData_v4': {
              const addr = params[0] as string;
              const raw = params[1] as string | Record<string, unknown>;

              return this.signTypedData(addr, raw);
            }
            default:
              return Promise.reject({ code: -32601, message: `Unsupported method: ${method}` });
          }
        } catch (err: unknown) {
          if (err && typeof err === 'object' && 'code' in err) {
            return Promise.reject(err);
          }
          // eslint-disable-next-line no-console
          console.error('EvmInAppConnect:request', err);
          return Promise.reject({ code: -32603, message: err instanceof Error ? err.message : 'Internal error' });
        }
      }

      private async signPersonalOrEth(address: string, data: string) {
        const { chain } = this.resolveChainForAddress(address);

        const id = ++this.lastGeneratedId;

        const unifiedPayload = {
          id: String(id),
          chain,
          payload: {
            url: window.origin,
            address,
            data,
            isEthSign: true,
          },
        };

        const response = await this.requestWc(
          'signData',
          [unifiedPayload],
        );

        if (!response?.success || !('result' in response)) {
          return Promise.reject({
            code: 4001,
            message: 'Rejected',
          });
        }

        return response.result.result;
      }

      private async signTypedData(address: string, raw: string | Record<string, unknown>) {
        const parsed = typeof raw === 'string' ? JSON.parse(raw) as Record<string, unknown> : raw;

        const domain = parsed.domain as Record<string, unknown>;
        const types = parsed.types as Record<string, Array<{ name: string; type: string }>>;
        const primaryType = parsed.primaryType as string;

        const message = parsed.message as Record<string, unknown>;

        if (!domain || !types || !primaryType || !message) {
          return Promise.reject({ code: -32602, message: 'Invalid typed data' });
        }

        const { chain } = this.resolveChainForAddress(address);

        const id = ++this.lastGeneratedId;

        const unifiedPayload = {
          id: String(id),
          chain,
          payload: {
            url: window.origin,
            address,
            eip712: {
              domain,
              types,
              primaryType,
              message,
            },
          },
        };

        const response = await this.requestWc(
          'signData',
          [unifiedPayload],
        );

        if (!response?.success || !('result' in response)) {
          return Promise.reject({
            code: 4001,
            message: 'Rejected',
          });
        }

        return response.result.result;
      }

      readonly provider = {
        isMyTonWallet: true,
        request: (reqArgs: any) => this.request(reqArgs),
        on: (event: string, handler: (...args: unknown[]) => void) => {
          this.addListener(event as Eip1193Event, handler);
          return () => {
            this.removeListener(event as Eip1193Event, handler);
          };
        },
        removeListener: (event: string, handler: (...args: unknown[]) => void) => {
          this.removeListener(event as Eip1193Event, handler);
        },
      };
    }

    const evm = new EvmInAppConnect();

    registerEvmInjectedWallet({
      info: {
        uuid: (typeof crypto !== 'undefined' && crypto.randomUUID)
          ? crypto.randomUUID()
          : `evm-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`,
        name: appName,
        icon: `data:image/svg+xml,${encodeURIComponent(icon)}`,
        rdns: 'app.mytonwallet',
      },
      provider: evm.provider,
    });
  }
}

export const initConnectorString = initConnector.toString();
