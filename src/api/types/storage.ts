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

export type ApiSolanaWallet = ApiBaseWallet;

/** A helper type that converts the chain names to the corresponding wallet types */
export type ApiWalletByChain = {
  ton: ApiTonWallet;
  tron: ApiTronWallet;
  solana: ApiSolanaWallet;
};

type ApiBaseAccount = {
  byChain: {
    [K in ApiChain]?: ApiWalletByChain[K];
  };
};

/** Also accounts based on a private key */
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

export interface ApiSseOptions {
  clientId: string;
  appClientId: string;
  secretKey: string;
  lastOutputId: number;
}
