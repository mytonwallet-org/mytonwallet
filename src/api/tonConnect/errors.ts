import type { ApiAnyDisplayError } from '../types';
import type { AllErrorCodes } from './types';
import { ApiTransactionError } from '../types';
import { CONNECT_EVENT_ERROR_CODES, SEND_TRANSACTION_ERROR_CODES } from './types';

import { ApiBaseError } from '../errors';

export class TonConnectError extends ApiBaseError {
  code: number;

  constructor(message: string, code: AllErrorCodes = 0, displayError?: ApiAnyDisplayError) {
    super(message);
    this.code = code;
    this.displayError = displayError;
  }
}

export class ManifestContentError extends TonConnectError {
  constructor(message = 'Manifest content error') {
    super(message, CONNECT_EVENT_ERROR_CODES.MANIFEST_CONTENT_ERROR);
  }
}

export class UnknownError extends TonConnectError {
  constructor(message = 'Unknown error.', displayError?: ApiAnyDisplayError) {
    super(message, SEND_TRANSACTION_ERROR_CODES.UNKNOWN_ERROR, displayError);
  }
}

export class BadRequestError extends TonConnectError {
  constructor(message = 'Bad request', displayError?: ApiAnyDisplayError) {
    super(message, SEND_TRANSACTION_ERROR_CODES.BAD_REQUEST_ERROR, displayError);
  }
}

export class UnknownAppError extends TonConnectError {
  constructor(message = 'Unknown app error') {
    super(message, SEND_TRANSACTION_ERROR_CODES.UNKNOWN_APP_ERROR);
  }
}

export class UserRejectsError extends TonConnectError {
  constructor(message = 'The user rejected the action') {
    super(message, SEND_TRANSACTION_ERROR_CODES.USER_REJECTS_ERROR);
  }
}

export class MethodNotSupportedError extends TonConnectError {
  constructor(message = 'The method is not supported') {
    super(message, SEND_TRANSACTION_ERROR_CODES.METHOD_NOT_SUPPORTED);
  }
}

export class InsufficientBalance extends BadRequestError {
  constructor(message = 'Insufficient balance') {
    super(message, ApiTransactionError.InsufficientBalance);
  }
}
