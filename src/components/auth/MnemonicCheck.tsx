import React, {
  memo,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
import useInactivityTimeout from '../../hooks/useInactivityTimeout';
import useLang from '../../hooks/useLang';

import CheckWordsForm from '../common/backup/CheckWordsForm';
import Button from '../ui/Button';
import ModalHeader from '../ui/ModalHeader';

import modalStyles from '../ui/Modal.module.scss';
import styles from './Auth.module.scss';

type OwnProps = {
  isActive?: boolean;
  mnemonic?: string[];
  checkIndexes?: number[];
  onSubmit: NoneToVoidFunction;
  onCancel: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
};

function MnemonicCheck({
  isActive, mnemonic, checkIndexes, onCancel, onSubmit, onClose,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

  // The word options are taken from the mnemonic. `onCancel` would show the secret words again, so the modal closes.
  useInactivityTimeout(onClose, isActive);

  return (
    <div className={modalStyles.transitionContentWrapper}>
      <ModalHeader title={lang('Let\'s Check!')} onClose={onClose} />
      <div className={buildClassName(modalStyles.transitionContent, 'custom-scroll')}>
        <p className={buildClassName(styles.info, styles.small)}>
          {lang('Let’s make sure your secrets words are recorded correctly.')}
        </p>

        <CheckWordsForm
          descriptionClassName={buildClassName(styles.info, styles.small)}
          isActive={isActive}
          mnemonic={mnemonic}
          checkIndexes={checkIndexes}
          errorClassName={buildClassName(styles.error, styles.small)}
          onSubmit={onSubmit}
        />

        <div className={modalStyles.buttons}>
          <Button onClick={onCancel} className={modalStyles.button}>{lang('Back')}</Button>
        </div>
      </div>
    </div>
  );
}

export default memo(MnemonicCheck);
