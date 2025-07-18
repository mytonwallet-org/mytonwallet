import type { ApiAnyDisplayError } from './types';
import { ApiCommonError, ApiTransactionError } from './types';

export class ApiBaseError extends Error {
  constructor(message?: string, public displayError?: ApiAnyDisplayError) {
    super(message);
    this.name = this.constructor.name;
  }
}

// todo: Remove
export class ApiUserRejectsError extends ApiBaseError {
  constructor(message: string = 'Canceled by the user') {
    super(message);
  }
}

export class ApiServerError extends ApiBaseError {
  constructor(message: string, public statusCode?: number) {
    super(message, ApiCommonError.ServerError);
  }
}

// todo: Remove
export class ApiUnsupportedVersionError extends ApiBaseError {
  constructor(message: string) {
    super(message, ApiCommonError.UnsupportedVersion);
  }
}

// todo: Remove
export class ApiHardwareBlindSigningNotEnabled extends ApiBaseError {
  constructor(message: string = 'Blind signing not enabled') {
    super(message, ApiTransactionError.HardwareBlindSigningNotEnabled);
  }
}

export class AbortOperationError extends ApiBaseError {
  constructor(message: string = 'Abort operation') {
    super(message);
  }
}

export class NotImplemented extends ApiBaseError {
  constructor(message: string = 'Not implemented') {
    super(message);
  }
}

export function maybeApiErrors(fn: AnyAsyncFunction) {
  return async (...args: any) => {
    try {
      return await fn(...args);
    } catch (err) {
      return handleServerError(err);
    }
  };
}

export function handleServerError(err: any) {
  if (err instanceof ApiServerError) {
    return { error: err.displayError! };
  }
  throw err;
}
