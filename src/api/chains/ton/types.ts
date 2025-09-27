import type { Cell } from '@ton/core';
import type { WalletContractV5R1 } from '@ton/ton/dist/wallets/WalletContractV5R1';

import type { DieselStatus } from '../../../global/types';
import type {
  ApiAnyDisplayError,
  ApiEmulationResult,
  ApiLocalTransactionParams,
  ApiParsedPayload,
  ApiTransaction,
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

export type AnyPayload = string | Cell | Uint8Array;

export interface TokenTransferBodyParams {
  queryId?: bigint;
  tokenAmount: bigint;
  toAddress: string;
  responseAddress: string;
  forwardAmount?: bigint;
  forwardPayload?: AnyPayload;
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

/** Ton transaction data in the simplest for constructing form */
export interface TonTransferParams {
  toAddress: string;
  amount: bigint;
  payload?: AnyPayload;
  stateInit?: Cell;
  isBase64Payload?: boolean;
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
  | 'toncoRouter';

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

export type ApiSubmitTransferTonResult = {
  toAddress: string;
  amount: bigint;
  seqno: number;
  msgHash: string;
  msgHashNormalized: string;
  toncoinAmount: bigint;
  encryptedComment?: string;
  localActivityParams?: Partial<ApiLocalTransactionParams>;
} | {
  error: string;
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

export type ApiFetchEstimateDieselResult = {
  status: DieselStatus;
  /**
   * The amount of the diesel itself. It will be sent together with the actual transfer. None of this will return back
   * as the excess. Undefined means that
   * gasless transfer is not available, and the diesel shouldn't be shown as the fee; nevertheless, the status should
   * be displayed by the UI.
   *
   * - If the status is not 'stars-fee', the value is measured in the transferred token and charged on top of the
   *   transferred amount.
   * - If the status is 'stars-fee', the value is measured in Telegram stars, and the BigInt assumes 0 decimal places
   *   (i.e. the number is equal to the visible number of stars).
   */
  amount?: bigint;
  /**
   * The native token amount covered by the diesel. Guaranteed to be > 0.
   */
  nativeAmount: bigint;
  /**
   * The remaining part of the fee (the first part is `nativeAmount`) that will be taken from the existing wallet
   * balance. Guaranteed that this amount is available in the wallet. Measured in the native token.
   */
  remainingFee: bigint;
  /**
   * An approximate fee that will be actually spent. The difference between `nativeAmount+remainingFee` and this
   * number is called "excess" and will be returned back to the wallet. Measured in the native token.
   */
  realFee: bigint;
};

export type ApiCheckTransactionDraftResult = {
  /**
   * The full fee that will be appended to the transaction. Measured in the native token. It's charged on top of the
   * transferred amount, unless it's a full-TON transfer.
   */
  fee?: bigint;
  /**
   * An approximate fee that will be actually spent. The difference between `fee` and this number is called "excess" and
   * will be returned back to the wallet. Measured in the native token. Undefined means that it can't be estimated.
   * If the value is equal to `fee`, then it's known that there will be no excess.
   */
  realFee?: bigint;
  addressName?: string;
  isScam?: boolean;
  resolvedAddress?: string;
  isToAddressNew?: boolean;
  isBounceable?: boolean;
  isMemoRequired?: boolean;
  error?: ApiAnyDisplayError;
  /**
   * Describes a possibility to use diesel for this transfer. The UI should prefer diesel when this field is defined,
   * and the diesel status is not "not-available". When the diesel is available, and the UI decides to use it, the `fee`
   * and `realFee` fields should be ignored, because they don't consider an extra transfer of the diesel to the
   * MTW wallet.
   */
  diesel?: ApiFetchEstimateDieselResult;
};

export type ApiSubmitTransferWithDieselResult = ApiSubmitMultiTransferResult & {
  encryptedComment?: string;
  withW5Gasless?: boolean;
};

export type ApiSubmitTransferOptions = {
  accountId: string;
  /** Required only for mnemonic accounts */
  password?: string;
  toAddress: string;
  amount: bigint;
  data?: AnyPayload;
  stateInit?: Cell;
  shouldEncrypt?: boolean;
  isBase64Data?: boolean;
  noFeeCheck?: boolean;
  // For token transfer
  tokenAddress?: string;
  forwardAmount?: bigint;
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
};

export type ParsedTracePart = {
  hashes: Set<string>;
  sent: bigint;
  /** How much TON will be received as a result of the transaction (the sent amount is not deducted) */
  received: bigint;
  /** The network fee in TON (the fee taken by the blockchain itself) */
  networkFee: bigint;
  /** Whether the transaction has succeeded */
  isSuccess: boolean;
};

export type ParsedTrace = {
  actions: AnyAction[];
  traceDetail: TraceDetail;
  addressBook: AddressBook;
  // Parsed
  byTransactionIndex: ParsedTracePart[];
  totalSent: bigint;
  totalReceived: bigint;
  totalNetworkFee: bigint;
};
