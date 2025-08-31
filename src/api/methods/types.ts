import type { Cell } from '@ton/core';

import type {
  ApiSubmitMultiTransferResult,
  ApiSubmitTransferTonResult,
  ApiSubmitTransferWithDieselResult,
} from '../chains/ton/types';
import type { ApiSubmitTransferTronResult } from '../chains/tron/types';
import type * as methods from './index';

export type Methods = typeof methods;
export type MethodArgs<N extends keyof Methods> = Parameters<Methods[N]>;
export type MethodResponse<N extends keyof Methods> = ReturnType<Methods[N]>;

export type CheckTransactionDraftOptions = {
  accountId: string;
  toAddress: string;
  /**
   * When the value is undefined, the method doesn't check the available balance. If you want only to estimate the fee,
   * don't send the amount, because:
   * - The fee doesn't depend on the amount neither in TON nor in TRON.
   * - Errors will happen in edge cases such as 0 and greater than the balance.
   */
  amount?: bigint;
  data?: string | Uint8Array | Cell;
  stateInit?: string;
  shouldEncrypt?: boolean;
  isBase64Data?: boolean;
  // For transfer token
  tokenAddress?: string;
  forwardAmount?: bigint;
  allowGasless?: boolean;
};

export interface ApiSubmitTransferOptions {
  accountId: string;
  /** Required only for mnemonic accounts */
  password?: string;
  toAddress: string;
  amount: bigint;
  comment?: string;
  tokenAddress?: string;
  /** To cap the fee in TRON transfers */
  fee?: bigint;
  /** To show in the created local transaction */
  realFee?: bigint;
  shouldEncrypt?: boolean;
  isBase64Data?: boolean;
  withDiesel?: boolean;
  dieselAmount?: bigint;
  stateInit?: string | Cell;
  isGaslessWithStars?: boolean;
  forwardAmount?: bigint;
  noFeeCheck?: boolean;
}

type ExtendSuccess<T, U> = T extends { error: unknown } ? T : T & U;

export type ApiSubmitTransferResult = ExtendSuccess<
  | ApiSubmitTransferTonResult
  | ApiSubmitTransferTronResult
  | ApiSubmitTransferWithDieselResult,
  {
    activityId?: string;
  }
>;

export type ApiSubmitNftTransferResult = ExtendSuccess<
  ApiSubmitMultiTransferResult,
  {
    activityIds: string[];
  }
>;
