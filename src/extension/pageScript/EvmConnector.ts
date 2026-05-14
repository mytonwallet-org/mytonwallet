import type {
  DappConnectionRequest,
  DappConnectionResult,
  DappMethodResult,
  DappProtocolType,
  DappSessionChain,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../api/dappProtocols';
import type {
  EvmTransactionParams,
  WalletConnectSessionProposal,
} from '../../api/dappProtocols/adapters/walletConnect/types';
import type { ApiChain, ApiNetwork } from '../../api/types';
import type {
  EIP1193Provider,
} from '../../util/injectedConnector/evmConnector';
import type { SolanaRequestMethods } from '../../util/injectedConnector/solanaConnector';
import type { Connector } from '../../util/PostMessageConnector';
import { EVM_CHAIN_IDS } from '../../api/dappProtocols/adapters/walletConnect/types';

import { APP_NAME } from '../../config';
import {
  registerEvmInjectedWallet,
} from '../../util/injectedConnector/evmConnector';
import { INJECTED_ICON } from '../../util/injectedConnector/injectedIcon';
import { READONLY_EVM_RPC_METHODS } from '../../api/dappProtocols/adapters/walletConnect/readonlyMethods';

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

function getCaip2ForSessionChain(chain: ApiChain, network: ApiNetwork): string | undefined {
  return Object.entries(EVM_CHAIN_IDS).find(
    ([, v]) => v.chain === chain && v.network === network,
  )?.[0];
}

type Eip1193Event = 'accountsChanged' | 'chainChanged' | 'connect' | 'disconnect';

// Per-method TTLs (ms) for readonly RPC coalescing. See connector.ts for rationale.
// Kept in sync across platforms.
const READ_CACHE_TTL_MS: Record<string, number> = {
  eth_blockNumber: 1500,
  eth_gasPrice: 1500,
  eth_maxPriorityFeePerGas: 1500,
  eth_syncing: 30000,
  eth_protocolVersion: 600000,
  net_listening: 600000,
  web3_clientVersion: 600000,
};

export class EvmConnect {
  private lastGeneratedId = 0;

  private readonly eventListeners = new Map<Eip1193Event, Set<(...args: unknown[]) => void>>();

  private sessionChains: DappSessionChain[] = [];

  private selectedCaip2: string | undefined;

  private readCache = new Map<string, { promise: Promise<unknown>; expiresAt: number }>();

  // Short-TTL cache for silent reconnect to absorb Reown/wagmi polling
  // (eth_accounts is polled at 100+/s; in-flight dedup at the SDK alone leaks
  // about 60% of the load to the worker between successive requests).
  private silentReconnect: { promise: Promise<unknown>; expiresAt: number } | undefined;

  readonly provider: EIP1193Provider;

  constructor(private apiConnector: Connector) {
    const provider: EIP1193Provider = {
      isMyTonWallet: true,
      request: (args) => this.request(args),
      on: (event, handler) => {
        this.addListener(event as Eip1193Event, handler);
      },
      removeListener: (event, handler) => {
        this.removeListener(event as Eip1193Event, handler);
      },
    };

    this.provider = provider;
  }

  onDisconnect() {
    ++this.lastGeneratedId;
    this.sessionChains = [];
    this.selectedCaip2 = undefined;
    this.readCache.clear();
    this.silentReconnect = undefined;

    this.emit('accountsChanged', [[]]);
    this.emit('disconnect', []);
  }

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
        console.error('EvmConnector:emit', err);
      }
    });
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

  private applySessionResult(response: DappConnectionResult<DappProtocolType.WalletConnect>) {
    if (!response.success) {
      return;
    }

    const prevAccounts = this.getAccountsLower();
    const prevChainHex = this.chainIdHex();

    this.sessionChains = response.session.chains;
    const evm = this.evmChains;

    if (evm.length) {
      const stillConnected = this.selectedCaip2 !== undefined && evm.some(
        (c) => getCaip2ForSessionChain(c.chain, c.network) === this.selectedCaip2,
      );

      if (!stillConnected) {
        this.selectedCaip2 = getCaip2ForSessionChain(evm[0].chain, evm[0].network);
      }

      const nextAccounts = this.getAccountsLower();
      const nextChainHex = this.chainIdHex();
      // Block-bound and gas-price cache must not leak across chains.
      if (nextChainHex !== prevChainHex) {
        this.readCache.clear();
      }
      // Only emit when state actually changed. Without this, every silent reconnect
      // (Reown polls eth_accounts ~100/s) re-emits accountsChanged and pins
      // React-based dapps in a re-render loop until the JS heap OOMs.
      // Fire `connect` on the disconnected->connected transition (prev had no accounts)
      // even if the resolved chain matches our default fallback ('0x1' for mainnet).
      if (prevAccounts.length === 0 || prevChainHex !== nextChainHex) {
        this.emit('connect', [{ chainId: nextChainHex }]);
      }
      if (prevAccounts.length !== nextAccounts.length
        || prevAccounts.some((a, i) => a !== nextAccounts[i])) {
        this.emit('accountsChanged', [nextAccounts]);
      }
    }
  }

  private async connectWallet(silent: boolean): Promise<DappConnectionResult<DappProtocolType.WalletConnect>> {
    if (silent) {
      const now = Date.now();
      const cached = this.silentReconnect;
      if (cached && cached.expiresAt > now) {
        return cached.promise as Promise<DappConnectionResult<DappProtocolType.WalletConnect>>;
      }
      const id = ++this.lastGeneratedId;
      const promise = this.requestWc('reconnect', [id]) as
        Promise<DappConnectionResult<DappProtocolType.WalletConnect>>;
      const entry = { promise, expiresAt: now + 500 };
      this.silentReconnect = entry;
      promise.then(
        (resp) => {
          if (!resp || !resp.success) {
            if (this.silentReconnect === entry) this.silentReconnect = undefined;
          }
        },
        () => {
          if (this.silentReconnect === entry) this.silentReconnect = undefined;
        },
      );
      return promise;
    }
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
          ...EVM_EIP155_NAMESPACES,
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
      requestedChains: Object.values(EVM_CHAIN_IDS),
    };

    const response = (await this.requestWc('connect', [unifiedPayload])) as DappConnectionResult<
      DappProtocolType.WalletConnect
    >;

    return response;
  }

  private requestWc(name: SolanaRequestMethods, args: unknown[] = []) {
    return this.apiConnector.request({ name: `walletConnect_${name}`, args });
  }

  private currentChain(): ApiChain | undefined {
    return this.selectedCaip2 ? EVM_CHAIN_IDS[this.selectedCaip2]?.chain : undefined;
  }

  private async proxyReadRpc(method: string, params: unknown[]): Promise<unknown> {
    const ttl = READ_CACHE_TTL_MS[method];
    if (!ttl) {
      return this.dispatchProxyRead(method, params);
    }
    const now = Date.now();
    const cached = this.readCache.get(method);
    if (cached && cached.expiresAt > now) {
      return cached.promise;
    }
    const promise = this.dispatchProxyRead(method, params);
    const entry = { promise, expiresAt: now + ttl };
    this.readCache.set(method, entry);
    promise.catch(() => {
      if (this.readCache.get(method) === entry) this.readCache.delete(method);
    });
    return promise;
  }

  private async dispatchProxyRead(method: string, params: unknown[]): Promise<unknown> {
    const chain = this.currentChain();
    if (!chain) {
      return Promise.reject({ code: 4901, message: 'No selected chain for RPC proxy' });
    }
    const response = await this.requestWc('proxyEvmRpc', [{ chain, method, params }]) as
      | { success: true; result: unknown }
      | { success: false; error: { code: number; message: string } }
      | undefined;
    if (response && response.success) {
      return response.result;
    }
    const err = response && 'error' in response ? response.error : undefined;
    return Promise.reject({
      code: err?.code ?? -32603,
      message: err?.message || 'RPC proxy error',
    });
  }

  private async request(args: { method: string; params?: readonly unknown[] | Record<string, unknown> }) {
    const { method } = args;
    const params = (args.params ?? []) as unknown[];

    try {
      switch (method) {
        case 'eth_requestAccounts': {
          const result = await this.connectWallet(false);

          this.applySessionResult(result);

          if (!result.success) {
            return [];
          }

          return this.getAccountsLower();
        }
        case 'eth_accounts': {
          const result = await this.connectWallet(true);

          this.applySessionResult(result);

          if (!result.success) {
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
          // Block-bound and gas-price cache must not leak across chains.
          this.readCache.clear();
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

          const id = ++this.lastGeneratedId;

          const unifiedPayload: DappTransactionRequest<DappProtocolType.WalletConnect> = {
            id: String(id),
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
          ) as DappMethodResult<DappProtocolType.WalletConnect>;

          if (!response.success) {
            return Promise.reject({ code: 4001, message: response.error?.message || 'Rejected' });
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
          if (READONLY_EVM_RPC_METHODS.has(method)) {
            return this.proxyReadRpc(method, params);
          }
          return Promise.reject({ code: -32601, message: `Unsupported method: ${method}` });
      }
    } catch (err: unknown) {
      if (err && typeof err === 'object' && 'code' in err) {
        return Promise.reject(err);
      }
      // eslint-disable-next-line no-console
      console.error('EvmConnector:request', err);
      return Promise.reject({ code: -32603, message: err instanceof Error ? err.message : 'Internal error' });
    }
  }

  private async signPersonalOrEth(address: string, data: string) {
    const { chain } = this.resolveChainForAddress(address);

    const id = ++this.lastGeneratedId;

    const unifiedPayload: DappSignDataRequest<DappProtocolType.WalletConnect> = {
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
    ) as DappMethodResult<DappProtocolType.WalletConnect>;

    if (!response.success) {
      return Promise.reject({ code: 4001, message: response.error?.message || 'Rejected' });
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

    const unifiedPayload: DappSignDataRequest<DappProtocolType.WalletConnect> = {
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
    ) as DappMethodResult<DappProtocolType.WalletConnect>;

    if (!response.success) {
      return Promise.reject({ code: 4001, message: response.error?.message || 'Rejected' });
    }

    return response.result.result;
  }
}

export function initEvmConnect(apiConnector: Connector) {
  const evm = new EvmConnect(apiConnector);

  registerEvmInjectedWallet({
    info: {
      uuid: crypto.randomUUID(),
      name: APP_NAME,
      icon: `data:image/svg+xml,${encodeURIComponent(INJECTED_ICON)}`,
      rdns: 'app.mytonwallet',
    },
    provider: evm.provider,
  });

  return evm;
}
