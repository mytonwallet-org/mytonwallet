import React, {
  memo,
} from '../../lib/teact/teact';

import buildClassName from '../../util/buildClassName';

import useHistoryBack from '../../hooks/useHistoryBack';
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
  buttonLabel: string;
  onSubmit: NoneToVoidFunction;
  onCancel: NoneToVoidFunction;
  onClose: NoneToVoidFunction;
};

function MnemonicCheck({
  isActive, mnemonic, checkIndexes, buttonLabel, onCancel, onSubmit, onClose,
}: OwnProps) {
  const lang = useLang();

  useHistoryBack({
    isActive,
    onBack: onCancel,
  });

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
          <Button isPrimary forFormId="check_mnemonic_form" className={modalStyles.button}>{buttonLabel}</Button>
        </div>
      </div>
    </div>
  );
}

export default memo(MnemonicCheck);
