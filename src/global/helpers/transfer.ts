import type { ApiAnyDisplayError } from '../../api/types';
import type { GlobalState } from '../types';
import { ApiCommonError } from '../../api/types';

import { getDoesUsePinPad } from '../../util/biometrics';
import { vibrateOnError, vibrateOnSuccess } from '../../util/haptics';
import { callApi } from '../../api';
import { getActions, getGlobal, setGlobal } from '../index';
import { clearIsPinAccepted, setIsPinAccepted } from '../reducers';
import { selectIsHardwareAccount } from '../selectors';
import { errorCodeToMessage, isInlineError } from './errors';

export type FormUpdate<State> = {
  state?: State;
  isLoading?: true;
  error?: string;
};

export type FormReducer<State> = (global: GlobalState, update: FormUpdate<State>) => GlobalState;

export type ErrorTransferResult = { error: ApiAnyDisplayError | string } | undefined;

/** Returns `false` if there is a problem preventing the further progress, which has been shown to the user */
export async function prepareTransfer<State>(
  hardwareConfirmState: State,
  updateForm: FormReducer<State>,
  password?: string,
) {
  let global = getGlobal();
  const isHardware = selectIsHardwareAccount(global);

  if (!isHardware) {
    const isPasswordCorrect = await callApi('verifyPassword', password ?? '');
    global = getGlobal();

    if (!isPasswordCorrect) {
      setGlobal(updateForm(global, {
        error: errorCodeToMessage(ApiCommonError.InvalidPassword),
      }));
      return false;
    }

    if (getDoesUsePinPad()) {
      global = setIsPinAccepted(global);
    }

    void vibrateOnSuccess();
  }

  setGlobal(updateForm(global, {
    isLoading: true,
    error: undefined,
    ...(isHardware && { state: hardwareConfirmState }),
  }));

  return true;
}

/** Returns `false` if the result is unsuccessful and the error has been shown to the user */
export function handleTransferResult<T>(
  result: T,
  updateForm: FormReducer<never>,
): result is Exclude<T, ErrorTransferResult> {
  let global = getGlobal();
  global = updateForm(global, { isLoading: undefined });
  global = clearIsPinAccepted(global);
  setGlobal(global);

  if (isErrorTransferResult(result)) {
    reportErrorTransferResult(result, updateForm);
    return false;
  }

  void vibrateOnSuccess();
  return true;
}

/** Returns `false` if any of the results is unsuccessful and the error has been shown to the user */
export function handleTransferResults<T>(
  results: T[],
  updateForm: FormReducer<never>,
): results is Exclude<T, ErrorTransferResult>[] {
  if (!results.length) {
    return true;
  }

  const errorResultIndex = results.findIndex(isErrorTransferResult);
  const result = results[errorResultIndex >= 0 ? errorResultIndex : 0];
  return handleTransferResult(result, updateForm);
}

export function isErrorTransferResult(result: unknown): result is ErrorTransferResult {
  return result === undefined || (!!result && typeof result === 'object' && 'error' in result);
}

export function reportErrorTransferResult(result: ErrorTransferResult, updateForm: FormReducer<never>) {
  void vibrateOnError();

  const error = result?.error;
  let global = getGlobal();
  global = updateForm(global, { isLoading: undefined });

  if (isInlineError(error)) {
    global = updateForm(global, {
      error: errorCodeToMessage(error),
    });
    setGlobal(global);
  } else {
    setGlobal(global);
    getActions().showError({ error });
  }
}

/** Returns `false` if there is a problem preventing the further progress, which has been shown to the user */
export async function prepareDappOperation<State>(
  accountId: string,
  hardwareConfirmState: State,
  updateForm: FormReducer<State>,
  doesNeedSigning: boolean,
  password?: string,
) {
  let global = getGlobal();
  const isHardware = selectIsHardwareAccount(global, accountId);

  if (!isHardware) {
    const isPasswordCorrect = !doesNeedSigning || await callApi('verifyPassword', password ?? '');
    global = getGlobal();

    if (!isPasswordCorrect) {
      setGlobal(updateForm(global, {
        error: errorCodeToMessage(ApiCommonError.InvalidPassword),
      }));
      return false;
    }

    if (getDoesUsePinPad()) {
      global = setIsPinAccepted(global);
    }
  }

  setGlobal(updateForm(global, {
    isLoading: true,
    error: undefined,
    ...(isHardware && { state: hardwareConfirmState }),
  }));

  return true;
}

/** Returns `false` if the result is unsuccessful and the error has been shown to the user */
export function handleDappSignatureResult<T>(
  result: T,
  updateForm: FormReducer<never>,
): result is Exclude<T, ErrorTransferResult> {
  if (isErrorTransferResult(result)) {
    reportErrorTransferResult(result, updateForm);
    return false;
  }

  void vibrateOnSuccess();
  return true;
}
