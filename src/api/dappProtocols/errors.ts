import type { ApiAnyDisplayError } from '../types';
import type { CONNECT_EVENT_ERROR_CODES, SEND_TRANSACTION_ERROR_CODES } from './adapters/tonConnect/errors';

import { ApiBaseError } from '../errors';

export type AllErrorCodes = CONNECT_EVENT_ERROR_CODES | SEND_TRANSACTION_ERROR_CODES;

export interface DappProtocolError {
  code: AllErrorCodes;
  message: string;
  /** Display error for UI, if applicable */
  displayError?: ApiAnyDisplayError;
}

export class DappAdapterError extends ApiBaseError {
  code: number;

  constructor(message: string, code: number, displayError?: ApiAnyDisplayError) {
    super(message);
    this.code = code;
    this.displayError = displayError;
  }
}
