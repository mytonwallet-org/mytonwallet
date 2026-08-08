import { useState } from '../lib/teact/teact';
import { getGlobal } from '../global';

import type { ApiTransactionActivity } from '../api/types';

import { errorCodeToMessage } from '../global/helpers/errors';
import { isErrorTransferResult } from '../global/helpers/transfer';
import { selectEnclaveToken, selectIsEnclaveSessionValid } from '../global/selectors';
import { getDoesUsePinPad } from '../util/biometrics';
import { vibrateOnSuccess } from '../util/haptics';
import { callApi } from '../api';
import useLastCallback from './useLastCallback';

export interface EncryptedCommentState {
  decryptedComment?: string;
  passwordError?: string;
  isPasswordSlideOpen: boolean;
}

export interface EncryptedCommentHandlers {
  openPasswordSlide: NoneToVoidFunction;
  closePasswordSlide: NoneToVoidFunction;
  clearPasswordError: NoneToVoidFunction;
  handleAuthorizeComment: (enclaveToken: string) => Promise<void>;
  handleCommentReveal: NoneToVoidFunction;
  resetDecryptedComment: NoneToVoidFunction;
}

interface UseEncryptedCommentOptions {
  transaction?: ApiTransactionActivity;
  encryptedComment?: string;
  onPinAccepted?: NoneToVoidFunction;
}

export default function useEncryptedComment({
  transaction,
  encryptedComment,
  onPinAccepted,
}: UseEncryptedCommentOptions): [EncryptedCommentState, EncryptedCommentHandlers] {
  const [decryptedComment, setDecryptedComment] = useState<string>();
  const [passwordError, setPasswordError] = useState<string>();
  const [isPasswordSlideOpen, setIsPasswordSlideOpen] = useState(false);

  const clearPasswordError = useLastCallback(() => {
    setPasswordError(undefined);
  });

  const openPasswordSlide = useLastCallback(() => {
    setIsPasswordSlideOpen(true);
  });

  const closePasswordSlide = useLastCallback(() => {
    setIsPasswordSlideOpen(false);
    clearPasswordError();
  });

  const resetDecryptedComment = useLastCallback(() => {
    setDecryptedComment(undefined);
  });

  const handleAuthorizeComment = useLastCallback(async (enclaveToken: string) => {
    if (!transaction) return;

    const result = await callApi(
      'decryptComment',
      getGlobal().currentAccountId!,
      transaction,
      enclaveToken,
    );

    if (isErrorTransferResult(result)) {
      setPasswordError(errorCodeToMessage(result?.error));
      return;
    }

    if (getDoesUsePinPad()) {
      onPinAccepted?.();
      await vibrateOnSuccess(true);
    }

    closePasswordSlide();
    setDecryptedComment(result);
  });

  const handleCommentReveal = useLastCallback(() => {
    if (!encryptedComment) return;

    if (selectIsEnclaveSessionValid(getGlobal())) {
      void handleAuthorizeComment(selectEnclaveToken(getGlobal())!);

      return;
    }

    openPasswordSlide();
  });

  return [
    {
      decryptedComment,
      passwordError,
      isPasswordSlideOpen,
    },
    {
      openPasswordSlide,
      closePasswordSlide,
      clearPasswordError,
      handleAuthorizeComment,
      handleCommentReveal,
      resetDecryptedComment,
    },
  ];
}
