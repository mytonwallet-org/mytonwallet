import type { DeviceInfo } from '@tonconnect/protocol';

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
}

export const initConnectorString = initConnector.toString();
