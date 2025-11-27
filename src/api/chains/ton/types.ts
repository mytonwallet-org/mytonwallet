import type { Cell } from '@ton/core';
import type { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type {
  ApiActivity,
  ApiAnyDisplayError,
  ApiEmulationResult,
  ApiParsedPayload,
  ApiTransaction,
  ApiTransferPayload,
} from '../../types';
import type { ContractType } from './constants';
import type { AddressBook, AnyAction, TraceDetail } from './toncenter/types';

export type ApiTonWalletVersion = 'simpleR1'
  | 'simpleR2'
  | 'simpleR3'
  | 'v2R1'
  | 'v2R2'
  | 'v3R1'
  | 'v3R2'
  | 'v4R2'
  | 'W5';

export type AnyTonTransferPayload = ApiTransferPayload | Cell;

export interface TokenTransferBodyParams {
  queryId?: bigint;
  tokenAmount: bigint;
  toAddress: string;
  responseAddress: string;
  forwardAmount?: bigint;
  forwardPayload?: Cell;
  /**
   * `forwardPayload` can be stored either at a tail of the root cell (i.e. inline) or as its ref.
   * This option forbids the inline variant. This requires more gas but safer.
   */
  noInlineForwardPayload?: boolean;
  customPayload?: Cell;
}

/**
 * Information about the transfer that is not necessary and doesn't participate in the transaction directly, but can
 * speed up the application by avoiding fetching data that is already available.
 */
export type TonTransferHints = {
  /** The transferred token (if it's a jetton transfer) */
  tokenAddress?: string;
};

/** Ton transaction data in a simple for constructing form */
export interface TonTransferParams {
  toAddress: string;
  amount: bigint;
  payload?: Cell;
  stateInit?: Cell;
  /** Optional, to optimize the signing process */
  hints?: TonTransferHints;
}

/** Ton transaction data in the most ready for signing form */
export type PreparedTransactionToSign = Pick<
  Parameters<WalletContractV5R1['createTransfer']>[0],
  'messages' | 'sendMode' | 'seqno' | 'timeout'
> & {
  authType?: 'internal' | 'external';
  /** Optional, to optimize the signing process */
  hints?: TonTransferHints;
};

export interface JettonMetadata {
  name: string;
  symbol: string;
  description?: string;
  decimals?: number | string;
  image?: string;
  image_data?: string;
  uri?: string;
  custom_payload_api_uri?: string;
}

export type ContractName = ApiTonWalletVersion
  | 'v4R1' | 'highloadV2' | 'multisig' | 'multisigV2' | 'multisigNew'
  | 'nominatorPool' | 'vesting'
  | 'dedustPool' | 'dedustVaultNative' | 'dedustVaultJetton'
  | 'stonPtonWallet' | 'stonRouter' | 'stonRouterV2_1' | 'stonPoolV2_1'
  | 'stonRouterV2_2' | 'stonRouterV2_2_alt' | 'stonPoolV2_2' | 'stonPtonWalletV2'
  | 'toncoRouter' | 'wrappedToncoTonWallet';

export type ContractInfo = {
  name: ContractName;
  type?: ContractType;
  oldHash?: string;
  hash?: string;
  isSwapAllowed?: boolean;
};

export type GetAddressInfoResponse = {
  '@type': 'raw.fullAccountState';
  balance: string | 0;
  code: string;
  data: string;
  last_transaction_id: {
    '@type': 'internal.transactionId';
    lt: string;
    hash: string;
  };
  block_id: {
    '@type': 'ton.blockIdExt';
    workchain: number;
    shard: string;
    seqno: number;
    root_hash: string;
    file_hash: string;
  };
  frozen_hash: string;
  sync_utime: number;
  '@extra': string;
  state: 'uninitialized' | 'active';
};

export type ApiSubmitMultiTransferResult = {
  messages: TonTransferParams[];
  amount: string;
  seqno: number;
  boc: string;
  msgHash: string;
  msgHashNormalized: string;
  paymentLink?: string;
  withW5Gasless?: boolean;
} | {
  error: string;
};

export type ApiEmulationWithFallbackResult = (
  { isFallback: false } & ApiEmulationResult |
  // Emulation is expected to work in 100% cases.
  // The fallback is used for insufficient balance cases and for the cases when the emulation is not available.
  // The legacy method is kept as a fallback while the emulation is tested. It should be completely removed eventually.
  { isFallback: true; networkFee: bigint }
);

export type ApiCheckMultiTransactionDraftResult = (
  {
    emulation?: ApiEmulationWithFallbackResult;
    error: ApiAnyDisplayError;
  } |
  {
    emulation: ApiEmulationWithFallbackResult;
  }
) & {
  parsedPayloads?: (ApiParsedPayload | undefined)[];
};

export type ApiTransactionExtended = ApiTransaction & {
  hash: string;
  msgHash: string;
  opCode?: number;
  body?: string;
};

export type TraceOutput = {
  hashes: Set<string>;
  sent: bigint;
  /** How much TON will be received as a result of the transaction (the sent amount is not deducted) */
  received: bigint;
  /** The network fee in TON (the fee taken by the blockchain itself) */
  networkFee: bigint;
  /** Whether the transaction has succeeded */
  isSuccess: boolean;
  walletActions: ParsedAction[];
  /** The total real fee of `walletActions` */
  realFee: bigint;
  /** The total excess of `walletActions` */
  excess: bigint;
};

/**
 * This is an object with action that is associated with a wallet, the activity of this action and Toncoin
 */
export type ParsedAction = {
  action: AnyAction;
  activities: ApiActivity[];
  // Explicit incoming or outgoing Toncoin (deposit, send, staking withdrawal, sending or receiving in swap, etc.)
  // This is the Toncoin amount shown to the user in the displayed transaction/activity
  toncoinChange?: bigint;
};

export type ParsedTrace = {
  actions: AnyAction[];
  traceDetail: TraceDetail;
  addressBook: AddressBook;
  // Parsed
  traceOutputs: TraceOutput[];
  totalSent: bigint;
  totalReceived: bigint;
  totalNetworkFee: bigint;
};
