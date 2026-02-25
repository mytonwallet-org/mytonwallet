import type { AllErrorCodes } from '../../errors';
import { type ApiAnyDisplayError, ApiTransactionError } from '../../../types';

import { DappAdapterError } from '../../errors';

export enum CONNECT_EVENT_ERROR_CODES {
  UNKNOWN_ERROR = 0,
  BAD_REQUEST_ERROR = 1,
  MANIFEST_NOT_FOUND_ERROR = 2,
  MANIFEST_CONTENT_ERROR = 3,
  UNKNOWN_APP_ERROR = 100,
  USER_REJECTS_ERROR = 300,
  METHOD_NOT_SUPPORTED = 400,
}

export enum SEND_TRANSACTION_ERROR_CODES {
  UNKNOWN_ERROR = 0,
  BAD_REQUEST_ERROR = 1,
  UNKNOWN_APP_ERROR = 100,
  USER_REJECTS_ERROR = 300,
  METHOD_NOT_SUPPORTED = 400,
}

export class TonConnectError extends DappAdapterError {
  constructor(message: string, code: AllErrorCodes = 0, displayError?: ApiAnyDisplayError) {
    super(message, code);
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
