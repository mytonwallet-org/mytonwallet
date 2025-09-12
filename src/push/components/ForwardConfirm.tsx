import React, { memo } from '../../lib/teact/teact';

import type { ApiCheck } from '../types';

import buildClassName from '../../util/buildClassName';
import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { formatCurrency } from '../../util/formatNumber';
import { MEANINGFUL_CHAR_LENGTH, shortenAddress } from '../../util/shortenAddress';
import { processCashCheck } from '../util/check';

import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';

interface OwnProps {
  isActive: boolean;
  check: ApiCheck;
  address: string;
  domain?: string;
  markJustSentRequest: NoneToVoidFunction;
  onConfirm: NoneToVoidFunction;
  onBack: NoneToVoidFunction;
}

function ForwardConfirm({ isActive, check, address, domain, markJustSentRequest, onConfirm, onBack }: OwnProps) {
  const lang = useLang();

  const [isLoading, markLoading, unmarkLoading] = useFlag(false);

  useHistoryBack({ isActive: true, onBack });

  useEffectOnce(() => captureKeyboardListeners({ onEnter: handleSubmit, onEsc: onBack }));

  const handleSubmit = useLastCallback(async () => {
    markLoading();

    try {
      await processCashCheck(check, markJustSentRequest, address);

      onConfirm();
    } catch (err: any) {
      alert(String(err));
    }

    unmarkLoading();
  });

  function renderFullAddress() {
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
        <h2 className={commonStyles.title}>{lang('Confirm Forward')}</h2>
      </div>

      <div className={commonStyles.field}>
        <div className={commonStyles.fieldContent}>
          {domain ? (
            <>
              <span className={commonStyles.strong}>{domain}</span> · {shortenAddress(address)}
            </>
          ) : (
            renderFullAddress()
          )}
        </div>
      </div>

      <div className={commonStyles.content}>
        <p className={commonStyles.description}>
          <b>{check.type === 'coin' ? formatCurrency(check.amount, check.symbol) : check.nftInfo.name}</b>{' '}
          {lang('will be forwarded to this address.')}
        </p>
      </div>

      <div className={commonStyles.footer}>
        <UniversalButton
          isActive={isActive}
          isPrimary
          isLoading={isLoading}
          className={commonStyles.button}
          onClick={handleSubmit}
        >
          {lang('Confirm')}
        </UniversalButton>
        <UniversalButton
          isActive={isActive}
          isSecondary
          isDisabled={isLoading}
          className={buildClassName(commonStyles.button, commonStyles.button_secondary)}
          onClick={onBack}
        >
          {lang('Edit')}
        </UniversalButton>
      </div>
    </div>
  );
}

export default memo(ForwardConfirm);
