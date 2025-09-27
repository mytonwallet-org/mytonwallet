import React, { memo } from '../../lib/teact/teact';

import renderText from '../../global/helpers/renderText';
import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useLang from '../../hooks/useLang';

import Emoji from '../ui/Emoji';
import ModalHeader from '../ui/ModalHeader';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Auth.module.scss';

type OwnProps = {
  isActive?: boolean;
  privateKeyHex?: string;
  onClose: NoneToVoidFunction;
};

function MnemonicPrivateKey({
  isActive, privateKeyHex, onClose,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onClose,
  });

  return (
    <div className={modalStyles.transitionContentWrapper}>
      <ModalHeader title={lang('Private Key')} onClose={onClose} />
      <div className={buildClassName(modalStyles.transitionContent, 'custom-scroll')}>
        <p className={buildClassName(styles.info, styles.small)}>
          <Emoji from="⚠️" />{' '}{renderText(lang('$mnemonic_warning'))}
        </p>
        <p className={styles.privateKey}>
          {privateKeyHex}
        </p>
      </div>
    </div>
  );
}

export default memo(MnemonicPrivateKey);
