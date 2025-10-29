import React, { memo, useRef, useState } from '../../lib/teact/teact';

import type { ApiCheck } from '../types';

import captureKeyboardListeners from '../../util/captureKeyboardListeners';
import { formatCurrency } from '../../util/formatNumber';
import { isValidAddressOrDomain, resolveOrValidate } from '../../util/validateAddress';

import useEffectOnce from '../../hooks/useEffectOnce';
import useFlag from '../../hooks/useFlag';
import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AddressInput from '../../components/ui/AddressInput';
import UniversalButton from './UniversalButton';

import commonStyles from './_common.module.scss';
import styles from './Forward.module.scss';

interface OwnProps {
  isActive: boolean;
  check: ApiCheck;
  address: string;
  setAddress: (address: string) => void;
  setDomain: (domain?: string) => void;
  onForward: NoneToVoidFunction;
  onBack: NoneToVoidFunction;
}

const CHAIN = 'ton';
const INVISIBLE_LABEL = '⁠';

function Forward({ isActive, check, address, setAddress, setDomain, onForward, onBack }: OwnProps) {
  const inputRef = useRef<HTMLInputElement>();

  const lang = useLang();

  const [error, setError] = useState<string>();
  const [isLoading, markLoading, unmarkLoading] = useFlag(false);

  useHistoryBack({ isActive: true, onBack });

  useEffectOnce(() => captureKeyboardListeners({ onEnter: handleSubmit, onEsc: onBack }));

  useFocusAfterAnimation(inputRef);

  const canSubmit = isValidAddressOrDomain(address, CHAIN);

  const handleInput = useLastCallback((newValue: string) => {
    setAddress(newValue);
    setError(undefined);
  });

  const handleSubmit = useLastCallback(async () => {
    inputRef.current!.blur();

    markLoading();
    const { resolvedAddress, error } = await resolveOrValidate(address);
    unmarkLoading();

    if (resolvedAddress) {
      setAddress(resolvedAddress);
      setDomain(resolvedAddress !== address ? address.toLowerCase() : undefined);
      onForward();
    } else {
      setError(error);
      unmarkLoading();

      return;
    }
  });

  return (
    <div className={commonStyles.container}>
      <div className={commonStyles.content}>
        <h2 className={commonStyles.title}>{lang('Forward to...')}</h2>
      </div>

      <div className={styles.addressInputWrapper}>
        <AddressInput
          ref={inputRef}
          isStatic
          withCurrentAccount
          label={INVISIBLE_LABEL}
          chain={CHAIN}
          value={address}
          address={address}
          addressName=""
          error={error}
          onInput={handleInput}
          onClose={onBack}
        />
      </div>

      <div className={commonStyles.content}>
        <p className={commonStyles.description}>
          {lang('Enter TON wallet address or domain to forward')}{' '}
          <b>{check.type === 'coin' ? formatCurrency(check.amount, check.symbol) : check.nftInfo?.name}</b>
        </p>
      </div>

      <div className={commonStyles.footer}>
        <UniversalButton
          isActive={isActive}
          isPrimary
          isDisabled={!canSubmit}
          isLoading={isLoading}
          className={commonStyles.button}
          onClick={handleSubmit}
        >
          {lang('Forward')}
        </UniversalButton>
      </div>
    </div>
  );
}

export default memo(Forward);
