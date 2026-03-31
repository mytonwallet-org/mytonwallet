import type { Wallet } from '@tonconnect/sdk';
import React, { memo } from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { MEANINGFUL_CHAR_LENGTH } from '../../util/shortenAddress';
import { getWalletAddress } from '../util/tonConnect';

import useEffectOnce from '../../hooks/useEffectOnce';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';

interface OwnProps {
  isActive: boolean;
  wallet: Wallet;
  onConfirm: NoneToVoidFunction;
  onCancel: NoneToVoidFunction;
}

function ConfirmAddress({ isActive, wallet, onConfirm, onCancel }: OwnProps) {
  const lang = useLang();

  useHistoryBack({ isActive: true, onBack: onCancel });

  useEffectOnce(() => captureKeyboardListeners({ onEnter: onConfirm, onEsc: onCancel }));

  const handleConfirmClick = useLastCallback(() => {
    onConfirm();
  });

  const handleCancelClick = useLastCallback(() => {
    onCancel();
  });

  function renderFullAddress() {
    const address = getWalletAddress(wallet);
    const suffixStart = address.length - MEANINGFUL_CHAR_LENGTH;

    return (
      <>
        <span className={commonStyles.strong}>{address.substring(0, MEANINGFUL_CHAR_LENGTH)}</span>
        <span>{address.substring(MEANINGFUL_CHAR_LENGTH, suffixStart)}</span>
        <span className={commonStyles.strong}>{address.substring(suffixStart)}</span>
      </>
    );
  }

  return (
    <div className={commonStyles.container}>
      <div className={commonStyles.content}>
        <h2 className={commonStyles.title}>{lang('Confirm Your Address')}</h2>
      </div>

      <div className={commonStyles.content}>
        <p className={commonStyles.description}>
          {lang('You will receive the transfer to this address:')}
        </p>
      </div>

      <div className={commonStyles.field}>
        <div className={commonStyles.fieldContent}>
          {renderFullAddress()}
        </div>
      </div>

      <div className={commonStyles.footer}>
        <UniversalButton
          isActive={isActive}
          isPrimary
          className={commonStyles.button}
          onClick={handleConfirmClick}
        >
          {lang('Confirm')}
        </UniversalButton>
        <UniversalButton
          isActive={isActive}
          isSecondary
          className={buildClassName(commonStyles.button, commonStyles.button_secondary)}
          onClick={handleCancelClick}
        >
          {lang('Cancel')}
        </UniversalButton>
      </div>
    </div>
  );
}

export default memo(ConfirmAddress);
