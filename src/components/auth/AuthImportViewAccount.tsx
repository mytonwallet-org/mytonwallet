import React, {
  memo, useRef, useState,
} from '../../lib/teact/teact';
import { getActions } from '../../global';

import type { ApiImportAddressByChain } from '../../api/types';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';
import { getSupportedChains } from '../../util/chain';
import { stopEvent } from '../../util/domEvents';
import { isValidAddressOrDomain } from '../../util/isValidAddressOrDomain';
import { ANIMATED_STICKERS_PATHS } from '../ui/helpers/animatedAssets';

import useFocusAfterAnimation from '../../hooks/useFocusAfterAnimation';
import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';
import useLastCallback from '../../hooks/useLastCallback';

import AnimatedIconWithPreview from '../ui/AnimatedIconWithPreview';
import Button from '../ui/Button';
import Input from '../ui/Input';
import ModalHeader from '../ui/ModalHeader';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Auth.module.scss';

type OwnProps = {
  isActive?: boolean;
  isLoading?: boolean;
  onCancel: NoneToVoidFunction;
};

function AuthImportViewAccount({
  isActive, isLoading, onCancel,
}: OwnProps) {
  const { importViewAccount } = getActions();

  const lang = useLang();

  const inputRef = useRef<HTMLInputElement>();
  const [value, setValue] = useState<string>('');
  const [isInvalidAddress, setIsInvalidAddress] = useState<boolean>(false);

  useFocusAfterAnimation(inputRef, !isActive);

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

  const handleChange = useLastCallback((newValue: string) => {
    setValue(newValue);
    if (isInvalidAddress) {
      setIsInvalidAddress(false);
    }
  });

  function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    stopEvent(e);

    if (isInvalidAddress || isLoading) return;

    const addresses = value.trim().split(/\s+/);
    const addressByChain: ApiImportAddressByChain = {};

    const hasValidAddress = addresses.reduce((isValid, address) => {
      for (const chain of getSupportedChains()) {
        if (isValidAddressOrDomain(address, chain)) {
          addressByChain[chain] = address;
          return true;
        }
      }

      return isValid;
    }, false);

    if (hasValidAddress) {
      importViewAccount({ addressByChain });
      inputRef.current?.blur(); // To hide the virtual keyboard to show the loading indicator in the button
    } else {
      setIsInvalidAddress(true);
    }
  }

  return (
    <div className={modalStyles.transitionContentWrapper}>
      <ModalHeader title={lang('View Any Address')} onBackButtonClick={onCancel} />
      <form
        action="#"
        className={buildClassName(modalStyles.transitionContent, 'custom-scroll')}
        onSubmit={handleSubmit}
      >
        <AnimatedIconWithPreview
          play={isActive}
          tgsUrl={ANIMATED_STICKERS_PATHS.bill}
          previewUrl={ANIMATED_STICKERS_PATHS.billPreview}
          noLoop={false}
          nonInteractive
          className={styles.viewModeSticker}
        />

        <Input
          ref={inputRef}
          value={value}
          hasError={isInvalidAddress}
          placeholder={lang('Wallet Address or Domain')}
          autoCapitalize="none"
          autoComplete="off"
          autoCorrect={false}
          enterKeyHint="done"
          onInput={handleChange}
        />

        <p className={styles.info}>{renderText(lang('$import_view_account_note'))}</p>

        <div className={styles.buttons}>
          <Button
            isPrimary
            isSubmit
            className={modalStyles.buttonFullWidth}
            isLoading={isLoading}
            isDisabled={isInvalidAddress}
          >
            {isInvalidAddress ? lang('Invalid Address') : lang('Continue')}
          </Button>
        </div>
      </form>
    </div>
  );
}

export default memo(AuthImportViewAccount);
