import { useState } from '../lib/teact/teact';
import { getGlobal } from '../global';

import type { ApiTransactionActivity } from '../api/types';

import { errorCodeToMessage } from '../global/helpers/errors';
import { isErrorTransferResult } from '../global/helpers/transfer';
import { getHasInMemoryPassword, getInMemoryPassword } from '../util/authApi/inMemoryPasswordStore';
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
  handlePasswordSubmit: (password: string) => Promise<void>;
  openHiddenComment: NoneToVoidFunction;
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

  const handlePasswordSubmit = useLastCallback(async (password: string) => {
    if (!transaction) return;

    const result = await callApi(
      'decryptComment',
      getGlobal().currentAccountId!,
      transaction,
      password,
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

  const openHiddenComment = useLastCallback(async () => {
    if (!encryptedComment) return;

    if (getHasInMemoryPassword()) {
      const password = await getInMemoryPassword();

      if (password) {
        void handlePasswordSubmit(password);
        return;
      }
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
      handlePasswordSubmit,
      openHiddenComment,
      resetDecryptedComment,
    },
  ];
}
