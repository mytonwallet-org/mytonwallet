import type { ApiTonWalletVersion } from '../chains/ton/types';
import type { ApiChain, ApiLedgerDriver } from './misc';

type ApiBaseWallet = {
  address: string;
  /** Misses in view wallets. Though, it is presented in TON view wallets that are initialized wallet contracts. */
  publicKey?: string;
  index: number;
};

export type ApiTonWallet = ApiBaseWallet & {
  version: ApiTonWalletVersion;
  isInitialized?: boolean;
  authToken?: string;
};

export type ApiTronWallet = ApiBaseWallet;

/** A helper type that converts the chain names to the corresponding wallet types */
export type ApiWalletByChain = {
  ton: ApiTonWallet;
  tron: ApiTronWallet;
};

type ApiBaseAccount = {
  byChain: {
    [K in ApiChain]?: ApiWalletByChain[K];
  };
};

export type ApiBip39Account = ApiBaseAccount & {
  type: 'bip39';
  mnemonicEncrypted: string;
};

export type ApiTonAccount = ApiBaseAccount & {
  type: 'ton';
  mnemonicEncrypted: string;
};

export type ApiLedgerAccount = ApiBaseAccount & {
  type: 'ledger';
  driver: ApiLedgerDriver;
  deviceId?: string;
  deviceName?: string;
};

export type ApiViewAccount = ApiBaseAccount & {
  type: 'view';
};

export type ApiAccountAny = ApiBip39Account | ApiTonAccount | ApiLedgerAccount | ApiViewAccount;
export type ApiAccountWithMnemonic = Extract<ApiAccountAny, { mnemonicEncrypted: string }>;
export type ApiAccountWithChain<T extends ApiChain> = ApiAccountAny & { byChain: Record<T, ApiWalletByChain[T]> };

export interface ApiDappMetadata {
  url: string;
  name: string;
  iconUrl: string;
  manifestUrl: string;
}

export interface ApiDapp extends ApiDappMetadata {
  connectedAt: number;
  isUrlEnsured?: boolean;
  sse?: ApiSseOptions;
}

export interface ApiSseOptions {
  clientId: string;
  appClientId: string;
  secretKey: string;
  lastOutputId: number;
}

/*
  Each account id maps to a collection of dApps, grouped by URL, and for every URL
  there could be several simultaneous connections (e.g., when the same site
  is opened in different browsers or tabs). The second level key (uniqueId)
  differentiates these connections:
    – "jsbridge"    – JS-Bridge connection (there could be only one per site)
    – appClientId    – SSE connection unique identifier
*/
export type ApiDappsState = Record<string, ApiDappsByUrl>;
export type ApiDappsByUrl = Record<string, ApiDappsById>;
export type ApiDappsById = Record<string, ApiDapp>;
